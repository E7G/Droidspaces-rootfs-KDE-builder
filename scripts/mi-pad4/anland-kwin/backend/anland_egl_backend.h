/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-License-Identifier: GPL-2.0-or-later

    Clover Extreme v3: Persistent scene FBO + GPU full blit architecture
    
    Instead of rendering directly into rotating Android BufferQueue dmabufs,
    we maintain a persistent scene framebuffer owned by KWin. The scene is
    composed partially (only damaged regions) into this FBO, then a single
    GPU full-screen blit copies it to the current Android dmabuf slot.
    
    This eliminates:
    - Full-screen scene composition on every frame
    - Per-slot damage bookkeeping overhead
    - Multiple repaints for video frames
    
    Architecture:
    Firefox/Plasma damage → KWin scene (partial composition to m_sceneFbo)
                           → GPU full blit to Android dmabuf
                           → async fence worker
                           → Android consumer
*/
#pragma once

#include "core/outputlayer.h"
#include "core/region.h"
#include "opengl/eglbackend.h"

#include <array>
#include <map>
#include <memory>
#include <optional>

extern "C" {
#include "display_producer.h"
#include "protocol.h"
}

namespace KWin
{
class GLFramebuffer;
class GLTexture;
class BackendOutput;
class DrmDevice;
class OutputFrame;
class AnlandBackend;
class AnlandEglBackend;
class AnlandOutput;

class AnlandEglLayer : public OutputLayer
{
public:
    AnlandEglLayer(AnlandOutput *output, AnlandEglBackend *backend);
    ~AnlandEglLayer() override;

    std::optional<OutputLayerBeginFrameInfo> doBeginFrame() override;
    bool doEndFrame(const Region &renderedDeviceRegion, const Region &damagedDeviceRegion, OutputFrame *frame) override;
    DrmDevice *scanoutDevice() const override;
    FormatModifierMap supportedDrmFormats() const override;
    bool importBuffers(int count);
    void releaseBuffers() override;

    /** True while at least one consumer-owned dmabuf still needs the current
     *  scene. Used by the output handshake to render dirty rotation buffers but
     *  acknowledge clean ones without running the GPU continuously. */
    bool needsRepaint() const;

private:
    void onOutputTransformChanged();
    void ensureSceneFbo();
    void blitSceneToDmabuf();

    AnlandEglBackend *const m_backend;
    AnlandOutput *m_output;
    display_ctx *const m_display;

    // Android BufferQueue dmabufs (destination only)
    int m_bufCount = 0;
    int m_currentIndex = 0;
    std::array<std::shared_ptr<GLTexture>, MAX_BUFS> m_textures;
    std::array<std::unique_ptr<GLFramebuffer>, MAX_BUFS> m_fbos;

    // Persistent scene FBO (source for composition)
    std::unique_ptr<GLTexture> m_sceneTexture;
    std::unique_ptr<GLFramebuffer> m_sceneFbo;
    std::optional<RenderTarget> m_sceneTarget;
    bool m_sceneInvalid = true;
    bool m_hasPendingDamage = true;
    QSize m_sceneSize;
};

class AnlandEglBackend : public EglBackend
{
    Q_OBJECT

public:
    AnlandEglBackend(AnlandBackend *b);
    ~AnlandEglBackend() override;

    bool init() override;
    QList<OutputLayer *> compatibleOutputLayers(BackendOutput *output) override;
    DrmDevice *drmDevice() const override;

    AnlandBackend *backend() const
    {
        return m_backend;
    }
    display_ctx *display() const;

private:
    bool initializeEgl();
    bool initRenderingContext();

    void addOutput(BackendOutput *output);
    void removeOutput(BackendOutput *output);

    AnlandBackend *m_backend;
    std::map<BackendOutput *, std::unique_ptr<AnlandEglLayer>> m_outputs;
};

} // namespace KWin