/* Ning: fixed userspace-reboot helper. No shell or caller-supplied commands. */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

extern int reboot3(uint64_t flags, ...);
#define C18_USERSPACE_REBOOT UINT64_C(0x2000000000000000)

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "--probe") && strcmp(argv[1], "--userspace"))) {
        fprintf(stderr, "C18PowerHelper: expected --probe or --userspace\n");
        return 64;
    }
    /* RootHide performs setuid check-in before main. Do not assume it worked. */
    if (geteuid() != 0) {
        fprintf(stderr, "C18PowerHelper: root unavailable uid=%u euid=%u\n", (unsigned)getuid(), (unsigned)geteuid());
        return 77;
    }
    if (getuid() != 0 && setuid(0) != 0) {
        fprintf(stderr, "C18PowerHelper: setuid failed errno=%d\n", errno);
        return 78;
    }
    if (getuid() != 0 || geteuid() != 0) {
        fprintf(stderr, "C18PowerHelper: root identity not established\n");
        return 79;
    }
    if (!strcmp(argv[1], "--probe")) {
        printf("C18_POWER_READY uid=%u euid=%u\n", (unsigned)getuid(), (unsigned)geteuid());
        return 0;
    }
    if (reboot3(C18_USERSPACE_REBOOT) != 0) {
        fprintf(stderr, "C18PowerHelper: userspace reboot failed errno=%d (%s)\n", errno, strerror(errno));
        return 80;
    }
    return 0;
}
