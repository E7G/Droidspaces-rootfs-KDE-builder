#include <dlfcn.h>
#include <stdarg.h>
#include <stdint.h>
#include <sys/types.h>
#include <unistd.h>

typedef int (*ioctl_fn)(int fd, unsigned long request, ...);
typedef int (*drm_get_cap_fn)(int fd, uint64_t capability, uint64_t *value);

static ioctl_fn next_ioctl;
static drm_get_cap_fn next_drm_get_cap;

struct ion_new_allocation {
    uint64_t len;
    uint32_t heap_id_mask;
    uint32_t flags;
    int32_t fd;
    uint32_t unused;
};

struct ion_legacy_allocation {
    uint64_t len;
    uint64_t align;
    uint32_t heap_id_mask;
    uint32_t flags;
    uint64_t handle;
};

struct ion_fd_data {
    uint64_t handle;
    int32_t fd;
    uint32_t unused;
};

struct ion_handle_data {
    uint64_t handle;
};

static int fd_target_is(int fd, const char *expected)
{
    char path[32] = "/proc/self/fd/";
    char target[64];
    unsigned int n = (unsigned int)fd;
    int i = 14;
    ssize_t len;
    size_t expected_len = 0;

    while (expected[expected_len] != '\0')
        expected_len++;

    do {
        path[i++] = (char)('0' + (n % 10));
        n /= 10;
    } while (n != 0);

    for (int left = 14, right = i - 1; left < right; left++, right--) {
        char c = path[left];
        path[left] = path[right];
        path[right] = c;
    }

    len = readlink(path, target, sizeof(target) - 1);
    if (len != (ssize_t)expected_len)
        return 0;
    target[len] = '\0';

    for (size_t j = 0; j < expected_len; j++) {
        if (target[j] != expected[j])
            return 0;
    }
    return 1;
}

int drmGetCap(int fd, uint64_t capability, uint64_t *value)
{
    /* KGSL exposes dma-buf import/export but is not a DRM fd. */
    if (capability == 5 && value && fd_target_is(fd, "/dev/kgsl-3d0")) {
        *value = 3;
        return 0;
    }

    if (!next_drm_get_cap)
        next_drm_get_cap = (drm_get_cap_fn)dlsym(RTLD_NEXT, "drmGetCap");
    return next_drm_get_cap(fd, capability, value);
}

int ioctl(int fd, unsigned long request, ...)
{
    __builtin_va_list ap;
    void *arg;

    if (!next_ioctl)
        next_ioctl = (ioctl_fn)dlsym(RTLD_NEXT, "ioctl");

    __builtin_va_start(ap, request);
    arg = __builtin_va_arg(ap, void *);
    __builtin_va_end(ap);

    /* Mesa's new ION request, translated to the legacy Android 4.4 ABI. */
    if (fd_target_is(fd, "/dev/ion") && request == 0xc0184900UL) {
        struct ion_new_allocation *new_alloc = arg;
        struct ion_legacy_allocation alloc = {
            .len = new_alloc->len,
            .align = 4096,
            .heap_id_mask = new_alloc->heap_id_mask,
            .flags = new_alloc->flags,
            .handle = 0,
        };
        struct ion_fd_data share = {
            .handle = 0,
            .fd = -1,
            .unused = 0,
        };
        struct ion_handle_data free_data;
        int ret;

        ret = next_ioctl(fd, 0xc0204900UL, &alloc);
        if (ret < 0)
            return ret;

        share.handle = alloc.handle;
        ret = next_ioctl(fd, 0xc0104904UL, &share);
        free_data.handle = alloc.handle;
        next_ioctl(fd, 0xc0084901UL, &free_data);
        if (ret < 0)
            return ret;

        new_alloc->fd = share.fd;
        return 0;
    }

    return next_ioctl(fd, request, arg);
}
