novacomd
========

A 2025 build of novacomd adapted for UNIX-like hosts using libusb-compat-0.1.

Before building:

*This command will vary depending on your distribution.*
> doas xbps-install -Su libusb-compat-devel

To build:

> ./install-novacomd-linux.sh

To install:

*May not require privilege escalation depending on your install location.*
> doas mv build-novacomd-host/* /YOUR/LOCATION/HERE/

novacomd runs as a daemon or service on the host and the device.

![In Action](https://i.imgur.com/GUqOYEp.png)

# Copyright and License Information

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


