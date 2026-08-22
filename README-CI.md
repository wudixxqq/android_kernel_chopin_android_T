# chopin (MT6893) 自动编译系统

本项目为 `android_kernel_chopin_android_T` 设计了一套类似 OPPO/Realme MT6853 仓库的自动编译系统，包含 GitHub Actions 工作流、本地编译脚本、Telegram 机器人通知及工作流清理工具。

## 文件结构

```
.
├── .github/
│   ├── bot.py                      # Telegram 文件上传机器人
│   └── workflows/
│       ├── build-kernel.yml        # 主编译工作流
│       └── clean.yml               # 工作流清理工作流
├── config.env                      # 编译配置（工具链、defconfig、AnyKernel3 等）
├── build-ci.sh                     # 本地一键编译脚本
├── build.sh                        # 原项目脚本（保留）
└── README-CI.md                    # 本文档
```

## 功能特性

- **代码自动检测**：工作流启动前自动检查 `Makefile`、`arch/arm64/configs`、指定 `defconfig` 是否存在。
- **可配置工具链**：通过 `config.env` 选择 Clang/GCC 来源，支持 git 仓库或 tar.gz 压缩包。
- **可选 Root 方案**：
  - `None`：不集成 KernelSU
  - `RKSU`：集成 [rsuntk/KernelSU](https://github.com/rsuntk/KernelSU)
  - `ReSukiSU`：集成 [ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU)
- **可选增强功能**：
  - `SUSFS`：需配合 KernelSU 使用
  - `BBR`：启用 BBR 拥塞控制
  - `DroidSpace`：启用 `USER_NS` 命名空间支持
- **错误提示与日志**：编译失败时自动上传 `error.log` 作为 artifact。
- **结果反馈**：
  - GitHub Actions 页面生成构建摘要
  - 编译产物自动上传到 Actions artifacts
  - 可选 Telegram 通知与文件上传

## 快速开始

### 1. 配置 config.env

根据你的需求编辑 `config.env`：

```bash
# 机型标识
KERNEL_JX=chopin

# defconfig 选择：chopin_user_defconfig 或 ares_user_defconfig
KERNEL_CONFIG=chopin_user_defconfig

# 本地脚本是否默认启用 KernelSU
KERNEL_KSU=yes

# AnyKernel3 仓库
ANYKERNEL_REPO=https://github.com/AbzRaider/AnyKernel33
ANYKERNEL_BRANCH=ares

# 工具链（支持 git 或 tar.gz）
CLANG_URL=https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-6443078 -b 10.0
GCC64_URL=https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-13.0.0_r1.tar.gz
GCC32_URL=https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-13.0.0_r1.tar.gz
```

### 2. 本地编译

```bash
# 默认配置（不启用 SU）
./build-ci.sh

# 启用 RKSU
./build-ci.sh --su=RKSU

# 启用 ReSukiSU + SUSFS
./build-ci.sh --su=ReSukiSU --susfs

# 启用 BBR（默认已启用）
./build-ci.sh --bbr

# 查看帮助
./build-ci.sh --help
```

产物为当前目录下的 `chopin-*.zip`。

### 3. GitHub Actions 编译

1. 将本仓库文件推送到 GitHub。
2. 进入 **Actions** → **Build Kernel for chopin (MT6893)** → **Run workflow**。
3. 选择选项后启动：
   - **Root 管理器**：`None`、`RKSU`、`ReSukiSU`
   - **SUSFS**：是否启用
   - **BBR**：是否启用
   - **DroidSpace**：是否启用
   - **Telegram**：是否上传
   - **Branch**：要编译的分支（默认 `T`）
4. 编译完成后在 Actions 页面下载 artifact。

### 4. Telegram 通知配置

如需启用 Telegram 上传，在仓库 **Settings → Secrets and variables → Actions** 中添加以下 Secrets：

| Secret            | 说明                         |
|-------------------|------------------------------|
| `API_ID`          | Telegram API ID              |
| `API_HASH`        | Telegram API Hash            |
| `BOT_TOKEN`       | Bot Token                    |
| `CHAT_ID`         | 目标聊天 ID（频道/群组/个人） |
| `BOT_CI_SESSION`  | Telethon StringSession       |

> 注意：首次使用 Telegram 机器人需要生成 `StringSession`，可本地运行 `bot.py` 相关脚本获取。

### 5. 清理工作流

- 进入 **Actions** → **清理仓库工作流** → **Run workflow**。
- 支持按保留数量或保留天数清理历史运行记录。

## 与旧 build.sh 的关系

- `build.sh` 为原项目脚本，使用 `proton-clang` 与 `ares_user_defconfig`。
- `build-ci.sh` 为新增脚本，读取 `config.env`，支持 AOSP Clang + GCC 组合，功能与 GitHub Actions 一致。
- 两者互不干扰，可按需选择使用。

## 故障排查

### 编译失败，未生成 Image.gz-dtb

1. 下载 `error-log-*` artifact 查看完整日志。
2. 检查 `config.env` 中的 `KERNEL_CONFIG` 是否存在。
3. 确认 patch 与当前内核版本兼容（4.14.186）。

### SUSFS patch 应用失败

SUSFS patch 可能随上游更新而变动。可在浏览器中打开 `config.env` 中使用的 patch URL 确认可访问性，必要时替换为其他兼容 patch。

### Clang 下载超时

如果 `CLANG_URL` 使用 git 仓库且网络较慢，可改为 tar.gz 直链或自行托管工具链。

## 参考

- 本系统参考 [OPPO-Realme_kernel_4.14_MT6853](https://github.com/wudixxqq/OPPO-Realme_kernel_4.14_MT6853) 的 `Build Kernel.yml`、`clean.yml`、`bot.py`、`config.env` 实现。
- chopin 内核基线：`wudixxqq/android_kernel_chopin_android_T`（fork 自 `froyoandroid/android_kernel_chopin_android_T`）。
