#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

if [[ $# -gt 0 ]]; then
  if [[ $# -eq 1 && "$1" == --help ]]; then
    printf '用法: bash ci/build/build-isolated.sh\n构建当前已提交的 HEAD, 全部输出位于 /tmp/vscode 下的独立目录.\n'
    exit 0
  fi
  fail '不支持该参数, 使用 --help 查看用法.'
fi

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
for tool in git node npm quilt jq rsync nfpm envsubst timeout tar sha256sum; do
  command -v "$tool" >/dev/null || fail "缺少工具: $tool"
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail '当前入口仅支持 x86_64 Linux.'
source_commit=$(git -C "$repo_root" rev-parse HEAD)
vscode_commit=$(git -C "$repo_root" rev-parse HEAD:lib/vscode)
required_node=$(git -C "$repo_root/lib/vscode" show "$vscode_commit:.nvmrc")
node -e 'const current=process.versions.node.split(".").map(Number); const required=process.argv[1].trim().split(".").map(Number); if(current[0]!==required[0] || current[1]<required[1] || (current[1]===required[1] && current[2]<required[2])) process.exit(1)' "$required_node" || fail "Node 版本不符合要求, 请使用 $required_node 或同主版本的更新版本."
git -C "$repo_root" diff --quiet --ignore-submodules=all HEAD -- || fail '主仓库有未提交改动, 请先提交要构建的源码.'
[[ -z $(git -C "$repo_root" ls-files --others --exclude-standard) ]] || fail '主仓库存在未跟踪文件, 请先处理后再构建.'
version=$(git -C "$repo_root" describe --tags --match 'v[0-9]*' --abbrev=0 "$source_commit")
version=${version#v}
version="${version%%-*}-byok-${source_commit:0:7}"
mkdir -p /tmp/vscode
build_root=$(mktemp -d "/tmp/vscode/build-${source_commit:0:7}-XXXXXX")
export TMPDIR="$build_root/tmp" npm_config_cache="$build_root/npm-cache"
export XDG_CACHE_HOME="$build_root/cache" GIT_CONFIG_NOSYSTEM=1
export npm_config_devdir="$build_root/node-gyp" ELECTRON_CACHE="$build_root/electron-cache"
export PLAYWRIGHT_BROWSERS_PATH="$build_root/playwright"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=8192}"
export VERSION="$version" RELEASE_PATH=release KEEP_MODULES=1 MINIFY=true CI=1
export VSCODE_TARGET=linux-x64 ARCH=amd64
mkdir -p "$TMPDIR" "$npm_config_cache" "$XDG_CACHE_HOME" "$build_root/logs"
trap 'printf "构建失败或中断, 日志和中间产物保留在: %s\n" "$build_root" >&2' ERR

run_step() {
  local label=$1
  local limit=$2
  shift 2
  printf '开始: %s, 日志: %s/logs/%s.log\n' "$label" "$build_root" "$label"
  if ! timeout -k 30s "$limit" "$@" >"$build_root/logs/$label.log" 2>&1; then
    tail -n 60 "$build_root/logs/$label.log" >&2
    fail "步骤失败: $label, 构建目录: $build_root"
  fi
}

run_step source 10m git clone --no-hardlinks --no-checkout "$repo_root" "$build_root/source"
cd "$build_root/source"
run_step checkout 2m git -c core.hooksPath=/dev/null checkout --detach "$source_commit"
run_step vscode-source 10m git clone --no-hardlinks --no-checkout "$repo_root/lib/vscode" lib/vscode
run_step vscode-checkout 2m git -C lib/vscode -c core.hooksPath=/dev/null checkout --detach "$vscode_commit"
run_step patches 5m quilt push -a --fuzz=0
run_step dependencies 60m env SKIP_SUBMODULE_DEPS=1 npm ci --foreground-scripts
run_step vscode-dependencies 90m npm --prefix lib/vscode ci --foreground-scripts
run_step code-server 15m npm run build
run_step vscode 180m npm run build:vscode
run_step release 90m npm run release

run_step metadata 2m node - "$source_commit" "$VERSION" <<'NODE'
const fs = require('fs');
const commit = process.argv[2];
const version = process.argv[3];
const product = JSON.parse(fs.readFileSync('release/lib/vscode/product.json', 'utf8'));
const pkg = JSON.parse(fs.readFileSync('release/package.json', 'utf8'));
if (product.commit !== commit || product.quality !== 'stable' || pkg.commit !== commit || pkg.version !== version) {
  throw new Error('发布版本元数据不一致.');
}
const bundle = fs.readFileSync('release/lib/vscode/out/vs/code/browser/workbench/workbench.js', 'utf8');
if (!bundle.includes(commit) || !/quality\s*:\s*["']stable["']|"quality"\s*:\s*"stable"/.test(bundle)) {
  throw new Error('前端 bundle 缺少预期的 commit 或 stable quality.');
}
NODE
run_step package 60m npm run package
cd release-packages
sha256sum ./*.deb ./*.rpm ./*.tar.gz > SHA256SUMS
printf '构建成功.\n源码提交: %s\n产物目录: %s/source/release-packages\n日志目录: %s/logs\n' "$source_commit" "$build_root" "$build_root"