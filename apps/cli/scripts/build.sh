#!/bin/sh
# Builds the medusa CLI tarball: a relocatable CPython 3.13 with medusa_cli and its pinned dependencies.
#
#   apps/cli/scripts/build.sh <version> <out dir>
#   apps/cli/scripts/build.sh -h | --help
#
# Writes <out dir>/medusa-cli-<version>-macos-arm64.tar.gz and its .sha256. Needs the network (python-build-standalone
# from GitHub, wheels from PyPI) and uv (~/.local/bin/uv or on PATH). The Python download is pinned by sha256 and
# cached in ~/Library/Caches/medusa-cli-build.
set -eu

python_release=20261013
python_version=3.13.16
python_sha256=16a5332fb0dcb77f163fc8f8cbccd95be1644cc53e68e5d2a79f50afd6680a0e
python_asset=cpython-$python_version+$python_release-aarch64-apple-darwin-install_only_stripped.tar.gz
python_url=https://github.com/astral-sh/python-build-standalone/releases/download/$python_release/$(printf %s "$python_asset" | sed 's/+/%2B/')

case ${1:-} in
  -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
esac
[ $# -eq 2 ] || { sed -n '4,5p' "$0" | sed 's/^# *//' >&2; exit 64; }
version=$1
out=$2
printf '%s\n' "$version" | grep -Eq '^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(-[a-z]{1,16}\.[0-9]{1,4})?$' \
  || { echo "build.sh: bad version: $version" >&2; exit 64; }

cli_dir=$(cd "$(dirname "$0")/.." && pwd)
uv=$(command -v uv 2>/dev/null || true)
[ -n "$uv" ] || uv=$HOME/.local/bin/uv
[ -x "$uv" ] || { echo "build.sh: uv not found" >&2; exit 1; }

cache=$HOME/Library/Caches/medusa-cli-build
mkdir -p "$cache" "$out"
out=$(cd "$out" && pwd)
if ! [ -f "$cache/$python_asset" ] || [ "$(shasum -a 256 "$cache/$python_asset" | awk '{ print $1 }')" != "$python_sha256" ]; then
  curl -fsSL --proto =https -o "$cache/$python_asset.part" "$python_url"
  mv "$cache/$python_asset.part" "$cache/$python_asset"
fi
actual=$(shasum -a 256 "$cache/$python_asset" | awk '{ print $1 }')
[ "$actual" = "$python_sha256" ] || { echo "build.sh: $python_asset checksum mismatch ($actual)" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/medusa-cli-build.XXXXXX")
trap 'rm -rf "$work"' EXIT
root=$work/medusa-cli-$version
mkdir -p "$root/bin"
tar -xzf "$cache/$python_asset" -C "$root"
python=$root/python/bin/python3
pyver=$("$python" -I -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
lib=$root/python/lib/python$pyver
site=$lib/site-packages

UV_CACHE_DIR=$cache/uv "$uv" pip install --quiet --python "$python" --break-system-packages --link-mode copy \
  --no-build --require-hashes -r "$cli_dir/requirements.lock"
cp -R "$cli_dir/medusa_cli" "$site/medusa_cli"
printf '__version__ = "%s"\n' "$version" >"$site/medusa_cli/__init__.py"

rm -rf "$lib/test" "$lib/idlelib" "$lib/tkinter" "$lib/turtledemo" "$lib/ensurepip" "$lib/lib2to3" \
  "$lib/turtle.py" "$lib/pydoc_data" "$lib"/config-* "$lib/lib-dynload"/_tkinter* \
  "$site"/pip "$site"/pip-* \
  "$root/python/include" "$root/python/share" "$root/python/lib/pkgconfig" \
  "$root/python/lib"/tcl* "$root/python/lib"/tk* "$root/python/lib"/itcl* "$root/python/lib"/thread* \
  "$root/python/lib"/libtcl* "$root/python/lib"/libtk* \
  "$root/python/bin"/idle* "$root/python/bin"/pydoc* "$root/python/bin"/2to3* "$root/python/bin"/pip* \
  "$root/python/bin"/python*-config "$root/python/lib"/libpython*.dylib
find "$root/python/bin" -type f ! -name "python$pyver" -delete
find "$root" \( -name tests -o -name test \) -type d -path '*/site-packages/*' -prune -exec rm -rf {} +
find "$root" \( -name '*.pyc' -o -name '*.a' -o -name RECORD -o -name INSTALLER -o -name REQUESTED -o -name direct_url.json \) -type f -delete
find "$root" -type l | while IFS= read -r link; do
  case $(readlink "$link") in
    /*|..|../*|*/../*|*/..) rm -f "$link" ;;
  esac
done
"$python" -I -c 'import medusa_cli.cli, pydoll, sqlite3, ssl, zoneinfo, ctypes, lzma' >/dev/null

cat >"$root/bin/medusa" <<'EOF'
#!/bin/sh
self=$0
while [ -L "$self" ]; do
  link=$(readlink "$self")
  case $link in
    /*) self=$link ;;
    *) self=$(dirname "$self")/$link ;;
  esac
done
root=$(cd -P "$(dirname "$self")/.." && pwd -P)
exec "$root/python/bin/python3" -I -m medusa_cli "$@"
EOF
chmod 755 "$root/bin/medusa"
mkdir "$root/.leases"
"$root/bin/medusa" --version >/dev/null
find "$root" -name __pycache__ -type d -prune -exec rm -rf {} +

tarball=medusa-cli-$version-macos-arm64.tar.gz
COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname wheel \
  -czf "$out/$tarball.part" -C "$work" "medusa-cli-$version"
mv "$out/$tarball.part" "$out/$tarball"
(cd "$out" && shasum -a 256 "$tarball" >"$tarball.sha256")
printf '%s\n' "$out/$tarball"
