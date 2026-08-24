/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "anland_output.h"
#include "anland_backend.h"
#include "anland_egl_backend.h"
#include "anland_logging.h"

#include "core/renderbackend.h" // OutputFrame
#include "core/renderloop.h"

#include <chrono>

namespace KWin
{

AnlandOutput::AnlandOutput(AnlandBackend *parent, const QString &name)
    : BackendOutput()
    , m_backend(parent)
    , m_renderLoop(std::make_unique<RenderLoop>(this))
{
    setInformation(Information{
        .name = name,
        .manufacturer = QStringLiteral("anland"),
        .model = QStringLiteral("anland"),
        // Mi Pad 4: 8-inch 16:10 panel (about 283 ppi).  A null physical size
        // becomes -1x-1 mm in wl_output. Plasma then replaces the initial
        // QScreen after output-management discovery and remaps a still-pending
        // layer surface, permanently hiding its panel on this Qt/KWin stack.
        .physicalSize = QSize(172, 108),
        .internal = true,
    });
}

AnlandOutput::~AnlandOutput()
{
}

RenderLoop *AnlandOutput::renderLoop() const
{
    return m_renderLoop.get();
}

bool AnlandOutput::testPresentation(const std::shared_ptr<OutputFrame> &frame)
{
    return true;
}

bool AnlandOutput::present(const QList<OutputLayer *> &layersToUpdate, const std::shared_ptr<OutputFrame> &frame)
{
    // The scene has already been rendered into the daemon's dmabuf by the layer
    // (AnlandEglLayer::doEndFrame). Hand it to the consumer now.
    m_frame = frame;
    const bool handedToConsumer = m_backend->notifyFramePresented();
    if (handedToConsumer) {
        // The consumer will present the buffer and then signal buffer-ready;
        // defer frame completion until then (see onConsumerReady()).
        m_awaitingPresent = true;
    } else {
        // Nothing was handed to the consumer this frame, so no buffer-ready will
        // arrive for it — complete it now so the RenderLoop never stalls.
        completeFrame();
    }
    return true;
}

void AnlandOutput::init(const QSize &pixelSize, int refresh, qreal scale)
{
    // refresh is in mHz, like RenderLoop/OutputMode expect.
    if (refresh <= 0) {
        refresh = 120000;
    }
    m_renderLoop->setRefreshRate(refresh);

    auto mode = std::make_shared<OutputMode>(OutputModeline(pixelSize, refresh, OutputModeline::Flag::Preferred));

    setState(State{
        .position = QPoint(0, 0),
        .scale = scale,
        .modes = {mode},
        .currentMode = mode,
    });
}

void AnlandOutput::updateEnabled(bool enabled)
{
    State next = m_state;
    next.enabled = enabled;
    setState(next);
}

void AnlandOutput::setRefreshRate(int refresh)
{
    // refresh is in mHz. Ignore noise and no-op changes; RenderLoop::setRefreshRate
    // already guards the latter, but we also skip rebuilding the mode below.
    if (refresh <= 0 || refresh == m_renderLoop->refreshRate()) {
        return;
    }
    m_renderLoop->setRefreshRate(refresh);

    // Keep the OutputMode in lockstep with the RenderLoop, mirroring init(), so
    // currentMode()->refreshRate() and any mode-based logic see the new rate.
    auto mode = std::make_shared<OutputMode>(OutputModeline(modeSize(), refresh, OutputModeline::Flag::Preferred));
    State next = m_state;
    next.modes = QList<std::shared_ptr<OutputMode>>{mode};
    next.currentMode = mode;
    setState(next);
}

void AnlandOutput::completeFrame()
{
    if (!m_frame) {
        return;
    }
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    m_frame->presented(now, PresentationMode::VSync);
    m_frame.reset();
}

void AnlandOutput::handOffWithoutFrame()
{
    // Direct stale-slot copies and clean acknowledgements have no OutputFrame,
    // so RenderLoop would otherwise accept client damage while Android still
    // owns the selected slot. Hold composition until its matching ready event.
    m_renderLoop->inhibit();
    m_unframedPresentInhibited = true;
    if (!m_backend->notifyFramePresented()) {
        m_renderLoop->uninhibit();
        m_unframedPresentInhibited = false;
    }
}

void AnlandOutput::onConsumerReady()
{
    if (m_unframedPresentInhibited) {
        m_renderLoop->uninhibit();
        m_unframedPresentInhibited = false;
    }

    if (m_awaitingPresent) {
        m_awaitingPresent = false;
        completeFrame();
    }

    // A buffer-ready event means the consumer has already selected its *next*
    // dmabuf and is blocked in refresh_done() waiting for exactly one reply. If
    // this slot still carries an older scene generation, copy the persistent
    // scene into it directly. Do not schedule a synthetic KWin frame: KWin folds
    // device repair into surfaceDamage, which would make that sync frame look
    // like new client damage and dirty every slot again forever.
    if (m_eglLayer && m_eglLayer->needsRepaint()) {
        if (m_eglLayer->syncSelectedBuffer()) {
            handOffWithoutFrame();
        } else {
            // The persistent scene itself is invalid after startup, reconnect or
            // rotation, so it must be composed once before direct slot copies.
            m_eglLayer->addDeviceRepaint(Region::infinite());
        }
        return;
    }

    // Idle scene: acknowledge the selected clean buffer without rendering. The
    // old code returned after completing the previous OutputFrame and left this
    // new request unanswered; the consumer hit its five-second safety timeout,
    // tore down every dmabuf and reconnected, producing the periodic full-screen
    // flash. A bare refresh message keeps BufferQueue alive while the GPU sleeps.
    handOffWithoutFrame();
}

void AnlandOutput::resize(const QSize &newSize)
{
    if (newSize == modeSize() || !newSize.isValid())
        return;

    qCInfo(KWIN_ANLAND) << "resizing output to" << newSize;

    // Keep the same refresh rate; update both the OutputMode and the RenderLoop
    // pacing. Mirroring setRefreshRate() / init().
    const int refresh = m_renderLoop->refreshRate();
    auto mode = std::make_shared<OutputMode>(OutputModeline(newSize, refresh, OutputModeline::Flag::Preferred));
    State next = m_state;
    next.modes = QList<std::shared_ptr<OutputMode>>{mode};
    next.currentMode = mode;
    setState(next);

    // setState() only emits currentModeChanged(); that does NOT re-lay-out windows.
    // The Workspace recomputes geometry in updateOutputs()/desktopResized(), which is
    // driven by OutputBackend::outputsQueried (see Workspace ctor). Since we changed
    // the mode directly here rather than through OutputConfiguration, emit it now so
    // the compositor recalculates the layout for the new size.
    m_backend->notifyOutputsChanged();

    // Invalidate any in-flight frame: the mode just changed, so the buffer that was
    // being presented corresponds to a different layout.
    if (m_awaitingPresent) {
        m_awaitingPresent = false;
        m_frame.reset();
    }
}

void AnlandOutput::setEglLayer(AnlandEglLayer *layer)
{
    m_eglLayer = layer;
}

AnlandEglLayer *AnlandOutput::eglLayer() const
{
    return m_eglLayer;
}

void AnlandOutput::stopRendering()
{
    if (m_awaitingPresent) {
        m_awaitingPresent = false;
        m_frame.reset();
    }

    if (m_unframedPresentInhibited) {
        m_renderLoop->uninhibit();
        m_unframedPresentInhibited = false;
    }

    if (!m_renderingInhibited) {
        m_renderLoop->inhibit();
        m_renderingInhibited = true;
    }
}

void AnlandOutput::resumeRendering()
{
    if (m_renderingInhibited) {
        m_renderLoop->uninhibit();
        m_renderingInhibited = false;
    }
}

} // namespace KWin
