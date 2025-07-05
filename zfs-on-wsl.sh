#!/usr/bin/env sh
set -xeu

KERNELNAME="penguins-rule"
KERNELDIR="/opt/zfs-on-wsl-kernel"
ZFSDIR="/opt/zfs-on-wsl-zfs"

# Install deps
# Install pre-requisites
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && \
sudo apt-get --autoremove upgrade -y && \
sudo apt-get install -y tzdata && \
sudo apt-get install -y \
  alien \
  autoconf \
  automake \
  bc \
  binutils \
  bison \
  build-essential \
  curl \
  dkms \
  dwarves \
  fakeroot \
  flex \
  gawk \
  libaio-dev \
  libattr1-dev \
  libblkid-dev \
  libelf-dev \
  libffi-dev \
  libssl-dev \
  libtirpc-dev \
  libtool \
  libudev-dev \
  python3 \
  python3-cffi \
  python3-dev \
  python3-setuptools \
  uuid-dev \
  wget \
  zlib1g-dev

# Remove the Ubuntu-provided ZFS utilities if we have them
# (our build process will build them later)
sudo apt-get purge -y zfsutils-linux

# Create kernel directory
sudo mkdir -p $KERNELDIR $ZFSDIR
sudo chown -R $USER:$USER $KERNELDIR $ZFSDIR

# Clone Microsoft kernel source or update it and reset it if it already exists
test -d $KERNELDIR/.git || git clone --branch linux-msft-wsl-"$(uname -r | cut -d- -f 1)" --single-branch --depth 1 https://github.com/microsoft/WSL2-Linux-Kernel.git $KERNELDIR

# Enter kernel source dir and update it
(cd $KERNELDIR && git reset --hard && git pull)

# Update existing kernel config with any custom config options we want
#
# Here, we enable CONFIG_USB_STORAGE to enable USB Mass Storage support,
# which does not appear to be enabled by default in Microsoft's kernel config
# but is needed for passing through USB devices to use for ZFS
export KCONFIG_CONFIG="Microsoft/config-wsl"
echo "CONFIG_USB_STORAGE=y" >> "$KERNELDIR/$KCONFIG_CONFIG"

# Prep kernel and use the defaults for any new config options we just unlocked
# by enabling USB_STORAGE
(cd $KERNELDIR && make olddefconfig && make prepare scripts)

# Clone ZFS, configure it and build/install the userspace binaries
#
# We could do this with the `native-deb` target added in OpenZFS 2.2, but that uses pre-configured
# paths for Debian and Ubuntu and the documentation does not recommend overriding it to use a kernel
# installed in a non-default location. TODO: I will see if I can sort this later.
#
# See: https://openzfs.github.io/openzfs-docs/Developer%20Resources/Building%20ZFS.html
test -d $ZFSDIR/.git || git clone --depth 1 https://github.com/zfsonlinux/zfs.git $ZFSDIR
(
cd $ZFSDIR || exit
git pull
sh autogen.sh
./configure --prefix=/ --libdir=/lib --includedir=/usr/include --datarootdir=/usr/share --enable-linux-builtin=yes --with-linux=$KERNELDIR --with-linux-obj=$KERNELDIR
./copy-builtin $KERNELDIR
make -j "$(nproc)"
sudo make install
)

# Enable statically compiling in ZFS, and build kernel
echo "CONFIG_ZFS=y" >> "$KERNELDIR/$KCONFIG_CONFIG"
(cd $KERNELDIR && make -j "$(nproc)" LOCALVERSION="-$KERNELNAME")

# Copy our kernel to C:\ZFSonWSL\bzImage
# (We don't save it as bzImage in case we overwrite the kernel we're actually running
# so after the build process is done, the user will need to shutdown WSL and then rename
# the bzImage-new kernel to bzImage)
mkdir -p /mnt/c/ZFSonWSL
cp -fv "${KERNELDIR}/arch/x86/boot/bzImage" "/mnt/c/ZFSonWSL/bzImage-new"
