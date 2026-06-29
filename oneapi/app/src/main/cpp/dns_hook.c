#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

static int (*real_open)(const char *, int, ...) = NULL;
static FILE *(*real_fopen)(const char *, const char *) = NULL;
static char *resolv_path = NULL;

static void init(void) {
    static int inited = 0;
    if (inited) return;
    inited = 1;
    resolv_path = getenv("CUSTOM_RESOLV_CONF");
    real_open = dlsym(RTLD_NEXT, "open");
    real_fopen = dlsym(RTLD_NEXT, "fopen");
}

int open(const char *path, int flags, ...) {
    init();
    if (resolv_path && strcmp(path, "/etc/resolv.conf") == 0) {
        if (flags & O_CREAT) {
            va_list ap;
            va_start(ap, flags);
            int result = real_open(resolv_path, flags, va_arg(ap, mode_t));
            va_end(ap);
            return result;
        }
        return real_open(resolv_path, flags);
    }
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        int result = real_open(path, flags, va_arg(ap, mode_t));
        va_end(ap);
        return result;
    }
    return real_open(path, flags);
}

FILE *fopen(const char *path, const char *mode) {
    init();
    if (resolv_path && strcmp(path, "/etc/resolv.conf") == 0) {
        return real_fopen(resolv_path, mode);
    }
    return real_fopen(path, mode);
}