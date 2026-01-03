git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b kernel-4.9 susfs4ksu

cp susfs4ksu/kernel_patches/50_add_susfs_in_kernel-4.9.patch ./
cp susfs4ksu/kernel_patches/fs/* ./fs
cp susfs4ksu/kernel_patches/include/linux/* ./include/linux
patch -p1 < 50_add_susfs_in_kernel-4.9.patch

rm -rf 50_add_susfs_in_kernel-4.9.patch susfs4ksu