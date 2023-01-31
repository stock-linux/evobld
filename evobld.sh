#!/bin/bash

# This script is used to build the evx packages in an isolated environment.
# It is intended to be run from the evx package directory.

# The script will create a directory called "chroot" in the current directory.
# It will then create a chroot environment in that directory (using evox).

# The script will then build the evx package in the chroot environment using evoke.

# We begin by creating the chroot directory if it does not already exist.
# If it exists, we delete it, we ask the user if he wants to use the existing chroot directory.
ALREADY_EXISTS=0

if [ -d chroot ]; then
    echo "The chroot directory already exists."
    echo "Do you want to delete it and create a new one? (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
        rm -rf chroot
        mkdir chroot
    else
        ALREADY_EXISTS=1
    fi
else
    mkdir chroot
fi

# If the chroot directory does not already exist, we must run evox to create the toolchain.
# But before that, we need to create a basic structure of the chroot directory.

# We can now install the toolchain.
if [ $ALREADY_EXISTS -eq 0 ]; then
    mkdir -p chroot/dev/pts
    mkdir -p chroot/proc
    mkdir -p chroot/sys
    mkdir -p chroot/run
    mkdir -p chroot/tmp
    mkdir -p chroot/etc
    mkdir -p chroot/var
    mkdir -p chroot/usr/bin
    mkdir -p chroot/usr/sbin
    mkdir -p chroot/usr/lib
    mkdir -p chroot/usr/share
    mkdir -p chroot/usr/include
    mkdir -p chroot/usr/libexec
    mkdir -p chroot/boot
    mkdir -p chroot/mnt

    ln -s usr/bin chroot/bin
    ln -s usr/lib chroot/lib
    ln -s usr/sbin chroot/sbin
    mkdir -p chroot/lib64
    mkdir -p chroot/usr/lib32
    ln -s usr/lib32 chroot/lib32

    mkdir -p chroot/{home,mnt,opt,srv}
    mkdir -p chroot/etc/{opt,sysconfig}
    mkdir -p chroot/lib/firmware
    mkdir -p chroot/media/{floppy,cdrom}
    mkdir -p chroot/usr/{,local/}{include,src}
    mkdir -p chroot/usr/local/{bin,lib,sbin}
    mkdir -p chroot/usr/{,local/}share/{color,dict,doc,info,locale,man}
    mkdir -p chroot/usr/{,local/}share/{misc,terminfo,zoneinfo}
    mkdir -p chroot/usr/{,local/}share/man/man{1..8}
    mkdir -p chroot/var/{cache,local,log,mail,opt,spool}
    mkdir -p chroot/var/lib/{color,misc,locate}
    cp /etc/resolv.conf chroot/etc/resolv.conf
    cp /etc/hosts chroot/etc/hosts
    cp /etc/evox.conf chroot/etc/evox.conf
    ROOT=$PWD/chroot evox init
    ROOT=$PWD/chroot evox sync
    ROOT=$PWD/chroot evox get glibc gcc m4 ncurses bash coreutils diffutils file findutils gawk grep gzip make patch sed tar xz binutils texinfo meson ninja gettext bison perl python util-linux kernel-headers libtool automake autoconf pkg-config evox evoke -y
    ln -s bash chroot/bin/sh
    # We chroot into the environment and install some python packages.
    chroot chroot /bin/bash -c "pip3 install -r /usr/lib/evox/requirements.txt"
    chroot chroot /bin/bash -c "pip3 install -r /usr/lib/evoke/requirements.txt"
else
    ROOT=$PWD/chroot evox sync
    ROOT=$PWD/chroot evox get glibc gcc m4 ncurses bash coreutils diffutils file findutils gawk grep gzip make patch sed tar xz binutils texinfo meson ninja gettext bison perl python util-linux kernel-headers libtool automake autoconf pkg-config evox evoke -y
    chroot chroot /bin/bash -c "pip3 install -r /usr/lib/evox/requirements.txt"
    chroot chroot /bin/bash -c "pip3 install -r /usr/lib/evoke/requirements.txt"
fi

# We can now build the evx package.
# We need to copy the evx package to the chroot directory.
# So we copy all the files (except the chroot directory) in the current directory to the chroot directory.
if [ -d chroot/usr/src/$(basename $PWD) ]; then
    rm -rf chroot/usr/src/$(basename $PWD)
fi

mkdir -p chroot/usr/src/$(basename $PWD)
cp -r metadata scripts chroot/usr/src/$(basename $PWD)

# We mount the necessary directories in the chroot environment.
mount -o bind /dev chroot/dev
mount -o bind /dev/pts chroot/dev/pts
mount -o bind /proc chroot/proc
mount -o bind /sys chroot/sys
mount -o bind /run chroot/run
mount -o bind /tmp chroot/tmp

# We chroot into the environment and build the evx package.
echo "Going to chroot into the environment."
# chroot chroot /bin/bash -c "cd /usr/src/$(basename $PWD) && JOBS=$JOBS evoke build"
# The above command does not work (it executes the evoke command multiple times).
# So we use the following command instead.
chroot chroot /bin/bash << EOF
cd /usr/src/$(basename $PWD)
JOBS=$JOBS evoke build
EOF

# We unmount the directories.
umount chroot/dev/pts
umount chroot/dev
umount chroot/proc
umount chroot/sys
umount chroot/run
umount chroot/tmp

# We copy the evx package to the current directory.
cp chroot/usr/src/$(basename $PWD)-*.evx .
# If they exist, we copy the log files to the current directory.
if [ -f chroot/usr/src/$(basename $PWD)/build.stdout.log ]; then
    cp chroot/usr/src/$(basename $PWD)/build.stdout.log .
fi

if [ -f chroot/usr/src/$(basename $PWD)/build.stderr.log ]; then
    cp chroot/usr/src/$(basename $PWD)/build.stderr.log .
fi