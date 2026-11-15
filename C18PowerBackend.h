#ifndef C18_POWER_BACKEND_H
#define C18_POWER_BACKEND_H
#include <stddef.h>

typedef enum {
    C18PowerShutdown,
    C18PowerRespring,
    C18PowerLdrestart,
    C18PowerUserspace
} C18PowerOperation;
typedef int (*C18PowerRun)(const char *,const char *const *,void *);

static inline int C18PowerExecute(C18PowerOperation operation,C18PowerRun run,void *context) {
    static const char *const rebootShutdown[]={"reboot","shutdown",NULL};
    static const char *const reboot[]={"reboot",NULL};
    static const char *const segv[]={"-SEGV","SpringBoard",NULL};
    static const char *const userspace[]={"reboot","userspace",NULL};
    static const char *const none[]={NULL};
    if (!run || operation<C18PowerShutdown || operation>C18PowerUserspace) return 0;
    switch (operation) {
        case C18PowerShutdown:
            if (run("/usr/bin/launchctl",rebootShutdown,context)) return 1;
            if (run("/usr/bin/launchctl",reboot,context)) return 1;
            return run("/var/jb/bin/launchctl",reboot,context);
        case C18PowerRespring:
            if (run("/usr/bin/killall",segv,context)) return 1;
            if (run("/usr/bin/sbreload",none,context)) return 1;
            if (run("/var/jb/usr/bin/killall",segv,context)) return 1;
            return run("/var/jb/usr/bin/sbreload",none,context);
        case C18PowerLdrestart:
            if (run("/usr/bin/ldrestart",none,context)) return 1;
            if (run("/usr/bin/sbreload",none,context)) return 1;
            if (run("/var/jb/usr/bin/ldrestart",none,context)) return 1;
            return run("/usr/bin/killall",segv,context);
        case C18PowerUserspace:
            if (run("/usr/bin/launchctl",userspace,context)) return 1;
            if (run("/var/jb/bin/launchctl",userspace,context)) return 1;
            if (run("/usr/bin/ldrestart",none,context)) return 1;
            return run("/var/jb/usr/bin/ldrestart",none,context);
    }
    return 0;
}
#endif
