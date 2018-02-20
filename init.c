#include <unistd.h>
#include <sys/reboot.h>
#include <stdio.h>

int main(int argc, char ** argv) {
  fprintf(stderr, "Hello, world!\n");
  reboot(RB_POWER_OFF);
  perror("rebooting");
  pause();
}
