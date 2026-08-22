#define _GNU_SOURCE
#include "display_producer.h"
#include "socket_utils.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <unistd.h>

/* poll() timeout (ms) for the two reconnect handshake steps. Kept short so the
 * caller's reconnect loop stays responsive when no consumer is present yet. */
#define HANDSHAKE_TIMEOUT_MS 100
#define FENCE_WAIT_TIMEOUT_MS 4000
#define FENCE_QUEUE_SIZE (MAX_BUFS * 4)

struct fence_job {
    int render_fence;
    int notify_fd;
    uint64_t generation;
};

struct display_ctx {
    int      ctrl_fd;
    int      data_fd;
    int      buf_ready_efd;
    int      fence_fd;        /* write end of the dedicated render-done fence channel */
    int      shm_fd;
    int      audio_fd;        /* local end of the bidirectional audio socketpair (hello slot 4) */
    int      pending_render_fence; /* render-done fence for the in-flight frame */
    pthread_t fence_worker;
    pthread_mutex_t fence_lock;
    pthread_cond_t fence_idle;
    int      fence_wake_efd;
    struct fence_job fence_queue[FENCE_QUEUE_SIZE];
    size_t   fence_queue_head;
    size_t   fence_queue_tail;
    size_t   fence_queue_count;
    uint64_t fence_generation;
    bool     fence_worker_started;
    bool     fence_worker_stop;
    bool     fence_worker_active;
    volatile uint32_t *shm_ptr;
    uint32_t screen_w, screen_h;
    uint32_t pixel_format;
    uint32_t refresh;
    bool     fallback;

    int      dmabuf_fds[MAX_BUFS];
    struct buf_info dmabuf_infos[MAX_BUFS];
    int      buf_count;

    void (*fallback_cb)(void *);
    void  *fallback_userdata;
};

static int send_refresh_ready(int fd)
{
    const char byte = 0;
    ssize_t sent = send(fd, &byte, sizeof(byte), MSG_NOSIGNAL | MSG_DONTWAIT);

    if (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        struct pollfd pfd = { .fd = fd, .events = POLLOUT };
        int ret;
        do {
            ret = poll(&pfd, 1, 100);
        } while (ret < 0 && errno == EINTR);
        if (ret > 0 && (pfd.revents & POLLOUT))
            sent = send(fd, &byte, sizeof(byte), MSG_NOSIGNAL | MSG_DONTWAIT);
    }

    if (sent != (ssize_t)sizeof(byte)) {
        fprintf(stderr, "anland: failed to send completed refresh: %s\n",
                sent < 0 ? strerror(errno) : "short write");
        return -1;
    }
    return 0;
}

/*
 * Clover compatibility fence bridge
 * ---------------------------------
 * Android 4.4's KGSL/BufferQueue stack accepts a sync fd in queueBuffer(), but
 * can recycle or display the slot before that imported fence is actually
 * honoured. Passing KWin's EGL fence to the consumer therefore produces
 * full-screen flicker and occasional mixed frames.
 *
 * Keep the wait outside KWin's render thread instead: a sleeping worker polls
 * the Linux sync_file, then sends a bare refresh byte. The Android consumer can
 * safely queue with fence=-1 because GPU rendering is already complete. The
 * wake eventfd cancels an old-generation job immediately on disconnect/reconnect,
 * so stale frames can never be submitted to a new BufferQueue.
 */
static void *fence_worker_main(void *userdata)
{
    display_ctx *ctx = userdata;
    (void)pthread_setname_np(pthread_self(), "anland-fence");

    for (;;) {
        pthread_mutex_lock(&ctx->fence_lock);
        if (ctx->fence_worker_stop) {
            pthread_mutex_unlock(&ctx->fence_lock);
            return NULL;
        }

        if (ctx->fence_queue_count == 0) {
            pthread_mutex_unlock(&ctx->fence_lock);
            uint64_t wake_count;
            while (eventfd_read(ctx->fence_wake_efd, &wake_count) < 0) {
                if (errno == EINTR)
                    continue;
                return NULL;
            }
            continue;
        }

        const struct fence_job job = ctx->fence_queue[ctx->fence_queue_head];
        ctx->fence_queue_head = (ctx->fence_queue_head + 1) % FENCE_QUEUE_SIZE;
        ctx->fence_queue_count--;
        ctx->fence_worker_active = true;
        pthread_cond_broadcast(&ctx->fence_idle);
        pthread_mutex_unlock(&ctx->fence_lock);

        bool completed = false;
        bool cancelled = false;
        for (;;) {
            struct pollfd pfds[2] = {
                { .fd = job.render_fence, .events = POLLIN | POLLERR | POLLHUP },
                { .fd = ctx->fence_wake_efd, .events = POLLIN },
            };
            const int ret = poll(pfds, 2, FENCE_WAIT_TIMEOUT_MS);
            if (ret < 0) {
                if (errno == EINTR)
                    continue;
                break;
            }
            if (ret == 0) {
                fprintf(stderr, "anland: render fence timed out after %d ms\n",
                        FENCE_WAIT_TIMEOUT_MS);
                break;
            }

            if (pfds[1].revents & POLLIN) {
                uint64_t wake_count;
                while (eventfd_read(ctx->fence_wake_efd, &wake_count) < 0
                       && errno == EINTR) {
                }
                pthread_mutex_lock(&ctx->fence_lock);
                cancelled = ctx->fence_worker_stop
                    || job.generation != ctx->fence_generation;
                pthread_mutex_unlock(&ctx->fence_lock);
                if (cancelled)
                    break;
                // Harmless stale wake; re-check the current sync_file.
                continue;
            }

            if (pfds[0].revents & POLLIN) {
                completed = true;
                break;
            }
            if (pfds[0].revents & (POLLERR | POLLHUP))
                break;
        }

        pthread_mutex_lock(&ctx->fence_lock);
        if (job.generation != ctx->fence_generation || ctx->fence_worker_stop)
            cancelled = true;
        pthread_mutex_unlock(&ctx->fence_lock);

        if (completed && !cancelled)
            (void)send_refresh_ready(job.notify_fd);

        close(job.render_fence);
        close(job.notify_fd);

        pthread_mutex_lock(&ctx->fence_lock);
        ctx->fence_worker_active = false;
        pthread_cond_broadcast(&ctx->fence_idle);
        pthread_mutex_unlock(&ctx->fence_lock);
    }
}

static int start_fence_worker(display_ctx *ctx)
{
    ctx->fence_wake_efd = eventfd(0, EFD_CLOEXEC);
    if (ctx->fence_wake_efd < 0)
        return -1;
    if (pthread_mutex_init(&ctx->fence_lock, NULL) != 0) {
        close(ctx->fence_wake_efd);
        ctx->fence_wake_efd = -1;
        return -1;
    }
    if (pthread_cond_init(&ctx->fence_idle, NULL) != 0) {
        pthread_mutex_destroy(&ctx->fence_lock);
        close(ctx->fence_wake_efd);
        ctx->fence_wake_efd = -1;
        return -1;
    }
    if (pthread_create(&ctx->fence_worker, NULL, fence_worker_main, ctx) != 0) {
        pthread_cond_destroy(&ctx->fence_idle);
        pthread_mutex_destroy(&ctx->fence_lock);
        close(ctx->fence_wake_efd);
        ctx->fence_wake_efd = -1;
        return -1;
    }
    ctx->fence_worker_started = true;
    return 0;
}

static void cancel_fence_job(display_ctx *ctx)
{
    if (!ctx->fence_worker_started)
        return;

    pthread_mutex_lock(&ctx->fence_lock);
    ctx->fence_generation++;
    while (ctx->fence_queue_count > 0) {
        struct fence_job *job = &ctx->fence_queue[ctx->fence_queue_head];
        close(job->render_fence);
        close(job->notify_fd);
        ctx->fence_queue_head = (ctx->fence_queue_head + 1) % FENCE_QUEUE_SIZE;
        ctx->fence_queue_count--;
    }
    ctx->fence_queue_tail = ctx->fence_queue_head;
    pthread_cond_broadcast(&ctx->fence_idle);
    pthread_mutex_unlock(&ctx->fence_lock);
    (void)eventfd_write(ctx->fence_wake_efd, 1);

    // Reconnect must not install a new BufferQueue while the worker still owns
    // a duplicated socket/fence from the previous generation.
    pthread_mutex_lock(&ctx->fence_lock);
    while (ctx->fence_worker_active)
        pthread_cond_wait(&ctx->fence_idle, &ctx->fence_lock);
    pthread_mutex_unlock(&ctx->fence_lock);
}

static void stop_fence_worker(display_ctx *ctx)
{
    if (!ctx->fence_worker_started)
        return;

    pthread_mutex_lock(&ctx->fence_lock);
    ctx->fence_worker_stop = true;
    ctx->fence_generation++;
    while (ctx->fence_queue_count > 0) {
        struct fence_job *job = &ctx->fence_queue[ctx->fence_queue_head];
        close(job->render_fence);
        close(job->notify_fd);
        ctx->fence_queue_head = (ctx->fence_queue_head + 1) % FENCE_QUEUE_SIZE;
        ctx->fence_queue_count--;
    }
    pthread_cond_broadcast(&ctx->fence_idle);
    pthread_mutex_unlock(&ctx->fence_lock);
    (void)eventfd_write(ctx->fence_wake_efd, 1);
    pthread_join(ctx->fence_worker, NULL);

    pthread_cond_destroy(&ctx->fence_idle);
    pthread_mutex_destroy(&ctx->fence_lock);
    close(ctx->fence_wake_efd);
    ctx->fence_wake_efd = -1;
    ctx->fence_worker_started = false;
}

/*
 * Release every consumer-side resource (dmabuf fds, the four picked-up fds and the
 * shm mapping), leaving the context holding only the daemon ctrl_fd. Does NOT touch
 * the fallback flag or fire the fallback callback — callers decide that. Idempotent.
 */
static void release_consumer_resources(display_ctx *ctx)
{
    cancel_fence_job(ctx);

    for (int i = 0; i < ctx->buf_count; i++) {
        if (ctx->dmabuf_fds[i] >= 0) {
            close(ctx->dmabuf_fds[i]);
            ctx->dmabuf_fds[i] = -1;
        }
    }
    ctx->buf_count = 0;

    if (ctx->data_fd >= 0)          { close(ctx->data_fd);          ctx->data_fd = -1; }
    if (ctx->buf_ready_efd >= 0)    { close(ctx->buf_ready_efd);    ctx->buf_ready_efd = -1; }
    if (ctx->fence_fd >= 0)         { close(ctx->fence_fd);         ctx->fence_fd = -1; }
    if (ctx->audio_fd >= 0)         { close(ctx->audio_fd);         ctx->audio_fd = -1; }
    if (ctx->pending_render_fence >= 0) { close(ctx->pending_render_fence); ctx->pending_render_fence = -1; }
    if (ctx->shm_ptr)               { munmap((void *)ctx->shm_ptr, sizeof(uint32_t)); ctx->shm_ptr = NULL; }
    if (ctx->shm_fd >= 0)           { close(ctx->shm_fd);           ctx->shm_fd = -1; }
}

static void enter_fallback(display_ctx *ctx)
{
    if (ctx->fallback)
        return;
    ctx->fallback = true;

    release_consumer_resources(ctx);

    if (ctx->fallback_cb)
        ctx->fallback_cb(ctx->fallback_userdata);
}

/*
 * Ask the daemon for the consumer-side fds and map the shm index. Polls ctrl_fd
 * with a short timeout so it returns promptly when no consumer is up yet. On
 * success the four fds and shm_ptr are installed on ctx; the caller releases them
 * via release_consumer_resources() on any later failure. Returns 0 / -1.
 */
static int pickup_fds(display_ctx *ctx)
{
    struct ctrl_msg hdr = { .type = CTRL_MSG_PICKUP_FDS, .size = 0 };
    if (send_all(ctx->ctrl_fd, &hdr, sizeof(hdr)) < 0)
        return -1;

    struct pollfd pfd = { .fd = ctx->ctrl_fd, .events = POLLIN };
    if (poll(&pfd, 1, HANDSHAKE_TIMEOUT_MS) <= 0)
        return -1;

    int fds[5];
    int fd_count = 0;
    struct ctrl_msg resp;
    int n = recv_fds(ctx->ctrl_fd, &resp, sizeof(resp), fds, 5, &fd_count);
    if (n <= 0 || resp.type != CTRL_MSG_FDS_READY || fd_count < 5) {
        for (int i = 0; i < fd_count; i++)
            close(fds[i]);
        return -1;
    }

    /* Slot order matches the consumer's send_hello_fds(): { buf_ready, fence, data, shm, audio }.
     * fence_fd is the write end of the dedicated producer->consumer render-done channel;
     * audio_fd is the full-duplex PCM socket (producer writes playback, reads mic). */
    ctx->buf_ready_efd    = fds[0];
    ctx->fence_fd         = fds[1];
    ctx->data_fd          = fds[2];
    ctx->shm_fd           = fds[3];
    ctx->audio_fd         = fds[4];

    ctx->shm_ptr = mmap(NULL, sizeof(uint32_t), PROT_READ, MAP_SHARED, ctx->shm_fd, 0);
    if (ctx->shm_ptr == MAP_FAILED) {
        ctx->shm_ptr = NULL;
        return -1;
    }
    return 0;
}

/*
 * Receive the dmabuf set the consumer pushes onto the data channel right after the
 * fd handshake. Polls data_fd with a short timeout. On failure the caller releases
 * the partially-acquired consumer resources. Returns 0 / -1.
 */
static int receive_dmabufs(display_ctx *ctx)
{
    if (ctx->buf_count > 0)
        return 0;

    struct pollfd pfd = { .fd = ctx->data_fd, .events = POLLIN | POLLHUP | POLLERR };
    if (poll(&pfd, 1, HANDSHAKE_TIMEOUT_MS) <= 0)
        return -1;
    if (pfd.revents & (POLLHUP | POLLERR))
        return -1;

    struct data_msg dhdr;
    int fds[MAX_BUFS];
    int fd_count = 0;

    int n = recv_fds(ctx->data_fd, &dhdr, sizeof(dhdr), fds, MAX_BUFS, &fd_count);
    if (n < (int)sizeof(struct data_msg) || fd_count < 1)
        return -1;

    if (dhdr.type != DATA_MSG_BUFS_READY) {
        for (int i = 0; i < fd_count; i++)
            close(fds[i]);
        return -1;
    }

    int count = dhdr.size / sizeof(struct buf_info);
    if (count != fd_count || count > MAX_BUFS) {
        for (int i = 0; i < fd_count; i++)
            close(fds[i]);
        return -1;
    }

    struct buf_info infos[MAX_BUFS];
    if (recv_all(ctx->data_fd, infos, dhdr.size) < 0) {
        for (int i = 0; i < fd_count; i++)
            close(fds[i]);
        return -1;
    }

    for (int i = 0; i < count; i++) {
        ctx->dmabuf_fds[i] = fds[i];
        ctx->dmabuf_infos[i] = infos[i];
    }
    ctx->buf_count = count;
    return 0;
}

int connect_to_deamon(display_ctx **out, const char *socket_path)
{
    display_ctx *ctx = calloc(1, sizeof(*ctx));
    if (!ctx)
        return -1;

    ctx->ctrl_fd = -1;
    ctx->data_fd = -1;
    ctx->buf_ready_efd = -1;
    ctx->fence_fd = -1;
    ctx->shm_fd = -1;
    ctx->audio_fd = -1;
    ctx->pending_render_fence = -1;
    ctx->fence_wake_efd = -1;
    ctx->shm_ptr = NULL;
    ctx->fallback = true; // stay in fallback until try_exit_fallback() succeeds
    for (int i = 0; i < MAX_BUFS; i++)
        ctx->dmabuf_fds[i] = -1;

    if (start_fence_worker(ctx) < 0)
        goto fail;

    ctx->ctrl_fd = connect_unix(socket_path);
    if (ctx->ctrl_fd < 0)
        goto fail;

    struct ctrl_msg hdr = { .type = CTRL_MSG_PRODUCER_HELLO, .size = 0 };
    if (send_all(ctx->ctrl_fd, &hdr, sizeof(hdr)) < 0)
        goto fail;

    uint8_t buf[sizeof(struct ctrl_msg) + sizeof(struct screen_info)];
    if (recv_all(ctx->ctrl_fd, buf, sizeof(buf)) < 0)
        goto fail;

    struct ctrl_msg resp;
    memcpy(&resp, buf, sizeof(resp));
    if (resp.type != CTRL_MSG_SCREEN_INFO || resp.size != sizeof(struct screen_info))
        goto fail;

    struct screen_info si;
    memcpy(&si, buf + sizeof(struct ctrl_msg), sizeof(si));
    ctx->screen_w = si.width;
    ctx->screen_h = si.height;
    ctx->pixel_format = si.format;
    ctx->refresh = si.refresh;

    // Daemon handshake only: screen info is in hand, but the consumer fds and
    // dmabufs are deliberately left for try_exit_fallback() so the backend brings
    // the consumer up through the single reconnect path. Stay in fallback.
    *out = ctx;
    return 0;

fail:
    stop_fence_worker(ctx);
    if (ctx->ctrl_fd >= 0)
        close(ctx->ctrl_fd);
    free(ctx);
    return -1;
}

void disconnect(display_ctx *ctx)
{
    if (!ctx)
        return;
    release_consumer_resources(ctx);
    stop_fence_worker(ctx);
    if (ctx->ctrl_fd >= 0)
        close(ctx->ctrl_fd);
    free(ctx);
}

int get_screen_info(display_ctx *ctx, uint32_t *width, uint32_t *height, uint32_t *format, uint32_t *refresh)
{
    *width  = ctx->screen_w;
    *height = ctx->screen_h;
    *format = ctx->pixel_format;
    *refresh = ctx->refresh;
    return 0;
}

/* Stash the render-done fence for the in-flight frame (created in doEndFrame).
 * trigger_refresh moves it to the compatibility worker. Closes any previous
 * unconsumed stash. */
void set_render_fence(display_ctx *ctx, int fence_fd)
{
    if (ctx->pending_render_fence >= 0)
        close(ctx->pending_render_fence);
    ctx->pending_render_fence = fence_fd;
}

int trigger_refresh(display_ctx *ctx)
{
    if (ctx->fallback) {
        if (ctx->pending_render_fence >= 0) {
            close(ctx->pending_render_fence);
            ctx->pending_render_fence = -1;
        }
        return 0;
    }

    /* Native fence present: wait on the compatibility worker, then notify the
     * old Android consumer without passing the sync fd. This keeps KWin's main
     * thread asynchronous while avoiding broken queueBuffer fence import. */
    if (ctx->pending_render_fence >= 0) {
        const int notify_fd = fcntl(ctx->fence_fd, F_DUPFD_CLOEXEC, 0);
        if (notify_fd < 0) {
            close(ctx->pending_render_fence);
            ctx->pending_render_fence = -1;
            return -1;
        }

        pthread_mutex_lock(&ctx->fence_lock);
        const uint64_t generation = ctx->fence_generation;
        while (ctx->fence_queue_count == FENCE_QUEUE_SIZE
               && generation == ctx->fence_generation
               && !ctx->fence_worker_stop) {
            pthread_cond_wait(&ctx->fence_idle, &ctx->fence_lock);
        }
        if (generation != ctx->fence_generation || ctx->fence_worker_stop) {
            pthread_mutex_unlock(&ctx->fence_lock);
            close(notify_fd);
            close(ctx->pending_render_fence);
            ctx->pending_render_fence = -1;
            return -1;
        }

        const bool wake_worker = ctx->fence_queue_count == 0
            && !ctx->fence_worker_active;
        struct fence_job *job = &ctx->fence_queue[ctx->fence_queue_tail];
        job->render_fence = ctx->pending_render_fence;
        job->notify_fd = notify_fd;
        job->generation = generation;
        ctx->fence_queue_tail = (ctx->fence_queue_tail + 1) % FENCE_QUEUE_SIZE;
        ctx->fence_queue_count++;
        ctx->pending_render_fence = -1;
        pthread_mutex_unlock(&ctx->fence_lock);
        if (wake_worker)
            (void)eventfd_write(ctx->fence_wake_efd, 1);
        return 0;
    }

    // Clean/idle BufferQueue slot: no GPU work is pending, acknowledge it now.
    return send_refresh_ready(ctx->fence_fd);
}

int poll_input_event(display_ctx *ctx, struct InputEvent *event, int timeout_ms)
{
    if (ctx->fallback)
        return 0;

    struct pollfd pfd = { .fd = ctx->data_fd, .events = POLLIN };
    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0)
        return 0;

    if (pfd.revents & (POLLHUP | POLLERR)) {
        enter_fallback(ctx);
        return -1;
    }

    uint8_t msg_buf[sizeof(struct data_msg) + sizeof(struct InputEvent)];
    ssize_t n = recv(ctx->data_fd, msg_buf, sizeof(msg_buf), MSG_PEEK);
    if (n < (ssize_t)sizeof(struct data_msg))
        return 0;

    struct data_msg hdr;
    memcpy(&hdr, msg_buf, sizeof(hdr));
    if (hdr.type != DATA_MSG_INPUT_EVENT)
        return 0;

    if (recv_all(ctx->data_fd, msg_buf, sizeof(struct data_msg) + sizeof(struct InputEvent)) < 0)
        return -1;

    memcpy(event, msg_buf + sizeof(struct data_msg), sizeof(*event));
    return 1;
}
int poll_input_event_extend_fds(display_ctx *ctx, int *fds, int max_fds,
                                int *fd_count, int timeout_ms)
{
    *fd_count = 0;
    if (ctx->fallback)
        return 0;

    struct pollfd pfd = { .fd = ctx->data_fd, .events = POLLIN };
    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0)
        return 0;

    if (pfd.revents & (POLLHUP | POLLERR)) {
        enter_fallback(ctx);
        return -1;
    }

    struct data_msg hdr;
    int got = 0;
    int n = recv_fds(ctx->data_fd, &hdr, sizeof(hdr), fds, max_fds, &got);
    if (n < (int)sizeof(struct data_msg)) {
        for (int i = 0; i < got; i++)
            close(fds[i]);
        return -1;
    }
    if (hdr.type != DATA_MSG_INPUT_EXTEND_FDS) {
        for (int i = 0; i < got; i++)
            close(fds[i]);
        return -1;
    }
    *fd_count = got;
    return 1;
}

int push_resources_request(display_ctx *ctx, uint32_t service_type, const uint32_t *args)
{
    struct OutputEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = OUTPUT_TYPE_RESOURCES_REQUEST;
    ev.resources_request.type = service_type;
    if (args) {
        ev.resources_request.args[0] = args[0];
        ev.resources_request.args[1] = args[1];
        ev.resources_request.args[2] = args[2];
    }
    return push_output_event(ctx, &ev);
}

int push_output_event(display_ctx *ctx, const struct OutputEvent *event)
{
    if (ctx->fallback)
        return 0;

    struct data_msg hdr = { .type = DATA_MSG_OUTPUT_EVENT, .size = sizeof(struct OutputEvent) };
    uint8_t msg[sizeof(struct data_msg) + sizeof(struct OutputEvent)];
    memcpy(msg, &hdr, sizeof(hdr));
    memcpy(msg + sizeof(hdr), event, sizeof(*event));

    if (send_all(ctx->data_fd, msg, sizeof(msg)) < 0) {
        enter_fallback(ctx);
        return -1;
    }
    return 0;
}
int push_output_event_with_length(display_ctx *ctx, const struct OutputEvent *event, void* payload, size_t size)
{
    if (ctx->fallback)
        return 0;

    struct data_msg hdr = { .type = DATA_MSG_OUTPUT_EVENT, .size = sizeof(struct OutputEvent) };
    uint8_t *msg = (uint8_t *)malloc(sizeof(struct data_msg) + sizeof(struct OutputEvent) + size);
    memcpy(msg, &hdr, sizeof(hdr));
    memcpy(msg + sizeof(hdr), event, sizeof(*event));
    memcpy(msg + sizeof(hdr) + sizeof(struct OutputEvent), payload, size);

    if (send_all(ctx->data_fd, msg, sizeof(struct data_msg) + sizeof(struct OutputEvent) + size) < 0) {
        free(msg);
        enter_fallback(ctx);
        return -1;
    }
    free(msg);
    return 0;
}
int poll_input_event_extend_data(display_ctx *ctx, void* payload, size_t size, int timeout_ms)
{
    if (ctx->fallback)
        return 0;

    struct pollfd pfd = { .fd = ctx->data_fd, .events = POLLIN };
    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0)
        return 0;

    if (pfd.revents & (POLLHUP | POLLERR)) {
        enter_fallback(ctx);
        return -1;
    }
    if (recv_all(ctx->data_fd, payload, size) < 0)
        return -1;
    return 1;
}
int set_fallback_callback(display_ctx *ctx, void (*on_fallback)(void *), void *userdata)
{
    ctx->fallback_cb = on_fallback;
    ctx->fallback_userdata = userdata;
    return 0;
}

bool is_fallback(display_ctx *ctx)
{
    return ctx->fallback;
}

int try_exit_fallback(display_ctx *ctx)
{
    if (!ctx->fallback)
        return 0;

    // Step 1: ask the daemon to hand over the consumer-side fds.
    if (pickup_fds(ctx) < 0) {
        release_consumer_resources(ctx);
        return -1;
    }

    // Step 2: immediately pull the dmabuf set the consumer pushes right after the
    // fd handshake. Only leave fallback once both fds and dmabufs are in hand, so
    // the backend can import straight away.
    if (receive_dmabufs(ctx) < 0) {
        release_consumer_resources(ctx);
        return -1;
    }

    ctx->fallback = false;
    return 0;
}

int get_data_fd(display_ctx *ctx)
{
    return ctx->data_fd;
}

/* Current local end of the audio socketpair, or -1 in fallback. The value changes
 * across reconnects (each pickup installs a fresh socket), so the audio engine must
 * be re-pointed via anland_audio_set_fd() rather than caching it. */
int get_audio_fd(display_ctx *ctx)
{
    return ctx->fallback ? -1 : ctx->audio_fd;
}

int get_buffer_ready_fd(display_ctx *ctx)
{
    return ctx->buf_ready_efd;
}

int get_buf_count(display_ctx *ctx)
{
    return ctx->buf_count;
}

int get_selected_idx(display_ctx *ctx)
{
    if (!ctx->shm_ptr)
        return 0;
    uint32_t idx = *ctx->shm_ptr;
    return (idx < (uint32_t)ctx->buf_count) ? (int)idx : 0;
}

int get_dmabuf_fd(display_ctx *ctx)
{
    return get_dmabuf_fd_at(ctx, get_selected_idx(ctx));
}

int get_dmabuf_fd_at(display_ctx *ctx, int idx)
{
    if (idx < 0 || idx >= ctx->buf_count)
        return -1;
    return ctx->dmabuf_fds[idx];
}

int get_dmabuf_info(display_ctx *ctx, struct buf_info *info)
{
    return get_dmabuf_info_at(ctx, get_selected_idx(ctx), info);
}

int get_dmabuf_info_at(display_ctx *ctx, int idx, struct buf_info *info)
{
    if (idx < 0 || idx >= ctx->buf_count)
        return -1;
    *info = ctx->dmabuf_infos[idx];
    return 0;
}
