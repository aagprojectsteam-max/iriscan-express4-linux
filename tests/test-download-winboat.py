#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("download_winboat", ROOT / "tools/download-winboat.py")
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

GOOD = {
    "draft": False,
    "prerelease": False,
    "assets": [{
        "name": "winboat-0.9.2-amd64.deb",
        "browser_download_url": "https://github.com/winboat-org/winboat/releases/download/v0.9.2/winboat-0.9.2-amd64.deb",
        "digest": "sha256:" + "a" * 64,
    }],
}

name, url, digest = module.select_asset(GOOD)
assert name.endswith("amd64.deb") and url.startswith(module.URL_PREFIX) and digest == "a" * 64
for mutation in ("draft", "prerelease"):
    bad = dict(GOOD)
    bad[mutation] = True
    try:
        module.select_asset(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"accepted {mutation} release")
bad = {**GOOD, "assets": [{**GOOD["assets"][0], "browser_download_url": "https://example.invalid/winboat.deb"}]}
try:
    module.select_asset(bad)
except ValueError:
    pass
else:
    raise AssertionError("accepted non-official asset URL")
print("WINBOAT_DOWNLOAD_METADATA_TEST=PASS")
