#!/usr/bin/env bash
# 构建 daidai-panel-fn 的 fnOS 应用包（.fpk）。
#
# 重要：.fpk 的格式是 **gzip 压缩的 tar**，不是 zip。
# 之前用 zip 打包，应用中心解析不了，install-fpk 会报
#   POST /app-center/v1/download/upload failed: {"code":10111,"msg":""}
# 现在按 fnOS 官方包结构生成：
#
#   <name>.fpk  (gzip tar)
#   ├── manifest
#   ├── ICON.PNG / ICON_256.PNG
#   ├── cmd/            (main + install/upgrade/uninstall/config 各 *_init/_callback)
#   ├── config/         (privilege, resource)
#   ├── wizard/         (安装向导，可为空目录)
#   └── app.tgz         (gzip tar；内容 = app/ 与 config/ 合并，即安装后的 target/)
#
# 优先使用官方 fnpack（若已安装）；否则用内置的纯 Python 打包器，保证 CI 无额外依赖。

set -euo pipefail
cd "$(dirname "$0")"

VERSION="${BUILD_VERSION:-}"
if [[ -z "${VERSION}" ]]; then
  VERSION="$(grep -E '^version=' manifest | head -n1 | cut -d= -f2- | tr -d '[:space:]')"
fi
[[ -n "${VERSION}" ]] || { echo "ERROR: cannot determine version" >&2; exit 1; }

if [[ -n "${BUILD_VERSION:-}" ]]; then
  sed -i.bak "s/^version=.*/version=${BUILD_VERSION}/" manifest && rm -f manifest.bak
fi

echo "==> version ${VERSION}"

# --- 前置校验：官方 fnpack 要求的必需文件 ---
for f in manifest ICON.PNG ICON_256.PNG cmd/main config/privilege config/resource; do
  [[ -e "$f" ]] || { echo "ERROR: required file missing: $f" >&2; exit 1; }
done
mkdir -p wizard

chmod +x cmd/* 2>/dev/null || true

rm -rf dist
mkdir -p dist

FPK="dist/daidai-panel-fn-${VERSION}.fpk"

if command -v fnpack >/dev/null 2>&1; then
  echo "==> using fnpack"
  fnpack build
  mv -f daidai-panel-fn.fpk "$FPK"
else
  echo "==> using built-in packer"
  python3 - "$FPK" <<'PY'
import io
import pathlib
import sys
import tarfile

root = pathlib.Path.cwd()
out = pathlib.Path(sys.argv[1])

SKIP_DIRS = {'dist', '.git', '.github'}


def add_tree(tf, src_root, arc_prefix='', skip_top=frozenset()):
    """把 src_root 下的内容按相对路径写进 tar。"""
    if arc_prefix:
        # 显式写出前缀目录本身，与 fnpack 的产物保持一致
        ti = tarfile.TarInfo(str(pathlib.PurePosixPath(arc_prefix)))
        ti.type = tarfile.DIRTYPE
        ti.mode = src_root.stat().st_mode & 0o777
        tf.addfile(ti)
    for p in sorted(src_root.rglob('*')):
        rel = p.relative_to(src_root)
        if rel.parts and rel.parts[0] in skip_top:
            continue
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if p.name == '.DS_Store' or p.suffix == '.pyc':
            continue
        arc = str(pathlib.PurePosixPath(arc_prefix) / pathlib.PurePosixPath(*rel.parts)) \
            if arc_prefix else str(pathlib.PurePosixPath(*rel.parts))
        if p.is_dir():
            ti = tarfile.TarInfo(arc)
            ti.type = tarfile.DIRTYPE
            ti.mode = p.stat().st_mode & 0o777
            tf.addfile(ti)
        else:
            data = p.read_bytes()
            ti = tarfile.TarInfo(arc)
            ti.size = len(data)
            ti.mode = p.stat().st_mode & 0o777
            tf.addfile(ti, io.BytesIO(data))


# 1) app.tgz = app/ 内容 + config/ 内容（即安装后的 target/ 目录）
#    注意前缀：app/ 的内容平铺到根（docker/、ui/），
#    而 config/ 必须保留目录名（config/privilege、config/resource）——
#    fnOS 安装后 target/ 的布局正是 config/{privilege,resource} + docker/ + ui/。
#    之前这里漏了 config 前缀，导致 CI（无 fnpack，走内置打包器）产出的包里
#    privilege/resource 落在根目录，安装后 target/config/ 为空、权限声明失效。
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w:gz') as tf:
    d = root / 'app'
    if d.is_dir():
        add_tree(tf, d)
    d = root / 'config'
    if d.is_dir():
        add_tree(tf, d, arc_prefix='config')
app_tgz = buf.getvalue()

# 2) 外层 .fpk = gzip tar
with tarfile.open(out, mode='w:gz') as tf:
    def add_bytes(name, data, mode=0o644):
        ti = tarfile.TarInfo(name)
        ti.size = len(data)
        ti.mode = mode
        tf.addfile(ti, io.BytesIO(data))

    for name in ('manifest', 'ICON.PNG', 'ICON_256.PNG'):
        p = root / name
        if p.is_file():
            add_bytes(name, p.read_bytes())

    add_bytes('app.tgz', app_tgz)

    for sub in ('cmd', 'config', 'wizard'):
        d = root / sub
        if d.is_dir():
            add_tree(tf, d, arc_prefix=sub)

print('wrote', out)
PY
fi

# 便于 CI / fndepot 取用的稳定文件名
cp -f "$FPK" dist/daidai-panel-fn.fpk

echo "==> verifying"
file "$FPK"
tar tzf "$FPK" | sed 's/^/    /'
ls -l "$FPK"
