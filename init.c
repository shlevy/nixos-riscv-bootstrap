#define _GNU_SOURCE
#include <sys/mount.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/reboot.h>
#include <stdlib.h>
#include <ftw.h>
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <syscall.h>

#define do_or_die(cmd, ...) do { \
  if ((cmd) == -1) { \
    fprintf(stderr, __VA_ARGS__); \
    fprintf(stderr, ": %s\n", strerror(errno)); \
    die();					\
  } } while (0)

static void die() {
  fprintf(stderr, "Syncing\n");
  mount("", "/", "", MS_REMOUNT | MS_RDONLY, "");
  umount("/sys/dev");
  umount("/sys");
  umount("/dev");
  umount("/");
  sync();
  reboot(RB_POWER_OFF);
}

static void do_modules() {
  int insmod_list_fd;
  do_or_die(insmod_list_fd = open("/insmod-list", O_RDONLY | O_CLOEXEC), "Opening the module list");
  FILE *insmod_list = fdopen(insmod_list_fd, "r");
  char * line = NULL;
  size_t size;
  ssize_t res;
  errno = 0;
  while ((res = getline(&line, &size, insmod_list)) != -1) {
    if (line[res - 1] == '\n') {
      line[res - 1] = '\0';
    }

    int module_fd;
    do_or_die(module_fd = open(line, O_RDONLY | O_CLOEXEC), "Opening module %s", line);
    do_or_die(syscall(SYS_finit_module, module_fd, "", 0), "Loading module %s", line);
    do_or_die(close(module_fd), "Closing module %s", line);

    errno = 0;
  }
  if (errno)
    do_or_die(-1, "Reading a line from the module list");

  free(line);
  do_or_die(fclose(insmod_list), "Closing the module list");
}

static int cleanup(const char *fpath, const struct stat *st, int typeflag, struct FTW *ftwbuf) {
  if (strcmp(fpath, "/") != 0 && strcmp(fpath, "") != 0) {
    do_or_die(unlinkat(AT_FDCWD, fpath, typeflag == FTW_DP ? AT_REMOVEDIR : 0), "Deleting %s", fpath);
  }
  return 0;
}

static void switch_root() {
  do_or_die(mount("/dev", "/sys/dev", NULL, MS_MOVE, NULL), "Moving /dev to real root filesystem");

  do_or_die(chdir("/sys"), "Moving to new root");

  do_or_die(mount("/sys", "/", NULL, MS_MOVE, NULL), "Moving the new root to /");

  do_or_die(nftw("/", &cleanup, 100, FTW_DEPTH | FTW_PHYS | FTW_MOUNT), "Cleaning up initrd");

  do_or_die(chroot("."), "Changing root");
  do_or_die(chdir("/"), "Changing root");
}

static void run(const char *path, char *const argv[]) {
  pid_t pid;
  do_or_die(posix_spawn(&pid, path, NULL, NULL, argv, environ), "Running %s", argv[0]);
  int status;
  waitpid(pid, &status, 0);
  if (WIFSIGNALED(status)) {
    fprintf(stderr, "%s died with signal %s\n", argv[0], strsignal(WTERMSIG(status)));
    die();
  } else if (WEXITSTATUS(status) != 0) {
    fprintf(stderr, "%s died with exit code %d\n", argv[0], WEXITSTATUS(status));
    die();
  }
}

static void resize_real_root() {
  int resize_fd = open("/sys/needs-resize", O_PATH | O_CLOEXEC);
  if (resize_fd != -1) {
    do_or_die(rename("/nix", "/nix-initrd"), "Moving aside the initrd /nix");

    do_or_die(symlink("/sys/nix", "/nix"), "Creating /nix symlink for resizing");

    char *const sgdisk_argv[] = { "sgdisk", "--clear", "--new", "1", "--change-name=1:riscv-base-nix-image", "/dev/sda", NULL };
    run("/nix/var/nix/profiles/system/bin/sgdisk", sgdisk_argv);

    do_or_die(close(resize_fd), "Closing needs-resize marker");
    do_or_die(umount("/sys"), "Unmounting real root for resizing");

    int dev_fd;
    do_or_die(dev_fd = open("/dev/sda", O_RDONLY | O_CLOEXEC), "Opening /dev/sda to rescan partition table");
    do_or_die(ioctl(dev_fd, BLKRRPART, NULL), "Rescanning partition table");
    do_or_die(close(dev_fd), "Closing /dev/sda");

    do_or_die(mount("/dev/sda1", "/sys", "btrfs", 0, ""), "Remounting root filesystem after resize");

    char *const btrfs_argv[] = { "btrfs", "filesystem", "resize", "max", "/sys", NULL };
    run("/nix/var/nix/profiles/system/bin/btrfs", btrfs_argv);

    sync();

    do_or_die(unlink("/sys/needs-resize"), "Removing needs-resize marker");
  } else if (errno != ENOENT) {
    do_or_die(-1, "Opening needs-resize marker on real root filesystem");
  }
}

int main(int argc, char ** argv) {
  do_modules();

  do_or_die(mount("devtmpfs", "/dev", "devtmpfs", 0, ""), "Mounting /dev");

  /* Arbitrarily reuse /sys */
  do_or_die(mount("/dev/sda1", "/sys", "btrfs", 0, ""), "Mounting root filesystem");

  resize_real_root();

  switch_root();

  do_or_die(execl("/nix/var/nix/profiles/system/bin/init", "init", NULL), "Executing real init");
}
