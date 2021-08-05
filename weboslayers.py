# Copyright (c) 2008-2021 LG Electronics, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This implementation introduces next generation build environment for
# Open webOS. The change introduces a mechanism to add additional layers to the
# base ones: oe-core, meta-oe, and meta-webos, and to specify the commits to be
# used for each. mcf now expects the layers to be defined in this file
# (weboslayers.py in the same directory as mcf) as a list of Python data tuples:
#
# webos_layers = [
# ('layer-name', priority, 'URL', 'submission', 'working-dir'),
# ...
# ]
#
# where:
#
# layer-name  = Unique identifier; it represents the layer directory containing
#               conf/layer.conf.
#
# priority    = Integer layer priority as defined by OpenEmbedded. It also
#               specifies the order in which layers are searched for files.
#               Larger values have higher priority. A value of -1 indicates
#               that the entry is not a layer; for example, bitbake.
#
# URL         = The Git repository address for the layer from which to clone.
#               A value of '' skips the cloning.
#
# submission  = The information used by Git to checkout and identify the precise
#               content. Submission values could be "branch=<name>" and
#               "commit=<id>" or "tag=<tag>". Omitted branch information means
#               only that "master" will be used as the name of the local
#               branch. Omitted commit or tag means origin/HEAD will be checked
#               out (which might NOT be origin/master, although
#               it usually is).
#
# working-dir = Alternative directory for the layer.
#
# The name of the distribution is also defined in this file
# along with a list of the valid MACHINE-s
#

Distribution = "webos"

# Supported MACHINE-s
Machines = ['qemux86', 'raspberrypi3', 'raspberrypi4']

# github.com/openembedded repositories are read-only mirrors of the authoritative
# repositories on git.openembedded.org
webos_layers = [
('bitbake',                   -1, 'git://github.com/openembedded/bitbake.git',              'branch=1.46,commit=0e0af15b', ''),

('meta',                       5, 'git://github.com/openembedded/openembedded-core.git',    'branch=dunfell,commit=9423ad8f0f', 'oe-core'),

('meta-oe',                   10, 'git://github.com/openembedded/meta-openembedded.git',    'branch=dunfell,commit=c38d2a74f7', 'meta-oe'),
('meta-multimedia',           11, 'git://github.com/openembedded/meta-openembedded.git',    '', 'meta-oe'),
('meta-networking',           12, 'git://github.com/openembedded/meta-openembedded.git',    '', 'meta-oe'),
('meta-python',               13, 'git://github.com/openembedded/meta-openembedded.git',    '', 'meta-oe'),
('meta-filesystems',          14, 'git://github.com/openembedded/meta-openembedded.git',    '', 'meta-oe'),

('meta-updater',              15, 'git://github.com/advancedtelematic/meta-updater.git',    'branch=dunfell,commit=5d49b28', ''),
('meta-virtualization',       16, 'git://git.yoctoproject.org/meta-virtualization',         'branch=dunfell,commit=bf2930c', ''),
('meta-python2',              17, 'git://git.openembedded.org/meta-python2',                'branch=dunfell,commit=b901080', ''),

('meta-qt6',                  20, 'git://code.qt.io/yocto/meta-qt6.git',                    'branch=6.2,commit=9a4453a', ''),

('meta-webos-backports-3.2',  33, 'git://github.com/webosose/meta-webosose',                '', ''),
('meta-webos-backports-3.4',  35, 'git://github.com/webosose/meta-webosose',                '', ''),

('meta-webos',                40, 'git://github.com/webosose/meta-webosose.git',            'branch=master,commit=37d6f271c', ''),

('meta-raspberrypi',          50, 'git://git.yoctoproject.org/meta-raspberrypi',            'branch=dunfell,commit=f0c7501', ''),
('meta-webos-raspberrypi',    51, 'git://github.com/webosose/meta-webosose.git',            '', ''),
('meta-webos-updater',        52, 'git://github.com/webosose/meta-webosose.git',            '', ''),
('meta-webos-virtualization', 53, 'git://github.com/webosose/meta-webosose.git',            '', ''),

('meta-webos-smack',          75, 'git://github.com/webosose/meta-webosose.git',            '', ''),
('meta-security',             77, 'git://git.yoctoproject.org/meta-security',               'branch=dunfell,commit=93232ae', ''),
]
