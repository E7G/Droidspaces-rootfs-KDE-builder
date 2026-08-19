/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-License-Identifier: GPL-2.0-or-later

    Clover Extreme v3: Persistent scene FBO + GPU full blit implementation
*/
#include "anland_egl_backend.h"
#include "anland_backend.h"
#include "anland_logging.h"
#include "anland_output.h"

// kwin
#include "core/graphicsbuffer.h"
#include "core/output.h"
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
    connect(m_output, &BackendOutput::transformChanged, this, &AnlandEglLayer::onOutputTransformChanged);
}

AnlandEglLayer::~AnlandEglLayer()
{
    if (m_output && m_output->eglLayer() == this) {
        m_output->setEglLayer(nullptr);
    }
    releaseBuffers();
}

void AnlandEglLayer::releaseBuffers()
{
    m_backend->openglContext()->makeCurrent();

    for (int i = 0; i < MAX_BUFS; i++) {
        m_fbos[i].reset();
        m_textures[i].reset();
    }
    m_sceneTexture.reset();
    m_sceneFbo.reset();
    m_sceneTarget.reset();
    m_sceneInvalid = true;
    m_bufCount = 0;
}

void AnlandEglLayer::ensureSceneFbo()
{
    if (m_sceneFbo && m_sceneSize == m_output->modeSize()) {
        return;
    }

    m_backend->openglContext()->makeCurrent();

    const QSize size = m_output->modeSize();
    m_sceneTexture = GLTexture::allocate();
    if (!m_sceneTexture) {
        qCWarning(KWIN_ANLAND) << "failed to allocate scene texture";
        return;
    }
    m_sceneTexture->setSize(size);
    m_sceneTexture->setInternalFormat(GL_RGBA8);
    m_sceneTexture->setFilter(GL_LINEAR);
    m_sceneTexture->setWrapMode(GL_CLAMP_TO_EDGE);
    m_sceneTexture->create();

    m_sceneFbo = std::make_unique<GLFramebuffer>(m_sceneTexture.get());
    if (!m_sceneFbo->valid()) {
        qCWarning(KWIN_ANLAND) << "scene framebuffer is not complete";
        m_sceneTexture.reset();
        m_sceneFbo.reset();
        return;
    }

    m_sceneTarget = RenderTarget(m_sceneFbo.get());
    m_sceneSize = size;
    m_sceneInvalid = true;

    qCDebug(KWIN_ANLAND) << "created scene FBO" << size;
}

void AnlandEglLayer::blitSceneToDmabuf()
{
    if (!m_sceneFbo || !m_fbos[m_currentIndex]) {
        return;
    }

    const QSize size = m_output->modeSize();
    const int w = size.width();
    const int h = size.height();

    GLFramebuffer::pushFramebuffer(m_fbos[m_currentIndex].get());

    glBlitFramebuffer(
        0, 0, w, h,
        0, 0, w, h,
        GL_COLOR_BUFFER_BIT,
        GL_NEAREST
    );

    GLFramebuffer::popFramebuffer();
}

bool AnlandEglLayer::importBuffers(int count)
{
    m_backend->openglContext()->makeCurrent();
    releaseBuffers();

    const OutputTransform contentTransform = m_output->transform().combine(OutputTransform::FlipY);

    for (int i = 0; i < count; i++) {
        const int fd = get_dmabuf_fd_at(m_display, i);
        buf_info info;
        if (fd < 0 || get_dmabuf_info_at(m_display, i, &info) < 0) {
            qCWarning(KWIN_ANLAND) << "failed to get dmabuf info for buffer" << i;
            releaseBuffers();
            return false;
        }

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
        attrs.modifier = info.modifier == 0 ? DRM_FORMAT_MOD_INVALID : info.modifier;
        attrs.fd[0] = FileDescriptor(dup(fd));
        attrs.offset[0] = static_cast<int>(info.offset);
        attrs.pitch[0] = static_cast<int>(info.stride);

        const std::array<uint32_t, 5> formatCandidates = {
            attrs.format,
            DRM_FORMAT_XRGB8888,
            DRM_FORMAT_ARGB8888,
            DRM_FORMAT_XBGR8888,
            DRM_FORMAT_ABGR8888,
        };
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
    }

    m_bufCount = count;
    ensureSceneFbo();
    m_sceneInvalid = true;
    return true;
}

bool AnlandEglLayer::needsRepaint() const
{
    return m_sceneInvalid;
}

void AnlandEglLayer::onOutputTransformChanged()
{
    const OutputTransform contentTransform = m_output->transform().combine(OutputTransform::FlipY);
    for (int i = 0; i < m_bufCount; i++) {
        m_textures[i]->setContentTransform(contentTransform);
    }
    m_sceneInvalid = true;
    scheduleRepaint(nullptr);
}

std::optional<OutputLayerBeginFrameInfo> AnlandEglLayer::doBeginFrame()
{
    m_backend->openglContext()->makeCurrent();

    m_currentIndex = get_selected_idx(m_display);

    if (m_currentIndex < 0 || m_currentIndex >= m_bufCount || !m_fbos[m_currentIndex]) {
        qCWarning(KWIN_ANLAND) << "no render target for consumer buffer" << m_currentIndex;
        return std::nullopt;
    }

    ensureSceneFbo();

    if (!m_sceneTarget) {
        qCWarning(KWIN_ANLAND) << "scene FBO not available";
        return std::nullopt;
    }

    OutputLayerBeginFrameInfo info;
    info.renderTarget = *m_sceneTarget;
    info.repaint = m_sceneInvalid ? Region::infinite() : Region();
    return info;
}

bool AnlandEglLayer::doEndFrame(const Region &renderedDeviceRegion, const Region &damagedDeviceRegion, OutputFrame *frame)
{
    glFlush();

    blitSceneToDmabuf();

    m_sceneInvalid = false;

    // Clover Extreme v3: Always use EGL native fence for async GPU completion
    // The Anland fence worker thread will wait for GPU completion instead of
    // blocking the KWin render thread with glFinish(). This eliminates
    // CPU/GPU synchronization from the render thread and improves frame pacing.
    EGLNativeFence fence{
        m_backend->openglContext()->displayObject()
    };
    set_render_fence(
        m_display,
        fence.takeFileDescriptor().take()
    );
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

    setEglDisplay(EglDisplay::create(eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_NO_DISPLAY, nullptr)));
    if (!eglDisplay()) {
        return false;
    }

    if (!eglDisplay()->initialize()) {
        return false;
    }

    return true;
}

bool AnlandEglBackend::initRenderingContext()
{
    if (!initializeEgl()) {
        return false;
    }

    const EGLint context_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };

    setContext(EglContext::create(eglDisplay(), EGL_NO_CONFIG_KHR, context_attribs));
    if (!openglContext()) {
        return false;
    }

    if (!openglContext()->makeCurrent()) {
        return false;
    }

    return true;
}

bool AnlandEglBackend::init()
{
    if (!initRenderingContext()) {
        return false;
    }

    for (auto *output : m_backend->outputs()) {
        addOutput(output);
    }

    connect(m_backend, &AnlandBackend::outputAdded, this, &AnlandEglBackend::addOutput);
    connect(m_backend, &AnlandBackend::outputRemoved, this, &AnlandEglBackend::removeOutput);

    return true;
}

void AnlandEglBackend::addOutput(BackendOutput *output)
{
    auto layer = std::make_unique<AnlandEglLayer>(static_cast<AnlandOutput *>(output), this);
    m_outputs[output] = std::move(layer);
}

void AnlandEglBackend::removeOutput(BackendOutput *output)
{
    m_outputs.erase(output);
}

QList<OutputLayer *> AnlandEglBackend::compatibleOutputLayers(BackendOutput *output)
{
    auto it = m_outputs.find(output);
    if (it != m_outputs.end()) {
        return {it->second.get()};
    }
    return {};
}

} // namespace KWin