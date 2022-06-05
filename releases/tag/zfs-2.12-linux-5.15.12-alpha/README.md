Following https://wsl.dev/wsl2-kernel-zfs/ and @alexhaydock 's excellent scripts two kernels both with zfs-2.1.2 and linux-5.15.12 built in Debian 11 WSL2 and Ubuntu 22.04 WSL2. Raw disk mounting and zfs [cmd] / zpool [cmd] I have so far tested work on an existing zpool created in Jammy to enable me to access a mirrorred pool in windows.

After building zfs into a linux kernel the wsl2 ext4.vhdx becomes many gigabytes larger. After removing unneeded build files the vdisk can be shrunk.

  wsl --shutdown
  optimize-vhd -Path .\ext4.vhdx -Mode full

Unless Windows Home edition then use diskpart

  select vdisk file=[path\to\ext.vhdx]
  compact vdisk
