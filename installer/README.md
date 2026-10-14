# OpenCode __VERSION__ 离线安装包（Linux）

本包包含 OpenCode 官方编译的**独立可执行文件**（standalone binary）。
安装和运行**不需要 Node.js**，安装过程**不需要联网**。

## 快速开始

1. 解压并进入目录

   ```bash
   tar -xzf opencode-offline-*.tar.gz
   cd opencode-offline-*
   ```

2. 运行安装脚本

   ```bash
   ./install.sh                 # 自动识别平台，默认安装到 ~/.opencode/bin
   ./install.sh --system        # 或安装到 /usr/local/bin（需要 sudo）
   ```

3. 新开终端（或按脚本提示 export PATH），然后启动：

   ```bash
   opencode
   ```

   首次使用请在 TUI 中执行 `/connect` 连接模型提供商。

## 包内文件

| 文件 | 说明 |
| --- | --- |
| `binaries/<平台版本>/opencode` | 各平台独立可执行文件 |
| `install.sh` | 离线安装脚本（安装前校验 SHA256SUMS） |
| `SHA256SUMS` | 包内所有文件的 SHA-256 校验和 |
| `VERSION` | opencode 版本号 |
| `README.md` | 本文件 |

## 平台自动识别规则

| 系统环境 | 识别结果 |
| --- | --- |
| x86_64 + glibc + 支持 AVX2 | `linux-x64` |
| x86_64 + glibc + 无 AVX2（老 CPU） | `linux-x64-baseline` |
| x86_64 + musl（Alpine 等） | `linux-x64-musl` |
| x86_64 + musl + 无 AVX2 | `linux-x64-baseline-musl` |
| aarch64 + glibc | `linux-arm64` |
| aarch64 + musl | `linux-arm64-musl` |

安装脚本按优先级依次尝试包内存在的版本，并实际运行 `opencode --version`
验证是否正确，无法运行时会自动回退到其他版本（例如 libc 识别有误时）。

## install.sh 选项

```
-h, --help               显示帮助
    --list               列出离线包中包含的平台版本
    --variant <名称>     强制使用指定平台版本（默认自动识别）
-d, --install-dir <目录> 安装目录（默认: ~/.opencode/bin）
    --system             安装到 /usr/local/bin（需要 root 或 sudo）
    --no-modify-path     不修改 shell 配置文件（如 ~/.bashrc）
    --init-config        如不存在则创建基础配置文件 ~/.config/opencode/opencode.json
```

## 校验完整性

```bash
sha256sum -c SHA256SUMS
```

校验和由构建流水线生成（数据来自 npm registry 上的官方包并做了
SHA-512 校验），可对比 Release 页面上的 `SHA256SUMS` 确认传输完整。

## 常见问题

- **目标机器完全离线可以安装吗？**
  可以，安装不访问网络。但 OpenCode 调用模型需要能访问你配置的 LLM
  服务；内网环境可配置自建的 OpenAI 兼容端点（如 Ollama、vLLM 等）。
- **运行报 illegal instruction？**
  CPU 不支持 AVX2，用 `./install.sh --variant linux-x64-baseline`。
- **Alpine / musl 系统？**
  用 `./install.sh --variant linux-x64-musl` 或 `linux-arm64-musl`。
- **如何卸载？**
  删除安装目录（默认 `~/.opencode`）中的二进制即可；配置在
  `~/.config/opencode/`，按需保留或删除。
