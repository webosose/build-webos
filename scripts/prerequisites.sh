#!/bin/bash -e

# Copyright (c) 2008-2020 LG Electronics, Inc.
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

# This has only been tested on Ubuntu-12.04 and Ubuntu-14.04 amd64.

check_sanity=true
usage="$0 [--help|-h] [--version|-V] [--force|-f]"
version="2.2.4"
statusfile="/etc/webos.prerequisites"

for i ; do
    case "$i" in
        --help|-h) echo ${usage}; exit 0 ;;
        --force|-f) rm -f $statusfile ;;
        --version|-V) echo ${version}; exit 0 ;;
        *)
            echo Unrecognized option: $i 1>&2
            echo ${usage}
            exit 1
            ;;
    esac
done

function checknumber()
{
    local rvalue=$2
    local number
    a=$(echo $1 | cut -d '.' -f 1)
    b=$(echo $1 | cut -d '.' -f 2)
    c=$(echo $1 | cut -d '.' -f 3)
    if [ "$a" -gt "255" ]; then echo "Error: $a is out of range[0,255]."; exit 1; fi
    if [ "$b" -gt "255" ]; then echo "Error: $b is out of range[0,255]."; exit 1; fi
    if [ "$c" -gt "255" ]; then echo "Error: $c is out of range[0,255]."; exit 1; fi
    (( number = $c + ($b << 8) + ($a << 16) ))
    eval $rvalue="'$number'"
}
checknumber $version refversion

if [ -e $statusfile ]
then
    checknumber $(cat $statusfile) newversion
    if [ "$refversion" -le  "$newversion" ]
    then
         echo "latest version of $0 appears to have been successfully run, use -f option to force script to run."
         exit 0
    fi
fi

sane=true

distributor_id_sane="^Ubuntu$"
release_sane="^14.04$|^16.04$|^18.04$"
codename_sane="^trusty$|^xenial$|^bionic$"
arch_sane="^amd64$"

case "${check_sanity}" in
    true)
        if [ ! -x /usr/bin/lsb_release ] ; then
            echo 'WARNING: /usr/bin/lsb_release not available, cannot test sanity of this system.' 1>&2
            sane=false
        else
            distributor_id=`/usr/bin/lsb_release -s -i`
            release=`/usr/bin/lsb_release -s -r`
            codename=`/usr/bin/lsb_release -s -c`

            if ! echo "${distributor_id}" | egrep -q "${distributor_id_sane}"; then
                echo "WARNING: Distributor ID reported by lsb_release '${distributor_id}' not in '${distributor_id_sane}'" 1>&2
                sane=false
            fi

            if ! echo "${release}" | egrep -q "${release_sane}"; then
                echo "WARNING: Release reported by lsb_release '${release}' not in '${release_sane}'" 1>&2
                sane=false
            fi

            if ! echo "${codename}" | egrep -q "${codename_sane}"; then
                echo "WARNING: Codename reported by lsb_release '${codename}' not in '${codename_sane}'" 1>&2
                sane=false
            fi
        fi

        if [ ! -x /usr/bin/dpkg ] ; then
            echo 'WARNING: /usr/bin/dpkg not available, cannot test architecture of this system.' 1>&2
            sane=false
        else
            arch=`/usr/bin/dpkg --print-architecture`
            if ! echo "${arch}" | egrep -q "${arch_sane}"; then
                echo "WARNING: Architecture reported by dpkg --print-architecture '${arch}' not in '${arch_sane}'" 1>&2
                sane=false
            fi
        fi

        case "${sane}" in
            true) ;;
            false)
                echo 'WARNING: This system configuration is untested. Let us know if it works.' 1>&2
                ;;
        esac
        ;;

    false) ;;
esac

# These are essential to pass OE sanity test
# locales, because utf8 is needed with newer bitbake which uses python3
essential="\
    build-essential \
    chrpath \
    cpio \
    diffstat \
    gawk \
    git \
    iputils-ping \
    locales \
    lsb-release \
    python \
    python2.7 \
    python3 \
    texinfo \
    wget \
"

# add python3-distutils only for 18.04 (and later should be added for newer)
# because it doesn't exist as separate package in older Ubuntu releases
[ `/usr/bin/lsb_release -s -r` = "18.04" ] && essential="${essential} python3-distutils"

# bzip2, gzip, tar, zip are used by our scripts/build.sh
archivers="\
    bzip2 \
    gzip \
    tar \
    zip \
"

# openjdk-11-jdk and ant is needed to build and run localization-tool
# software-properties-common is needed to add ppa for openjdk
# gcc-multilib is needed to build 32bit version of pseudo
# g++-multilib is needed to build and run 32bit mksnapshot of V8 (in chromium53)
extras="\
    gcc-multilib \
    g++-multilib \
    time \
    software-properties-common \
    openjdk-11-jdk
"

# add ppa for openjdk
java_version=`java -version 2>&1 | head -n 1 | cut -d\" -f 2 | cut -d\. -f 1`

add-apt-repository ppa:openjdk-r/ppa --yes
apt-get update

apt-get install --yes \
    ${essential} \
    ${extras} \
    ${archivers} \

if [ -z $java_version ] || [ $java_version -lt 10 ]; then
    update-alternatives --set java /usr/lib/jvm/java-11-openjdk-amd64/bin/java
fi

locale-gen en_US.utf8

echo $version  > $statusfile
