#!/usr/bin/env python3
"""Convert IRIScan per-line planar RGB raw data to PNG using stdlib only."""
from __future__ import annotations
import argparse, json, struct, zlib
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"

def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--metadata", required=True)
    ap.add_argument("--raw", required=True)
    ap.add_argument("--output", required=True)
    ns = ap.parse_args()
    meta = json.loads(Path(ns.metadata).read_text())
    w = int(meta["width_pixels"])
    h = int(meta["height_pixels"])
    raw_path = Path(ns.raw)
    out_path = Path(ns.output)
    expected = w * h * 3
    actual = raw_path.stat().st_size
    if actual != expected:
        raise SystemExit(f"raw size mismatch: {actual} != {expected}")

    compressor = zlib.compressobj(level=6)
    compressed_parts: list[bytes] = []
    with raw_path.open("rb") as f:
        for y in range(h):
            line = f.read(w * 3)
            if len(line) != w * 3:
                raise SystemExit(f"short raw line at {y}")
            r = line[0:w]
            g = line[w:2*w]
            b = line[2*w:3*w]
            interleaved = bytearray(w * 3 + 1)
            interleaved[0] = 0  # PNG filter None
            interleaved[1::3] = r
            interleaved[2::3] = g
            interleaved[3::3] = b
            part = compressor.compress(interleaved)
            if part:
                compressed_parts.append(part)
    compressed_parts.append(compressor.flush())
    idat = b"".join(compressed_parts)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    with out_path.open("wb") as out:
        out.write(PNG_SIG)
        out.write(chunk(b"IHDR", ihdr))
        out.write(chunk(b"IDAT", idat))
        out.write(chunk(b"IEND", b""))
    print(f"PNG={out_path}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
