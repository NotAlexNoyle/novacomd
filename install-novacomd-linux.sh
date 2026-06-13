#!/usr/bin/env bash
#
# Build and install novacomd (NotAlexNoyle's 2025 libusb-compat fork) on a UNIX-like host.
#
# Run this from the novacomd source directory (the directory that holds the makefile), or
# point it at that directory with $NOVACOMD_SRC or the first argument. With no privileges it
# builds only. When run as root (e.g. via sudo or doas) it builds as the invoking
# unprivileged user and then installs the resulting binary into $INSTALL_DIR so it lands on
# PATH.
#
# Environment overrides:
#   NOVACOMD_SRC  novacomd source directory. Default: this script's directory.
#   CC            C compiler, simple whitespace-separated form only (e.g. "gcc -std=gnu17").
#                 Auto-set to "gcc -std=gnu17" on GCC >= 15 when unset. Quoted/escaped
#                 arguments and compiler paths containing spaces are not supported.
#   INSTALL_DIR   Install location for the novacomd binary. Default: /usr/local/bin
#   JOBS          Parallel make jobs (positive integer). Default: detected CPU count.
#
# Exit status: 0 on success, non-zero on any failure.
#
# This is free and unencumbered software released into the public domain.
# Author: NotAlexNoyle (alexnoyle@icloud.com)

set -u

readonly TARGET="novacomd"
readonly BUILD_BIN="build-${TARGET}-host/${TARGET}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

log() { printf 'novacomd-install: %s\n' "$*"; }
err() { printf 'novacomd-install: ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

# --- locate the source tree ------------------------------------------------
# Precedence: $1, then $NOVACOMD_SRC, then this script's own (symlink-resolved) directory.
self="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
script_dir="$(cd -- "$(dirname -- "$self")" >/dev/null 2>&1 && pwd -P)"
src_dir="${1:-${NOVACOMD_SRC:-$script_dir}}"
cd -- "$src_dir" >/dev/null 2>&1 || die "cannot enter novacomd source directory: $src_dir"
src_dir="$(pwd -P)"

if [ ! -f makefile ] && [ ! -f Makefile ]; then
    die "no makefile in $src_dir -- pass the novacomd source directory as the first argument."
fi

# --- privilege model -------------------------------------------------------
# The toolchain (compiler + make recipes) must never run as root. When invoked as root via
# sudo or doas, drop to the invoking user for every toolchain call; refuse if that is not
# possible. sudo exports SUDO_USER, doas exports DOAS_USER.
orig_user="${SUDO_USER:-${DOAS_USER:-}}"
builder_prefix=()
if (( EUID == 0 )); then
    # Resolve the invoking user to a UID and require a real, non-root account (catches UID-0
    # aliases, not just the literal name "root").
    builder_uid="$(id -u "$orig_user" 2>/dev/null || true)"
    if [ -n "$orig_user" ] && [[ "$builder_uid" =~ ^[1-9][0-9]*$ ]] \
            && command -v runuser >/dev/null 2>&1; then
        builder_prefix=(runuser -u "$orig_user" --)
    else
        die "refusing to run the build toolchain as root. Run this script as a normal user; \
it will only ask for elevation to install."
    fi
fi
as_builder() { "${builder_prefix[@]}" "$@"; }

# --- preflight: build tools ------------------------------------------------
command -v make >/dev/null 2>&1 \
    || die "'make' not found. Install your distribution's build tools (build-essential / base-devel)."

# --- compiler selection ----------------------------------------------------
# GCC 15 defaults to C23, which rejects this older code; pin gnu17 there.
if [ -z "${CC:-}" ]; then
    if command -v gcc >/dev/null 2>&1; then
        gcc_ver="$(as_builder gcc -dumpfullversion -dumpversion 2>/dev/null)"
        gcc_major="${gcc_ver%%.*}"
        case "$gcc_major" in
            ''|*[!0-9]*) : ;;                                  # unknown format -> leave CC unset
            *) [ "$gcc_major" -ge 15 ] && CC="gcc -std=gnu17" ;;
        esac
    fi
fi
CC="${CC:-cc}"

# CC may carry flags ("gcc -std=gnu17"); split into an argv array for direct invocation.
read -r -a cc_argv <<<"$CC"
command -v "${cc_argv[0]}" >/dev/null 2>&1 || die "C compiler not found: ${cc_argv[0]}"

# --- preflight: libusb-compat header ---------------------------------------
# The host transport needs libusb-compat-0.1 (<usb.h>). Probe early for a clear message.
if ! printf '#include <usb.h>\nint main(void){return 0;}\n' \
        | as_builder "${cc_argv[@]}" -fsyntax-only -xc - >/dev/null 2>&1; then
    die "could not compile a <usb.h> probe -- the libusb-compat-0.1 dev headers are most likely
       missing. Install them, e.g.:
       Debian/Ubuntu:  sudo apt install libusb-dev
       Fedora:         sudo dnf install libusb-compat-0.1-devel
       Void:           doas xbps-install -Su libusb-compat-devel
       Arch:           sudo pacman -S libusb-compat"
fi

# --- build -----------------------------------------------------------------
# Validate JOBS and neutralize inherited make flags so the build cannot be turned into a
# no-op (e.g. JOBS or MAKEFLAGS carrying -n/--version, which would exit 0 without building).
if [ -z "${JOBS:-}" ]; then
    JOBS="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS=1
unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKEFILES

log "building $TARGET (CC=$CC, jobs=$JOBS${builder_prefix:+, as $orig_user})..."
as_builder make -j"$JOBS" CC="$CC" host || die "build failed -- see the compiler output above."
[ -f "$BUILD_BIN" ] && [ -x "$BUILD_BIN" ] || die "build reported success but $BUILD_BIN is missing."
log "build succeeded: $BUILD_BIN"

# --- install ---------------------------------------------------------------
# Only attempt the system install when running with the privilege for it.
if (( EUID == 0 )); then
    dest="$INSTALL_DIR/$TARGET"
    [ -d "$dest" ] && die "install destination is a directory: $dest"
    mkdir -p -- "$INSTALL_DIR" || die "cannot create $INSTALL_DIR"
    log "installing to $dest..."
    install -T -m 0755 -- "$BUILD_BIN" "$dest" || die "failed to install to $dest"
    [ -f "$dest" ] && [ -x "$dest" ] || die "post-install check failed: $dest"
    log "installed: $dest"
else
    # Build-only run: suggest the right elevation tool for a manual install (doas or sudo).
    elevate="sudo"
    command -v doas >/dev/null 2>&1 && elevate="doas"
    log "not running as root -- skipping install."
    log "to install:  $elevate install -T -m 0755 '$src_dir/$BUILD_BIN' '$INSTALL_DIR/$TARGET'"
fi

exit 0
