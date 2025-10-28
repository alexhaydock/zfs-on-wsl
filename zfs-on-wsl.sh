#!/usr/bin/env bash
set -euo pipefail

# Exit if we're running as root, unless this is a GitHub Actions runner
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  echo -e "Running inside GitHub Actions runner.\nAllowing rootful build.\n"
  SUDO=""
  USER="root"
else
  if [ "$(id -u)" -eq 0 ]; then
    echo -e "Please do not run this script as root.\nThis script uses sudo to elevate only where needed.\n" >&2; exit 1
  fi
  SUDO="sudo"
fi

KERNELSUFFIX="with-zfs"
KERNELDIR="/opt/zfs-on-wsl-kernel"
ZFSDIR="/opt/zfs-on-wsl-zfs"

# Install pre-requisites
export DEBIAN_FRONTEND=noninteractive
${SUDO} apt-get update && \
${SUDO} apt-get --autoremove upgrade -y && \
${SUDO} apt-get install -y tzdata && \
${SUDO} apt-get install -y \
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
  git \
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
${SUDO} apt-get purge -y zfsutils-linux

# Create kernel directory
${SUDO} mkdir -p $KERNELDIR $ZFSDIR
${SUDO} chown -R $USER:$USER $KERNELDIR $ZFSDIR

# Clone Microsoft kernel source
UPSTREAMKERNELVER=$(curl -s https://api.github.com/repos/microsoft/WSL2-Linux-Kernel/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
test -d $KERNELDIR/.git || git clone --branch $UPSTREAMKERNELVER --single-branch --depth 1 https://github.com/microsoft/WSL2-Linux-Kernel.git $KERNELDIR

# Enter kernel source dir, reset it in case we have any half-finished builds, and update it
(cd $KERNELDIR && git reset --hard && git checkout $UPSTREAMKERNELVER && git pull)

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

# Clone ZFS
UPSTREAMZFSVER=$(curl -s https://api.github.com/repos/openzfs/zfs/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
test -d $ZFSDIR/.git || git clone --branch $UPSTREAMZFSVER --depth 1 https://github.com/zfsonlinux/zfs.git $ZFSDIR

# Enter ZFS source dir, reset it in case we have any half-finished builds, and update it
(cd $ZFSDIR && git reset --hard && git checkout $UPSTREAMZFSVER && git pull)

# Configure ZFS and build/install the userspace binaries
#
# We could do this with the `native-deb` target added in OpenZFS 2.2, but that uses pre-configured
# paths for Debian and Ubuntu and the documentation does not recommend overriding it to use a kernel
# installed in a non-default location. TODO: I will see if I can sort this later.
#
# See: https://openzfs.github.io/openzfs-docs/Developer%20Resources/Building%20ZFS.html
(
cd $ZFSDIR || exit
sh autogen.sh
./configure --prefix=/ --libdir=/lib --includedir=/usr/include --datarootdir=/usr/share --enable-linux-builtin=yes --with-linux=$KERNELDIR --with-linux-obj=$KERNELDIR
./copy-builtin $KERNELDIR
make -j "$(nproc)"
${SUDO} make install
)

# Enable statically compiling in ZFS, and build kernel
echo "CONFIG_ZFS=y" >> "$KERNELDIR/$KCONFIG_CONFIG"
(cd $KERNELDIR && make -j "$(nproc)" LOCALVERSION="-$KERNELSUFFIX")

# Copy our kernel to C:\ZFSonWSL\bzImage
# (We don't save it as bzImage in case we overwrite the kernel we're actually running
# so after the build process is done, the user will need to shutdown WSL and then rename
# the bzImage-new kernel to bzImage)
mkdir -p /mnt/c/ZFSonWSL
cp -fv "${KERNELDIR}/arch/x86/boot/bzImage" "/mnt/c/ZFSonWSL/bzImage-new"
