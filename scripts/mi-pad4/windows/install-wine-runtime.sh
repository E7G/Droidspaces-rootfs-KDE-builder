#!/bin/bash
set -euo pipefail

# Install Wine runtime components for Mi Pad 4
# Uses existing PipeWire/Anland audio path, no additional audio daemon needed

# Install Wine with WoW64 support (for x86_64 Wine)
pacman -S --needed --noconfirm wine wine-mono wine-gecko

# Configure Wine for Wayland + Anland
# Priority: Wayland driver -> X11 fallback
wine reg.exe add 'HKCU\Software\Wine\Drivers' /v Graphics /d wayland,x11 /f

# Configure WineD3D to use OpenGL (not Vulkan since Adreno 512 lacks Turnip)
wine reg.exe add 'HKCU\Software\Wine\Direct3D' /v DirectDrawRenderer /d opengl /f
wine reg.exe add 'HKCU\Software\Wine\Direct3D' /v Direct3DRenderer /d opengl /f

# Disable Vulkan (Adreno 512 a5xx has no Turnip support)
wine reg.exe add 'HKCU\Software\Wine\AppDefaults' /v DllOverrides /d vulkan-1,steamclient=n /f

# Optimize for Adreno 512 performance
wine reg.exe add 'HKCU\Software\Wine\Direct3D' /v VideoMemorySize /d 2048 /f
wine reg.exe add 'HKCU\Software\Wine\Direct3D' /v OffscreenRenderingMode /d fbo /f

# Configure audio to use existing PipeWire/Anland path
wine reg.exe add 'HKCU\Software\Wine\Drivers' /v Audio /d pulse /f

echo "Wine runtime installed and configured for Mi Pad 4"