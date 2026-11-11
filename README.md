novacomd
========

novacomd is the daemon that connects the webOS SDK tools (`novacom`, `novaterm`, the palm-* tools) to webOS devices.
This fork runs on UNIX-like hosts and is built on the libusb-0.1 API.

**Hosts:** Linux on any architecture, Raspberry Pi included (Raspberry Pi OS, armhf or arm64), and macOS (Intel and
Apple Silicon).

> **Windows is not supported**, and will not be. If you need novacomd on Windows, use the
> [webos-sdk-redux](https://github.com/webOSArchive/webos-sdk-redux) fork by webOSArchive, which ships a Windows build
> and installer.

## Devices

* **HP/Palm webOS devices** (Pre, Pixi, Veer, TouchPad and the rest of HP's line), on webOS 1-3 and webOS CE, over USB.
* **LuneOS** (webOS-ports). A LuneOS device that presents Palm's USB IDs, such as a TouchPad, is listed under its usual
  type. One that adds novacom to its own USB gadget under another vendor's IDs is found by the novacom interface itself
  (vendor class, subclass 0x47, protocol 0x11) and listed as `unknown-linux`.
* **Lunacy** (webOSArchive's legacy webOS apps on Android). novacomd asks the adb server you run (`127.0.0.1:5037`, or
  `ADB_SERVER_SOCKET` / `ANDROID_ADB_SERVER_PORT`) for its devices every few seconds and lists each one whose Lunacy
  answers as `adb lunacy`, beside the USB devices; `novacom` and `novaterm` reach it like any other webOS device, and the
  palm-* tools from webos-sdk-redux 0.4 on recognise it. novacomd never starts an adb server. `-A` (`--no-adb`) turns the
  search off, for instance when you use adb for other phones and no Lunacy.
* **Over TCP**: a device or emulator that serves novacom over TCP is reached with `-c <host>:<port>`.

## Release binaries

[Releases](https://git.trueog.net/NotAlexNoyle/novacomd/releases) from 1.2.1 on carry ready-built binaries, each with a
`.sha256`:

| File | Runs on |
| --- | --- |
| `novacomd-<version>-linux-x86_64` | 64-bit PC Linux with glibc 2.15 or later |
| `novacomd-<version>-linux-arm64` | 64-bit ARM Linux (64-bit Raspberry Pi OS and others) with glibc 2.17 or later |
| `novacomd-<version>-linux-armhf` | 32-bit ARMv7 Linux with glibc 2.15 or later (Raspberry Pi 2 and later on a 32-bit OS) |
| `novacomd-<version>-macos-x86_64` | Intel Macs, macOS 10.13 or later |
| `novacomd-<version>-macos-arm64` | Apple Silicon Macs, macOS 11 or later |

libusb is built in, so a binary needs nothing beyond the operating system. Install one where your Palm SDK looks for
it, usually `/opt/nova/bin`:

> sudo install -m 0755 novacomd-&lt;version&gt;-linux-x86_64 /opt/nova/bin/novacomd

The macOS binaries are not notarized: if macOS refuses to start one you downloaded, clear its quarantine flag with
`xattr -d com.apple.quarantine novacomd-<version>-macos-<arch>`. A Raspberry Pi 1 or Zero (ARMv6) builds from source.

## Building from source

You need a C compiler (GCC or Clang), **GNU make**, and the **libusb-0.1 API** (`<usb.h>`, `-lusb`).

Build tools:

* **macOS:** the Xcode Command Line Tools (`xcode-select --install`).
* **Linux:** `build-essential` on Debian, Ubuntu and Raspberry Pi OS, `gcc` and `make` on Fedora, `base-devel` on Arch
  and Void.

The libusb-0.1 API:

| Platform | Command | Provides |
| --- | --- | --- |
| macOS (Homebrew) | `brew install libusb-compat` | libusb-compat 0.1.9 |
| Debian / Ubuntu / Raspberry Pi OS | `sudo apt install libusb-dev` | libusb 0.1.12 |
| Fedora | `sudo dnf install libusb-compat-0.1-devel` | libusb-compat 0.1.9 |
| Arch | `sudo pacman -S libusb-compat` | libusb-compat 0.1.9 |
| Void | `doas xbps-install -S libusb-compat-devel` | libusb-compat 0.1.8 |

libusb-compat and the original libusb 0.1.12 provide the same API, and novacomd builds against either. (`libusb-1.0-0-dev`
is libusb 1.0, a different API that novacomd does not use.)

Build from the source directory with the script. It uses `gcc` (or `cc`; set `CC` to choose, e.g. `CC=clang`) at the
compiler's default C standard:

> ./install-novacomd.sh

The daemon lands at `build-novacomd-host/novacomd`. On macOS the build finds Homebrew's libusb-compat under `/usr/local`
or `/opt/homebrew` by itself.

## Installing from source

**Linux and Raspberry Pi**: run the script with privilege escalation. It still builds as your normal user, then installs
to `/usr/local/bin` (set `INSTALL_DIR` for another place):

> sudo ./install-novacomd.sh

`doas ./install-novacomd.sh` works too.

**macOS**: build *without* privilege escalation (the script refuses to build as root), then copy the binary into your
Palm SDK's `bin`, usually `/opt/nova/bin`:

> ./install-novacomd.sh
>
> sudo cp build-novacomd-host/novacomd /opt/nova/bin/novacomd

![In Action](https://i.imgur.com/GUqOYEp.png)

## Credits

novacomd is HP's, released as open source in 2012. This fork carries work by Jonathan Dieter (the libusb-compat port),
[incidentist](https://github.com/incidentist/novacomd) (macOS), jessicarod7 (GCC 15),
[webos-sdk-redux](https://github.com/webOSArchive/webos-sdk-redux) by webOSArchive (codepoet80: the Lunacy relay;
achunt2143), Travis Geiselbrecht, Maksym Sditanov and jwmaag.

## Copyright

Unless otherwise specified, all content in this repository, including all source code and documentation files, is
Copyright (c) 2008-2012 Hewlett-Packard Development Company, L.P., and licensed under the Apache License, Version 2.0
(the "License"); you may not use this content except in compliance with the License. You may obtain a copy of the
License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
