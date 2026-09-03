#!/usr/bin/env python3
"""Download the official WinBoat amd64 Debian asset and verify GitHub's SHA256."""
from __future__ import annotations

import hashlib
import json
import re
import sys
import urllib.request
from pathlib import Path

API = "https://api.github.com/repos/winboat-org/winboat/releases/latest"
URL_PREFIX = "https://github.com/winboat-org/winboat/releases/download/"


def select_asset(metadata: dict) -> tuple[str, str, str]:
    if metadata.get("draft") or metadata.get("prerelease"):
        raise ValueError("latest WinBoat release is not a stable published release")
    candidates = []
    for asset in metadata.get("assets", []):
        name = str(asset.get("name", ""))
        url = str(asset.get("browser_download_url", ""))
        digest = str(asset.get("digest", ""))
        if re.fullmatch(r"winboat-[0-9][0-9A-Za-z.+~-]*-amd64\.deb", name):
            candidates.append((name, url, digest))
    if len(candidates) != 1:
        raise ValueError(f"expected one official amd64 Debian asset; found {len(candidates)}")
    name, url, digest = candidates[0]
    if not url.startswith(URL_PREFIX) or not digest.startswith("sha256:"):
        raise ValueError("official asset URL or SHA256 digest is missing")
    expected = digest.removeprefix("sha256:")
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("invalid SHA256 digest")
    return name, url, expected


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} DESTINATION_DIRECTORY", file=sys.stderr)
        return 2
    destination = Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(API, headers={"Accept": "application/vnd.github+json", "User-Agent": "iriscan-express4-ubuntu-installer/0.3.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        metadata = json.load(response)
    name, url, expected = select_asset(metadata)
    output = destination / name
    h = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=120) as response, output.open("wb") as target:
        while chunk := response.read(1024 * 1024):
            target.write(chunk)
            h.update(chunk)
    actual = h.hexdigest()
    if actual != expected:
        output.unlink(missing_ok=True)
        raise SystemExit(f"WinBoat SHA256 mismatch: {actual} != {expected}")
    print(f"WINBOAT_DEB={output}")
    print(f"WINBOAT_SHA256={actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
