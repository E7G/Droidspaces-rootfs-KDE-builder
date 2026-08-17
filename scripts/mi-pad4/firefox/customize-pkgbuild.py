#!/usr/bin/env python3
"""Turn Arch's pinned Firefox package into the Clover direct-DMABUF build."""

from pathlib import Path


path = Path("PKGBUILD")
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one PKGBUILD match, got {count}: {old!r}")
    text = text.replace(old, new, 1)


replace_once("pkgrel=1\n", "pkgrel=1.3\n")
replace_once("arch=(x86_64)\n", "arch=(aarch64)\n")
replace_once("  onnxruntime\n", "")
replace_once("  jack\n", "")
for package in (
    "wasi-compiler-rt",
    "wasi-libc",
    "wasi-libc++",
    "wasi-libc++abi",
):
    replace_once(f"  {package}\n", "")
replace_once("ac_add_options --with-wasi-sysroot=/usr/share/wasi-sysroot\n", "")
replace_once(
    "ac_add_options --enable-crashreporter\n",
    "ac_add_options --disable-crashreporter\n"
    "ac_add_options --disable-debug-symbols\n"
    "ac_add_options --without-onnx-runtime\n"
    "ac_add_options --without-wasm-sandboxed-libraries\n",
)
replace_once(
    "ac_add_options --enable-alsa\n"
    "ac_add_options --enable-jack\n",
    "# Clover uses Anland's PipeWire-Pulse bridge. Remove unused audio backends.\n"
    "ac_add_options --enable-pulseaudio\n"
    "ac_add_options --disable-alsa\n"
    "ac_add_options --disable-jack\n"
    "# Tablet-only build: remove large services not used by normal browsing.\n"
    "ac_add_options --disable-backgroundtasks\n"
    "ac_add_options --disable-webdriver\n"
    "ac_add_options --disable-profiling\n"
    "ac_add_options --enable-mobile-optimize\n",
)
replace_once(
    '  echo -n "$_google_api_key" >google-api-key\n',
    '  patch -Np1 <"$srcdir/../0002-mi-pad4-clover-direct-dmabuf.patch"\n'
    '  patch -Np1 <"$srcdir/../0003-mi-pad4-clover-full-egl-damage.patch"\n\n'
    '  echo -n "$_google_api_key" >google-api-key\n',
)
replace_once(
    "  # Link up system ONNX runtime\n"
    '  ln -srv "$pkgdir/usr/lib/libonnxruntime.so" -t "$appdir"\n\n',
    "",
)

build_command = "  ./mach build --priority normal\n"
if text.count(build_command) != 2:
    raise SystemExit("expected two Firefox build commands")
text = text.replace(build_command, "  ./mach build -j2 --priority normal\n")

path.write_text(text)
