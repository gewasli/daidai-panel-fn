#!/usr/bin/env bash
# 构建 daidai-panel-fn 的 fnOS 应用包（.fpk）。
#
# 输出：dist/daidai-panel-fn-{version}.fpk（用于 GitHub Release 与 fndepot 源）
# 行为：
#   - 拉取 manifest 里的 version（默认 1.0.0）
#   - 如设置 BUILD_VERSION 则覆写 manifest 的 version
#   - 打包整个项目目录成一个 .fpk（fnOS fndepot 接受的 app 包格式）

set -euo pipefail
cd "$(dirname "$0")"

mkdir -p dist

VERSION="${BUILD_VERSION:-1.0.0}"
if [[ -z "${BUILD_VERSION:-}" ]]; then
  VERSION="$(grep -E '^version=' manifest | head -n1 | cut -d= -f2-)"
fi

if [[ -n "${BUILD_VERSION:-}" ]] && [[ "${BUILD_VERSION}" != "${VERSION}" ]]; then
  sed -i "s/^version=.*/version=${BUILD_VERSION}/" manifest
fi

WORK="dist/daidai-panel-fn-${VERSION}"
rm -rf "${WORK}"
mkdir -p "${WORK}"

python3 - "${WORK}" <<'PY'
import pathlib
import shutil
import sys

work = pathlib.Path(sys.argv[1])
root = pathlib.Path.cwd()

# 排除开发辅助文件，只打包 fnOS 应用所需内容
exclude = {'dist', '.github', 'build.sh', 'icon_gen.py', 'README.md'}

for entry in sorted(root.iterdir()):
    if entry.name in exclude:
        continue
    if entry.is_dir():
        shutil.copytree(entry, work / entry.name)
    else:
        shutil.copy2(entry, work / entry.name)

for junk in work.rglob('*.pyc'):
    junk.unlink()
for junk in work.rglob('.DS_Store'):
    junk.unlink()
PY

fpk="dist/daidai-panel-fn-${VERSION}.fpk"
rm -f "${fpk}"

python3 - "${WORK}" "${fpk}" <<'PY'
import pathlib
import stat
import sys
import zipfile

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

if out.exists():
    out.unlink()

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for p in sorted(src.rglob('*')):
        arc = str(p.relative_to(src))
        if p.is_dir():
            # 目录 0755
            zi = zipfile.ZipInfo(arc + "/")
            zi.external_attr = (stat.S_IFDIR | 0o755) << 16
            z.writestr(zi, b"")
        else:
            zi = zipfile.ZipInfo(arc)
            # cmd/ 下的生命周期脚本必须可执行（fnOS 安装校验 chmod +x cmd/*）
            if p.parent.name == "cmd":
                zi.external_attr = (stat.S_IFREG | 0o755) << 16
            else:
                zi.external_attr = (stat.S_IFREG | 0o644) << 16
            z.writestr(zi, p.read_bytes())

print("wrote", out)
PY

ls -l "${fpk}"
