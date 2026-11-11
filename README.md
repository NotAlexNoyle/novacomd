novacomd
========

A 2026 build of novacomd for UNIX-like hosts built on top of libusb-compat-0.1. novacomd runs as a daemon or service on the host and the device.

Supported hosts: **Linux** on any architecture, **Raspberry Pi** included (Raspberry Pi OS, armhf or arm64), and **macOS**
(Intel and Apple Silicon).

Supported devices: HP/Palm webOS devices (webOS 1-3 and webOS CE), **LuneOS**, and **Lunacy** on Android. See
[Devices](#devices).

> **Windows is not supported.** This fork builds and runs on Linux and macOS only, and Windows support will not be
> added. If you need novacomd on Windows, use the [webos-sdk-redux](https://github.com/webOSArchive/webos-sdk-redux)
> fork by webOSArchive, which ships a Windows build and installer.

## Dependencies

Building from source needs a C compiler (GCC or Clang), **GNU make**, and the **libusb-0.1 API** (`<usb.h>`, `-lusb`): libusb-compat-0.1, or the original libusb 0.1.12 where a distribution still ships that.

Get a compiler:

* **macOS:** Apple's Clang and make come with the Xcode Command Line Tools (`xcode-select --install`).
* **Linux:** install your distribution's build tools (`build-essential` on Debian/Ubuntu and Raspberry Pi OS, `gcc` and `make` on Fedora, `base-devel` on Arch, `base-devel` on Void).

Get the libusb-0.1 API:

| Platform | Command | What it installs |
| --- | --- | --- |
| macOS (Homebrew, Intel or Apple Silicon) | `brew install libusb-compat` | libusb-compat 0.1.9 (and libusb 1.0) |
| Debian / Ubuntu | `sudo apt install libusb-dev` | libusb 0.1.12 |
| Raspberry Pi OS (armhf or arm64) | `sudo apt install libusb-dev` | libusb 0.1.12 |
| Fedora | `sudo dnf install libusb-compat-0.1-devel` | libusb-compat 0.1.9 |
| Arch | `sudo pacman -S libusb-compat` | libusb-compat 0.1.9 |
| Void | `doas xbps-install -S libusb-compat-devel` | libusb-compat 0.1.8 |

Debian, Ubuntu and Raspberry Pi OS package the original libusb 0.1.12 as `libusb-dev` rather than libusb-compat; it
provides the same `<usb.h>` API, and novacomd builds against either. `libusb-1.0-0-dev` is libusb 1.0, a different API
that novacomd does not use. Checked 2026-11-11 by building with `install-novacomd.sh` on Debian 13, Ubuntu 24.04,
Fedora 42 (gcc 15, C23), Arch (gcc 16, C23) and Void, against each distribution's own package indexes for the rest.

## Building

Run the build script from the source directory. It uses `gcc` (or `cc`) at the compiler's own default C standard; GCC 15's C23 builds as older ones do:

> ./install-novacomd.sh

To force a specific compiler, set `CC`:

> CC=clang ./install-novacomd.sh

The built daemon lands at `build-novacomd-host/novacomd`.

## Installing

**Linux** — re-run the script with privilege escalation. It still builds as your normal user, then installs to `/usr/local/bin` (override with `INSTALL_DIR`):

> sudo ./install-novacomd.sh

`doas ./install-novacomd.sh` works too.

**Raspberry Pi** — the same as Linux: the build has no architecture flags, so it builds natively on the Pi (armhf or arm64):

> sudo ./install-novacomd.sh

**macOS** — build *without* privilege escalation (running the script as root is refused), then copy the binary into your Palm SDK `bin`, usually `/opt/nova/bin`. The build finds Homebrew's libusb-compat by itself, under `/usr/local` on Intel and `/opt/homebrew` on Apple Silicon:

> ./install-novacomd.sh
>
> sudo cp build-novacomd-host/novacomd /opt/nova/bin/novacomd

![In Action](https://i.imgur.com/GUqOYEp.png)

## Devices

* **HP/Palm webOS devices** (Pre, Pixi, Veer, TouchPad and the others HP listed), on webOS 1-3 and webOS CE, over USB
  as always.
* **LuneOS** (webOS-ports): a TouchPad on LuneOS presents Palm's USB IDs and is found as before. A LuneOS device that
  adds novacom to its own USB gadget under another vendor's IDs is found by the novacom interface itself (vendor class,
  subclass 0x47, protocol 0x11) and listed as `unknown-linux`.
* **Over TCP**: a device or emulator that serves novacom over TCP is reached with `-c <host>:<port>`; that transport no
  longer stalls on Linux in this fork.
* **Lunacy** (webOSArchive's legacy webOS apps on Android): novacomd looks through the adb server you run
  (`127.0.0.1:5037`, or `ADB_SERVER_SOCKET` / `ANDROID_ADB_SERVER_PORT`) for Android devices whose Lunacy answers, and
  lists each as `adb lunacy` beside the USB devices, so `novacom` and `novaterm` reach it like any other webOS device
  (the palm-* tools recognise Lunacy from webos-sdk-redux 0.4 on). It never starts an adb server. Every few seconds it asks the adb server for its devices; start novacomd
  with `-A` (`--no-adb`) to turn the search off, for instance when you use adb for other phones and no Lunacy.

## Changes from HP's release

* libusb-compat-0.1 instead of HP's own USB handlers (Jonathan Dieter, 2012), and its 2025 compatibility update.
* Builds on Raspberry Pi (armhf, 2019) and on macOS, Intel and Apple Silicon (incidentist; Homebrew's libusb-compat found wherever Homebrew lives).
* Builds with GCC 15, whose default is C23: `bool` comes from `<stdbool.h>` instead of HP's `typedef int bool`, so every C standard from gnu89 to gnu23 builds, and older GCC as before.
* LuneOS devices found by the novacom interface when their USB IDs are not in HP's list.
* A device's SYN packet can no longer make novacomd write outside its receive buffer (an empty data field wrote at index
  0xffffffff; the bounds no longer wrap on 32-bit hosts). After Travis Geiselbrecht's travisg/novacomd 733d5ca.
* Every USB packet written is no longer logged to syslog (Maksym Sditanov's Gentoo patch, also in nixpkgs).
* macOS drops a replugged device's stale link at once, as Linux does (after jwmaag/novacomd 9d94645).
* From [webos-sdk-redux](https://github.com/webOSArchive/webos-sdk-redux)'s novacomd (webOSArchive: codepoet80, achunt2143), Unix parts only:
  * Lunacy devices reached through adb (codepoet80), with the nduid a device reports checked as hex before it is listed;
  * the token storage path no longer writes its terminating NUL one byte past its buffer, and holds a full `PATH_MAX`;
  * novacom over TCP no longer stalls on Linux (a 4096-byte receive low-water mark against a 48-byte handshake), and reads whole packets;
  * no spurious "old GCC" warning under Clang.

Thanks to [incidentist](https://github.com/incidentist/novacomd) for the macOS build support, to Jonathan Dieter for the
libusb-compat port, to jessicarod7 for the GCC 15 instructions, to the webos-sdk-redux maintainers, Travis Geiselbrecht,
Maksym Sditanov and jwmaag for the fixes above.

## Copyright

Unless otherwise specified, all content, including all source code files 
and documentation files in this repository are:
 Copyright (c) 2008-2012 Hewlett-Packard Development Company, L.P.

Unless otherwise specified, all content, including all source code files
and documentation files in this repository are:
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this content except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.


