#!/bin/bash
# Mi Pad 4 SDM660 user-space defaults. Keep this dependency-free: the guest
# uses an Android 4.4/4.19-style kernel and must not inherit desktop-sized
# allocator arenas or generic workstation tuning.
export MALLOC_ARENA_MAX=2
export GLIBC_TUNABLES="glibc.malloc.trim_threshold=131072:glibc.malloc.mmap_threshold=131072"
export QT_ENABLE_GLYPH_CACHE_WORKAROUND=1
