#!/usr/bin/env bash
#
# OpenCode 离线安装脚本（Linux）
#
# 特点:
#   * 完全离线: 不使用 curl/wget，所有二进制都在本目录 binaries/ 下
#   * 不依赖 Node.js: 安装的是官方独立可执行文件（standalone binary）
#   * 自动识别平台: x86_64/aarch64、glibc/musl、是否需要 baseline（无 AVX2 的 CPU）
#   * 默认安装到 ~/.opencode/bin（与官方安装器一致）
#
# 用法: ./install.sh [选项]   （./install.sh --help 查看全部选项）
#
set -euo pipefail

APP="opencode"
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$BUNDLE_DIR/binaries"
VERSION="$(cat "$BUNDLE_DIR/VERSION" 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
    VERSION="unknown"
fi

RED=$'\033[0;31m'
ORANGE=$'\033[38;5;214m'
MUTED=$'\033[0;2m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

ALL_VARIANTS=(linux-x64 linux-x64-baseline linux-x64-musl linux-x64-baseline-musl linux-arm64 linux-arm64-musl)

die()  { printf '%s\n' "${RED}错误: $*${NC}" >&2; exit 1; }
warn() { printf '%s\n' "${ORANGE}警告: $*${NC}" >&2; }
note() { printf '%s\n' "$*"; }
gray() { printf '%s\n' "${MUTED}$*${NC}"; }

usage() {
    cat <<'EOF'
OpenCode 离线安装脚本（Linux）

用法:
  ./install.sh [选项]

选项:
  -h, --help               显示本帮助
      --list               列出离线包中包含的平台版本
      --variant <名称>     强制使用指定平台版本（默认自动识别）
  -d, --install-dir <目录> 安装目录（默认: ~/.opencode/bin）
      --system             安装到 /usr/local/bin（需要 root 或 sudo）
      --no-modify-path     不修改 shell 配置文件（如 ~/.bashrc）
      --init-config        如不存在则创建基础配置文件 ~/.config/opencode/opencode.json

示例:
  ./install.sh                             # 自动识别平台并安装到 ~/.opencode/bin
  ./install.sh --system                    # 安装到 /usr/local/bin
  ./install.sh --install-dir /opt/opencode --no-modify-path
  ./install.sh --variant linux-x64-musl    # Alpine 等 musl 系统
EOF
}

bundled_variants() {
    local v
    for v in "${ALL_VARIANTS[@]}"; do
        if [[ -f "$BIN_DIR/$v/$APP" ]]; then
            printf '%s\n' "$v"
        fi
    done
}

# ---------- 参数解析 ----------
use_system=false
no_modify_path=false
init_config=false
list_bundled=false
forced_variant=""
install_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        --list)
            list_bundled=true; shift ;;
        --variant)
            [[ -n "${2:-}" ]] || die "--variant 需要一个参数"
            forced_variant="$2"; shift 2 ;;
        -d|--install-dir)
            [[ -n "${2:-}" ]] || die "--install-dir 需要一个参数"
            install_dir="$2"; shift 2 ;;
        --system)
            use_system=true; shift ;;
        --no-modify-path)
            no_modify_path=true; shift ;;
        --init-config)
            init_config=true; shift ;;
        *)
            die "未知参数: $1（用 --help 查看用法）" ;;
    esac
done

if [[ "$list_bundled" == true ]]; then
    note "离线包版本: $VERSION"
    note "包含的平台版本:"
    while IFS= read -r v; do
        note "  - $v"
    done < <(bundled_variants)
    exit 0
fi

# ---------- 平台识别（与官方安装器一致的规则） ----------
detect_variant_candidates() {
    local raw_os arch is_musl=false needs_baseline=false

    raw_os="$(uname -s)"
    if [[ "$raw_os" != "Linux" ]]; then
        die "此离线包只包含 Linux 版二进制，当前系统: $raw_os"
    fi

    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) die "不支持的 CPU 架构: $arch" ;;
    esac

    if [[ -f /etc/alpine-release ]]; then
        is_musl=true
    elif command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
        is_musl=true
    fi

    if [[ "$arch" == "x64" ]]; then
        if ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
            needs_baseline=true
        fi
        if [[ "$is_musl" == true && "$needs_baseline" == true ]]; then
            printf '%s\n' linux-x64-baseline-musl linux-x64-musl linux-x64-baseline linux-x64
        elif [[ "$is_musl" == true ]]; then
            printf '%s\n' linux-x64-musl linux-x64-baseline-musl linux-x64 linux-x64-baseline
        elif [[ "$needs_baseline" == true ]]; then
            printf '%s\n' linux-x64-baseline linux-x64 linux-x64-baseline-musl linux-x64-musl
        else
            printf '%s\n' linux-x64 linux-x64-baseline linux-x64-musl linux-x64-baseline-musl
        fi
    else
        if [[ "$is_musl" == true ]]; then
            printf '%s\n' linux-arm64-musl linux-arm64
        else
            printf '%s\n' linux-arm64 linux-arm64-musl
        fi
    fi
}

# ---------- 安装目录 ----------
if [[ -n "$install_dir" && "$use_system" == true ]]; then
    die "同时指定 --system 与 --install-dir 没有意义，请二选一"
fi

if [[ "$use_system" == true ]]; then
    INSTALL_DIR="/usr/local/bin"
else
    install_dir="${install_dir/#\~/$HOME}"
    INSTALL_DIR="${install_dir:-$HOME/.opencode/bin}"
fi

as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        die "需要 root 权限（或 sudo）来写入 $INSTALL_DIR"
    fi
}

if [[ "$use_system" == true ]]; then
    as_root mkdir -p "$INSTALL_DIR"
else
    mkdir -p "$INSTALL_DIR" || die "无法创建目录 $INSTALL_DIR（可尝试 --system 或检查权限）"
    if [[ ! -w "$INSTALL_DIR" ]]; then
        die "目录不可写: $INSTALL_DIR"
    fi
fi

# ---------- 选择候选平台版本 ----------
candidates=()
if [[ -n "$forced_variant" ]]; then
    if [[ ! -f "$BIN_DIR/$forced_variant/$APP" ]]; then
        die "离线包中没有 '$forced_variant'（可用: $(bundled_variants | tr '\n' ' ')）"
    fi
    candidates=("$forced_variant")
else
    detected="$(detect_variant_candidates)"
    while IFS= read -r v; do
        [[ -n "$v" ]] || continue
        if [[ -f "$BIN_DIR/$v/$APP" ]]; then
            candidates+=("$v")
        fi
    done <<< "$detected"
    if [[ ${#candidates[@]} -eq 0 ]]; then
        die "离线包中没有可用于当前机器的二进制（包含: $(bundled_variants | tr '\n' ' ')）"
    fi
fi

# ---------- 完整性校验 ----------
verify_bundle() {
    local sums="$BUNDLE_DIR/SHA256SUMS"
    if [[ ! -f "$sums" ]]; then
        warn "未找到 SHA256SUMS，跳过完整性校验"
        return 0
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        if ! (cd "$BUNDLE_DIR" && sha256sum -c --status SHA256SUMS); then
            die "完整性校验失败：文件可能已损坏，请重新解压离线包"
        fi
    elif command -v shasum >/dev/null 2>&1; then
        if ! (cd "$BUNDLE_DIR" && shasum -a 256 -c --status SHA256SUMS); then
            die "完整性校验失败：文件可能已损坏，请重新解压离线包"
        fi
    else
        warn "系统缺少 sha256sum，跳过完整性校验"
        return 0
    fi
    gray "完整性校验通过 (SHA256SUMS)"
}

# ---------- 安装与验证 ----------
copy_binary() {
    local src="$1" tmp="$INSTALL_DIR/.${APP}.new.$$"
    if [[ "$use_system" == true ]]; then
        as_root cp -f "$src" "$tmp"
        as_root chmod 755 "$tmp"
        as_root mv -f "$tmp" "$INSTALL_DIR/$APP"
    else
        cp -f "$src" "$tmp"
        chmod 755 "$tmp"
        mv -f "$tmp" "$INSTALL_DIR/$APP"
    fi
}

binary_version() {
    local bin="$1" out
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 60 "$bin" --version 2>&1)" || return 1
    else
        out="$("$bin" --version 2>&1)" || return 1
    fi
    printf '%s' "$out"
}

if command -v "$APP" >/dev/null 2>&1; then
    gray "检测到已安装的 $APP: $(command -v "$APP")（$("$APP" --version 2>/dev/null || true)）"
fi

gray "离线包版本: $VERSION"
gray "安装目录:   $INSTALL_DIR"
verify_bundle

installed_variant=""
last_error=""
output=""
for variant in "${candidates[@]}"; do
    if [[ ${#candidates[@]} -gt 1 ]]; then
        gray "尝试平台版本: $variant"
    fi
    copy_binary "$BIN_DIR/$variant/$APP"
    if output="$(binary_version "$INSTALL_DIR/$APP")"; then
        installed_variant="$variant"
        break
    fi
    last_error="$output"
    warn "平台版本 $variant 在当前系统无法运行，尝试下一个可用版本..."
done

if [[ -z "$installed_variant" ]]; then
    die "没有可用于当前机器的二进制（最后一次错误: ${last_error:-未知}）"
fi

# 兼容旧命令名的 shim（与官方安装器一致）
if [[ "$use_system" == true ]]; then
    as_root tee "$INSTALL_DIR/opencode2" >/dev/null <<'SHIM'
#!/bin/sh
exec "$(dirname "$0")/opencode" "$@"
SHIM
    as_root chmod 755 "$INSTALL_DIR/opencode2"
else
    cat > "$INSTALL_DIR/opencode2" <<'SHIM'
#!/bin/sh
exec "$(dirname "$0")/opencode" "$@"
SHIM
    chmod 755 "$INSTALL_DIR/opencode2"
fi

# ---------- PATH 配置 ----------
add_to_path() {
    local config_file="$1" command="$2"
    if grep -Fxq "$command" "$config_file" 2>/dev/null; then
        gray "已存在于 $config_file，跳过。"
    elif [[ -w "$config_file" ]]; then
        printf '\n# opencode\n%s\n' "$command" >> "$config_file"
        note "${MUTED}已将 opencode 加入 PATH: ${NC}$config_file"
    else
        warn "请手动把下面这行加到 $config_file:"
        note "  $command"
    fi
}

if [[ "$no_modify_path" != true && "$use_system" != true ]]; then
    case ":$PATH:" in
        *":$INSTALL_DIR:"*)
            gray "PATH 中已包含 $INSTALL_DIR，跳过 shell 配置。"
            ;;
        *)
            XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
            current_shell="$(basename "${SHELL:-bash}")"
            case "$current_shell" in
                fish)
                    config_files="$HOME/.config/fish/config.fish"
                    ;;
                zsh)
                    config_files="${ZDOTDIR:-$HOME}/.zshrc ${ZDOTDIR:-$HOME}/.zshenv $XDG_CONFIG_HOME/zsh/.zshrc $XDG_CONFIG_HOME/zsh/.zshenv"
                    ;;
                bash)
                    config_files="$HOME/.bashrc $HOME/.bash_profile $HOME/.profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
                    ;;
                ash|sh)
                    config_files="$HOME/.ashrc $HOME/.profile /etc/profile"
                    ;;
                *)
                    config_files="$HOME/.bashrc $HOME/.bash_profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
                    ;;
            esac

            config_file=""
            for f in $config_files; do
                if [[ -f "$f" ]]; then
                    config_file="$f"
                    break
                fi
            done

            if [[ -z "$config_file" ]]; then
                warn "未找到 shell 配置文件，请手动把下面这行加入你的 shell 配置:"
                note "  export PATH=$INSTALL_DIR:\$PATH"
            elif [[ "$current_shell" == "fish" ]]; then
                add_to_path "$config_file" "fish_add_path $INSTALL_DIR"
            else
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            fi
            ;;
    esac
fi

if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "${GITHUB_PATH:-}" ]]; then
    echo "$INSTALL_DIR" >> "$GITHUB_PATH"
fi

# ---------- 可选：生成基础配置 ----------
if [[ "$init_config" == true ]]; then
    cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    cfg_file="$cfg_dir/opencode.json"
    mkdir -p "$cfg_dir"
    if [[ -f "$cfg_file" ]]; then
        gray "配置文件已存在，未修改: $cfg_file"
    else
        printf '{\n  "$schema": "https://opencode.ai/config.json"\n}\n' > "$cfg_file"
        note "${GREEN}已创建基础配置: $cfg_file${NC}"
    fi
fi

# ---------- 完成 ----------
note ""
note "${GREEN}OpenCode $VERSION 安装完成！${NC}"
note "  可执行文件: $INSTALL_DIR/$APP"
note "  平台版本:   $installed_variant"
note "  版本输出:   $output"
note ""
note "快速开始:"
if [[ "$use_system" == true ]]; then
    note "  opencode             # 直接运行（/usr/local/bin 通常已在 PATH 中）"
else
    note "  当前终端:  export PATH=\"$INSTALL_DIR:\$PATH\""
    note "  新开终端会自动生效"
    note "  opencode             # 启动 TUI"
fi
note "  在 TUI 中执行 /connect 连接模型提供商"
note "  文档: https://opencode.ai/v2/docs"
