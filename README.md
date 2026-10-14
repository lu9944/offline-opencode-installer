# offline-opencode-installer

使用 GitHub Actions 构建 [OpenCode](https://opencode.ai/v2/docs) 的 **Linux 离线安装包**。

- 内含 OpenCode 官方编译的**独立可执行文件**（standalone binary），**不依赖 Node.js**
- 支持指定任意 release 版本（如 `2.0.29`），或 `latest` 自动获取最新版
- 离线包解压后运行 `./install.sh` 即可完成安装，安装过程**无需联网**
- 自动识别目标平台：x86_64 / aarch64、glibc / musl、是否需要 baseline（无 AVX2 的 CPU）

## 工作原理

二进制来源是 npm registry 上的官方平台包 `@opencode/cli-<target>`
（即官方安装器 `curl -fsSL https://opencode.ai/v2/install | bash` 使用的同一渠道）。
该包内**只有独立可执行文件**，构建脚本会将其解压后原样放入离线包的
`binaries/` 目录，运行时不需要 Node.js。

## 使用方式（GitHub Actions）

1. 把本仓库推送到你的 GitHub 账号（或 fork）。
2. 打开 **Actions → Build Offline Installer → Run workflow**，填写参数：

   | 参数 | 说明 | 默认值 |
   | --- | --- | --- |
   | `version` | opencode 版本号，如 `2.0.29` / `v2.0.29`，或 `latest` | `latest` |
   | `variants` | `all` 或逗号分隔的平台列表（见下表） | `linux-x64,linux-arm64` |
   | `create_release` | 创建/更新 Release 并上传安装包 | `true` |
   | `upload_artifact` | 同时上传到 Actions Artifacts（私有仓库注意存储配额） | `false` |

3. 构建完成后，从 **Releases** 下载 `opencode-offline-<版本>-linux-*.tar.gz`
   （或从 Artifacts 下载）。

4. 把压缩包拷贝到目标 Linux 机器（U 盘 / scp / 内网传输均可）：

   ```bash
   tar -xzf opencode-offline-*.tar.gz
   cd opencode-offline-*
   ./install.sh              # 自动识别平台，默认安装到 ~/.opencode/bin
   ./install.sh --system     # 或安装到 /usr/local/bin（需要 sudo）
   ```

   然后新开终端运行 `opencode`，首次使用在 TUI 中执行 `/connect` 连接模型。

## 平台变体

| 变体 | 适用环境 |
| --- | --- |
| `linux-x64` | x86_64 + glibc（绝大多数服务器） |
| `linux-x64-baseline` | x86_64 + glibc + 不支持 AVX2 的老 CPU |
| `linux-x64-musl` | x86_64 + musl（Alpine 等） |
| `linux-x64-baseline-musl` | x86_64 + musl + 无 AVX2 |
| `linux-arm64` | aarch64 + glibc |
| `linux-arm64-musl` | aarch64 + musl |

> 只需给某一台机器用时，`variants` 填单个变体（如 `linux-x64`）包更小。

## 离线包内容

```
opencode-offline-<版本>-<变体>/
├── install.sh                  # 离线安装脚本（校验 → 解压安装 → PATH 配置 → 运行验证）
├── README.md                   # 使用说明
├── VERSION                     # opencode 版本号
├── SHA256SUMS                  # 全部文件校验和
└── binaries/
    └── <变体>/opencode         # 独立可执行文件
```

`install.sh` 常用选项：

```bash
./install.sh --list                              # 列出包内平台
./install.sh --install-dir /opt/opencode/bin     # 自定义安装目录
./install.sh --system                            # 安装到 /usr/local/bin
./install.sh --variant linux-x64-musl            # 强制指定平台
./install.sh --no-modify-path --init-config      # 不改 PATH、生成基础配置
```

## 本地构建（可选）

不依赖 GitHub Actions 也可以构建（本仓库的 CI 使用的就是同一个脚本）：

```bash
bash scripts/build-offline-package.sh --version 2.0.29 --variants linux-x64
# 产物在 dist/ 下
```

## 安全与校验

- 构建时对每个下载的官方包做 npm **SHA-512 integrity 校验**；
- 构建流水线自带**端到端自检**：解压产出的离线包 → 运行 `install.sh` 实际安装 → 执行 `opencode --version`，自检失败会阻断发布；
- 离线包内 `SHA256SUMS` 覆盖所有文件，`install.sh` 安装前自动校验；
- Release 页面同时提供整包 `SHA256SUMS`，可与下载文件比对。

## 已知说明

- 目标机器离线安装没问题，但 OpenCode 使用模型时需能访问你配置的
  LLM 服务；纯内网可配置自建的 OpenAI 兼容端点（Ollama、vLLM 等）。
- 默认只构建 x86_64（`linux-x64`）与 aarch64（`linux-arm64`）两个平台，
  压缩包约 180 MB；需要 Alpine(musl) 或老 CPU(baseline) 支持时，在
  `variants` 中追加对应变体即可（全部 6 个变体约 550 MB）。
- 私有仓库的 Actions Artifacts 受存储配额限制，故工作流默认
  `upload_artifact=false`，通过 Release 分发安装包。
