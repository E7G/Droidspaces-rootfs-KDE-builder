#!/bin/bash
# Portable CachyOS user-space defaults for Mi Pad 4.
# Keep this file dependency-free: the guest uses a 4.4 Android kernel and
# cannot safely consume CachyOS kernel-only services or x86-specific packages.
export MALLOC_ARENA_MAX=2
export QT_ENABLE_GLYPH_CACHE_WORKAROUND=1
