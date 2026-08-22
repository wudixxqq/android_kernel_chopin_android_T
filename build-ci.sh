#!/bin/bash
# chopin (MT6893) 本地内核编译脚本
# 兼容 GitHub Actions 工作流逻辑，支持 config.env 配置
# 用法：
#   ./build-ci.sh                 # 读取 config.env 默认配置
#   ./build-ci.sh --su=ReSukiSU   # 指定 Root 管理器
#   ./build-ci.sh --susfs         # 启用 SUSFS
#   ./build-ci.sh --bbg           # 启用 BBRPlus（保留选项名，实际映射为 BBR）

set -e

# 默认值
SU="None"
SUSFS="false"
BBR="true"
DROIDSPACE="false"
TG="false"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --su=*)
            SU="${1#*=}"
            shift
            ;;
        --su)
            SU="$2"
            shift 2
            ;;
        --susfs)
            SUSFS="true"
            shift
            ;;
        --bbr)
            BBR="true"
            shift
            ;;
        --bbg)
            # 保留别名，与部分社区脚本习惯保持一致
            BBR="true"
            shift
            ;;
        --no-bbr)
            BBR="false"
            shift
            ;;
        --droidspace)
            DROIDSPACE="true"
            shift
            ;;
        --tg)
            TG="true"
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --su=NAME        Root 管理器: None, RKSU, ReSukiSU"
            echo "  --susfs          启用 SUSFS（需同时启用 SU）"
            echo "  --bbr            启用 BBR 拥塞控制（默认启用）"
            echo "  --no-bbr         关闭 BBR"
            echo "  --droidspace     启用 DroidSpace (USER_NS)"
            echo "  --tg             编译完成后上传到 Telegram"
            echo "  -h, --help       显示本帮助"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

# 加载配置文件
CONFIG_FILE="config.env"
if [ -f "$CONFIG_FILE" ]; then
    echo "[+] 加载配置: $CONFIG_FILE"
    set -a
    source "$CONFIG_FILE"
    set +a
else
    echo "[-] 未找到 $CONFIG_FILE，使用内置默认值"
    KERNEL_JX=chopin
    KERNEL_CONFIG=chopin_user_defconfig
    ANYKERNEL_REPO=https://github.com/AbzRaider/AnyKernel33
    ANYKERNEL_BRANCH=ares
    CLANG_URL="https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-6443078 -b 10.0"
    GCC64_URL=https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-13.0.0_r1.tar.gz
    GCC32_URL=https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-13.0.0_r1.tar.gz
fi

# 若 config.env 中默认启用 KSU，则映射为 RKSU
if [ "${KERNEL_KSU,,}" = "yes" ] && [ "$SU" = "None" ]; then
    SU="RKSU"
fi

echo "================================================"
echo "  chopin (MT6893) 本地内核编译"
echo "  机型: $KERNEL_JX"
echo "  defconfig: $KERNEL_CONFIG"
echo "  SU: $SU"
echo "  SUSFS: $SUSFS"
echo "  BBR: $BBR"
echo "  DroidSpace: $DROIDSPACE"
echo "  Telegram: $TG"
echo "================================================"

# 源码检测
echo "[+] 检测源码结构..."
[ -f "Makefile" ] || { echo "[-] 错误：未找到 Makefile"; exit 1; }
[ -d "arch/arm64/configs" ] || { echo "[-] 错误：未找到 arch/arm64/configs"; exit 1; }
[ -f "arch/arm64/configs/$KERNEL_CONFIG" ] || { echo "[-] 错误：未找到 defconfig: $KERNEL_CONFIG"; exit 1; }
echo "[+] 源码检测通过"

# 工作目录
WORKSPACE="$(pwd)"
TOOL_DIR="$WORKSPACE/kernel_workspace"
mkdir -p "$TOOL_DIR"

# 下载工具链（不存在时自动下载）
install_toolchain() {
    cd "$TOOL_DIR"

    # Clang
    if [ ! -d "$TOOL_DIR/clang/bin" ]; then
        echo "[+] 准备 Clang 工具链..."
        rm -rf "$TOOL_DIR/clang"
        if echo "$CLANG_URL" | grep -qE '\.tar\.gz|\.tgz'; then
            mkdir clang
            wget -q -O clang.tar.gz "$CLANG_URL"
            tar -C clang/ -zxvf clang.tar.gz >/dev/null
            rm -f clang.tar.gz
        else
            URL=$(echo "$CLANG_URL" | awk '{print $1}')
            BR=$(echo "$CLANG_URL" | awk '{print $3}')
            [ -z "$BR" ] && BR="main"
            git clone --depth=1 "$URL" -b "$BR" clang
        fi
        [ -d clang/bin ] || { echo "[-] Clang 下载或解压失败"; exit 1; }
    fi

    # GCC64
    if [ ! -d "$TOOL_DIR/gcc64/bin" ]; then
        echo "[+] 准备 GCC64 工具链..."
        rm -rf "$TOOL_DIR/gcc64"
        if echo "$GCC64_URL" | grep -qE '\.tar\.gz|\.tgz'; then
            mkdir gcc64
            wget -q -O gcc-aarch64.tar.gz "$GCC64_URL"
            tar -C gcc64/ -zxvf gcc-aarch64.tar.gz >/dev/null
            rm -f gcc-aarch64.tar.gz
        else
            URL=$(echo "$GCC64_URL" | awk '{print $1}')
            BR=$(echo "$GCC64_URL" | awk '{print $3}')
            [ -z "$BR" ] && BR="main"
            git clone --depth=1 "$URL" -b "$BR" gcc64
        fi
        [ -d gcc64/bin ] || { echo "[-] GCC64 下载或解压失败"; exit 1; }
    fi

    # GCC32
    if [ ! -d "$TOOL_DIR/gcc32/bin" ]; then
        echo "[+] 准备 GCC32 工具链..."
        rm -rf "$TOOL_DIR/gcc32"
        if echo "$GCC32_URL" | grep -qE '\.tar\.gz|\.tgz'; then
            mkdir gcc32
            wget -q -O gcc-arm.tar.gz "$GCC32_URL"
            tar -C gcc32/ -zxvf gcc-arm.tar.gz >/dev/null
            rm -f gcc-arm.tar.gz
        else
            URL=$(echo "$GCC32_URL" | awk '{print $1}')
            BR=$(echo "$GCC32_URL" | awk '{print $3}')
            [ -z "$BR" ] && BR="main"
            git clone --depth=1 "$URL" -b "$BR" gcc32
        fi
        [ -d gcc32/bin ] || { echo "[-] GCC32 下载或解压失败"; exit 1; }
    fi
}

# 应用补丁
apply_patches() {
    cd "$WORKSPACE"
    if [ "$SU" = "RKSU" ]; then
        echo "[+] 下载并应用 RKSU 4.14 patch"
        wget -q https://github.com/rksuorg/kernel_patches/raw/master/manual_hook/kernel-4.14.patch -O ksu-4.14.patch
        patch -p1 < ksu-4.14.patch || { echo "[-] RKSU patch 应用失败"; exit 1; }
        rm -f ksu-4.14.patch
    elif [ "$SU" = "ReSukiSU" ]; then
        echo "[+] 下载并应用 ReSukiSU 4.14 patch"
        if [ "$SUSFS" = "true" ]; then
            echo "[+] SUSFS 使用 inline hooks，跳过 manual hook patch"
        else
            wget -q -O resukisu-4.14.patch \
                https://raw.githubusercontent.com/ReSukiSU/ReSukiSU_Patches/main/scope-minimized/kernel-4.14.patch
            patch -p1 < resukisu-4.14.patch || { echo "[-] ReSukiSU patch 应用失败"; exit 1; }
            rm -f resukisu-4.14.patch
        fi
    fi

    if [ "$SUSFS" = "true" ]; then
        if [ "$SU" = "None" ]; then
            echo "[-] 错误：启用 SUSFS 必须同时选择 RKSU 或 ReSukiSU"
            exit 1
        fi
        echo "[+] 下载并应用 SUSFS 4.14 patch"
        wget -q -O susfs-4.14.patch \
            https://raw.githubusercontent.com/sanba0519/Kernel-patch/refs/heads/main/USeless/susfs_patch_to_4.14-bak.patch
        patch -p1 < susfs-4.14.patch || { echo "[-] SUSFS patch 应用失败"; exit 1; }
        sed -i 's/^orig_flow:$/orig_flow:;/' "$WORKSPACE/fs/notify/fdinfo.c"
        grep -q '^orig_flow:;' "$WORKSPACE/fs/notify/fdinfo.c" || { echo "[-] SUSFS fdinfo 修正失败"; exit 1; }
        rm -f susfs-4.14.patch
    fi
}

# 设置 KernelSU
setup_ksu() {
    cd "$WORKSPACE"
    if [ "$SU" != "None" ]; then
        echo "[+] 设置 KernelSU: $SU"
        rm -rf KernelSU
        if [ "$SU" = "ReSukiSU" ]; then
            curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
            if [ "$SUSFS" = "true" ]; then
                echo "[+] 应用 ReSukiSU SUSFS inline hooks"
                wget -q -O susfs_inline_hook_patches.sh \
                    https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/mainline/Patches/susfs_inline_hook_patches.sh
                bash susfs_inline_hook_patches.sh
                rm -f susfs_inline_hook_patches.sh
            fi
        else
            curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s main
        fi
    fi
}

# 编译内核
build_kernel() {
    cd "$WORKSPACE"
    export PATH="$TOOL_DIR/clang/bin:$TOOL_DIR/gcc64/bin:$TOOL_DIR/gcc32/bin:$PATH"
    export ARCH=arm64
    export SUBARCH=arm64
    export KBUILD_BUILD_HOST="$(hostname)"
    export KBUILD_BUILD_USER="$(whoami)"
    export USE_CCACHE=1
    ccache -M 50G >/dev/null 2>&1 || true

    echo "[+] 生成初始配置: $KERNEL_CONFIG"
    make -j$(nproc --all) O=out ARCH=arm64 "$KERNEL_CONFIG"

    if [ "$DROIDSPACE" = "true" ]; then
        echo "[+] 启用 DroidSpace..."
        ./scripts/config --file out/.config \
            --enable CONFIG_NAMESPACES \
            --enable CONFIG_USER_NS \
            --enable CONFIG_DEVTMPFS \
            --enable CONFIG_DEVTMPFS_MOUNT
        make O=out olddefconfig
    fi

    if [ "$BBR" = "true" ]; then
        echo "[+] 启用 BBR..."
        ./scripts/config --file out/.config \
            --enable CONFIG_TCP_CONG_BBR \
            --enable CONFIG_NET_SCH_FQ
        make O=out olddefconfig
    fi

    ./scripts/config --file out/.config \
        --enable CONFIG_NAMESPACES \
        --enable CONFIG_DEVTMPFS \
        --disable CONFIG_USER_NS \
        --enable CONFIG_DEVTMPFS_MOUNT

    if [ "$SU" = "ReSukiSU" ]; then
        if [ "$SUSFS" = "true" ]; then
            ./scripts/config --file out/.config \
                --enable CONFIG_KSU \
                --enable CONFIG_KSU_SUSFS \
                --disable CONFIG_KSU_MANUAL_HOOK \
                --disable CONFIG_KSU_TRACEPOINT_HOOK
        else
            ./scripts/config --file out/.config \
                --enable CONFIG_KSU \
                --enable CONFIG_KSU_MANUAL_HOOK \
                --disable CONFIG_KSU_SUSFS \
                --disable CONFIG_KSU_TRACEPOINT_HOOK
        fi
    elif [ "$SU" = "RKSU" ]; then
        ./scripts/config --file out/.config --enable CONFIG_KSU
    fi

    make O=out ARCH=arm64 olddefconfig

    echo "[+] 开始编译..."
    make -j"$(nproc)" \
        O=out \
        ARCH=arm64 \
        CC="ccache clang" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-android- \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        LD=ld.lld 2>&1 | tee error.log

    if [ ! -f "out/arch/arm64/boot/Image.gz-dtb" ]; then
        echo "[-] 编译失败：未生成 Image.gz-dtb"
        exit 1
    fi
    echo "[+] 编译成功"
}

# 打包 AnyKernel3
package_kernel() {
    cd "$TOOL_DIR"
    if [ ! -d "$TOOL_DIR/AnyKernel3" ]; then
        git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" AnyKernel3
    fi
    cp "$WORKSPACE/out/arch/arm64/boot/Image.gz-dtb" AnyKernel3/
    cd AnyKernel3

    NAME="${KERNEL_JX}"
    [ "$SU" != "None" ] && NAME="${NAME}-${SU}"
    [ "$BBR" = "true" ] && NAME="${NAME}-BBR"
    [ "$DROIDSPACE" = "true" ] && NAME="${NAME}-DroidSpace"
    [ "$SUSFS" = "true" ] && NAME="${NAME}-SUSFS"
    NAME="${NAME}-$(date +%Y%m%d-%H%M).zip"

    zip -r9 "$WORKSPACE/$NAME" . >/dev/null
    echo "[+] 产物已生成: $WORKSPACE/$NAME"
}

# 主流程
install_toolchain
apply_patches
setup_ksu
build_kernel
package_kernel

echo "[+] 全部完成"
