#!/usr/bin/env bash
#
# Build and (optionally) install novacomd -- NotAlexNoyle's 2025 libusb-compat fork.
#
# Run from the novacomd source dir, or point at it with $NOVACOMD_SRC or the first argument.
# Unprivileged: builds only. As root (sudo/doas): builds as the invoking user, then installs.
#
# Environment overrides:
#   NOVACOMD_SRC  source directory (default: this script's directory)
#   CC            C compiler (default: gcc/cc + -std=gnu17 when supported; whitespace-split, no quoted args)
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
as_builder() { "${builder_prefix[@]}" "$@"; }

# --- preflight: build tools ---
command -v make >/dev/null 2>&1 || die "'make' not found -- install your build tools (build-essential / base-devel)."

# --- compiler selection ---
# Default the compiler when CC is unset, and add -std=gnu17 only if accepted (C23-default compilers need it).
if [ -z "${CC:-}" ]; then
    if command -v gcc >/dev/null 2>&1; then CC=gcc; else CC=cc; fi
    if printf 'int main(void){return 0;}\n' | as_builder $CC -std=gnu17 -fsyntax-only -xc - >/dev/null 2>&1; then
        CC="$CC -std=gnu17"
    fi
fi

# Split CC ("gcc -std=gnu17") into an argv array, then confirm a compiler is set and exists.
read -r -a cc_argv <<<"$CC"
[ "${#cc_argv[@]}" -gt 0 ] || die "CC is empty -- set it to a C compiler, e.g. CC=gcc."
command -v "${cc_argv[0]}" >/dev/null 2>&1 || die "C compiler not found: ${cc_argv[0]}"

# --- preflight: libusb-compat header ---
# The host transport needs libusb-compat-0.1 (<usb.h>); probe for it up front for a clear message.
if ! printf '#include <usb.h>\nint main(void){return 0;}\n' | as_builder "${cc_argv[@]}" -fsyntax-only -xc - >/dev/null 2>&1; then
    die "missing libusb-compat-0.1 (<usb.h>). Install it, e.g.:
       Debian/Ubuntu:  sudo apt install libusb-dev
       Fedora:         sudo dnf install libusb-compat-0.1-devel
       Void:           doas xbps-install -Su libusb-compat-devel
       Arch:           sudo pacman -S libusb-compat"
fi

# --- build ---
# Default JOBS to the CPU count, and clear inherited make flags that could turn the build into a no-op.
[ -n "${JOBS:-}" ] || JOBS="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS=1
unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES

log "building $TARGET (CC=$CC, jobs=$JOBS${builder_prefix:+, as $orig_user})..."
as_builder make -j"$JOBS" CC="$CC" host || die "build failed -- see the compiler output above."
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
