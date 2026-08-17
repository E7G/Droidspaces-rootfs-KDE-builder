/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "anland_egl_backend.h"
#include "anland_backend.h"
#include "anland_logging.h"
#include "anland_output.h"

// kwin
#include "core/graphicsbuffer.h" // DmaBufAttributes
#include "core/output.h" // OutputTransform
#include "opengl/egldisplay.h"
#include "opengl/eglcontext.h"
#include "opengl/eglnativefence.h"
#include "opengl/glutils.h"
#include "utils/filedescriptor.h"

#include <drm_fourcc.h>
#include <unistd.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif

namespace KWin
{

/*
 * The daemon's screen_info.format / buf_info.format uses the consumer-side
 * pixel-format enum (see common/protocol.h). 1 == RGBA_8888 in Android memory
 * layout, which is ABGR8888 in DRM fourcc terms; everything else is treated as
 * XRGB8888. Mirrors protocol_format_to_drm() in weston's backend-anland.
 */
static uint32_t protocol_format_to_drm(uint32_t fmt)
{
    switch (fmt) {
    case 1:
        return DRM_FORMAT_ABGR8888;
    default:
        return DRM_FORMAT_XRGB8888;
    }
}

AnlandEglLayer::AnlandEglLayer(AnlandOutput *output, AnlandEglBackend *backend)
    : OutputLayer(output, OutputLayerType::Primary)
    , m_backend(backend)
    , m_output(output)
    , m_display(backend->display())
{
    // React to runtime orientation changes (System Settings / kscreen-doctor)
    // through the output's transformChanged signal instead of polling the transform
    // in the per-frame render path. Qt drops the connection automatically when this
    // layer (a QObject via OutputLayer) or the output is destroyed.
    connect(m_output, &BackendOutput::transformChanged, this, &AnlandEglLayer::onOutputTransformChanged);
}

AnlandEglLayer::~AnlandEglLayer()
{
    // Avoid leaving a dangling pointer in the output when we're destroyed without a
    // removeOutput() call (e.g. ~AnlandEglBackend clearing m_outputs).
    if (m_output && m_output->eglLayer() == this) {
        m_output->setEglLayer(nullptr);
    }
    releaseBuffers();
}

void AnlandEglLayer::releaseBuffers()
{
    // Destroying the GL textures/framebuffers needs the context current. Callers
    // (backend state machine on fallback, ~AnlandEglLayer) may run outside a frame.
    m_backend->openglContext()->makeCurrent();

    for (int i = 0; i < MAX_BUFS; i++) {
        m_fbos[i].reset();
        m_textures[i].reset();
        m_renderTargets[i].reset();
        m_accumDamage[i] = Region();
    }
    m_damageFlags = 0;
    m_damageMask = 0;
    m_bufCount = 0;
}

bool AnlandEglLayer::importBuffers(int count)
{
    m_backend->openglContext()->makeCurrent();

    releaseBuffers();

    // The consumer reads this dmabuf top-down, while GL renders bottom-up, so the
    // content transform always carries a vertical flip. On top of that we fold in
    // the output's configured rotation, so the scene is rendered pre-rotated into
    // the (fixed-size, landscape) dmabuf — that is what lets the very same buffer
    // drive a portrait / 180° display. KWin's renderer (RenderTarget/RenderViewport)
    // bakes this single transform into the root projection with no extra copy; it is
    // the official 6.x replacement for the old GLFramebuffer::setYInverted() flag the
    // 5.27 patch carried. Combining the output rotation with FlipY mirrors the DRM
    // backend exactly (drmOutput()->transform().combine(OutputTransform::FlipY)).
    // The tag is sticky on each texture; after import it is only ever updated
    // reactively, in onOutputTransformChanged().
    const OutputTransform contentTransform = m_output->transform().combine(OutputTransform::FlipY);

    for (int i = 0; i < count; i++) {
        const int fd = get_dmabuf_fd_at(m_display, i);
        buf_info info;
        if (fd < 0 || get_dmabuf_info_at(m_display, i, &info) < 0) {
            qCWarning(KWIN_ANLAND) << "failed to get dmabuf info for buffer" << i;
            releaseBuffers();
            return false;
        }

        /* The per-buffer width/height come from the consumer's native resolution
         * (buf_info, filled by collect_dmabufs). If it differs from the current
         * OutputMode, resize the output to match — the consumer may have rotated or
         * switched display modes. All buffers in a set share the same size, so we
         * only need to check the first buffer. */
        if (i == 0) {
            const QSize bufSize(info.width, info.height);
            if (bufSize != m_output->modeSize() && bufSize.isValid()) {
                qCInfo(KWIN_ANLAND) << "dmabuf size changed, resizing output to" << bufSize;
                m_output->resize(bufSize);
            }
        }
        const QSize actual(info.width, info.height);

        DmaBufAttributes attrs;
        attrs.planeCount = 1;
        attrs.width = actual.width();
        attrs.height = actual.height();
        attrs.format = protocol_format_to_drm(info.format);
        /* Android's ANativeWindow path reports modifier=0 for a linear buffer.
         * In EGL dma-buf import, however, 0 means an explicit DRM_LINEAR
         * modifier, while DRM_FORMAT_MOD_INVALID means implicit layout.  The
         * 4.4 clover gralloc buffers are implicit-linear and Mesa's KGSL EGL
         * rejects the explicit modifier with EGL_BAD_PARAMETER. */
        attrs.modifier = info.modifier == 0 ? DRM_FORMAT_MOD_INVALID : info.modifier;
        // The producer owns the dmabuf fd; DmaBufAttributes (and the EGLImage we
        // hand the fd to) must not close it, so dup() into the owning slot.
        attrs.fd[0] = FileDescriptor(dup(fd));
        attrs.offset[0] = static_cast<int>(info.offset);
        attrs.pitch[0] = static_cast<int>(info.stride);

        // EglBackend::importDmaBufAsTexture() builds the EGLImage and wraps it in
        // a GLTexture in one step (the 5.27-era manual EGLImageKHR +
        // EGLImageTexture(...) dance is gone in 6.x).
        /* Qualcomm's 4.4 gralloc and the KGSL EGL implementation disagree on
         * whether the buffer is advertised as RGBA/XRGB and whether a linear
         * modifier is explicit.  Keep the protocol value first, then retry
         * the equivalent legacy combinations instead of turning the whole
         * output black on EGL_BAD_PARAMETER. */
        const std::array<uint32_t, 5> formatCandidates = {
            attrs.format,
            DRM_FORMAT_XRGB8888,
            DRM_FORMAT_ARGB8888,
            DRM_FORMAT_XBGR8888,
            DRM_FORMAT_ABGR8888,
        };
        /* Keep the literal protocol value 0 as a separate retry.  Android 9's
         * clover gralloc uses 0 for its legacy implicit layout, while Mesa's
         * DRM path uses DRM_FORMAT_MOD_INVALID for the same EGL attribute
         * omission and DRM_FORMAT_MOD_LINEAR (1) for an explicit linear
         * modifier.  The old KGSL EGL driver accepts only one of these forms
         * depending on the buffer allocation path. */
        const std::array<uint64_t, 3> modifierCandidates = {
            attrs.modifier,
            0,
            DRM_FORMAT_MOD_LINEAR,
        };
        std::shared_ptr<GLTexture> texture;
        uint32_t importedFormat = attrs.format;
        uint64_t importedModifier = attrs.modifier;
        for (const uint32_t candidateFormat : formatCandidates) {
            for (const uint64_t candidateModifier : modifierCandidates) {
                if (candidateFormat == attrs.format && candidateModifier == attrs.modifier) {
                    // This is the normal protocol path and was already tried
                    // by the first import below.
                }
                attrs.format = candidateFormat;
                attrs.modifier = candidateModifier;
                texture = m_backend->importDmaBufAsTexture(attrs);
                if (texture) {
                    importedFormat = candidateFormat;
                    importedModifier = candidateModifier;
                    break;
                }
            }
            if (texture) {
                break;
            }
        }
        attrs.format = importedFormat;
        attrs.modifier = importedModifier;
        if (!texture) {
            qCWarning(KWIN_ANLAND) << "failed to import dmabuf" << i << "as texture";
            releaseBuffers();
            return false;
        }

        texture->setContentTransform(contentTransform);
        auto fbo = std::make_unique<GLFramebuffer>(texture.get());
        if (!fbo->valid()) {
            qCWarning(KWIN_ANLAND) << "framebuffer for dmabuf" << i << "is not complete";
            releaseBuffers();
            return false;
        }

        qCDebug(KWIN_ANLAND) << "imported buffer" << i << "fd" << fd << actual
                             << "fmt" << Qt::hex << attrs.format << "mod" << attrs.modifier;

        m_textures[i] = std::move(texture);
        m_fbos[i] = std::move(fbo);
        m_renderTargets[i].emplace(m_fbos[i].get());
        // Freshly imported dmabuf has undefined contents: owe it a full repaint.
        m_accumDamage[i] = Region::infinite();
    }

    m_bufCount = count;
    // We repaint the selected BufferQueue slot completely on every submitted
    // frame, so there is no need to pre-warm every buffer with extra frames.
    // Keep this flag only as a one-shot forced repaint for reconnect/startup.
    m_damageMask = 1;
    m_damageFlags = 1;
    return true;
}

bool AnlandEglLayer::needsRepaint() const
{
    return m_damageFlags != 0;
}

void AnlandEglLayer::onOutputTransformChanged()
{
    const OutputTransform contentTransform =
        m_output->transform().combine(OutputTransform::FlipY);
    for (int i = 0; i < m_bufCount; i++) {
        m_textures[i]->setContentTransform(contentTransform);
        m_renderTargets[i].emplace(m_fbos[i].get());
        m_accumDamage[i] = Region::infinite();
    }
    // One forced full repaint is enough. doBeginFrame() always repaints
    // the complete selected dmabuf anyway.
    m_damageFlags = 1;
    scheduleRepaint(nullptr);
}

std::optional<OutputLayerBeginFrameInfo> AnlandEglLayer::doBeginFrame()
{
    m_backend->openglContext()->makeCurrent();

    m_currentIndex = get_selected_idx(m_display);

    if (m_currentIndex < 0 || m_currentIndex >= m_bufCount || !m_renderTargets[m_currentIndex]) {
        // A failed EGLImage import must not turn into std::optional::operator*
        // aborts. Wait for the next consumer reconnect/frame instead.
        qCWarning(KWIN_ANLAND) << "no render target for consumer buffer" << m_currentIndex;
        return std::nullopt;
    }

    return OutputLayerBeginFrameInfo{
        .renderTarget = *m_renderTargets[m_currentIndex],
        // Android BufferQueue contents outside damage are not reliable on
        // Clover. Always redraw the selected slot completely.
        .repaint = Region::infinite(),
    };
}

bool AnlandEglLayer::doEndFrame(const Region &renderedDeviceRegion, const Region &damagedDeviceRegion, OutputFrame *frame)
{
    glFlush();
    /*
     * doBeginFrame() already returns Region::infinite(), therefore the
     * currently selected Android BufferQueue slot has just been completely
     * redrawn.
     *
     * Do NOT propagate every client damage to every other slot. Video clients
     * produce damage continuously and the old code turned every video frame
     * into multiple full-screen KWin composites.
     *
     * m_damageFlags is retained only for initial buffer warm-up and output
     * transform changes.
     */
    m_accumDamage[m_currentIndex] = Region();
    m_damageFlags &=
        ~(uint8_t)(1 << m_currentIndex);
    if (m_damageFlags != 0)
        scheduleRepaint(nullptr);
    if (qEnvironmentVariableIntValue("ANLAND_NATIVE_FENCE") == 1) {
        EGLNativeFence fence{
            m_backend->openglContext()->displayObject()
        };
        set_render_fence(
            m_display,
            fence.takeFileDescriptor().take()
        );
    } else {
        glFinish();
        set_render_fence(m_display, -1);
    }
    return true;
}

DrmDevice *AnlandEglLayer::scanoutDevice() const
{
    return m_backend->drmDevice();
}

FormatModifierMap AnlandEglLayer::supportedDrmFormats() const
{
    return m_backend->supportedFormats();
}

AnlandEglBackend::AnlandEglBackend(AnlandBackend *b)
    : m_backend(b)
{
}

AnlandEglBackend::~AnlandEglBackend()
{
    m_outputs.clear();
    cleanup();
}

display_ctx *AnlandEglBackend::display() const
{
    return m_backend->display();
}

DrmDevice *AnlandEglBackend::drmDevice() const
{
    return m_backend->drmDevice();
}

bool AnlandEglBackend::initializeEgl()
{
    if (!initClientExtensions()) {
        return false;
    }
    if (!m_backend->renderDevice()) {
        return false;
    }
    setRenderDevice(m_backend->renderDevice());
    return true;
}

bool AnlandEglBackend::init()
{
    if (!initializeEgl()) {
        qCWarning(KWIN_ANLAND) << "Could not initialize egl";
        return false;
    }
    if (!initRenderingContext()) {
        qCWarning(KWIN_ANLAND) << "Could not initialize rendering context";
        return false;
    }

    if (checkGLError("Init")) {
        qCWarning(KWIN_ANLAND) << "Error during init of AnlandEglBackend";
        return false;
    }

    // EglBackend::initWayland() assumes a non-null DRM scanout device. Anland
    // imports Android buffers directly, so skip DRM feedback on KGSL-only
    // kernels and keep the surfaceless EGL path alive.
    if (m_backend->drmDevice()) {
        initWayland();
    } else {
        qCInfo(KWIN_ANLAND) << "skipping DRM Wayland feedback for surfaceless EGL";
    }

    const auto outputs = m_backend->outputs();
    for (BackendOutput *output : outputs) {
        addOutput(output);
    }

    connect(m_backend, &AnlandBackend::outputAdded, this, &AnlandEglBackend::addOutput);
    connect(m_backend, &AnlandBackend::outputRemoved, this, &AnlandEglBackend::removeOutput);
    return true;
}

bool AnlandEglBackend::initRenderingContext()
{
    return createContext() && openglContext()->makeCurrent();
}

void AnlandEglBackend::addOutput(BackendOutput *output)
{
    openglContext()->makeCurrent();
    auto *anlandOutput = static_cast<AnlandOutput *>(output);
    auto layer = std::make_unique<AnlandEglLayer>(anlandOutput, this);
    // Let AnlandBackend reach this layer through its output (output->eglLayer()).
    anlandOutput->setEglLayer(layer.get());
    m_outputs[output] = std::move(layer);
}

void AnlandEglBackend::removeOutput(BackendOutput *output)
{
    openglContext()->makeCurrent();
    static_cast<AnlandOutput *>(output)->setEglLayer(nullptr);
    m_outputs.erase(output);
}

QList<OutputLayer *> AnlandEglBackend::compatibleOutputLayers(BackendOutput *output)
{
    auto it = m_outputs.find(output);
    if (it == m_outputs.end()) {
        return {};
    }
    return {it->second.get()};
}

} // namespace KWin
