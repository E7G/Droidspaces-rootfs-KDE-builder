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


replace_once("pkgrel=1\n", "pkgrel=1.1\n")
replace_once("arch=(x86_64)\n", "arch=(aarch64)\n")
replace_once(
    "ac_add_options --enable-crashreporter\n",
    "ac_add_options --disable-crashreporter\n"
    "ac_add_options --disable-debug-symbols\n",
)
replace_once(
    '  echo -n "$_google_api_key" >google-api-key\n',
    '  patch -Np1 <../0002-mi-pad4-clover-direct-dmabuf.patch\n\n'
    '  echo -n "$_google_api_key" >google-api-key\n',
)

path.write_text(text)
