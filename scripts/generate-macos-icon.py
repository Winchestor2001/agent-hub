#!/usr/bin/env python3
"""Generate the Agent Hub macOS app icon as an `.icns` file.

The script intentionally uses only the Python standard library plus macOS
`iconutil`, so `make macos-app` does not need image dependencies.
"""

from __future__ import annotations

import argparse
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

ICONSET_ENTRIES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, size: int) -> None:
    rows = bytearray()
    radius = size * 0.22
    center = (size - 1) / 2
    for y in range(size):
        rows.append(0)
        for x in range(size):
            dx = abs(x - center) - (center - radius)
            dy = abs(y - center) - (center - radius)
            outside = max(dx, dy, 0)
            alpha = 255 if outside <= 0 else max(0, int(255 * (1 - outside / radius)))
            blue = int(50 + 80 * (x / max(size - 1, 1)))
            violet = int(80 + 100 * (y / max(size - 1, 1)))
            rows.extend((blue, violet, 220, alpha))

    paint_letters(rows, size)
    payload = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(payload)


def fill_rect(rows: bytearray, size: int, x0: float, y0: float, x1: float, y1: float) -> None:
    left = max(0, int(size * x0))
    top = max(0, int(size * y0))
    right = min(size, int(size * x1))
    bottom = min(size, int(size * y1))
    for y in range(top, bottom):
        row = y * (1 + size * 4) + 1
        for x in range(left, right):
            offset = row + x * 4
            rows[offset : offset + 4] = b"\xff\xff\xff\xff"


def paint_letters(rows: bytearray, size: int) -> None:
    # Blocky "A"
    fill_rect(rows, size, 0.20, 0.68, 0.30, 0.78)
    fill_rect(rows, size, 0.28, 0.44, 0.38, 0.78)
    fill_rect(rows, size, 0.38, 0.24, 0.48, 0.78)
    fill_rect(rows, size, 0.24, 0.50, 0.48, 0.60)

    # Blocky "H"
    fill_rect(rows, size, 0.55, 0.24, 0.65, 0.78)
    fill_rect(rows, size, 0.78, 0.24, 0.88, 0.78)
    fill_rect(rows, size, 0.55, 0.48, 0.88, 0.58)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Agent Hub.icns")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="agent-hub-icon-") as tmp:
        iconset = Path(tmp) / "AgentHub.iconset"
        iconset.mkdir()
        for name, size in ICONSET_ENTRIES.items():
            write_png(iconset / name, size)
        subprocess.run(  # noqa: S603
            ["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(args.output)],
            check=True,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
