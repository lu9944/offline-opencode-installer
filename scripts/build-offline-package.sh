#!/usr/bin/env bash
#
# 构建 OpenCode Linux 离线安装包
#
# 在 GitHub Actions（或任意联网 Linux）上运行。
#
# 数据来源: npm registry 上的官方平台包 @opencode/cli-<target>
#   即官方安装器 https://opencode.ai/v2/install 使用的同一分发渠道。
#   该包内只有官方独立可执行文件（standalone ELF binary），运行时
#   不依赖 Node.js。本脚本会将其解压后原样放入离线包的 binaries/ 目录。
#
# 用法:
#   scripts/build-offline-package.sh --version 2.0.29 [--variants all]
#                                    [--out-dir dist] [--work-dir .build]
#                                    [--keep-work] [--no-smoke-test]
#
# 参数:
#   -v, --version <版本>    opencode 版本号（如 2.0.29 / v2.0.29 / latest）
#       --variants <列表>   all 或逗号分隔（linux-x64,linux-arm64,...），默认 all
#   -o, --out-dir <目录>    输出目录，默认 <仓库根>/dist
#   -w, --work-dir <目录>   工作目录，默认 <仓库根>/.build
#       --keep-work         保留工作目录（调试用）
#       --no-smoke-test     跳过构建机上的二进制运行冒烟测试
#   -h, --help              显示帮助
#
set -euo pipefail

ALL_VARIANTS=(
    linux-x64
    linux-x64-baseline
    linux-x64-musl
    linux-x64-baseline-musl
    linux-arm64
    linux-arm64-musl
)

REGISTRY="https://registry.npmjs.org"
NPM_SCOPES=("@opencode" "@opencode-ai")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

version="latest"
variants_input="all"
out_dir="$REPO_DIR/dist"
work_dir="$REPO_DIR/.build"
keep_work=false
smoke_test=true

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }

usage() {
    sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            [[ -n "${2:-}" ]] || die "--version 需要一个参数"
            version="$2"; shift 2 ;;
        --variants)
            [[ -n "${2:-}" ]] || die "--variants 需要一个参数"
            variants_input="$2"; shift 2 ;;
        -o|--out-dir)
            [[ -n "${2:-}" ]] || die "--out-dir 需要一个参数"
            out_dir="$2"; shift 2 ;;
        -w|--work-dir)
            [[ -n "${2:-}" ]] || die "--work-dir 需要一个参数"
            work_dir="$2"; shift 2 ;;
        --keep-work)
            keep_work=true; shift ;;
        --no-smoke-test)
            smoke_test=false; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            die "未知参数: $1（用 --help 查看用法）" ;;
    esac
done

# ---------- 预检 ----------
for tool in curl tar python3 sha256sum zip; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少必要工具: $tool"
done

# ---------- 解析版本 ----------
if [[ "$version" == "latest" ]]; then
    log "解析最新版本（latest）..."
    term_meta="$(curl -fsSL --retry 3 --retry-delay 2 "$REGISTRY/@opencode%2Fcli/latest")" \
        || die "无法获取最新版本号"
    version="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["version"])' <<<"$term_meta")"
fi
version="${version#v}"
if [[ ! "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
    die "非法版本号: $version"
fi
log "目标版本: $version"

# ---------- 解析平台变体 ----------
selected=()
if [[ "$variants_input" == "all" ]]; then
    selected=("${ALL_VARIANTS[@]}")
else
    IFS=',' read -r -a selected <<< "$variants_input"
    for v in "${selected[@]}"; do
        if [[ " ${ALL_VARIANTS[*]} " != *" $v "* ]]; then
            die "未知平台变体: $v（可用: ${ALL_VARIANTS[*]}）"
        fi
    done
fi
log "平台变体: ${selected[*]}"

# ---------- 准备目录 ----------
rm -rf "$work_dir"
mkdir -p "$work_dir/tarballs" "$work_dir/extract" "$work_dir/stage" "$out_dir"
: > "$out_dir/SHA256SUMS"

# ---------- 校验函数 ----------
verify_integrity() {
    local file="$1" spec="$2"
    if [[ -z "$spec" ]]; then
        log "警告: 元数据缺少校验和，跳过 $file 的完整性校验"
        return 0
    fi
    python3 - "$file" "$spec" <<'PY'
import base64
import hashlib
import sys

path, spec = sys.argv[1], sys.argv[2]
alg, _, expected = spec.partition("-")
h = hashlib.new(alg)
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
if alg == "sha1":
    actual = h.hexdigest()
else:
    actual = base64.b64encode(h.digest()).decode()
sys.exit(0 if actual == expected else 1)
PY
}

# ---------- 下载并解压 ----------
for variant in "${selected[@]}"; do
    tarball="$work_dir/tarballs/cli-$variant-$version.tgz"
    meta_file="$work_dir/meta-$variant.json"
    url=""
    integrity=""
    code=""

    for scope in "${NPM_SCOPES[@]}"; do
        code="$(curl -sS -o "$meta_file" -w '%{http_code}' --retry 3 --retry-delay 2 \
            "$REGISTRY/$scope%2Fcli-$variant/$version")"
        if [[ "$code" == "200" ]]; then
            break
        fi
        if [[ "$code" != "404" ]]; then
            die "获取 $variant 元数据失败 (HTTP $code)"
        fi
    done
    if [[ "$code" != "200" ]]; then
        die "版本 $version 没有 $variant 平台（npm registry 上不存在，请检查版本号）"
    fi

    url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["dist"]["tarball"])' "$meta_file")"
    integrity="$(python3 -c '
import json, sys
dist = json.load(open(sys.argv[1]))["dist"]
value = dist.get("integrity") or ""
if not value and dist.get("shasum"):
    value = "sha1-" + dist["shasum"]
print(value)
' "$meta_file")"

    log "下载 $variant: $url"
    curl -fSL --retry 3 --retry-delay 2 -o "$tarball" "$url" || die "下载失败: $url"
    verify_integrity "$tarball" "$integrity" || die "$variant 校验失败（文件损坏或被篡改）"

    extract_dir="$work_dir/extract/$variant"
    mkdir -p "$extract_dir"
    tar -xzf "$tarball" -C "$extract_dir" package/bin/opencode
    [[ -f "$extract_dir/package/bin/opencode" ]] || die "$variant 包内未找到 package/bin/opencode"
done

# ---------- 构建机上的冒烟测试 ----------
native_variants() {
    [[ "$(uname -s)" == "Linux" ]] || return 0
    if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
        return 0
    fi
    local with_avx2=false
    case "$(uname -m)" in
        x86_64)
            if grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
                with_avx2=true
            fi
            if [[ "$with_avx2" == true ]]; then
                printf '%s\n' linux-x64
            fi
            printf '%s\n' linux-x64-baseline
            ;;
        aarch64)
            printf '%s\n' linux-arm64
            ;;
    esac
}

if [[ "$smoke_test" == true ]]; then
    native_list=" $(native_variants | tr '\n' ' ')"
    for variant in "${selected[@]}"; do
        if [[ "$native_list" == *" $variant "* ]]; then
            log "冒烟测试 $variant ..."
            bin="$work_dir/extract/$variant/package/bin/opencode"
            out="$(timeout 60 "$bin" --version 2>&1)" || die "$variant 在构建机上无法运行"
            if [[ "$out" != *"$version"* ]]; then
                die "$variant 版本不符: $out"
            fi
            log "  -> $out"
        fi
    done
fi

# ---------- 组装离线包 ----------
suffix_for() {
    if [[ ${#selected[@]} -eq 1 ]]; then
        printf '%s' "${selected[0]}"
    elif [[ ${#selected[@]} -eq ${#ALL_VARIANTS[@]} ]]; then
        printf 'linux-all'
    else
        local parts=() v
        for v in "${selected[@]}"; do
            parts+=("${v#linux-}")
        done
        local IFS='-'
        printf 'linux-%s' "${parts[*]}"
    fi
}

bundle_suffix="$(suffix_for)"
bundle_name="opencode-offline-$version-$bundle_suffix"
bundle_dir="$work_dir/stage/$bundle_name"

mkdir -p "$bundle_dir/binaries"
cp "$REPO_DIR/installer/install.sh" "$bundle_dir/install.sh"
cp "$REPO_DIR/installer/README.md" "$bundle_dir/README.md"
chmod 755 "$bundle_dir/install.sh"
printf '%s\n' "$version" > "$bundle_dir/VERSION"
sed -i "s/__VERSION__/$version/g" "$bundle_dir/README.md"

for variant in "${selected[@]}"; do
    mkdir -p "$bundle_dir/binaries/$variant"
    install -m 755 "$work_dir/extract/$variant/package/bin/opencode" "$bundle_dir/binaries/$variant/opencode"
done

(cd "$bundle_dir" && sha256sum install.sh README.md VERSION binaries/*/opencode > SHA256SUMS)

out_abs="$(cd "$out_dir" && pwd)"
log "打包 $bundle_name.zip ..."
(cd "$work_dir/stage" && zip -r -q "$out_abs/$bundle_name.zip" "$bundle_name")
(cd "$out_dir" && sha256sum "$bundle_name.zip" >> SHA256SUMS)

{
    echo "version=$version"
    echo "variants=${selected[*]}"
    echo "bundle=$bundle_name.zip"
} > "$out_dir/BUILD_INFO"

# ---------- 清理与汇总 ----------
if [[ "$keep_work" != true ]]; then
    rm -rf "$work_dir"
fi

log "构建完成，输出目录: $out_dir"
ls -lh "$out_dir"
printf '\n'
cat "$out_dir/SHA256SUMS"
