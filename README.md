# build-webos

This repository contains the top level code that aggregates the various [OpenEmbedded](http://openembedded.org) layers into a whole from which [webOS Open Source Edition (OSE)](https://www.webosose.org/) images can be built.

## Prerequisites

Before you begin, make sure that you prepare the target device and systems that meet the [System Requirements](https://www.webosose.org/docs/guides/setup/system-requirements/).

## How to Build a webOS OSE Image

To build a webOS OSE image, refer to [Building webOS OSE](https://www.webosose.org/docs/guides/setup/building-webos-ose/)

If you are already familiar with building webOS OSE, check the following quick summary:

``` bash
# Download this repository
$ git clone https://github.com/webosose/build-webos.git
$ cd build-webos
$ git checkout -t origin/<branch of the latest webOS OSE version>

# Install and configure the build
$ sudo scripts/prerequisites.sh
$ ./mcf -p 0 -b 0 raspberrypi4-64

# Start to build
$ source oe-init-build-env
$ bitbake webos-image
```

> **Note**: See also [Flashing webOS OSE](https://www.webosose.org/docs/guides/setup/flashing-webos-ose/).

## Copyright and License Information

Unless otherwise specified, all content, including all source code files and documentation files in this repository are:

Copyright (c) 2008-2023 LG Electronics, Inc.

All content, including all source code files and documentation files in this repository except otherwise noted are: Licensed under the Apache License, Version 2.0 (the "License"); you may not use this content except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

SPDX-License-Identifier: Apache-2.0

## How to Download Source Codes and Licenses

If you *ONLY* want to check the source codes and those license information, enter the following commands:

``` bash
# Download this repository
$ git clone https://github.com/webosose/build-webos.git
$ cd build-webos
$ git checkout -t origin/<branch of the latest webOS OSE version>

# Install and configure the build
$ sudo scripts/prerequisites.sh
$ ./mcf -p 0 -b 0 raspberrypi4-64

# Download source codes and licenses
$ source oe-init-build-env
$ bitbake --runall=patch webos-image
```

You can check the source codes and licenses under the `BUILD/work` directory.
