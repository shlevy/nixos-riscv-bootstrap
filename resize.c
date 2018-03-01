#define _GNU_SOURCE
#include <sys/mount.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <syscall.h>
#include <linux/fs.h>

#define do_or_die(cmd, ...) do { \
  if ((cmd) == -1) { \
    fprintf(stderr, __VA_ARGS__); \
    fprintf(stderr, ": %s\n", strerror(errno)); \
    exit(1); \
  } } while (0)

static void run(char *const argv[]) {
  pid_t pid;
  do_or_die(posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ), "Running %s", argv[0]);
  int status;
  waitpid(pid, &status, 0);
  if (WIFSIGNALED(status)) {
    fprintf(stderr, "%s died with signal %s\n", argv[0], strsignal(WTERMSIG(status)));
    exit(1);
  } else if (WEXITSTATUS(status) != 0) {
    fprintf(stderr, "%s died with exit code %d\n", argv[0], WEXITSTATUS(status));
    exit(1);
  }
}

int main(int argc, char ** argv) {
  do_or_die(symlink("/mnt-root/nix", "/nix-initrd"), "Creating /nix symlink for resizing");

  do_or_die(syscall(SYS_renameat2, AT_FDCWD, "/nix", AT_FDCWD, "/nix-initrd", RENAME_EXCHANGE), "Swapping /nix and /nix-initrd");

  char *const sgdisk_argv[] = { "sgdisk", "--clear", "--new", "1", "--change-name=1:riscv-base-nix-image", "/dev/sda", NULL };
  run(sgdisk_argv);

  do_or_die(umount("/mnt-root"), "Unmounting real root for resizing");

  int dev_fd;
  do_or_die(dev_fd = open("/dev/sda", O_RDONLY | O_CLOEXEC), "Opening /dev/sda to rescan partition table");
  do_or_die(ioctl(dev_fd, BLKRRPART, NULL), "Rescanning partition table");
  do_or_die(close(dev_fd), "Closing /dev/sda");

  do_or_die(mount("/dev/disk/by-label/root", "/mnt-root", "btrfs", 0, ""), "Remounting root filesystem after resize");

  char *const btrfs_argv[] = { "btrfs", "filesystem", "resize", "max", "/mnt-root", NULL };
  run(btrfs_argv);

  do_or_die(syscall(SYS_renameat2, AT_FDCWD, "/nix", AT_FDCWD, "/nix-initrd", RENAME_EXCHANGE), "Swapping /nix and /nix-initrd");

  do_or_die(unlink("/nix-initrd"), "Removing the /nix symlink");

  sync();

  do_or_die(unlink("/mnt-root/needs-resize"), "Removing needs-resize marker");

  return 0;
}
