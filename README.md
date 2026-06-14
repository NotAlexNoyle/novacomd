novacomd
========

A 2026 build of novacomd for UNIX-like hosts built on top of libusb-compat-0.1. novacomd runs as a daemon or service on the host and the device.

## Dependencies

Building from source needs a C compiler (GCC or Clang), **GNU make**, and **libusb-compat-0.1**.

Get a compiler:

* **macOS:** Apple's Clang and make come with the Xcode Command Line Tools (`xcode-select --install`).
* **Linux:** install your distribution's build tools (`build-essential` on Debian/Ubuntu, `base-devel` on Arch, etc.).

Get libusb-compat-0.1:

| Platform | Command |
| --- | --- |
| macOS (Homebrew) | `brew install libusb-compat` |
| Debian / Ubuntu | `sudo apt install libusb-dev` |
| Fedora | `sudo dnf install libusb-compat-0.1-devel` |
| Arch | `sudo pacman -S libusb-compat` |
| Void | `doas xbps-install -Su libusb-compat-devel` |

(On Debian/Ubuntu the libusb-0.1 development package is named `libusb-dev`; `libusb-1.0-0-dev` is a legacy, unused package.)

## Building

> ./install-novacomd-linux.sh

To force a specific compiler, set `CC`, for example:

> CC="gcc -std=gnu17" ./install-novacomd-linux.sh

To install, copy or symlink `build-novacomd-host/novacomd` to the `/bin` directory of your Palm SDK install (usually `/opt/nova/bin`).

*May not require privilege escalation depending on your install location.*
> mv build-novacomd-host/novacomd /YOUR/LOCATION/HERE/

![In Action](https://i.imgur.com/GUqOYEp.png)

Thanks to [incidentist](https://github.com/incidentist/novacomd) for the macOS build support.

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


