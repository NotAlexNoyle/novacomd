#!/usr/bin/env bash
#
# Build and (optionally) install novacomd -- NotAlexNoyle's 2025 libusb-compat fork.
#
# Run from the novacomd source dir, or point at it with $NOVACOMD_SRC or the first argument.
# Unprivileged: builds only. As root (sudo/doas): builds as the invoking user, then installs.
#
# Environment overrides:
#   NOVACOMD_SRC  source directory (default: this script's directory)
#   CC            C compiler (default: gcc, else cc; whitespace-split, no quoted args)
#   INSTALL_DIR   install location (default: /usr/local/bin)
#   JOBS          parallel make jobs (default: CPU count)
#
# Exit status: 0 on success, non-zero on failure. Public domain.
# Author: NotAlexNoyle (alexnoyle@icloud.com)

set -u

readonly TARGET="novacomd"
readonly BUILD_BIN="build-${TARGET}-host/${TARGET}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

log() { printf 'novacomd-install: %s\n' "$*"; }
err() { printf 'novacomd-install: ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

# --- locate the source tree ---
# Source precedence: argument 1, then $NOVACOMD_SRC, then this script's own directory.
self="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
script_dir="$(cd -- "$(dirname -- "$self")" >/dev/null 2>&1 && pwd -P)"
src_dir="${1:-${NOVACOMD_SRC:-$script_dir}}"
cd -- "$src_dir" >/dev/null 2>&1 || die "cannot enter novacomd source directory: $src_dir"
src_dir="$(pwd -P)"

[ -f makefile ] || [ -f Makefile ] || die "no makefile in $src_dir -- pass the source directory as the first argument."

# --- privilege model ---
# The build toolchain must never run as root; when root, drop to the invoking user for every build step.
orig_user="${SUDO_USER:-${DOAS_USER:-}}"
builder_prefix=()
if (( EUID == 0 )); then
    builder_uid="$(id -u "$orig_user" 2>/dev/null || true)"   # require a real, non-root account (UID > 0)
    if [ -n "$orig_user" ] && [[ "$builder_uid" =~ ^[1-9][0-9]*$ ]] && command -v runuser >/dev/null 2>&1; then
        builder_prefix=(runuser -u "$orig_user" --)
    else
        die "refusing to build as root -- run as a normal user; privilege escalation is only used to install."
    fi
fi
as_builder() { ${builder_prefix[@]+"${builder_prefix[@]}"} "$@"; }   # this form: macOS bash 3.2 calls an empty "${a[@]}" unbound under set -u

# --- preflight: build tools ---
command -v make >/dev/null 2>&1 || die "'make' not found -- install your build tools (build-essential / base-devel)."

# --- compiler selection ---
# Default the compiler when CC is unset. Each compiler builds at its own default C standard, C23 (gcc 15) included.
if [ -z "${CC:-}" ]; then
    if command -v gcc >/dev/null 2>&1; then CC=gcc; else CC=cc; fi
fi

# Split CC (e.g. "gcc -std=gnu11") into an argv array, then confirm a compiler is set and exists.
read -r -a cc_argv <<<"$CC"
[ "${#cc_argv[@]}" -gt 0 ] || die "CC is empty -- set it to a C compiler, e.g. CC=gcc."
command -v "${cc_argv[0]}" >/dev/null 2>&1 || die "C compiler not found: ${cc_argv[0]}"

# --- preflight: libusb-compat header (macOS) ---
# On macOS libusb-compat comes from Homebrew, looked for under Homebrew's prefix as the makefile does (Apple Silicon's
# /opt/homebrew is not searched); probe for it up front for a clear message. Linux is handled under "libusb" below.
if [ "$(uname -s)" = Darwin ]; then
    probe_flags=()
    if command -v brew >/dev/null 2>&1; then
        libusb_prefix="$(brew --prefix libusb-compat 2>/dev/null || printf '%s/opt/libusb-compat' "$(brew --prefix)")"
        probe_flags=(-I"$libusb_prefix/include")
    fi
    if ! printf '#include <usb.h>\nint main(void){return 0;}\n' | as_builder "${cc_argv[@]}" ${probe_flags[@]+"${probe_flags[@]}"} -fsyntax-only -xc - >/dev/null 2>&1; then
        die "missing libusb-compat (<usb.h>). Install it: brew install libusb-compat"
    fi
fi

# --- build ---
# Default JOBS to the CPU count, and clear inherited make flags that could turn the build into a no-op.
[ -n "${JOBS:-}" ] || JOBS="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS=1
unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES

# --- libusb (Linux): the libusb-0.1 API from libusb-compat, on libusb 1.0 ---
# novacomd reads and writes a device from two threads. The original libusb 0.1.12 (the libusb-dev of Debian, Ubuntu and
# Raspberry Pi OS) cancels a timed-out transfer and then waits, with no timeout, for whichever transfer on the device
# finishes next: after a USB timeout that wait can take the other thread's transfer or never return, and novacomd stops
# answering until it is restarted. libusb-compat waits for each transfer by itself. So the original is never linked:
# when it is what the system has, libusb-compat is built here from its release tarball, against the system's libusb 1.0.
readonly COMPAT_VERSION=0.1.9
readonly COMPAT_SHA256=179d934676ad3bd172a5a37cf5c6351b8e9d7816feb3029252e79b30a518a3be
readonly COMPAT_URL="https://github.com/libusb/libusb-compat-0.1/releases/download/v${COMPAT_VERSION}/libusb-compat-${COMPAT_VERSION}.tar.bz2"
make_args=()

# compat, original or none: libusb-compat calls into libusb 1.0 (linked or loaded at run time), the original does not
usb0_flavour() {
    local name lib
    printf '#include <usb.h>\nint main(void){usb_init();return 0;}\n' | as_builder "${cc_argv[@]}" -xc - -lusb -o /dev/null >/dev/null 2>&1 || { echo none; return; }
    for name in libusb.so libusb.a; do
        lib="$(as_builder "${cc_argv[@]}" -print-file-name="$name" 2>/dev/null)"
        if [ -f "$lib" ]; then
            if grep -qa libusb_init "$lib"; then echo compat; else echo original; fi
            return
        fi
    done
    echo original   # linkable, but not found by name: assume the original
}

build_compat() {
    local prefix="$src_dir/build-libusb-compat" tarball usb1_libs sum
    tarball="$prefix/libusb-compat-${COMPAT_VERSION}.tar.bz2"
    # libusb-compat's configure finds libusb 1.0 through pkg-config, so both are needed
    if ! { command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libusb-1.0; }; then
        die "novacomd needs libusb-compat (the libusb-0.1 API on libusb 1.0); the original libusb 0.1.12 can hang it.
       Install your distribution's libusb-compat, or libusb 1.0's development files and pkg-config, and this script
       builds libusb-compat itself:
       Debian/Ubuntu/Raspberry Pi OS:  sudo apt install libusb-1.0-0-dev pkg-config
       Fedora:                         sudo dnf install libusb-compat-0.1-devel
       Void:                           doas xbps-install -Su libusb-compat-devel
       Arch:                           sudo pacman -S libusb-compat"
    fi
    usb1_libs="$(pkg-config --libs libusb-1.0)"
    if [ ! -f "$prefix/lib/libusb.a" ]; then
        command -v bzip2 >/dev/null 2>&1 || die "building libusb-compat needs bzip2 (Debian/Ubuntu: sudo apt install bzip2)."
        as_builder mkdir -p "$prefix" || die "cannot create $prefix"
        if [ ! -f "$tarball" ]; then
            log "fetching libusb-compat $COMPAT_VERSION..."
            if command -v curl >/dev/null 2>&1; then
                as_builder curl -fsSL -o "$tarball" "$COMPAT_URL" || die "cannot download $COMPAT_URL"
            elif command -v wget >/dev/null 2>&1; then
                as_builder wget -q -O "$tarball" "$COMPAT_URL" || die "cannot download $COMPAT_URL"
            else
                die "building libusb-compat needs curl or wget to fetch $COMPAT_URL"
            fi
        fi
        if command -v sha256sum >/dev/null 2>&1; then sum="$(sha256sum "$tarball")"; else sum="$(shasum -a 256 "$tarball")"; fi
        [ "${sum%% *}" = "$COMPAT_SHA256" ] || { rm -f "$tarball"; die "libusb-compat tarball checksum mismatch (got ${sum%% *})"; }
        log "building libusb-compat $COMPAT_VERSION (static) against libusb 1.0..."
        as_builder tar -xjf "$tarball" -C "$prefix" || die "cannot unpack $tarball"
        (cd "$prefix/libusb-compat-${COMPAT_VERSION}" &&
            as_builder ./configure -q --prefix="$prefix" --disable-shared --enable-static --with-pic CC="$CC" >/dev/null &&
            as_builder make -s -j"$JOBS" install >/dev/null) || die "building libusb-compat failed."
    fi
    # libusb-compat loads the system's libusb 1.0 (libusb-1.0.so.0) at run time when it finds it shared: -ldl for glibc
    # before 2.34, where dlopen is not in libc yet
    make_args=(CFLAGS="-I$prefix/include" HOSTLDLIBS="$prefix/lib/libusb.a $usb1_libs -ldl -lpthread")
    as_builder rm -f "$BUILD_BIN"   # relink against it even when the objects are current
}

if [ "$(uname -s)" != Darwin ]; then
    case "$(usb0_flavour)" in
        compat) log "libusb: the system's libusb-compat" ;;
        *) log "libusb: no libusb-compat on the system (the original libusb 0.1.12 is never used); building it"; build_compat ;;
    esac
fi

log "building $TARGET (CC=$CC, jobs=$JOBS${builder_prefix:+, as $orig_user})..."
as_builder make -j"$JOBS" CC="$CC" ${make_args[@]+"${make_args[@]}"} host || die "build failed -- see the compiler output above."
[ -f "$BUILD_BIN" ] && [ -x "$BUILD_BIN" ] || die "build reported success but $BUILD_BIN is missing."
log "build succeeded: $BUILD_BIN"

# --- install (root only) ---
if (( EUID == 0 )); then
    dest="$INSTALL_DIR/$TARGET"
    [ -d "$dest" ] && die "install destination is a directory: $dest"
    mkdir -p -- "$INSTALL_DIR" || die "cannot create $INSTALL_DIR"
    log "installing to $dest..."
    install -T -m 0755 -- "$BUILD_BIN" "$dest" || die "failed to install to $dest"
    [ -f "$dest" ] && [ -x "$dest" ] || die "post-install check failed: $dest"
    log "installed: $dest"
else
    # Not root: print the manual install command using the available privilege escalation tool.
    if command -v doas >/dev/null 2>&1; then elevate="doas"; else elevate="sudo"; fi
    log "not running as root -- skipping install."
    log "to install:  $elevate install -T -m 0755 '$src_dir/$BUILD_BIN' '$INSTALL_DIR/$TARGET'"
fi

exit 0
