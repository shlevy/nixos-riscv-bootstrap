#define _GNU_SOURCE
#include <unistd.h>
#include <sys/reboot.h>
#include <stdio.h>
#include <string.h>
#include <libgen.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>

static void die() {
  execl("/poweroff", "poweroff", NULL);
  perror("re-execing");
  pause();
}

static void fail(const char * reason) {
  perror(reason);
  die();
}

int main(int argc, char ** argv) {
  if (strcmp(basename(argv[0]), "poweroff") == 0) {
    fprintf(stderr, "Goodbye, world!\n");
    sync();
    reboot(RB_POWER_OFF);
    perror("rebooting");
    pause();
  } else {
    fprintf(stderr, "Hello, world!\n");

    int root = open("/", O_PATH | O_CLOEXEC);
    if (root == -1)
      fail("Opening /");

    if (mount("procfs", "/proc", "proc", 0, "defaults") == -1)
      fail("Mounting /proc");

    if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL) == -1)
      fail("mounting devtmpfs");

    if (mount("sysfs", "/sys", "sysfs", 0, "defaults") == -1)
      fail("mounting sysfs");

    die();
  }

}
