#include <unistd.h>
#include <sys/reboot.h>
#include <stdio.h>
#include <string.h>
#include <libgen.h>

int main(int argc, char ** argv) {
  if (strcmp(basename(argv[0]), "poweroff") == 0) {
    fprintf(stderr, "Goodbye, world!\n");
    sync();
    reboot(RB_POWER_OFF);
    perror("rebooting");
    pause();
  } else {
    fprintf(stderr, "Hello, world!\n");
    execl("/poweroff", "poweroff", NULL);
    perror("re-execing");
    pause();
  }

}
