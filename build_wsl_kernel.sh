#!/bin/bash
set -xe

# Root trap
if [[ "$EUID" -ne 0 ]]; then echo "Please run as root"; exit; fi

# Import variables
source ./vars.sh

# Install pre-requisites
export DEBIAN_FRONTEND=noninteractive
apt-get update && \
apt-get upgrade -y && \
apt-get install -y tzdata && \
apt-get install -y \
  alien \
  autoconf \
  automake \
  bc \
  binutils \
  bison \
  build-essential \
  curl \
  dkms \
  fakeroot \
  flex \
  gawk \
  libaio-dev \
  libattr1-dev \
  libblkid-dev \
  libelf-dev \
  libffi-dev \
  libssl-dev \
  libtool \
  libudev-dev \
  python3 \
  python3-cffi \
  python3-dev \
  python3-setuptools \
  uuid-dev \
  wget \
  zlib1g-dev

# Create temp build dir (delete it first if we find it already exists)
if [[ -d "/tmp/kbuild" ]]; then rm -rf /tmp/kbuild; fi
mkdir /tmp/kbuild

# Download and extract the latest stable kernel source
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNELVER}.tar.xz -O /tmp/kbuild/kernel.tar.xz
tar -xf /tmp/kbuild/kernel.tar.xz -C /tmp/kbuild

# Move our kernel directory to reflect our custom name
mv -fv /tmp/kbuild/linux-${KERNELVER} /usr/src/linux-${KERNELVER}-${KERNELNAME}

# Add the WSL2 kernel config from upstream into our extracted kernel directory
wget https://raw.githubusercontent.com/microsoft/WSL2-Linux-Kernel/master/Microsoft/config-wsl -O /usr/src/linux-${KERNELVER}-${KERNELNAME}/.config

# Use our custom localversion so we can tell when we've actually successfully installed one of our custom kernels
sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-${KERNELNAME}"/g' /usr/src/linux-${KERNELVER}-${KERNELNAME}/.config

# Enter the kernel directory
cd /usr/src/linux-${KERNELVER}-${KERNELNAME}

# Update our .config file by accepting the defaults for any new kernel
# config options added to the kernel since the Microsoft config was
# generated.
make olddefconfig

# Check and resolve any dependencies needed before building the kernel
make prepare

# Download and extract the latest ZFS source
wget https://github.com/openzfs/zfs/releases/download/zfs-${ZFSVER}/zfs-${ZFSVER}.tar.gz -O /tmp/kbuild/zfs.tar.gz
tar -xf /tmp/kbuild/zfs.tar.gz -C /tmp/kbuild

# Move our ZFS directory to reflect our custom name
mv -fv /tmp/kbuild/zfs-${ZFSVER} /usr/src/zfs-${ZFSVER}-for-linux-${KERNELVER}-${KERNELNAME}

# Enter the ZFS module directory
cd /usr/src/zfs-${ZFSVER}-for-linux-${KERNELVER}-${KERNELNAME}

# Run OpenZFS autogen.sh script
./autogen.sh

# Configure the OpenZFS modules
# See: https://openzfs.github.io/openzfs-docs/Developer%20Resources/opt/kbuilding%20ZFS.html
./configure --prefix=/ --libdir=/lib --includedir=/usr/include --datarootdir=/usr/share --enable-linux-builtin=yes --with-linux=/usr/src/linux-${KERNELVER}-${KERNELNAME} --with-linux-obj=/usr/src/linux-${KERNELVER}-${KERNELNAME}

# Run the copy-builtin script
./copy-builtin /usr/src/linux-${KERNELVER}-${KERNELNAME}

# Build ZFS!
make -s -j$(nproc)
make install

# Return to the kernel directory
cd /usr/src/linux-${KERNELVER}-${KERNELNAME}

# Make sure that we're going to build ZFS support when we build our kernel
sed -i '/.*CONFIG_ZFS.*/d' /usr/src/linux-${KERNELVER}-${KERNELNAME}/.config
echo "CONFIG_ZFS=y" >> /usr/src/linux-${KERNELVER}-${KERNELNAME}/.config

# Build our kernel and install the modules into /lib/modules!
make -j$(nproc)
make modules_install

# Copy our kernel to C:\ZFSonWSL\bzImage
# (We don't save it as bzImage in case we overwrite the kernel we're actually running
# so after the build process is done, the user will need to shutdown WSL and then rename
# the bzImage-new kernel to bzImage)
mkdir -p /mnt/c/ZFSonWSL
cp -fv /usr/src/linux-${KERNELVER}-${KERNELNAME}/arch/x86/boot/bzImage /mnt/c/ZFSonWSL/bzImage-new

# Tar up the build directories for the kernel and for ZFS
# Mostly useful for our GitLab CI process but might help with redistribution
cd /tmp/kbuild
tar -czf linux-${KERNELVER}-${KERNELNAME}.tgz /usr/src/linux-${KERNELVER}-${KERNELNAME}
tar -czf zfs-${ZFSVER}-for-${KERNELVER}-${KERNELNAME}.tgz /usr/src/zfs-${ZFSVER}-for-linux-${KERNELVER}-${KERNELNAME}
