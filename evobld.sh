#!/bin/bash

# This script is used to build the evx packages in an isolated environment.
# It is intended to be run from the evx package directory.

# The script will create a directory called "chroot" in the current directory.
# It will then create a chroot environment in that directory (using evox).

# The script will then build the evx package in the chroot environment using evoke.

# We begin by creating the chroot directory if it does not already exist.
# If it exists, we delete it, we ask the user if he wants to use the existing chroot directory.
ROOT=$PWD/chroot

install_toolchain() {
    ROOT=$ROOT evox sync
    ROOT=$ROOT evox get glibc gcc m4 ncurses bash coreutils diffutils file findutils gawk grep gzip make patch sed tar xz binutils texinfo meson ninja gettext bison perl python util-linux kernel-headers libtool automake autoconf pkg-config evox evoke -y
}

setup_chroot() {
    mkdir -p $ROOT
    mkdir -p $ROOT/dev/pts
    mkdir -p $ROOT/proc
    mkdir -p $ROOT/sys
    mkdir -p $ROOT/run
    mkdir -p $ROOT/tmp
    mkdir -p $ROOT/etc
    mkdir -p $ROOT/var
    mkdir -p $ROOT/usr/bin
    mkdir -p $ROOT/usr/sbin
    mkdir -p $ROOT/usr/lib
    mkdir -p $ROOT/usr/share
    mkdir -p $ROOT/usr/include
    mkdir -p $ROOT/usr/libexec
    mkdir -p $ROOT/boot
    mkdir -p $ROOT/mnt

    ln -s usr/bin $ROOT/bin
    ln -s usr/lib $ROOT/lib
    ln -s usr/sbin $ROOT/sbin
    mkdir -p $ROOT/lib64
    mkdir -p $ROOT/usr/lib32
    ln -s usr/lib32 $ROOT/lib32

    mkdir -p $ROOT/{home,mnt,opt,srv}
    mkdir -p $ROOT/etc/{opt,sysconfig}
    mkdir -p $ROOT/lib/firmware
    mkdir -p $ROOT/media/{floppy,cdrom}
    mkdir -p $ROOT/usr/{,local/}{include,src}
    mkdir -p $ROOT/usr/local/{bin,lib,sbin}
    mkdir -p $ROOT/usr/{,local/}share/{color,dict,doc,info,locale,man}
    mkdir -p $ROOT/usr/{,local/}share/{misc,terminfo,zoneinfo}
    mkdir -p $ROOT/usr/{,local/}share/man/man{1..8}
    mkdir -p $ROOT/var/{cache,local,log,mail,opt,spool}
    mkdir -p $ROOT/var/lib/{color,misc,locate}
    cp /etc/resolv.conf $ROOT/etc/resolv.conf
    cp /etc/hosts $ROOT/etc/hosts
    cp /etc/evox.conf $ROOT/etc/evox.conf
    ROOT=$ROOT evox init
    install_toolchain
    ln -s bash $ROOT/bin/sh
}

sync_structure() {
    # For each line of etc/evox.conf, we copy the repo folder to the chroot directory if the repo exists.
    # The line is of the form "REPO name url".
    # We just need to get the path of the repo.
    while read line; do
    # If line is not empty and begins with "REPO", we copy the repo.
        if [ "$line" != "" ] && [ "$(echo $line | cut -d ' ' -f 1)" = "REPO" ]; then
            repo_path=$(echo $line | cut -d ' ' -f 3)
            if [ -d $repo_path ]; then
                if [ ! -d $ROOT/$repo_path ]; then
                    mkdir -p $ROOT/$repo_path
                fi
                cp -r $repo_path/* $ROOT/$repo_path
            fi
        fi
    done < $ROOT/etc/evox.conf
}

print_help() {
    echo "Usage: evobld.sh [--use-chroot <chroot directory>]"
    echo "                 setup"
}

if [ "$1" = "--help" ]; then
    print_help
    exit 0
fi

if [ "$1" = "--use-chroot" ] && [ "$2" = "" ]; then
    print_help
    exit 1
fi

if [ "$1" != "--use-chroot" ] && [ "$1" != "setup" ] && [ "$1" != "" ]; then
    print_help
    exit 1
fi

if [ "$1" == "setup" ]; then
    setup_chroot
    exit 0
fi

ALREADY_EXISTS=0

# If there is the --use-chroot option, we use the existing chroot directory given as argument.
if [ "$1" = "--use-chroot" ]; then
    if [ -d $2 ]; then
        ROOT=$2
        ALREADY_EXISTS=1
    else
        echo "The chroot directory does not exist."
        exit 1
    fi
fi

if [ -d $ROOT ]; then
    echo "The chroot directory already exists."
    echo "Do you want to delete it and create a new one? (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
        rm -rf $ROOT
        ALREADY_EXISTS=0
    else
        ALREADY_EXISTS=1
    fi
fi

# If the chroot directory does not already exist, we must run evox to create the toolchain.
# But before that, we need to create a basic structure of the chroot directory.

# We can now install the toolchain.
if [ $ALREADY_EXISTS -eq 0 ]; then
    setup_chroot
fi

sync_structure
install_toolchain

chroot $ROOT /bin/bash -c "pip3 install -r /usr/lib/evox/requirements.txt"
chroot $ROOT /bin/bash -c "pip3 install -r /usr/lib/evoke/requirements.txt"

# We can now build the evx package.
# We need to copy the package folder to the chroot directory.
# So we copy all the files (except the chroot directory) in the current directory to the chroot directory.
if [ -d $ROOT/usr/src/$(basename $PWD) ]; then
    rm -rf $ROOT/usr/src/$(basename $PWD)
fi

mkdir -p $ROOT/usr/src/$(basename $PWD)
cp -r metadata scripts $ROOT/usr/src/$(basename $PWD)

# We mount the necessary directories in the chroot environment.
mount -o bind /dev $ROOT/dev
mount -o bind /dev/pts $ROOT/dev/pts
mount -o bind /proc $ROOT/proc
mount -o bind /sys $ROOT/sys
mount -o bind /run $ROOT/run
mount -o bind /tmp $ROOT/tmp

# We chroot into the environment and build the evx package.
echo "Going to chroot into the environment."
# chroot chroot /bin/bash -c "cd /usr/src/$(basename $PWD) && JOBS=$JOBS evoke build"
# The above command does not work (it executes the evoke command multiple times).
# So we use the following command instead.
chroot $ROOT /bin/bash << EOF
cd /usr/src/$(basename $PWD)
JOBS=$JOBS evoke build
EOF

# We unmount the directories.
umount $ROOT/dev/pts
umount $ROOT/dev
umount $ROOT/proc
umount $ROOT/sys
umount $ROOT/run
umount $ROOT/tmp

# We copy the evx package to the current directory.
cp $ROOT/usr/src/$(basename $PWD)-*.evx .
# If they exist, we copy the log files to the current directory.
if [ -f $ROOT/usr/src/$(basename $PWD)/build.stdout.log ]; then
    cp $ROOT/usr/src/$(basename $PWD)/build.stdout.log .
fi

if [ -f $ROOT/usr/src/$(basename $PWD)/build.stderr.log ]; then
    cp $ROOT/usr/src/$(basename $PWD)/build.stderr.log .
fi

# And finally, we can copy the file in the local branch /var/evox/local
mkdir -p /var/evox/local
cp $(basename $PWD)-*.evx /var/evox/local

# If there is already the package in the INDEX, we delete the line
sed -i "/$(basename $PWD)/d" /var/evox/local/INDEX 

# And we index the package in the INDEX
version=$(awk -F "= " '/version / {print $2}' metadata/PKGINFO)
pkgrel=$(awk -F "= " '/pkgrel / {print $2}' metadata/PKGINFO)

echo "$(basename $PWD) $version $pkgrel" >> /var/evox/local/INDEX

# Ask the user in which group he wants the package to be
read -p 'Package distant branch: ' distant_branch

mkdir -p /var/evobld/$distant_branch

if test -f "/var/evobld/$distant_branch/INDEX"; then
    sed -i "/$(basename $PWD)/d" /var/evobld/$distant_branch/INDEX
fi

echo "$(basename $PWD) $version $pkgrel" >> /var/evobld/$distant_branch/INDEX
ln -s "/var/evox/local/$(basename $PWD)-$version.evx" "/var/evobld/$distant_branch/$(basename $PWD)-$version.evx"