#!/bin/bash

# Copyright 2014-2017 Jonathan Vasquez <jon@xyinn.org>
# 
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation and/or
# other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Instructions:
# ./create.sh <rescue64> <zfs version to display in menu> <path_to_iso>

# Your files will be located in the out/ directory.

H="$(pwd)"
SRM="${H}/zfs-srm"
BIC="/opt/bliss-initramfs"
BIC_EXE="mkinitrd.py"
R="${H}/extract"
IR="${H}/initram"
OUT="${H}/out"
T=`mktemp -d`
VOLUME_ID_NAME="sysresccd_zfs"
ISO_PATH_NEW_OUT="${H}/sysresccd.iso"
ISO_PATH_NEW_DIR=`mktemp -d`
MENU_FILE_NAME="${H}/isolinux-ori.cfg"
MENU_FILE_NAME_NEW="${H}/isolinux-new.cfg"

# Utility Functions

# Extracts a complete module string so that we can use it in /etc/conf.d/modules
extract_module_string()
{
        local kernel_version=$(echo $1 | cut -d "-" -f 1)
        local kernel_version_first=$(echo ${kernel_version} | cut -d "." -f 1)
        local kernel_version_second=$(echo ${kernel_version} | cut -d "." -f 2)
        local kernel_version_third=$(echo ${kernel_version} | cut -d "." -f 3)
        local kernel_label=$(echo $1 | cut -d "-" -f 2)
        local kernel_arch=$(echo $1 | cut -d "-" -f 3)
        local module_string="modules_${kernel_version_first}_${kernel_version_second}_${kernel_version_third}_${kernel_label}_${kernel_arch}"

        echo "${module_string}"
}

# Makes the iso
create_iso()
{
	xorriso -as mkisofs -joliet -rock \
			-omit-version-number -disable-deep-relocation \
			-b isolinux/isolinux.bin -c isolinux/boot.cat \
			-no-emul-boot -boot-load-size 4 -boot-info-table \
			-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
			-volid "${VOLUME_ID_NAME}" -o "${ISO_PATH_NEW_OUT}" "${ISO_PATH_NEW_DIR}"
}

# Used for displaying information
einfo()
{
        eline && echo -e "\e[1;32m>>>\e[0;m ${@}"
}

# Used for input (questions)
eqst()
{
        eline && echo -en "\e[1;37m>>>\e[0;m ${@}"
}

# Used for warnings
ewarn()
{
        eline && echo -e "\e[1;33m>>>\e[0;m ${@}"
}

# Used for flags
eflag()
{
        eline && echo -e "\e[1;34m>>>\e[0;m ${@}"
}

# Used for options
eopt()
{
        echo -e "\e[1;36m>>\e[0;m ${@}"
}


# Prints empty line
eline()
{
    echo ""
}


# Used for errors
die()
{
        eline && echo -e "\e[1;31m>>>\e[0;m ${@}" && eline && exit
}

# Clean up
clean()
{
        rm -rf "${R}" "${SRM}" "${IR}" "${H}"/*-ori* "${OUT}" "${T}" "${ISO_PATH_NEW_DIR}"
}

# Remove 32 bit kernel entry
# Add +ZFS to title
update_menu()
{
	# We really just want to delete the line before the match and everything from the match
	# till the end of the line. But seems complicated and confusing when just using sed.

	# get line number
	local standard32Text="Standard 32bit kernel"
	local endText="MENU END"
	local matchLineNumber=$(grep -n "${standard32Text}" "${MENU_FILE_NAME}" | cut -d ":" -f 1)
	local lineBegin="$(echo "${matchLineNumber} - 4" | bc)"
	local lineEnd="$(echo "${matchLineNumber} - 1" | bc)"
	local MENU_FILE_NAME_TEMP="${MENU_FILE_NAME_NEW}.tmp"

	# Delete lines before the match (to make it pretty) and then delete the menu section
	cat ${MENU_FILE_NAME} | sed "${lineBegin},${lineEnd}d" | sed "/${standard32Text}/,/${endText}/d" > ${MENU_FILE_NAME_TEMP}

	# Add "+ ZFS" after the version in the title to distinguish it from original disks
	local titleText="SYSTEM-RESCUE-CD"
	SRV="$(cat ${MENU_FILE_NAME_TEMP} | grep ${titleText} | cut -d " " -f 4)"
	cat ${MENU_FILE_NAME_TEMP} | sed "s/${SRV}.*/${SRV} + ZFS ${ZFS_VERSION}/" > ${MENU_FILE_NAME_NEW}
}

# ============================================================

if [[ $# != 3 ]] ; then
    die "./create.sh <rescue64> <zfs_version> <path_to_iso>. Example: ./create.sh 4.9.30-std502-amd64 0.6.5.10 /root/sysresccd.iso"
fi

ZFS_VERSION="${2}"
ISO_PATH="${3}"

if [[ ! -f "${ISO_PATH}" ]]; then
    die "${ISO_PATH} doesn't exist."
fi

# We will make sure we are home (We are already home though since H = pwd)
cd ${H}

# First we will extract the required files from the sysresccd iso
einfo "Mounting..."

mount -o ro,loop ${ISO_PATH} ${T} || "Failed to loop mount the iso. Make sure you have loop support in your kernel."

einfo "Copying required files..."

cp -f ${T}/sysrcd.dat sysrcd-ori.dat
cp -f ${T}/isolinux/initram.igz initram-ori.igz
cp -f ${T}/isolinux/isolinux.cfg isolinux-ori.cfg

# Check to see if required files exist
if [ ! -f "sysrcd-ori.dat" ]; then
    die "The 'sysrcd-ori.dat' file doesn't exist."
elif [ ! -f "initram-ori.igz" ]; then
    die "The 'initram-ori.igz' file doesn't exist."
elif [ ! -f "isolinux-ori.cfg" ]; then
    die "The 'isolinux-ori.cfg' file doesn't exist."
fi

# Check to see if the kernel directory exists
if [ ! -d "/usr/src/linux-${1}" ]; then
    die "The kernel directory: /usr/src/linux-${1} doesn't exist."
fi

# Check to see if the kernel modules directory exists
if [ ! -d "/lib64/modules/${1}" ]; then
    die "The kernel modules directory: /lib64/modules/${1} doesn't exist."
else
    if [ ! -d "/lib64/modules/${1}/extra" ]; then
        die "The kernel modules directory for spl/zfs: /lib64/modules/${1}/extra doesn't exist. Please compile your spl and zfs modules before running the application."
    fi
fi

einfo "Creating clean baselayout..."

if [ ! -d "${R}" ]; then
    mkdir ${R}
else
    rm -rf ${R} && mkdir ${R}
fi

if [ ! -d "${IR}" ]; then
    mkdir ${IR}
else
    rm -rf ${IR} && mkdir ${IR}
fi

if [ ! -d "${SRM}" ]; then
    mkdir ${SRM}
else
    rm -rf ${SRM} && mkdir ${SRM}
fi

if [ ! -d ${OUT} ]; then
    mkdir ${OUT}
else
    rm -rf ${OUT} && mkdir ${OUT}
fi

# =========
# Generate the zfs srm (bliss-initramfs basically, and then we strip it to only keep userspace applications and a few other files)
# =========

# Generate a bliss-initramfs and extract it in the zfs-srm directory

cd ${BIC} && ./${BIC_EXE} zfs ${1} && mv initrd-${1} ${SRM} && cd ${SRM}
mv initrd-${1} initrd.gz && cat initrd.gz | gzip -d | cpio -id && rm initrd.gz

# ===========
# Clean out the junk not necessary for sysresccd
# ===========

einfo "Removing unnecessary files from bliss-initramfs and configuring it for sysresccd use..."

# Remove unncessary directories
rm -rf bin/ dev/ proc/ sys/ root/ run/ mnt/ usr/bin/ etc/ \
    init libraries/ lib/modules/ lib/udev/
rm sbin/{depmod,insmod,kmod,lsmod,modinfo,modprobe,rmmod,*udevd} 2> /dev/null

# Make /etc/zfs directory so that the zpool.cache file can be created
# when the user creates/imports their pool in the iso
mkdir -p etc/zfs

# Copy udev files from live system
mkdir -p lib/udev/rules.d
cp /lib64/udev/rules.d/{60-zvol,69-vdev,90-zfs}.rules lib/udev/rules.d
cp /lib64/udev/{vdev,zvol}_id lib/udev

# Perform some substitions so that udev uses the correct udev_id file
# (Needed for making swap zvol - /dev/zvol/<pool name>/<swap dataset name>)
sed -i -e 's:/lib64/:/lib/:' lib/udev/rules.d/69-vdev.rules
sed -i -e 's:/lib64/:/lib/:' lib/udev/rules.d/60-zvol.rules

# ============
# Prepare the sysrcd.dat
# ============

einfo "Extracting sysresccd rootfs and installing our modules/userspace applications into it..."

cd ${R} && unsquashfs ${H}/sysrcd-ori.dat

if [ ! -d "squashfs-root" ]; then
    die "The 'squashfs-root' directory doesn't exist."
fi

einfo "Adding and configuring zfs module strings in the iso's /etc/conf.d/modules..."

# Add our zfs modules to load only for these kernel versions
# This saves the user from having to do a 'modprobe zfs' manually at startup
echo "$(extract_module_string ${1})=\"zfs\"" >> squashfs-root/etc/conf.d/modules

einfo "Removing old kernel modules and copying new ones..."

# Remove the old sysresccd 64 bit kernel modules since we will be replacing them
rm -rf squashfs-root/lib64/modules/${1}

# Copy the spl/zfs modules into the squashfs image (sysresccd rootfs)
cp -r /lib64/modules/${1} squashfs-root/lib64/modules/

# Remove 32 bit modules. Killing 32 bit support for these discs. They are just causing problems
# and I don't use them. If other people use them, they can use another iso. Only 64 bit will be supported.
rm -rf squashfs-root/lib/modules/*-i586

einfo "Regenerating module dependencies from within the sysresccd rootfs..."

# Regenerate module dependencies for the kernel from within the sysresccd rootfs
chroot squashfs-root /bin/bash -l -c "depmod ${1}" 2> /dev/null

# Merge zfs-srm folder with this folder
einfo "Installing zfs userspace applications and files into the sysresccd rootfs..."
rsync -av ${SRM}/ squashfs-root/

einfo "Remaking the squashfs..."
mksquashfs squashfs-root/ ${H}/sysrcd-new.dat

# ============
# Now it's time to work on the initram
# ============

einfo "Extracting the sysresccd initramfs and installing our modules into it..."
cd ${IR} && cat ${H}/initram-ori.igz | xz -d | cpio -id

# Copy the kernel modules to the /lib/modules directory.
mkdir lib/modules
cp -r ${R}/squashfs-root/lib64/modules/${1} lib/modules

# Delete old firmware files for wireless cards (This folder only contains the kernel provided firmware)
rm -rf lib/firmware

# Copy the firmware files for wireless cards (This includes support for all wireless cards - linux-firmware)
cp -r ${R}/squashfs-root/lib/firmware/ lib/firmware

# 32 bit option booting is completely broken because something related to the
# initramfs created here. Switching to busybox cpio did not fix it.
# Maybe someone can figure it out. It seems to be non-deterministic. Sometimes the
# generated isos work, sometimes they don't, but it's definitely do to the initramfs
# created at this point. I really don't care about 32 bit though so I'm not going
# to let that hold back the 64 bit releases (Which everything works on).

# http://www.sysresccd.org/forums/viewtopic.php?f=25&t=5335

# Remake the initramfs
ewarn "Creating the new initram.igz. Please wait a moment since this is a single-threaded operation!"
find . | cpio -H newc -o | xz --check=crc32 --x86 --lzma2 > ${H}/initram-new.igz

# =========
# Edit the isolinux.cfg (remove 32 bit entry and add + ZFS)
# =========

einfo "Editing the isolinux.cfg [Removing 32 bit menu entry and adding '+ ZFS' to the title]"
update_menu

einfo "Renaming other files and making sure all necessary files are in the out/ directory ..."

# Move the new files to the out/ directory
mv ${H}/*-new* ${OUT}

cd ${OUT}
mv sysrcd-new.dat sysrcd.dat && md5sum sysrcd.dat > sysrcd.md5
mv initram-new.igz initram.igz
mv isolinux-new.cfg isolinux.cfg

cp /usr/src/linux-${1}/arch/x86_64/boot/bzImage rescue64

# Generate new iso
einfo "Copying files for new iso ..."
cp -a "${T}"/* "${ISO_PATH_NEW_DIR}"

einfo "Modifying and generating iso ..."
cp sysrcd.* "${ISO_PATH_NEW_DIR}"
cp initram.igz isolinux.cfg *64 "${ISO_PATH_NEW_DIR}/isolinux/"

# Removing 32 bit kernel option from isolinux dir
rm "${ISO_PATH_NEW_DIR}"/isolinux/rescue32

# Remove the 32 bit kernel from the usb_inst.sh script's required files
sed -i -e "s:'???linux/rescue32'::g" "${ISO_PATH_NEW_DIR}"/usb_inst.sh

create_iso

# Unmount and clean up
einfo "Unmounting..." && umount ${T}

clean

einfo "Complete"
