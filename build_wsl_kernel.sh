#!/bin/bash
set -xe

# Root trap
if [[ "$EUID" -ne 0 ]]; then echo "Please run as root"; exit; fi

# Define the Linux Kernel and OpenZFS version we want to build here
export KERNELVER=5.13.6
export ZFSVER=2.1.0

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

# Create build dir (delete it first if we find it already exists)
if [[ -d "/opt/kbuild" ]]; then rm -rf /opt/kbuild; fi
mkdir /opt/kbuild

# Download and extract the latest stable kernel source
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNELVER}.tar.xz -O /opt/kbuild/kernel.tar.xz
tar -xf /opt/kbuild/kernel.tar.xz -C /opt/kbuild

# Add the WSL2 kernel config from upstream into our extracted kernel directory
wget https://raw.githubusercontent.com/microsoft/WSL2-Linux-Kernel/master/Microsoft/config-wsl -O /opt/kbuild/linux-${KERNELVER}/.config

# Use our custom localversion so we can tell when we've actually successfully installed one of our custom kernels
sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-penguins-rule"/g' /opt/kbuild/linux-${KERNELVER}/.config

# Enter the kernel directory
cd /opt/kbuild/linux-${KERNELVER}

# Update our .config file by accepting the defaults for any new kernel
# config options added to the kernel since the Microsoft config was
# generated.
make olddefconfig

# Check and resolve any dependencies needed before building the kernel
make prepare

# Download and extract the latest ZFS source
wget https://github.com/openzfs/zfs/releases/download/zfs-${ZFSVER}/zfs-${ZFSVER}.tar.gz -O /opt/kbuild/zfs.tar.gz
tar -xf /opt/kbuild/zfs.tar.gz -C /opt/kbuild

# Enter the ZFS module directory
cd /opt/kbuild/zfs-${ZFSVER}

# Run OpenZFS autogen.sh script
./autogen.sh

# Configure the OpenZFS modules
# See: https://openzfs.github.io/openzfs-docs/Developer%20Resources/opt/kbuilding%20ZFS.html
./configure --prefix=/ --libdir=/lib --includedir=/usr/include --datarootdir=/usr/share --enable-linux-builtin=yes --with-linux=/opt/kbuild/linux-${KERNELVER} --with-linux-obj=/opt/kbuild/linux-${KERNELVER}

# Run the copy-builtin script
./copy-builtin /opt/kbuild/linux-${KERNELVER}

# Build and install ZFS!
make -s -j$(nproc)
make install

# Return to the kernel directory
cd /opt/kbuild/linux-${KERNELVER}

# Make sure that we're going to build ZFS support when we build our kernel
sed -i '/.*CONFIG_ZFS.*/d' /opt/kbuild/linux-${KERNELVER}/.config
echo "CONFIG_ZFS=y" >> /opt/kbuild/linux-${KERNELVER}/.config

# Build our kernel and install the modules into /lib/modules!
make -j$(nproc)
make modules_install

# Copy our kernel to C:\ZFSonWSL\bzImage
# (We don't save it as bzImage in case we overwrite the kernel we're actually running
# so after the build process is done, the user will need to shutdown WSL and then rename
# the bzImage-new kernel to bzImage)
mkdir -p /mnt/c/ZFSonWSL
cp -fv /opt/kbuild/linux-${KERNELVER}/arch/x86/boot/bzImage /mnt/c/ZFSonWSL/bzImage-new
