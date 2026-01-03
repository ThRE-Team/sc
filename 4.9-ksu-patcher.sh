#!/usr/bin/env bash
set -eu

# Patches author: weishu <twsxtd@gmail.com>
# Shell authon: xiaoleGun <1592501605@qq.com>
# Mod script for 4.9 by ThRE Team
# Tested kernel versions: 4.9.228 Redmi 4X
# 20240812

GKI_ROOT="$(pwd)"
EXEC_C="$GKI_ROOT/fs/exec.c"
OPEN_C="$GKI_ROOT/fs/open.c"
RW_C="$GKI_ROOT/fs/read_write.c"
STAT_C="$GKI_ROOT/fs/stat.c"
NAMESPACE_C="$GKI_ROOT/fs/namespace.c"
INPUT_C="$GKI_ROOT/drivers/input/input.c"

patch_files=(
    "$EXEC_C"
    "$OPEN_C"
    "$RW_C"
    "$STAT_C"
    "$NAMESPACE_C"
    "$INPUT_C"
)

for i in "${patch_files[@]}"; do

    if grep -q "ksu" "$i"; then
        echo "Warning: $i contains KernelSU"
        continue
    fi

    case $i in

    # fs/ changes
    "$EXEC_C")
        sed -i '/static int do_execveat_common/i\#ifdef CONFIG_KSU\nextern bool ksu_execveat_hook __read_mostly;\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\n			void *envp, int *flags);\nextern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\n				 void *argv, void *envp, int *flags);\n#endif' "$EXEC_C"
        if grep -q "return __do_execve_file(fd, filename, argv, envp, flags, NULL);" "$EXEC_C"; then
            sed -i '/return __do_execve_file(fd, filename, argv, envp, flags, NULL);/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' "$EXEC_C"
        else
            sed -i '/if (IS_ERR(filename))/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' "$EXEC_C"
        fi
        ;;

    "$OPEN_C")
        if grep -q "long do_faccessat(int dfd, const char __user \*filename, int mode)" "$OPEN_C"; then
            sed -i '/long do_faccessat(int dfd, const char __user \*filename, int mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' "$OPEN_C"
        else
            sed -i '/SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' "$OPEN_C"
        fi
        sed -i '/if (mode & ~S_IRWXO)/i\	#ifdef CONFIG_KSU\n	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n	#endif\n' "$OPEN_C"
        ;;

    "$RW_C")
        sed -i '/ssize_t vfs_read(struct file/i\#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n		size_t *count_ptr, loff_t **pos);\n#endif' "$RW_C"
        sed -i '/ssize_t vfs_read(struct file/,/ssize_t ret;/{/ssize_t ret;/a\
    #ifdef CONFIG_KSU\
    if (unlikely(ksu_vfs_read_hook))\
        ksu_handle_vfs_read(&file, &buf, &count, &pos);\
    #endif
        }' "$RW_C"
        ;;

    "$STAT_C")
        if grep -q "int vfs_statx(int dfd, const char __user \*filename, int flags," "$STAT_C"; then
            sed -i '/int vfs_statx(int dfd, const char __user \*filename, int flags,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif' "$STAT_C"
            sed -i '/unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;/a\\n	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flags);\n	#endif' "$STAT_C"
        else
            sed -i '/int vfs_fstatat(int dfd, const char __user \*filename, struct kstat \*stat,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif\n' "$STAT_C"
            sed -i '/if ((flag & ~(AT_SYMLINK_NOFOLLOW | AT_NO_AUTOMOUNT |/i\	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flag);\n	#endif\n' "$STAT_C"
        fi
        ;;

    "$NAMESPACE_C")
        sed -i '/static inline bool may_mandlock(void)/i \
#ifdef CONFIG_KSU\
static int can_umount(const struct path *path, int flags)\
{\
    struct mount *mnt = real_mount(path->mnt);\
\
    if (!may_mount())\
        return -EPERM;\
    if (path->dentry != path->mnt->mnt_root)\
        return -EINVAL;\
    if (!check_mnt(mnt))\
        return -EINVAL;\
    if (mnt->mnt.mnt_flags & MNT_LOCKED) /* Check optimistically */\
        return -EINVAL;\
    if (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))\
        return -EPERM;\
    return 0;\
}\
\
// caller is responsible for flags being sane\
int path_umount(struct path *path, int flags)\
{\
    struct mount *mnt = real_mount(path->mnt);\
    int ret;\
\
    ret = can_umount(path, flags);\
    if (!ret)\
        ret = do_umount(mnt, flags);\
\
    /* we must not call path_put() as that would clear mnt_expiry_mark */\
    dput(path->dentry);\
    mntput_no_expire(mnt);\
    return ret;\
}\
#endif\
' "$NAMESPACE_C"
        ;;

    # drivers/input changes
    "$INPUT_C")
        sed -i '/static void input_handle_event/i\#ifdef CONFIG_KSU\nextern bool ksu_input_hook __read_mostly;\nextern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\n#endif\n' "$INPUT_C"
        sed -i '/int disposition = input_get_disposition(dev, type, code, &value);/a\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_input_hook))\n		ksu_handle_input_handle_event(&type, &code, &value);\n	#endif' "$INPUT_C"
        ;;
    esac

done

# Enjoy Your Life
