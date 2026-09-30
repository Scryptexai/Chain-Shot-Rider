#!/usr/bin/env python3
"""Measures the music stems and draws a structure sheet.

    python3 tools/audit_music.py

Nothing in this sandbox can play audio, so the stems are checked the same way
the SFX are: numerically, plus a picture. Music needs three things the one-shot
cues did not:

  loop seam  - the stem repeats forever, so the last sample has to meet the
               first without a step. A discontinuity there is an audible click
               once every 60 seconds, which is the kind of defect that ships.
  grid       - percussion onsets must land on the 120 BPM eighth-note grid. If
               they drift, the layers will not stack.
  structure  - intro / A / B / A' must actually differ. A stem that renders one
               bar and repeats it measures fine on every other metric while
               being musically dead.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
MUSIC = ROOT / "godot" / "audio" / "music"
BPM = 120.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
SECTIONS = {"intro": (0, 6), "A": (6, 14), "B": (14, 22), "A'": (22, 30)}
LOOPING = {"base_synth", "arp", "pad", "percussion", "glitch", "drums_fill"}
# Sustained stems have no attacks to align; testing a pad against a rhythmic
# grid measures the detector, not the music.
RHYTHMIC = {"percussion", "drums_fill", "arp"}
GRID = {"arp": BEAT / 4.0}
# drums_fill is a wave-5 overlay that rides on top of an existing
# arrangement; uniformity across sections is correct for it.
STRUCTURED = {"base_synth", "arp", "pad", "percussion", "glitch"}


def seam_step(x: np.ndarray, sr: int) -> float:
    """Discontinuity at the loop point, measured against the stem's own edges.

    The comparison is to the 99th percentile of sample-to-sample movement, not
    the mean. Against the mean, any stem that opens on a drum hit looks broken:
    the attack at t=0 is a real transient, and a sparse percussion loop has a
    tiny mean step, so the ratio explodes even though the loop is perfect. The
    question worth asking is whether the seam is sharper than the sharpest
    transitions the music already contains - a ratio near or below 1 means the
    loop point is indistinguishable from an ordinary hit.
    """
    mono = x.mean(axis=1)
    jump = abs(float(mono[0]) - float(mono[-1]))
    steps = np.abs(np.diff(mono))
    reference = float(np.percentile(steps, 99))
    return jump / max(reference, 1e-9)


def onset_grid_error(x: np.ndarray, sr: int, step: float) -> tuple[float, int]:
    """Mean distance from each detected onset to the nearest grid position."""
    mono = np.abs(x.mean(axis=1))
    win = int(sr * 0.01)
    env = np.convolve(mono, np.ones(win) / win, mode="same")
    d = np.diff(env, prepend=env[0])
    thresh = float(np.mean(np.abs(d))) * 6.0
    peaks = np.where((d > thresh) & (d > np.roll(d, 1)) & (d > np.roll(d, -1)))[0]
    if len(peaks) == 0:
        return 0.0, 0
    # Thin out peaks that sit within 60 ms of each other.
    keep = [peaks[0]]
    for p in peaks[1:]:
        if p - keep[-1] > sr * 0.06:
            keep.append(p)
    times = np.array(keep) / sr
    err = np.abs(times - np.round(times / step) * step)
    return float(np.mean(err)), len(keep)


def section_rms(x: np.ndarray, sr: int) -> dict[str, float]:
    mono = x.mean(axis=1)
    out = {}
    for name, (b0, b1) in SECTIONS.items():
        a, b = int(b0 * BAR * sr), int(b1 * BAR * sr)
        seg = mono[a:min(b, len(mono))]
        out[name] = float(np.sqrt(np.mean(seg**2))) if len(seg) else 0.0
    return out


def main() -> None:
    files = sorted(MUSIC.glob("*.ogg"))
    if not files:
        raise SystemExit("tidak ada stem — jalankan tools/gen_music.py")

    problems: list[str] = []
    rows = []
    print("\nCHAIN RIDER — audit musik")
    print("=" * 84)
    print(f"{'stem':<16}{'durasi':>8}{'peak':>7}{'rms':>7}{'seam':>8}"
          f"{'grid err':>10}{'onset':>7}   struktur (rms per seksi)")
    print("-" * 84)

    for path in files:
        x, sr = sf.read(str(path), always_2d=True)
        dur = len(x) / sr
        peak = float(np.max(np.abs(x)))
        rms = float(np.sqrt(np.mean(x**2)))
        name = path.stem
        loops = name in LOOPING

        seam = seam_step(x, sr) if loops else 0.0
        gerr, onsets = onset_grid_error(x, sr, GRID.get(name, BEAT / 2.0))
        secs = section_rms(x, sr) if loops else {}

        if loops and abs(dur - 60.0) > 0.05:
            problems.append(f"{name}: durasi {dur:.2f}s, stem loop harus 60.00s")
        if rms < 0.01:
            problems.append(f"{name}: nyaris senyap (rms {rms:.4f})")
        if peak > 0.999:
            problems.append(f"{name}: clipping (peak {peak:.3f})")
        if loops and seam > 2.5:
            problems.append(
                f"{name}: sambungan loop melompat {seam:.1f}x gerak normal — akan berbunyi klik")
        if name in RHYTHMIC and onsets >= 8 and gerr > 0.012:
            problems.append(
                f"{name}: onset meleset {gerr * 1000:.0f} ms dari grid 120 BPM")
        if name in STRUCTURED:
            spread = max(secs.values()) - min(secs.values())
            if spread < 0.004:
                problems.append(
                    f"{name}: intro/A/B/A' hampir sama (spread rms {spread:.4f}) — "
                    "struktur tidak terdengar")

        struct = " ".join(f"{k}:{v:.3f}" for k, v in secs.items()) if secs else "-"
        print(f"{name:<16}{dur:>7.2f}s{peak:>7.2f}{rms:>7.3f}{seam:>8.1f}"
              f"{gerr * 1000:>9.1f}ms{onsets:>7}   {struct}")
        rows.append((name, x, sr))

    print("-" * 84)
    draw_sheet(rows)

    if problems:
        print(f"\n{len(problems)} MASALAH:")
        for p in problems:
            print(f"  - {p}")
        raise SystemExit(1)
    print("\nSemua stem lolos: 60 s tepat, loop mulus, onset di grid, struktur terdengar.\n")


def draw_sheet(rows) -> None:
    """Waveform envelope per stem, with section boundaries marked."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("(PIL tidak ada — lewati contact sheet)")
        return

    w, h = 1100, 90
    img = Image.new("RGB", (w, h * len(rows) + 30), (10, 16, 48))
    d = ImageDraw.Draw(img)
    d.text((10, 8), "CHAIN RIDER — struktur stem musik (docs/07 7.3)", fill=(245, 249, 255))

    for i, (name, x, sr) in enumerate(rows):
        top = 30 + i * h
        mid = top + h // 2
        mono = np.abs(x.mean(axis=1))
        dur = len(mono) / sr
        # Section dividers, only meaningful on the 60 s loops.
        if abs(dur - 60.0) < 0.1:
            for _, (b0, _b1) in SECTIONS.items():
                px = int((b0 * BAR / dur) * (w - 20)) + 10
                d.line([(px, top + 6), (px, top + h - 10)], fill=(31, 211, 232), width=1)
        step = max(1, len(mono) // (w - 20))
        for px in range(w - 20):
            seg = mono[px * step:(px + 1) * step]
            if len(seg) == 0:
                continue
            a = int(float(np.max(seg)) * (h / 2 - 14))
            d.line([(px + 10, mid - a), (px + 10, mid + a)], fill=(0, 229, 255))
        d.text((12, top + h - 14), f"{name}  {dur:.1f}s", fill=(138, 155, 184))

    out = ROOT / "screenshots" / "music-structure.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"structure sheet: {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
