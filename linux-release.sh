#!/usr/bin/env bash
#
# Build the Linux release binaries of a tag: novacomd-<tag>-linux-{x86_64,arm64,armhf}, each with a .sha256, into
# release-<tag>/. The macOS ones come from .github/workflows/macos-release.yml.
#
#   ./linux-release.sh <tag>
#
# Needs git and podman or docker. The build runs in Ubuntu 18.04 (glibc 2.27), so the binaries run on older systems
# than the one building them; arm64 and armhf are cross-compiled there and started under qemu as a check.
#
# libusb-compat and libusb 1.0 are built from their release tarballs (checked against pinned SHA-256s) as static
# libraries and linked in, so a binary needs only the C library. Never the original libusb 0.1.12: after a USB timeout
# its blocking wait can hang novacomd for good (see install-novacomd.sh). libusb 1.0 is built static-only, so
# libusb-compat links it in rather than loading a libusb-1.0.so at run time; the build fails if a binary names one.
#
# Public domain.

set -euo pipefail

readonly LIBUSB_VERSION=1.0.30
readonly LIBUSB_SHA256=fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf
readonly COMPAT_VERSION=0.1.9
readonly COMPAT_SHA256=179d934676ad3bd172a5a37cf5c6351b8e9d7816feb3029252e79b30a518a3be
readonly IMAGE=docker.io/library/ubuntu:18.04

tag="${1:?usage: $0 <tag>}"
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null || { echo "no tag $tag in this repository" >&2; exit 1; }
if command -v podman >/dev/null 2>&1; then engine=podman; elif command -v docker >/dev/null 2>&1; then engine=docker
else echo "needs podman or docker" >&2; exit 1; fi

out="$PWD/release-$tag"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rm -rf "$out"; mkdir -p "$out" "$work/src"
git archive "$tag" | tar -x -C "$work/src"

cat > "$work/build.sh" <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture arm64; dpkg --add-architecture armhf
sed -i 's|^deb http://archive.ubuntu.com|deb [arch=amd64] http://archive.ubuntu.com|; s|^deb http://security.ubuntu.com|deb [arch=amd64] http://security.ubuntu.com|' /etc/apt/sources.list
for s in bionic bionic-updates bionic-security; do echo "deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports $s main universe" >> /etc/apt/sources.list; done
apt-get -qq update >/dev/null
apt-get -qq install -y build-essential gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf pkg-config curl ca-certificates bzip2 qemu-user file >/dev/null

mkdir -p /x/dl && cd /x/dl
curl -fsSLO "https://github.com/libusb/libusb/releases/download/v$LIBUSB_VERSION/libusb-$LIBUSB_VERSION.tar.bz2"
curl -fsSLO "https://github.com/libusb/libusb-compat-0.1/releases/download/v$COMPAT_VERSION/libusb-compat-$COMPAT_VERSION.tar.bz2"
echo "$LIBUSB_SHA256  libusb-$LIBUSB_VERSION.tar.bz2" | sha256sum -c -
echo "$COMPAT_SHA256  libusb-compat-$COMPAT_VERSION.tar.bz2" | sha256sum -c -

for spec in x86_64:x86_64-linux-gnu: arm64:aarch64-linux-gnu:aarch64-linux-gnu- armhf:arm-linux-gnueabihf:arm-linux-gnueabihf-; do
	IFS=: read -r name triple pre <<<"$spec"
	p=/x/$name; mkdir -p "$p"
	# libusb 1.0, static only: without a shared one to find, libusb-compat links it in
	rm -rf /x/b && mkdir /x/b && tar -xjf "/x/dl/libusb-$LIBUSB_VERSION.tar.bz2" -C /x/b && cd "/x/b/libusb-$LIBUSB_VERSION"
	./configure -q --host="$triple" --prefix="$p" --disable-shared --enable-static --with-pic --disable-udev >/dev/null
	make -s -j"$(nproc)" install >/dev/null
	rm -rf /x/b && mkdir /x/b && tar -xjf "/x/dl/libusb-compat-$COMPAT_VERSION.tar.bz2" -C /x/b && cd "/x/b/libusb-compat-$COMPAT_VERSION"
	PKG_CONFIG_LIBDIR="$p/lib/pkgconfig" ./configure -q --host="$triple" --prefix="$p" --disable-shared --enable-static --with-pic >/dev/null
	! grep -q 'define LIBUSB_1_0_SONAME' config.h || { echo "libusb-compat for $name would load libusb-1.0 at run time" >&2; exit 1; }
	make -s -j"$(nproc)" install >/dev/null

	rm -rf /w && cp -r /t/src /w && cd /w
	BUILDVERSION="$TAG" make -s host CC="${pre}gcc" CFLAGS="-I$p/include" \
		HOSTLDLIBS="$p/lib/libusb.a $p/lib/libusb-1.0.a -lpthread -lrt" >/x/build-$name.log 2>&1 || { cat /x/build-$name.log; exit 1; }
	f="/t/out/novacomd-$TAG-linux-$name"
	"${pre}strip" -o "$f" build-novacomd-host/novacomd
	if grep -qa 'libusb-1.0.so' "$f"; then echo "$f would load libusb-1.0 at run time" >&2; exit 1; fi
	echo "== $(basename "$f"): $(file -b "$f" | cut -d, -f1-2)"
	echo "   needs: $(readelf -d "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | tr '\n' ' ')"
	echo "   newest glibc symbol: $(objdump -T "$f" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"
done

cd /t/out
# each must start and name its version (-V exits 1 after printing it)
for run in "./novacomd-$TAG-linux-x86_64" "qemu-aarch64 -L /usr/aarch64-linux-gnu ./novacomd-$TAG-linux-arm64" \
		"qemu-arm -L /usr/arm-linux-gnueabihf ./novacomd-$TAG-linux-armhf"; do
	v="$($run -V 2>&1 || true)"
	case "$v" in *"novacomd version novacomd-$TAG"*) echo "${v##*] }" ;; *) echo "$run -V: $v" >&2; exit 1 ;; esac
done
for f in novacomd-$TAG-linux-*; do sha256sum "$f" > "$f.sha256"; done
cat ./*.sha256
EOF

"$engine" run --rm -v "$work/src:/t/src:ro,Z" -v "$work/build.sh:/t/build.sh:ro,Z" -v "$out:/t/out:Z" \
	-e TAG="$tag" -e LIBUSB_VERSION="$LIBUSB_VERSION" -e LIBUSB_SHA256="$LIBUSB_SHA256" \
	-e COMPAT_VERSION="$COMPAT_VERSION" -e COMPAT_SHA256="$COMPAT_SHA256" \
	"$IMAGE" bash /t/build.sh
echo "built into $out"
