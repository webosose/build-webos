#!/bin/bash

# Copyright (c) 2013-2021 LG Electronics, Inc.
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

# Uncomment line below for debugging
#set -x

# Some constants
SCRIPT_VERSION="6.10.11"
SCRIPT_NAME=`basename $0`
AUTHORITATIVE_OFFICIAL_BUILD_SITE="rpt"

BUILD_REPO="webosose/build-webos"
BUILD_LAYERS=("webosose/meta-webosose")

# Create BOM files, by default disabled
CREATE_BOM=

# Dump signatures, by default disabled
SIGNATURES=

# Build site passed to script from outside (Replaces detecting it from JENKINS_URL)
BUILD_SITE=
# Build job passed to script from outside (Replaces detecting it from JOB_NAME)
BUILD_JOB=
# Branch where to push buildhistory, for repositories on gerrit it should start with refs/heads (Replaces detecting it from JOB_NAME and JENKINS_URL)
BUILD_BUILDHISTORY_BRANCH=
# Name of git remote used in cloned repos
BUILD_REMOTE=origin

# We assume that script is inside scripts subfolder of build project
# and form paths based on that
CALLDIR=${PWD}

BUILD_TIMESTAMP_START=`date -u +%s`
BUILD_TIMESTAMP_OLD=$BUILD_TIMESTAMP_START

TIME_STR="TIME: %e %S %U %P %c %w %R %F %M %x %C"

# We need absolute path for ARTIFACTS
pushd `dirname $0` > /dev/null
SCRIPTDIR=`pwd -P`
popd > /dev/null

# Now let's ensure that:
pushd ${SCRIPTDIR} > /dev/null
if [ ! -d "../scripts" ] ; then
  echo "Make sure that ${SCRIPT_NAME} is in scripts folder of project"
  exit 2
fi
popd > /dev/null

cd "${SCRIPTDIR}/.."

BUILD_TOPDIR=`echo "$SCRIPTDIR" | sed 's#/scripts/*##g'`
ARTIFACTS="${BUILD_TOPDIR}/BUILD-ARTIFACTS"
mkdir -p "${ARTIFACTS}"
BUILD_TIME_LOG=${BUILD_TOPDIR}/time.txt

function print_timestamp {
  BUILD_TIMESTAMP=`date -u +%s`
  BUILD_TIMESTAMPH=`date -u +%Y%m%dT%TZ`

  local BUILD_TIMEDIFF=`expr ${BUILD_TIMESTAMP} - ${BUILD_TIMESTAMP_OLD}`
  local BUILD_TIMEDIFF_START=`expr ${BUILD_TIMESTAMP} - ${BUILD_TIMESTAMP_START}`
  BUILD_TIMESTAMP_OLD=${BUILD_TIMESTAMP}
  printf "TIME: ${SCRIPT_NAME}-${SCRIPT_VERSION} $1: ${BUILD_TIMESTAMP}, +${BUILD_TIMEDIFF}, +${BUILD_TIMEDIFF_START}, ${BUILD_TIMESTAMPH}\n" | tee -a ${BUILD_TIME_LOG}
}

print_timestamp "start"

declare -i RESULT=0

function showusage {
  echo "Usage: ${SCRIPT_NAME} [OPTION...]"
  cat <<!
OPTIONS:
  -I, --images             Images to build
  -T, --targets            Targets to build (unlike images they aren't copied from buildhistory)
  -M, --machines           Machines to build
  -b, --bom                Generate BOM files
  -s, --signatures         Dump sstate signatures, useful to compare why something is rebuilding
  -u, --scp-url            scp will use this path to download and update
                           \${URL}/latest_project_baselines.txt and also
                           \${URL}/history will be populated
  -S, --site               Build site, replaces detecting it from JENKINS_URL
  -j, --jenkins            Jenkins server which triggered this job, replaces detecting it form JENKINS_UL
  -J, --job                Type of job we want to run, replaces detecting it from JOB_NAME
  -B, --buildhistory-ref   Branch where to push buildhistory
                           for repositories on gerrit it should start with refs/heads
                           replaces detecting it from JOB_NAME and JENKINS_URL
  -V, --version            Show script version
  -h, --help               Print this help message
!
  exit 0
}

function wait_for_git_mirror {
    local ref="${1}"
    local nr_of_retries=30
    for i in `seq 1 ${nr_of_retries}`; do
        echo "INFO: ${SCRIPT_NAME}-${SCRIPT_VERSION} trying to fetch revision ${ref} in `pwd` attempt ${i} from ${nr_of_retries}" >&2
        if echo ${ref} | grep -q "^refs/changes/"; then
            git fetch ${BUILD_REMOTE} ${ref} >&2 && return
        else
            local cmd="git log --pretty=oneline -n 1 ${ref} --"
            local contains=`${cmd} 2>/dev/null | wc -l`
            if [ "${contains}" -gt 1 ] ; then
                echo "ERROR: ${SCRIPT_NAME}-${SCRIPT_VERSION} '${cmd}' gave output with more then 1 line unexpectedly in `pwd`." >&2
                exit 1
            elif [ "${contains}" -ne 1 ] ; then
                git remote update >&2
                git fetch ${BUILD_REMOTE} --tags >&2
            else
                echo "INFO: ${SCRIPT_NAME}-${SCRIPT_VERSION} ${ref} is now available in `pwd`." >&2
                return
            fi
        fi
        sleep 30 # wait 30s for git-mirror to get ${ref}
    done
    echo "ERROR: ${SCRIPT_NAME}-${SCRIPT_VERSION} Cannot checkout ${ref} in `pwd`" >&2
    exit 1
}

function check_project {
# Check out appropriate refspec for layer verification based on GERRIT_PROJECT
# or master if we assume other layers stable
  layer=`basename $1`
  if [ -d "${layer}" ] ; then
    pushd "${layer}" >/dev/null
    if [ "${GERRIT_PROJECT}" = "$1" ] ; then
      echo "NOTE: Checking out layer '${layer}' in gerrit refspec '${GERRIT_REFSPEC}'" >&2
      wait_for_git_mirror ${GERRIT_REFSPEC} && git checkout FETCH_HEAD >&2
      if [ $? -ne 0 ] ; then
        echo "ERROR: Failed to checkout layer '${layer}' at gerrit refspec '${GERRIT_REFSPEC}'!" >&2
        exit 1
      fi
    else
      current_branch=`git branch --list|grep ^*\ |awk '{print $2}'`
      echo "NOTE: Run 'git remote update && git reset --hard ${BUILD_REMOTE}/${current_branch}' in layer '${layer}'" >&2
      echo "NOTE: Current branch - ${current_branch}" >&2
      git remote update >&2 && git reset --hard ${BUILD_REMOTE}/${current_branch} >&2
      if [ $? -ne 0 ] ; then
        echo "ERROR: Failed to checkout layer '${layer}' at ref '${ref}'!" >&2
        exit 1
      fi
    fi
    popd >/dev/null
  fi
}

function check_project_vars {
  # Check out appropriate refspec passed in <layer-name>_commit
  # when requested by use_<layer-name>_commit
  layer=`basename $1`
  use=$(eval echo \$"use_${layer//-/_}_commit")
  ref=$(eval echo "\$${layer//-/_}_commit")
  if [ "$use" = "true" ]; then
    echo "NOTE: Checking out layer '${layer}' in ref '${ref}'" >&2
    ldesc=" ${layer}:${ref}"
    if [ -d "${layer}" ] ; then
      pushd "${layer}" >/dev/null
      if echo ${ref} | grep -q '^refs/changes/'; then
        wait_for_git_mirror ${ref} && git checkout FETCH_HEAD >&2
        if [ $? -ne 0 ] ; then
          echo "ERROR: Failed to checkout layer '${layer}' at ref '${ref}'!" >&2
          exit 1
        fi
      else
        # Check if the ref is branch name without remote name
        if git branch -a | grep -q "${BUILD_REMOTE}/@${ref}$"; then
          ref=${BUILD_REMOTE}/@${ref}
          echo "NOTE: Checking out layer '${layer}' as remote branch '${ref}'" >&2
        elif git branch -a | grep -q "${BUILD_REMOTE}/${ref}$"; then
          ref=${BUILD_REMOTE}/${ref}
          echo "NOTE: Checking out layer '${layer}' as remote branch '${ref}'" >&2
        fi
        git remote update >&2 && git fetch ${BUILD_REMOTE} --tags >&2 && wait_for_git_mirror ${ref} && git reset --hard ${ref} >&2;
        if [ $? -ne 0 ] ; then
          echo "ERROR: Failed to checkout layer '${layer}' at ref '${ref}'!" >&2
          exit 1
        fi
      fi
      popd >/dev/null
    else
      echo "ERROR: Layer ${layer} does not exist!" >&2
    fi
  fi
  echo "$ldesc"
}

function unset_buildhistory_commit {
  [ -f webos-local.conf ] && sed -i '/BUILDHISTORY_COMMIT/d' webos-local.conf
  echo "BUILDHISTORY_COMMIT = \"0\"" >> webos-local.conf
}

function set_buildhistory_commit {
  [ -f webos-local.conf ] && sed -i '/BUILDHISTORY_COMMIT/d' webos-local.conf
  echo "BUILDHISTORY_COMMIT = \"1\"" >> webos-local.conf
}

function generate_webos_bom {
  MACHINE=$1
  I=$2
  F=$3

  rm -f webos-bom.json
  rm -f webos-bom-sort.json
  unset_buildhistory_commit
  /usr/bin/time -f "$TIME_STR" bitbake --runall=write_bom_data ${I} 2>&1 | tee /dev/stderr | grep '^TIME:' >> ${BUILD_TIME_LOG}
  [ -d ${ARTIFACTS}/${MACHINE}/${I} ] || mkdir -p ${ARTIFACTS}/${MACHINE}/${I}
  sort webos-bom.json > webos-bom-sort.json
  sed -e '1s/^{/[{/' -e '$s/,$/]/' webos-bom-sort.json > ${ARTIFACTS}/${MACHINE}/${I}/${F}
}

function filter_images {
  FILTERED_IMAGES=""
  # remove images which aren't available for some MACHINEs
  # no restriction in webos
  FILTERED_IMAGES="${IMAGES}"
  if [ -n "${IMAGES}" -a -z "${FILTERED_IMAGES}" ] ; then
    echo "ERROR: All images were filtered for MACHINE: '${MACHINE}', IMAGES: '${IMAGES}'"
  fi
}

function call_bitbake {
  filter_images
  set_buildhistory_commit
  /usr/bin/time -f "$TIME_STR" bitbake ${BBFLAGS} ${FILTERED_IMAGES} ${TARGETS} 2>&1 | tee /dev/stderr | grep '^TIME:' >> ${BUILD_TIME_LOG}

  # Be aware that non-zero exit code from bitbake doesn't always mean that images weren't created.
  # All images were created if it shows "all succeeded" in" Tasks Summary":
  # NOTE: Tasks Summary: Attempted 5450 tasks of which 5205 didn't need to be rerun and all succeeded.

  # Sometimes it's followed by:
  # Summary: There were 2 ERROR messages shown, returning a non-zero exit code.
  # the ERRORs can be from failed setscene tasks or from QA checks, but weren't fatal for build.

  # Collect exit codes to return them from this script (Use PIPESTATUS to read return code from bitbake, not from added tee)
  RESULT+=${PIPESTATUS[0]}
}

function add_md5sums_and_buildhistory_artifacts {
  local I
  for I in ${FILTERED_IMAGES}; do
    local found_image=false
    # Add .md5 files for image files, if they are missing or older than image file
    local IMG_FILE
    for IMG_FILE in ${ARTIFACTS}/${MACHINE}/${I}/*.vmdk* \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.tar.gz \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.tar.bz2 \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.rpi-sdimg \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.rpi-sdimg.gz \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.wic \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.wic.gz \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.zip \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.vfat \
                    ${ARTIFACTS}/${MACHINE}/*.fastboot \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.fastboot \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.epk \
                    ${ARTIFACTS}/${MACHINE}/${I}/*.sh \
                    ${ARTIFACTS}/${SDKMACHINE}/*.sh; do
      if echo ${IMG_FILE} | grep -q "\.md5$"; then
        continue
      fi
      if [ -e ${IMG_FILE} -a ! -L ${IMG_FILE} ] ; then
        found_image=true
        if [ ! -e ${IMG_FILE}.md5 -o ${IMG_FILE}.md5 -ot ${IMG_FILE} ] ; then
          echo MD5: ${IMG_FILE}
          md5sum ${IMG_FILE} | sed 's#  .*/#  #g' > ${IMG_FILE}.md5
        fi
      fi
    done

    # copy few interesting buildhistory reports only if the image was really created
    # (otherwise old report from previous build checked out from buildhistory repo could be used)
    if $found_image ; then
      add_buildhistory_artifacts
    fi
  done
}

function add_buildhistory_artifacts {
  # XXX Might there be other subdirectories under buildhistory/sdk that weren't created by this build?
  # Some MACHINEs like raspberrypi3-64 now contain dash which gets converted to underscore
  # for MACHINE_ARCH, which is also the directory in buildhistory
  BHMACHINE=`echo ${MACHINE} | sed 's/-/_/g'`
  if ls buildhistory/sdk/*/${I} >/dev/null 2>/dev/null; then
    if [ -n "${SDKMACHINE}" ] ; then
      for d in buildhistory/sdk/${I}-${SDKMACHINE}-*; do
        [ -d ${ARTIFACTS}/${SDKMACHINE}/${MACHINE} ] || mkdir -p ${ARTIFACTS}/${SDKMACHINE}/${MACHINE}/
        cp -a $d/${I} ${ARTIFACTS}/${SDKMACHINE}/${MACHINE}/
      done
    else
      for d in buildhistory/sdk/*; do
        mkdir -p ${ARTIFACTS}/${MACHINE}/
        cp -a $d/${I} ${ARTIFACTS}/${MACHINE}/
      done
    fi
  else
    if [ -f buildhistory/images/${BHMACHINE}/glibc/${I}/build-id.txt ]; then
      ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/build-id.txt ${ARTIFACTS}/${MACHINE}/${I}/build-id.txt
    else
      ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/build-id ${ARTIFACTS}/${MACHINE}/${I}/build-id.txt
    fi
    if [ -z "$FIRST_IMAGE" -a -e ${ARTIFACTS}/${MACHINE}/${I}/build-id.txt ] ; then
      # store build-id.txt from first IMAGE and first MACHINE as representant of whole build for InfoBadge
      # instead of requiring jenkins job to hardcode MACHINE/IMAGE name in:
      # manager.addInfoBadge("${manager.build.getWorkspace().child('buildhistory/images/qemux86/glibc/webos-image/build-id.txt').readToString()}")
      # we should be able to use:
      # manager.addInfoBadge("${manager.build.getWorkspace().child('BUILD-ARTIFACTS/build-id.txt').readToString()}")
      # in all builds (making BUILD_IMAGES/BUILD_MACHINE changes less error-prone)
      FIRST_IMAGE="${MACHINE}/${I}"
      ln -vnf ${ARTIFACTS}/${MACHINE}/${I}/build-id.txt ${ARTIFACTS}/build-id.txt
    fi
    ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/image-info.txt ${ARTIFACTS}/${MACHINE}/${I}/image-info.txt
    ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/files-in-image.txt ${ARTIFACTS}/${MACHINE}/${I}/files-in-image.txt
    ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/installed-packages.txt ${ARTIFACTS}/${MACHINE}/${I}/installed-packages.txt
    ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/installed-package-names.txt ${ARTIFACTS}/${MACHINE}/${I}/installed-package-names.txt
    ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/installed-package-sizes.txt ${ARTIFACTS}/${MACHINE}/${I}/installed-package-sizes.txt
    if [ -e buildhistory/images/${BHMACHINE}/glibc/${I}/installed-package-file-sizes.txt ] ; then
      ln -vn buildhistory/images/${BHMACHINE}/glibc/${I}/installed-package-file-sizes.txt ${ARTIFACTS}/${MACHINE}/${I}/installed-package-file-sizes.txt
    fi
  fi
}

function move_kernel_image_and_add_symlinks {
  # include .fastboot kernel image if present; XXX we are assuming that their
  # basenames start with "linux"
  if ls BUILD/deploy/images/${MACHINE}/linux*.fastboot >/dev/null 2>/dev/null; then
    [ -d ${ARTIFACTS}/${MACHINE}/kernel/ ] || mkdir -p ${ARTIFACTS}/${MACHINE}/kernel/
    ln -vn BUILD/deploy/images/${MACHINE}/linux*.fastboot ${ARTIFACTS}/${MACHINE}/kernel/
    # create symlinks in all image directories
    local I
    for I in ${FILTERED_IMAGES}; do
      if [ -d ${ARTIFACTS}/${MACHINE}/${I} ] ; then
        pushd ${ARTIFACTS}/${MACHINE}/${I} >/dev/null
          local f
          for f in ../kernel/linux*.fastboot; do
            ln -snf $f .
          done
        popd >/dev/null
      fi
    done
  fi
}

function move_artifacts {
  for I in ${FILTERED_IMAGES}; do
    mkdir -p "${ARTIFACTS}/${MACHINE}/${I}" || true
    # we store only tar.gz, vmdk.zip and .epk images
    # and we don't publish kernel images anymore
    if ls BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.vmdk >/dev/null 2>/dev/null; then
      if type zip >/dev/null 2>/dev/null; then
        # zip vmdk images if they exists
        find BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.vmdk -exec zip -j {}.zip {} \;
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.vmdk.zip ${ARTIFACTS}/${MACHINE}/${I}/
      else
        # report failure and publish vmdk
        echo "ERROR: ${SCRIPT_NAME}-${SCRIPT_VERSION} zip utility isn't installed on the build server" >&2
        RESULT+=1
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.vmdk ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      # copy webosvbox if we've built vmdk image
      if [ -e meta-webosose/meta-webos/scripts/webosvbox -a ! -e ${ARTIFACTS}/${MACHINE}/webosvbox ] ; then
        ln -vn meta-webosose/meta-webos/scripts/webosvbox ${ARTIFACTS}/${MACHINE}
      fi
      # copy few more files for creating different vmdk files with the same rootfs
      if ls BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.rootfs.ext3 >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.rootfs.ext3 ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*-dbg.tar.gz >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*-dbg.tar.gz ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if [ -e BUILD/sysroots/${MACHINE}/usr/lib/syslinux/mbr.bin ] ; then
        ln -vn BUILD/sysroots/${MACHINE}/usr/lib/syslinux/mbr.bin ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      # this won't work in jobs which inherit rm_work, but until we change the image build to stage them use WORKDIR paths
      if ls BUILD/work/${MACHINE}*/${I}/*/*/hdd/boot/ldlinux.sys >/dev/null 2>/dev/null; then
        ln -vn BUILD/work/${MACHINE}*/${I}/*/*/hdd/boot/ldlinux.sys ${ARTIFACTS}/${MACHINE}/${I}/
      else
        echo "INFO: ldlinux.sys doesn't exist, probably using rm_work"
      fi
      if ls BUILD/work/${MACHINE}*/${I}/*/*/hdd/boot/syslinux.cfg >/dev/null 2>/dev/null; then
        ln -vn BUILD/work/${MACHINE}*/${I}/*/*/hdd/boot/syslinux.cfg ${ARTIFACTS}/${MACHINE}/${I}/
      else
        echo "INFO: syslinux.cfg doesn't exist, probably using rm_work"
      fi
      if ls BUILD/work/${MACHINE}*/${I}/*/*/hdd/boot/vmlinuz >/dev/null 2>/dev/null; then
        ln -vn BUILD/work/${MACHINE}*/${I}/*/*/hdd/boot/vmlinuz ${ARTIFACTS}/${MACHINE}/${I}/
      else
        echo "INFO: vmlinuz doesn't exist, probably using rm_work"
      fi
    elif ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.rpi-sdimg >/dev/null 2>/dev/null; then
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.rpi-sdimg >/dev/null 2>/dev/null; then
        gzip -f BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.rpi-sdimg
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.rpi-sdimg.gz ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.gz >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.gz ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.bz2 >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.bz2 ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.vfat >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.vfat ${ARTIFACTS}/${MACHINE}/${I}/
      fi
    elif ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.wic >/dev/null 2>/dev/null; then
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.wic >/dev/null 2>/dev/null; then
        gzip -f BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.wic
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.wic.gz ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.bz2 >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.bz2 ${ARTIFACTS}/${MACHINE}/${I}/
      fi
    elif ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.gz >/dev/null 2>/dev/null \
      || ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.fastboot >/dev/null 2>/dev/null \
      || ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.epk    >/dev/null 2>/dev/null; then
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*-dbg.tar.gz >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*-dbg.tar.gz ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.gz >/dev/null 2>/dev/null; then
        for TARBALL in BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.gz; do
          if echo $TARBALL | grep -q ".-dbg.*.tar.gz"; then
            continue
          fi
          ln -vn ${TARBALL} ${ARTIFACTS}/${MACHINE}/${I}/
        done
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.fastboot >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.fastboot ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.epk >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.epk ${ARTIFACTS}/${MACHINE}/${I}/
      fi
    elif ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.bz2 >/dev/null 2>/dev/null \
      || ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.zip >/dev/null 2>/dev/null; then
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.bz2 >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.tar.bz2 ${ARTIFACTS}/${MACHINE}/${I}/
      fi
      if ls    BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.zip >/dev/null 2>/dev/null; then
        ln -vn BUILD/deploy/images/${MACHINE}/${I}-${MACHINE}-*.zip ${ARTIFACTS}/${MACHINE}/${I}/
      fi
    elif ls BUILD/deploy/sdk/${I}-*.sh >/dev/null 2>/dev/null; then
      if [ -n "${SDKMACHINE}" ] ; then
        [ -d ${ARTIFACTS}/${SDKMACHINE} ] || mkdir -p ${ARTIFACTS}/${SDKMACHINE}
        ln -vn BUILD/deploy/sdk/${I}-*.sh ${ARTIFACTS}/${SDKMACHINE}/
      else
        ln -vn BUILD/deploy/sdk/${I}-*.sh ${ARTIFACTS}/${MACHINE}/${I}/
      fi
    else
      echo "WARN: No ${I} images with recognized IMAGE_FSTYPES found to copy as build artifacts"
    fi

    if ls    BUILD/deploy/images/${MACHINE}/${I}-oss-pkg-info.yaml >/dev/null 2>/dev/null; then
      ln -vn BUILD/deploy/images/${MACHINE}/${I}-oss-pkg-info.yaml ${ARTIFACTS}/${MACHINE}/${I}/oss-pkg-info.yaml
    else
      echo "WARN: No oss-pkg-info.yaml to copy as build artifacts"
    fi

    if ls    BUILD/deploy/images/${MACHINE}/${I}-dependency.json >/dev/null 2>/dev/null; then
      ln -vn BUILD/deploy/images/${MACHINE}/${I}-dependency.json ${ARTIFACTS}/${MACHINE}/${I}/dependency.json
    else
      echo "WARN: No dependency.json to copy as build artifacts"
    fi

    # delete possibly empty directories
    rmdir --ignore-fail-on-non-empty ${ARTIFACTS}/${MACHINE}/${I} ${ARTIFACTS}/${MACHINE}
  done

  if ls BUILD/deploy/images/${MACHINE}/partitiongroup-*.tar.bz2 >/dev/null 2>/dev/null; then
    mkdir -p ${ARTIFACTS}/${MACHINE}/partitiongroups/
    # don't copy the symlinks without WEBOS_VERSION suffix
    find BUILD/deploy/images/${MACHINE}/ -name partitiongroup-\*.tar.bz2 -type f -exec cp -a {} ${ARTIFACTS}/${MACHINE}/partitiongroups/ \;
  fi

  if [ "${BUILD_ENABLE_RSYNC_IPK}" = "Y" ] ; then
    if ls BUILD/deploy/ipk/* >/dev/null 2>/dev/null; then
      cp -ra BUILD/deploy/ipk ${ARTIFACTS}
    else
      echo "WARN: No ipk files to copy to build artifacts"
    fi
  fi

  move_kernel_image_and_add_symlinks
  add_md5sums_and_buildhistory_artifacts
}

TEMP=`getopt -o I:T:M:S:j:J:B:u:bshV --long images:,targets:,machines:,scp-url:,site:,jenkins:,job:,buildhistory-ref:,bom,signatures,help,version \
     -n $(basename $0) -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 2 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
  case $1 in
    -I|--images) IMAGES="$2" ; shift 2 ;;
    -T|--targets) TARGETS="$2" ; shift 2 ;;
    -M|--machines) BMACHINES="$2" ; shift 2 ;;
    -S|--site) BUILD_SITE="$2" ; shift 2 ;;
    -j|--jenkins) BUILD_JENKINS_SERVER="$2" ; shift 2 ;;
    -J|--job) BUILD_JOB="$2" ; shift 2 ;;
    -B|--buildhistory-ref) BUILD_BUILDHISTORY_PUSH_REF="$2" ; shift 2 ;;
    -u|--scp-url) URL="$2" ; shift 2 ;;
    -b|--bom) CREATE_BOM="Y" ; shift ;;
    -s|--signatures) SIGNATURES="Y" ; shift ;;
    -h|--help) showusage ; shift ;;
    -V|--version) echo ${SCRIPT_NAME} ${SCRIPT_VERSION}; exit ;;
    --) shift ; break ;;
    *) echo "${SCRIPT_NAME} Unrecognized option '$1'";
       showusage ;;
  esac
done

# Has mcf been run and generated a makefile?
if [ ! -f "Makefile" ] ; then
  echo "Make sure that mcf has been run and Makefile has been generated"
  exit 2
fi

if [ -z "${BUILD_SITE}" -o "${BUILD_JENKINS_SERVER}" = "anaconda" ]; then
  # Let the distro determine the policy on setting WEBOS_DISTRO_BUILD_ID when builds
  # are unofficial
  unset WEBOS_DISTRO_BUILD_ID
else
  # If this is an official build, no BUILD_JOB prefix appears in
  # WEBOS_DISTRO_BUILD_ID regardless of the build site.
  if [ "${BUILD_JOB}" = "official" ]; then
    if [ "${BUILD_SITE}" = "${AUTHORITATIVE_OFFICIAL_BUILD_SITE}" ]; then
      BUILD_SITE=""
    fi
    BUILD_JOB=""
  else
    # BUILD_JOB can not contain any hyphens
    BUILD_JOB="${BUILD_JOB//-/}"
  fi

  # Append the separators to site and build-type.
  #
  # Use intermediate variables so that the remainder of the script need not concern
  # itself with the separators, which are purely related to formatting the build id.
  idsite="${BUILD_SITE}"
  idtype="${BUILD_JOB}"

  if [ -n "$idsite" ]; then
    idsite="${idsite}-"
  fi

  if [ -n "$idtype" ]; then
    idtype="${idtype}."
  fi

  # BUILD_NUMBER should be set by the Jenkins executor
  if [ -z "${BUILD_NUMBER}" ] ; then
    echo "BUILD_SITE is set, but BUILD_NUMBER isn't"
    exit 1
  fi

  # Format WEBOS_DISTRO_BUILD_ID as <build-type>.<site>-<build number>
  export WEBOS_DISTRO_BUILD_ID=${idtype}${idsite}${BUILD_NUMBER}
fi

# Generate BOM files with metadata checked out by mcf (pinned versions)
if [ -n "${CREATE_BOM}" -a -n "${BMACHINES}" ]; then
  print_timestamp "before first bom"
  if [ "${BUILD_JOB}" = "verf" -o "${BUILD_JOB}" = "mlverf" -o "${BUILD_JOB}" = "integ" -o "${BUILD_JOB}" = "engr" -o "${BUILD_JOB}" = "clean" ] ; then
    # don't use -before suffix for official builds, because they don't need -after and .diff because
    # there is no logic for using different revisions than weboslayers.py
    BOM_FILE_SUFFIX="-before"
  fi
  . oe-init-build-env
  for MACHINE in ${BMACHINES}; do
    filter_images
    for I in ${FILTERED_IMAGES} ${TARGETS}; do
      generate_webos_bom "${MACHINE}" "${I}" "webos-bom${BOM_FILE_SUFFIX}.json"
    done
  done
fi

print_timestamp "before verf/engr/clean logic"

if [ "${BUILD_JOB}" = "verf" -o "${BUILD_JOB}" = "mlverf" -o "${BUILD_JOB}" = "integ" -o "${BUILD_JOB}" = "engr" ] ; then
  if [ "$GERRIT_PROJECT" != "${BUILD_REPO}" ] ; then
    set -e # checkout issues are critical for verification and engineering builds
    for project in "${BUILD_LAYERS[@]}" ; do
      check_project ${project}
    done
    set +e
  fi
  # use -k for verf and engr builds, see [ES-85]
  BBFLAGS="${BBFLAGS} -k"
fi

if [ "${BUILD_JOB}" = "clean" ] ; then
  set -e # checkout issues are critical for clean build
  desc="[DESC]"
  for project in "${BUILD_LAYERS[@]}" ; do
    desc="${desc}`check_project_vars ${project}`"
  done
  # This is picked by regexp in jenkins config as description of the build
  echo $desc
  set +e
fi

# Generate BOM files again, this time with metadata possibly different for engineering and verification builds
if [ -n "${CREATE_BOM}" -a -n "${BMACHINES}" ]; then
  if [ "${BUILD_JOB}" = "verf" -o "${BUILD_JOB}" = "mlverf" -o "${BUILD_JOB}" = "integ" -o "${BUILD_JOB}" = "engr" -o "${BUILD_JOB}" = "clean" ] ; then
    print_timestamp "before 2nd bom"
    . oe-init-build-env
    for MACHINE in ${BMACHINES}; do
      filter_images
      for I in ${FILTERED_IMAGES} ${TARGETS}; do
        generate_webos_bom "${MACHINE}" "${I}" "webos-bom-after.json"
        diff ${ARTIFACTS}/${MACHINE}/${I}/webos-bom-before.json \
             ${ARTIFACTS}/${MACHINE}/${I}/webos-bom-after.json \
           > ${ARTIFACTS}/${MACHINE}/${I}/webos-bom-diff.txt
      done
    done
  fi
fi

print_timestamp "before signatures"

if [ -n "${SIGNATURES}" -a -n "${BMACHINES}" ]; then
  . oe-init-build-env
  for MACHINE in ${BMACHINES}; do
    mkdir -p "${ARTIFACTS}/${MACHINE}" || true
    filter_images
    # normally this is executed for all MACHINEs together, but we're using MACHINE-specific FILTERED_IMAGES
    oe-core/scripts/sstate-diff-machines.sh --tmpdir=BUILD --targets="${FILTERED_IMAGES} ${TARGETS}" --machines="${MACHINE}"
    tar cjf ${ARTIFACTS}/${MACHINE}/sstate-diff.tar.bz2 BUILD/sstate-diff/*/${MACHINE} --remove-files
  done
fi

# If there is git checkout in buildhistory dir and we have BUILD_BUILDHISTORY_PUSH_REF
# add or replace push repo in webos-local
# Write it this way so that BUILDHISTORY_PUSH_REPO is kept in the same place in webos-local.conf
if [ -d "buildhistory/.git" -a -n "${BUILD_BUILDHISTORY_PUSH_REF}" ] ; then
  if [ -f webos-local.conf ] && grep -q ^BUILDHISTORY_PUSH_REPO webos-local.conf ; then
    sed "s#^BUILDHISTORY_PUSH_REPO.*#BUILDHISTORY_PUSH_REPO ?= \"${BUILD_REMOTE} HEAD:${BUILD_BUILDHISTORY_PUSH_REF}\"#g" -i webos-local.conf
  else
    echo "BUILDHISTORY_PUSH_REPO ?= \"${BUILD_REMOTE} HEAD:${BUILD_BUILDHISTORY_PUSH_REF}\"" >> webos-local.conf
  fi
  echo "INFO: buildhistory will be pushed to '${BUILD_BUILDHISTORY_PUSH_REF}'"
  pushd buildhistory > /dev/null
  git remote -v
  git branch
  popd > /dev/null

else
  [ -f webos-local.conf ] && sed "/^BUILDHISTORY_PUSH_REPO.*/d" -i webos-local.conf
  echo "INFO: buildhistory won't be pushed because buildhistory directory isn't git repo or BUILD_BUILDHISTORY_PUSH_REF wasn't set"
fi

print_timestamp "before main '${JOB_NAME}' build"

FIRST_IMAGE=
if [ -z "${BMACHINES}" ]; then
  echo "ERROR: calling build.sh without -M parameter"
else
  . oe-init-build-env
  if [ -n "${BUILD_SDKMACHINES}" ] && echo "${IMAGES}" | grep -q "^[^- ]\+-bdk$" ; then
    # if there is only one image ending with "-bdk" and BUILD_SDKMACHINES is defined
    # then build it for every SDKMACHINE before moving the artifacts
    for SDKMACHINE in ${BUILD_SDKMACHINES}; do
      export SDKMACHINE
      for MACHINE in ${BMACHINES}; do
        call_bitbake
        move_artifacts
      done
    done
  else
    for MACHINE in ${BMACHINES}; do
      call_bitbake
      move_artifacts
    done
  fi

  grep -R "Elapsed time" BUILD/buildstats | sed 's/^.*\/\([^\/]*\/[^\/]*\):Elapsed time: \(.*\)$/\2 \1/g' | sort -n | tail -n 20 | tee -a ${ARTIFACTS}/top20buildstats.txt
  tar cjf ${ARTIFACTS}/buildstats.tar.bz2 BUILD/buildstats
  if [ -e BUILD/qa.log ]; then
    ln -vn BUILD/qa.log ${ARTIFACTS} || true
    # show them in console log so they are easier to spot (without downloading qa.log from artifacts
    echo "WARN: Following QA issues were found:"
    cat BUILD/qa.log
  else
    echo "NOTE: No QA issues were found."
  fi
  if [ -d BUILD/deploy/sources ] ; then
    # exclude diff.gz files, because with old archiver they contain whole source (nothing creates .orig directory)
    # see http://lists.openembedded.org/pipermail/openembedded-core/2013-December/087729.html
    tar czf ${ARTIFACTS}/sources.tar.gz BUILD/deploy/sources --exclude \*.diff.gz
  fi
fi

print_timestamp "before baselines"

# Don't do these for unofficial builds
if [ -n "${WEBOS_DISTRO_BUILD_ID}" -a "${RESULT}" -eq 0 ]; then
  if [ ! -f latest_project_baselines.txt ]; then
    # create dummy, especially useful for verification builds (diff against ${BUILD_REMOTE}/master)
    echo ". ${BUILD_REMOTE}/master" > latest_project_baselines.txt
    for project in "${BUILD_LAYERS[@]}" ; do
      layer=`basename ${project}`
      if [ -d "${layer}" ] ; then
        echo "${layer} ${BUILD_REMOTE}/master" >> latest_project_baselines.txt
      fi
    done
  fi

  command \
    meta-webosose/meta-webos/scripts/build-changes/update_build_changes.sh \
      "${BUILD_NUMBER}" \
      "${URL}" 2>&1 || printf "\nChangelog generation failed or script not found.\nPlease check lines above for errors\n"
  ln -vn build_changes.log ${ARTIFACTS} || true
fi

print_timestamp "stop"

cd "${CALLDIR}"

# only the result from bitbake/make is important
exit ${RESULT}

# vim: ts=2 sts=2 sw=2 et
