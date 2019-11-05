build-webos
===========

Summary
-------
Build webOS OSE (Open Source Edition) images

Description
-----------
This repository contains the top level code that aggregates the various [OpenEmbedded](http://openembedded.org) layers into a whole from which webOS OSE images can be built.

Cloning
=======
Set up build-webos by cloning its Git repository:

     git clone https://github.com/webosose/build-webos.git

Note: If you populate it by downloading an archive (zip or tar.gz file), then you will get the following error when you run mcf:

     fatal: Not a git repository (or any parent up to mount parent).
     Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYTEM not set).


Prerequisites
=============
Before you can build, you will need some tools.  If you try to build without them, bitbake will fail a sanity check and tell you what's missing, but not really how to get the missing pieces. On Ubuntu, you can force all of the missing pieces to be installed by entering:

    $ cd build-webos
    $ sudo scripts/prerequisites.sh

Also, the bitbake sanity check will issue a warning if you're not running under Ubuntu 18.04 64bit LTS.


Building
========
To configure the build for the raspberrypi4 and to fetch the sources:

    $ ./mcf -p 0 -b 0 raspberrypi4

The `-p 0` and `-b 0` options set the make and bitbake parallelism values to the number of CPU cores found on your computer.

To kick off a full build of webOS OSE, make sure you have at least 100GB of disk space available and enter the following:

    $ make webos-image

This may take in the neighborhood of two hours on a multi-core workstation with a fast disk subsystem and lots of memory, or many more hours on a laptop with less memory and slower disks or in a VM.

If you need more information about the build, please see the build guide on the webOS OSE website(webosose.org).

Images
======
The following images can be built:

- `webos-image`: The production webOS OSE image.
- `webos-image-devel`: Adds various development tools to `webos-image`, including gdb and strace. See `packagegroup-core-tools-debug` and `packagegroup-core-tools-profile` in `oe-core` and `packagegroup-webos-test` in `meta-webos` for the complete list.


Cleaning
========
To blow away the build artifacts and prepare to do clean build, you can remove the build directory and recreate it by typing:

    $ rm -rf BUILD
    $ ./mcf.status

What this retains are the caches of downloaded source (under `./downloads`) and shared state (under `./sstate-cache`). These caches will save you a tremendous amount of time during development as they facilitate incremental builds, but can cause seemingly inexplicable behavior when corrupted. If you experience strangeness, use the command presented below to remove the shared state of suspicious components. In extreme cases, you may need to remove the entire shared state cache. See [here](https://www.yoctoproject.org/docs/current/ref-manual/ref-manual.html#shared-state-cache) for more information on it.


Building Individual Components
==============================
To build an individual component, enter:

    $ make <component-name>

To clean a component's build artifacts under BUILD, enter:

    $ make clean-<component-name>

To remove the shared state for a component as well as its build artifacts to ensure it gets rebuilt afresh from its source, enter:

    $ make cleanall-<component-name>

Adding new layers
=================
The script automates the process of adding new OE layers to the build environment.  The information required for integrate new layer are; layer name, OE priority, repository, identification in the form branch, commit or tag ids. It is also possible to reference a layer from local storage area.  The details are documented in weboslayers.py.

Copyright and License Information
=================================
Unless otherwise specified, all content, including all source code files and documentation files in this repository are:

Copyright (c) 2008-2019 LG Electronics, Inc.

All content, including all source code files and documentation files in this repository except otherwise noted are: Licensed under the Apache License, Version 2.0 (the "License"); you may not use this content except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

SPDX-License-Identifier: Apache-2.0
