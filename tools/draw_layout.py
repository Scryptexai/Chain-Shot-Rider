#!/usr/bin/env python3
"""Draws a diagram of UI rects measured by the smoke test.

    python3 tools/draw_layout.py

This is NOT a screenshot. The sandbox has no GPU, no X server and no libGL, so
the Godot renderer cannot be captured here at all. What it draws is the
geometry Godot's layout engine actually computed while running headless -
`Control.get_global_rect()` on the live scene - rendered as boxes.

That distinction matters both ways. The numbers are real: if a card is 36 px
wide or hangs off the bottom of the screen, this shows it, and the smoke test
already failed on it. But colour, type, spacing inside the widgets and every
visual detail are invented by this script and prove nothing.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "screenshots"

BG = (10, 16, 48)
INK = (245, 249, 255)
DIM = (138, 155, 184)
ACCENT = (0, 229, 255)
SAFE = (31, 211, 232)


def draw(payload: dict, out: Path) -> None:
    from PIL import Image, ImageDraw

    vw = int(payload["viewport"]["w"])
    vh = int(payload["viewport"]["h"])
    scale = 0.38
    w, h = int(vw * scale), int(vh * scale)
    pad = 40
    img = Image.new("RGB", (w + pad * 2, h + pad * 2 + 46), BG)
    d = ImageDraw.Draw(img)

    d.text((pad, 14), f"CHAIN RIDER — {payload['screen']}: geometri terukur "
                      f"({vw}x{vh})", fill=INK)
    d.text((pad, 30), "diagram dari Control.get_global_rect() headless — bukan screenshot",
           fill=DIM)

    top = pad + 46
    d.rectangle([pad, top, pad + w, top + h], outline=DIM)

    # Safe area top (docs/06: 88 px) and the 90 px column margins.
    sy = top + int(88 * scale)
    d.line([pad, sy, pad + w, sy], fill=SAFE)
    d.text((pad + 6, sy + 2), "safe top 88", fill=SAFE)
    for mx in (90, vw - 90):
        x = pad + int(mx * scale)
        d.line([x, top, x, top + h], fill=(40, 60, 100))

    for r in payload["rects"]:
        x0 = pad + int(r["x"] * scale)
        y0 = top + int(r["y"] * scale)
        x1 = pad + int((r["x"] + r["w"]) * scale)
        y1 = top + int((r["y"] + r["h"]) * scale)
        d.rectangle([x0, y0, x1, y1], outline=ACCENT, fill=(14, 34, 66))
        d.text((x0 + 10, y0 + 8), str(r["label"]), fill=INK)
        d.text((x0 + 10, y1 - 18),
               f'{int(r["w"])}x{int(r["h"])} @ {int(r["x"])},{int(r["y"])}', fill=DIM)

    img.save(out)
    print(f"  {out.relative_to(ROOT)}")


def main() -> None:
    files = sorted(SHOTS.glob("layout-*.json"))
    if not files:
        raise SystemExit("tidak ada dump layout — jalankan smoke test dulu")
    print("\nCHAIN RIDER — diagram layout (dari pengukuran, bukan render)")
    for path in files:
        payload = json.loads(path.read_text())
        draw(payload, path.with_suffix(".png"))
    print("")


if __name__ == "__main__":
    main()
