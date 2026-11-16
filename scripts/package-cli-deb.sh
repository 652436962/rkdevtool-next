#!/usr/bin/env bash
# Package the standalone rkdevcli binary as a Debian package. Run on Linux
# after building the CLI:
#
#   cargo build --locked --release --manifest-path src-tauri/Cargo.toml \
#     --no-default-features --features headless-cli --bin rkdevcli
#   ./scripts/package-cli-deb.sh
#
# Only dpkg-deb is required. Files are installed as root via
# --root-owner-group, so fakeroot is not needed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="" arch="" bin="" out=""

usage() {
  cat <<'EOF'
usage: scripts/package-cli-deb.sh [--version V] [--arch ARCH] [--bin PATH] [--out FILE]

  --version  package version (default: version in src-tauri/tauri.conf.json)
  --arch     Debian architecture (default: detected from uname -m)
  --bin      rkdevcli binary (default: src-tauri/target/release/rkdevcli)
  --out      output .deb path (default: ./RKDevTool-Next-CLI_<version>_linux-x64.deb)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2:?missing value for --version}"; shift 2 ;;
    --arch) arch="${2:?missing value for --arch}"; shift 2 ;;
    --bin) bin="${2:?missing value for --bin}"; shift 2 ;;
    --out) out="${2:?missing value for --out}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$version" ]; then
  version="$(sed -n 's/^[[:space:]]*"version": "\([^"]*\)".*/\1/p' \
    "$root/src-tauri/tauri.conf.json" | head -n 1)"
fi
if [ -z "$version" ]; then
  echo "could not read version from tauri.conf.json; pass --version" >&2
  exit 1
fi

if [ -z "$arch" ]; then
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    armv7l|armv6l) arch=armhf ;;
    i386|i686) arch=i386 ;;
    *) echo "unsupported architecture: $(uname -m); pass --arch" >&2; exit 1 ;;
  esac
fi

if [ -z "$bin" ]; then
  bin="$root/src-tauri/target/release/rkdevcli"
fi
if [ ! -x "$bin" ]; then
  echo "missing binary: $bin (build the headless CLI first)" >&2
  exit 1
fi

if [ -z "$out" ]; then
  case "$arch" in
    amd64) suffix=linux-x64 ;;
    arm64) suffix=linux-arm64 ;;
    armhf) suffix=linux-armhf ;;
    *) suffix="linux-$arch" ;;
  esac
  out="$PWD/RKDevTool-Next-CLI_${version}_${suffix}.deb"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/stage"

install -d "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/share/doc/rkdevtool-next-cli"
install -m 755 "$bin" "$stage/usr/bin/rkdevcli"
install -m 644 "$root/README.md" "$root/LICENSE" "$stage/usr/share/doc/rkdevtool-next-cli/"
install -m 644 "$root/LICENSE" "$stage/usr/share/doc/rkdevtool-next-cli/copyright"

size="$(du -sk --exclude=DEBIAN "$stage" | cut -f1)"

cat > "$stage/DEBIAN/control" <<EOF
Package: rkdevtool-next-cli
Version: $version
Architecture: $arch
Maintainer: FantasyGmm <16450052+FantasyGmm@users.noreply.github.com>
Section: utils
Priority: optional
Depends: libc6 (>= 2.35)
Installed-Size: $size
Homepage: https://github.com/FantasyGmm/rkdevtool-next
Description: standalone CLI for RKDevTool Next
 rkdevcli talks to Rockchip Maskrom/Loader devices over USB to scan
 devices, inspect and unpack RKFW/RKAF firmware, and flash images or
 partitions without the desktop app or an external rkdeveloptool.
EOF

mkdir -p "$(dirname "$out")"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$out"
echo "built $out"
