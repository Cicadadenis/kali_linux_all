#!/bin/bash
# This is the FriendlyARM NanoPi2 Kali ARM build script - http://nanopi.io/
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com
set -e

# Uncomment to activate debug
# debug=true
if [ "$debug" = true ]; then
  exec > >(tee -a -i "${0%.*}.log") 2>&1
  set -x
fi

# Architecture
architecture=${architecture:-"armhf"}
# Generate a random machine name to be used.
machine=$(dbus-uuidgen)
# Custom hostname variable
hostname=${2:-kali}
# Custom image file name variable - MUST NOT include .img at the end.
imagename=${3:-kali-linux-$1-nanopi2}
# Suite to use, valid options are:
# kali-rolling, kali-dev, kali-bleeding-edge, kali-dev-only, kali-experimental, kali-last-snapshot
suite=${suite:-"kali-rolling"}
# Free space rootfs in MiB
free_space="300"
# /boot partition in MiB
bootsize="128"
# Select compression, xz or none
compress="xz"
# Choose filesystem format to format ( ext3 or ext4 )
fstype="ext3"
# If you have your own preferred mirrors, set them here.
mirror=${mirror:-"http://http.kali.org/kali"}
# Gitlab url Kali repository
kaligit="https://gitlab.com/kalilinux"
# Github raw url
githubraw="https://raw.githubusercontent.com"

# Check EUID=0 you can run any binary as root.
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or have super user permissions"
  echo "Use: sudo $0 ${1:-2.0} ${2:-kali}"
  exit 1
fi

# Pass version number
if [[ $# -eq 0 ]] ; then
  echo "Please pass version number, e.g. $0 2.0, and (if you want) a hostname, default is kali"
  exit 0
fi

# Check exist bsp directory.
if [ ! -e "bsp" ]; then
  echo "Error: missing bsp directory structure"
  echo "Please clone the full repository ${kaligit}/build-scripts/kali-arm"
  exit 255
fi

# Current directory
current_dir="$(pwd)"
# Base directory
basedir=${current_dir}/nanopi2-"$1"
# Working directory
work_dir="${basedir}/kali-${architecture}"

# Check directory build
if [ -e "${basedir}" ]; then
  echo "${basedir} directory exists, will not continue"
  exit 1
elif [[ ${current_dir} =~ [[:space:]] ]]; then
  echo "The directory "\"${current_dir}"\" contains whitespace. Not supported."
  exit 1
else
  echo "The basedir thinks it is: ${basedir}"
  mkdir -p ${basedir}
fi

components="main,contrib,non-free"
arm="kali-linux-arm ntpdate"
base="apt-transport-https apt-utils bash-completion console-setup dialog e2fsprogs ifupdown initramfs-tools inxi iw man-db mlocate netcat-traditional net-tools parted psmisc rfkill screen tmux unrar usbutils vim wget whiptail zerofree"
desktop="kali-desktop-xfce kali-root-login xserver-xorg-video-fbdev xfonts-terminus xinput"
tools="kali-linux-default"
services="apache2 atftpd"
extras="alsa-utils bc bison crda bluez bluez-firmware i2c-tools kali-linux-core libnss-systemd libssl-dev python3-smbus triggerhappy"

packages="${arm} ${base} ${services}"

# Automatic configuration to use an http proxy, such as apt-cacher-ng.
# You can turn off automatic settings by uncommenting apt_cacher=off.
# apt_cacher=off
# By default the proxy settings are local, but you can define an external proxy.
# proxy_url="http://external.intranet.local"
apt_cacher=${apt_cacher:-"$(lsof -i :3142|cut -d ' ' -f3 | uniq | sed '/^\s*$/d')"}
if [ -n "$proxy_url" ]; then
  export http_proxy=$proxy_url
elif [ "$apt_cacher" = "apt-cacher-ng" ] ; then
  if [ -z "$proxy_url" ]; then
    proxy_url=${proxy_url:-"http://127.0.0.1:3142/"}
    export http_proxy=$proxy_url
  fi
fi

# Detect architecture
case ${architecture} in
  arm64)
    qemu_bin="/usr/bin/qemu-aarch64-static"
    lib_arch="aarch64-linux-gnu" ;;
  armhf)
    qemu_bin="/usr/bin/qemu-arm-static"
    lib_arch="arm-linux-gnueabihf" ;;
  armel)
    qemu_bin="/usr/bin/qemu-arm-static"
    lib_arch="arm-linux-gnueabi" ;;
esac

# create the rootfs - not much to modify here, except maybe throw in some more packages if you want.
eatmydata debootstrap --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --include=kali-archive-keyring,eatmydata \
  --components=${components} --arch ${architecture} ${suite} ${work_dir} http://http.kali.org/kali

# systemd-nspawn enviroment
systemd-nspawn_exec(){
  LANG=C systemd-nspawn -q --bind-ro ${qemu_bin} --capability=cap_setfcap --setenv=RUNLEVEL=1 -M ${machine} -D ${work_dir} "$@"
}

# We need to manually extract eatmydata to use it for the second stage.
for archive in ${work_dir}/var/cache/apt/archives/*eatmydata*.deb; do
  dpkg-deb --fsys-tarfile "$archive" > ${work_dir}/eatmydata
  tar -xkf ${work_dir}/eatmydata -C ${work_dir}
  rm -f ${work_dir}/eatmydata
done

# Prepare dpkg to use eatmydata
systemd-nspawn_exec dpkg-divert --divert /usr/bin/dpkg-eatmydata --rename --add /usr/bin/dpkg

cat > ${work_dir}/usr/bin/dpkg << EOF
#!/bin/sh
if [ -e /usr/lib/${lib_arch}/libeatmydata.so ]; then
    [ -n "\${LD_PRELOAD}" ] && LD_PRELOAD="\$LD_PRELOAD:"
    LD_PRELOAD="\$LD_PRELOAD\$so"
fi
for so in /usr/lib/${lib_arch}/libeatmydata.so; do
    [ -n "\$LD_PRELOAD" ] && LD_PRELOAD="\$LD_PRELOAD:"
    LD_PRELOAD="\$LD_PRELOAD\$so"
done
export LD_PRELOAD
exec "\$0-eatmydata" --force-unsafe-io "\$@"
EOF
chmod 755 ${work_dir}/usr/bin/dpkg

# debootstrap second stage
systemd-nspawn_exec eatmydata /debootstrap/debootstrap --second-stage

cat << EOF > ${work_dir}/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF

mkdir -p ${work_dir}/etc/network/
cat << EOF > ${work_dir}/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

# This prevents NetworkManager from attempting to use this
# device to connect to wifi, since NM doesn't show which device is which.
# Unfortunately, it still SHOWS the device, just that it's not managed.
iface p2p0 inet manual
EOF

# Set hostname
echo "${hostname}" > ${work_dir}/etc/hostname

# So X doesn't complain, we add kali to hosts
cat << EOF > ${work_dir}/etc/hosts
127.0.0.1       ${hostname}    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# Disable IPv6
cat << EOF > ${work_dir}/etc/modprobe.d/ipv6.conf
# Don't load ipv6 by default
alias net-pf-10 off
EOF

# Copy directory bsp into build dir.
cp -rp bsp ${work_dir}

export MALLOC_CHECK_=0 # workaround for LP: #520465

# Enable the use of http proxy in third-stage in case it is enabled.
if [ -n "$proxy_url" ]; then
  echo "Acquire::http { Proxy \"$proxy_url\" };" > ${work_dir}/etc/apt/apt.conf.d/66proxy
fi

# Third stage
cat << EOF >  ${work_dir}/third-stage
#!/bin/bash -e
export DEBIAN_FRONTEND=noninteractive

eatmydata apt-get update

eatmydata apt-get -y install binutils ca-certificates console-common git initramfs-tools less locales nano u-boot-tools

# Create kali user with kali password... but first, we need to manually make some groups because they don't yet exist...
# This mirrors what we have on a pre-installed VM, until the script works properly to allow end users to set up their own... user.
# However we leave off floppy, because who a) still uses them, and b) attaches them to an SBC!?
# And since a lot of these have serial devices of some sort, dialout is added as well.
# scanner, lpadmin and bluetooth have to be added manually because they don't
# yet exist in /etc/group at this point.
groupadd -r -g 118 bluetooth
groupadd -r -g 113 lpadmin
groupadd -r -g 122 scanner
groupadd -g 1000 kali

useradd -m -u 1000 -g 1000 -G sudo,audio,bluetooth,cdrom,dialout,dip,lpadmin,netdev,plugdev,scanner,video,kali -s /bin/bash kali
echo "kali:kali" | chpasswd

aptops="--allow-change-held-packages -o dpkg::options::=--force-confnew -o Acquire::Retries=3"

# This looks weird, but we do it twice because every so often, there's a failure to download from the mirror
# So to workaround it, we attempt to install them twice.
eatmydata apt-get install -y \$aptops ${packages} || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get install -y \$aptops ${packages} || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get install -y \$aptops ${desktop} ${extras} ${tools} || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get install -y \$aptops ${desktop} ${extras} ${tools} || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get install -y \$aptops --autoremove systemd-timesyncd || eatmydata apt-get --yes --fix-broken install
eatmydata apt-get dist-upgrade -y \$aptops

eatmydata apt-get -y --allow-change-held-packages --purge autoremove

# Linux console/Keyboard configuration
echo 'console-common console-data/keymap/policy select Select keymap from full list' | debconf-set-selections
echo 'console-common console-data/keymap/full select en-latin1-nodeadkeys' | debconf-set-selections

# Copy all services
cp -p /bsp/services/all/*.service /etc/systemd/system/

# Regenerated the shared-mime-info database on the first boot
# since it fails to do so properly in a chroot.
systemctl enable smi-hack

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys
# Enable sshd
systemctl enable ssh

# Resize FS on first run (hopefully)
systemctl enable rpiwiggle

# Allow users to use NM over ssh
install -m644 /bsp/polkit/10-NetworkManager.pkla /var/lib/polkit-1/localauthority/50-local.d

cd /root
apt download -o APT::Sandbox::User=root ca-certificates 2>/dev/null

# Copy over the default bashrc
cp /etc/skel/.bashrc /root/.bashrc

# Set a REGDOMAIN.  This needs to be done or wireless doesn't work correctly on the RPi 3B+
sed -i -e 's/REGDOM.*/REGDOMAIN=00/g' /etc/default/crda

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

# Try and make the console a bit nicer
# Set the terminus font for a bit nicer display.
sed -i -e 's/FONTFACE=.*/FONTFACE="Terminus"/' /etc/default/console-setup
sed -i -e 's/FONTSIZE=.*/FONTSIZE="6x12"/' /etc/default/console-setup

# Fix startup time from 5 minutes to 15 secs on raise interface wlan0
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/usr/lib/systemd/system/networking.service"

# Clean up dpkg.eatmydata
rm -f /usr/bin/dpkg
dpkg-divert --remove --rename /usr/bin/dpkg
EOF

# Run third stage
chmod 755 ${work_dir}/third-stage
systemd-nspawn_exec /third-stage

# Clean system
systemd-nspawn_exec << 'EOF'
rm -f /0
rm -rf /bsp
fc-cache -frs
rm -rf /tmp/*
rm -rf /etc/*-
rm -rf /hs_err*
rm -rf /third-stage
rm -rf /userland
rm -rf /opt/vc/src
rm -f /etc/ssh/ssh_host_*
rm -rf /var/lib/dpkg/*-old
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*.bin
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*.data-old
for logs in $(find /var/log -type f); do > $logs; done
history -c
EOF

# Define DNS server after last running systemd-nspawn.
echo "nameserver 8.8.8.8" > ${work_dir}/etc/resolv.conf

# Disable the use of http proxy in case it is enabled.
if [ -n "$proxy_url" ]; then
  unset http_proxy
  rm -rf ${work_dir}/etc/apt/apt.conf.d/66proxy
fi

# Mirror & suite replacement
if [[ ! -z "${4}" || ! -z "${5}" ]]; then
  mirror=${4}
  suite=${5}
fi

# Define sources.list
cat << EOF > ${work_dir}/etc/apt/sources.list
deb ${mirror} ${suite} ${components//,/ }
#deb-src ${mirror} ${suite} ${components//,/ }
EOF

# We need an older gcc because of kernel age.
cd "${basedir}"
git clone --depth 1 https://gitlab.com/kalilinux/packages/gcc-arm-linux-gnueabihf-4-7.git gcc-arm-linux-gnueabihf-4.7

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section.
git clone --depth 1 https://github.com/friendlyarm/linux-3.4.y -b nanopi2-lollipop-mr1 ${work_dir}/usr/src/kernel
cd ${work_dir}/usr/src/kernel
git rev-parse HEAD > ${work_dir}/usr/src/kernel-at-commit
touch .scmversion
export ARCH=arm
export CROSS_COMPILE="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf-
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/mac80211.patch
# Ugh, this patch is needed because the ethernet driver uses parts of netdev
# from a newer kernel?
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/0001-Remove-define.patch
cp ${current_dir}/kernel-configs/nanopi2* ${work_dir}/usr/src/
cp ../nanopi2-vendor.config .config
make -j $(grep -c processor /proc/cpuinfo)
make uImage
make modules_install INSTALL_MOD_PATH=${work_dir}
# We copy this twice because you can't do symlinks on fat partitions.
# Also, the uImage known as uImage.hdmi is used by uboot if hdmi output is
# detected.
cp arch/arm/boot/uImage ${work_dir}/boot/uImage-720p
cp arch/arm/boot/uImage ${work_dir}/boot/uImage.hdmi
# Friendlyarm suggests staying at 720p for now.
#cp ../nanopi2-1080p.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
#cp arch/arm/boot/uImage ${work_dir}/boot/uImage-1080p
#cp ../nanopi2-lcd-hd101.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
#cp arch/arm/boot/uImage ${work_dir}/boot/uImage-hd101
#cp ../nanopi2-lcd-hd700.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
#cp arch/arm/boot/uImage ${work_dir}/boot/uImage-hd700
#cp ../nanopi2-lcd.config .config
#make -j $(grep -c processor /proc/cpuinfo)
#make uImage
# The default uImage is for lcd usage, so we copy the lcd one twice
# so people have a backup in case they overwrite uImage for some reason.
#cp arch/arm/boot/uImage ${work_dir}/boot/uImage-s70
#cp arch/arm/boot/uImage ${work_dir}/boot/uImage.lcd
#cp arch/arm/boot/uImage ${work_dir}/boot/uImage
cd "${basedir}"

# FriendlyARM suggest using backports for wifi with their devices, and the
# recommended version is the 4.4.2.
cd ${work_dir}/usr/src/
#wget https://www.kernel.org/pub/linux/kernel/projects/backports/stable/v4.4.2/backports-4.4.2-1.tar.xz
#tar -xf backports-4.4.2-1.tar.xz
git clone https://github.com/friendlyarm/wireless
cd wireless
cd backports-4.4.2-1
patch -p1 --no-backup-if-mismatch < ${current_dir}/patches/kali-wifi-injection-4.4.patch
cd ..
#cp ${current_dir}/kernel-configs/backports.config .config
#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j $(grep -c processor /proc/cpuinfo) KLIB_BUILD=${work_dir}/usr/src/kernel KLIB=${work_dir}
#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KLIB_BUILD=${work_dir}/usr/src/kernel KLIB=${work_dir} INSTALL_MOD_PATH=${work_dir} install
#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KLIB_BUILD=${work_dir}/usr/src/kernel KLIB=${work_dir} mrproper
#cp ${current_dir}/kernel-configs/backports.config .config
XCROSS="${basedir}"/gcc-arm-linux-gnueabihf-4.7/bin/arm-linux-gnueabihf- ANDROID=n ./build.sh -k ${work_dir}/usr/src/kernel -c nanopi2 -o ${work_dir}
cd "${basedir}"

# Now we clean up the kernel build
cd ${work_dir}/usr/src/kernel
make mrproper
cd "${basedir}"

# Copy over the firmware for the nanopi2/3 wifi.
# At some point, nexmon could work for the device, but the support would need to
# be added to nexmon.
mkdir -p ${work_dir}/lib/firmware/ap6212/
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/nvram.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212a.txt -O ${work_dir}/lib/firmware/ap6212/nvram_ap6212.txt
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a1.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a1.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/fw_bcm43438a0_apsta.bin -O ${work_dir}/lib/firmware/ap6212/fw_bcm43438a0_apsta.bin
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a0.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a0.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/bcm43438a1.hcd -O ${work_dir}/lib/firmware/ap6212/bcm43438a1.hcd
wget https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/config_ap6212.txt -O ${work_dir}/lib/firmware/ap6212/config.txt
cd "${basedir}"

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${work_dir}/lib/modules/)
cd ${work_dir}/lib/modules/${kernver}
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source
cd "${basedir}"

# Calculate the space to create the image.
root_size=$(du -s -B1 ${work_dir} --exclude=${work_dir}/boot | cut -f1)
root_extra=$((${root_size}/1024/1000*5*1024/5))
raw_size=$(($((${free_space}*1024))+${root_extra}+$((${bootsize}*1024))+4096))

# Create the disk and partition it
echo "Creating image file ${imagename}.img"
fallocate -l $(echo ${raw_size}Ki | numfmt --from=iec-i --to=si) ${current_dir}/${imagename}.img
parted -s ${current_dir}/${imagename}.img mklabel msdos
parted -s ${current_dir}/${imagename}.img mkpart primary ext3 1MiB ${bootsize}MiB
parted -s -a minimal ${current_dir}/${imagename}.img mkpart primary $fstype ${bootsize}MiB 100%

# Set the partition variables
loopdevice=`losetup -f --show ${current_dir}/${imagename}.img`
device=`kpartx -va ${loopdevice} | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
mkfs.ext3 -L BOOT ${bootp}
if [[ $fstype == ext4 ]]; then
  features="-O ^64bit,^metadata_csum"
elif [[ $fstype == ext3 ]]; then
  features="-O ^64bit"
fi
mkfs $features -t $fstype -L ROOTFS ${rootp}

# Create the dirs for the partitions and mount them
mkdir -p "${basedir}"/root
mount ${rootp} "${basedir}"/root
mkdir -p "${basedir}"/root/boot
mount ${bootp} "${basedir}"/root/boot

# Create an fstab so that we don't mount / read-only.
UUID=$(blkid -s UUID -o value ${rootp})
echo "UUID=$UUID /               $fstype    errors=remount-ro 0       1" >> ${work_dir}/etc/fstab

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${work_dir}/ ${basedir}/root/

# Unmount partitions
sync
umount -l ${bootp}
umount -l ${rootp}
kpartx -dv ${loopdevice}

# Samsung bootloaders must be signed.
# These are the same steps that are done by
# https://github.com/friendlyarm/sd-fuse_nanopi2/blob/master/fusing.sh

# Download the latest prebuilt from the above url.
mkdir -p "${basedir}"/bootloader
cd "${basedir}"/bootloader
wget 'https://github.com/friendlyarm/sd-fuse_nanopi2/blob/96e1ba9603d237d0169485801764c5ce9591bf5e/prebuilt/2ndboot.bin?raw=true' -O 2ndboot.bin
wget 'https://github.com/friendlyarm/sd-fuse_nanopi2/blob/96e1ba9603d237d0169485801764c5ce9591bf5e/prebuilt/boot.TBI?raw=true' -O boot.TBI
wget 'https://github.com/friendlyarm/sd-fuse_nanopi2/blob/96e1ba9603d237d0169485801764c5ce9591bf5e/prebuilt/bootloader' -O bootloader
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/bl1-mmcboot.bin
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/bl_mon.img
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/bootloader.img # This is u-boot
#wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/prebuilt/loader-mmc.img
wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_nanopi2/master/tools/fw_printenv
chmod 755 fw_printenv
ln -s fw_printenv fw_setenv

dd if=2ndboot.bin of=${loopdevice} bs=512 seek=1
dd if=boot.TBI of=${loopdevice} bs=512 seek=64 count=1
dd if=bootloader of=${loopdevice} bs=512 seek=65

cat << EOF > ${basedir}/bootloader/env.conf
# U-Boot environment for Debian, Ubuntu
#
# Copyright (C) Guangzhou FriendlyARM Computer Tech. Co., Ltd.
# (http://www.friendlyarm.com)
#

bootargs	console=ttyAMA0,115200n8 root=/dev/mmcblk0p2 rootfstype=$fstype rootwait rw consoleblank=0 net.ifnames=0
bootdelay	1
EOF

./fw_setenv ${loopdevice} -s env.conf

sync

cd "${basedir}"

losetup -d ${loopdevice}

# Limite use cpu function
limit_cpu (){
  rand=$(tr -cd 'A-Za-z0-9' < /dev/urandom | head -c4 ; echo) # Randowm name group
  cgcreate -g cpu:/cpulimit-${rand} # Name of group cpulimit
  cgset -r cpu.shares=800 cpulimit-${rand} # Max 1024
  cgset -r cpu.cfs_quota_us=80000 cpulimit-${rand} # Max 100000
  # Retry command
  local n=1; local max=5; local delay=2
  while true; do
    cgexec -g cpu:cpulimit-${rand} "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo -e "\e[31m Command failed. Attempt $n/$max \033[0m"
        sleep $delay;
      else
        echo "The command has failed after $n attempts."
        break
      fi
    }
  done
}

if [ $compress = xz ]; then
  if [ $(arch) == 'x86_64' ]; then
    echo "Compressing ${imagename}.img"
    [ $(nproc) \< 3 ] || cpu_cores=3 # cpu_cores = Number of cores to use
    limit_cpu pixz -p ${cpu_cores:-2} ${current_dir}/${imagename}.img # -p N?? cpu cores use
    chmod 644 ${current_dir}/${imagename}.img.xz
  fi
else
  chmod 644 ${current_dir}/${imagename}.img
fi

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone wrong.
echo "Clean up the build system"
rm -rf "${basedir}"
