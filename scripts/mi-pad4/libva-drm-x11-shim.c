#include <pthread.h>
#include <stdlib.h>

#include <X11/Xlib.h>
#include <va/va.h>
#include <va/va_x11.h>

static pthread_once_t display_once = PTHREAD_ONCE_INIT;
static Display *x11_display;

static void open_x11_display(void)
{
    const char *name = getenv("LIBVA_DRM_X11_DISPLAY");
    x11_display = XOpenDisplay(name && name[0] ? name : NULL);
}

/* Gecko hardcodes vaGetDisplayDRM for both its probe and RDD decoder. KGSL's
 * render node is not a standard DRM display, while the Xwayland VA display is
 * functional. Keep the ABI Gecko expects and select that working display. */
VADisplay vaGetDisplayDRM(int fd)
{
    (void)fd;
    pthread_once(&display_once, open_x11_display);
    return x11_display ? vaGetDisplay(x11_display) : NULL;
}
