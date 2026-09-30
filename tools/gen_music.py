#!/usr/bin/env python3
"""Compose the music stems described in docs/07 section 7.3.

Output: godot/audio/music/*.ogg - Ogg Vorbis, stereo, 44.1 kHz, loopable.

WHY THESE ARE SYNTHESISED
No licensed music is reachable from the sandbox, and there is no encoder on
the box either - no ffmpeg, no oggenc, no sox. The Vorbis encoder here comes
from the libsndfile bundled inside the `soundfile` wheel, which is the only
route to the compressed streaming format section 7.6 asks for. Uncompressed
stems would not fit: 60 s of stereo 44.1 kHz PCM is 10 MB per layer against a
12 MB budget for all audio.

A NOTE ON THE SPEC
Section 7.3 states a 60 s loop AND a structure of 8 + 16 + 16 + 16 bars with
the loop point at the end of bar 56. At 120 BPM in 4/4 a bar is 2 s, so 56
bars is 112 s. The two figures cannot both hold.

This resolves in favour of 60 s, because that is the number the rest of the
project leans on - the audio budget in 7.6, and the 1-3 minute session length,
which a 112 s loop would barely cover once. The section proportions are kept
by halving them: 6 intro / 8 A / 8 B / 8 A' = 30 bars = exactly 60 s.

Every stem is the same length and starts on the same sample, so they can be
started together and layered without drift - which is what the dynamic mixing
in 7.3 needs.

Usage:  python3 tools/gen_music.py
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100
BPM = 120.0
BEAT = 60.0 / BPM          # 0.5 s
BAR = BEAT * 4             # 2.0 s
BARS = 30                  # 60 s exactly
TOTAL = BAR * BARS
N = int(SR * TOTAL)

ROOT = Path(__file__).resolve().parent.parent
RNG = np.random.default_rng(20260929)

# Section boundaries in bars: intro, A, B, A-prime.
SECTIONS = {"intro": (0, 6), "a": (6, 14), "b": (14, 22), "aprime": (22, 30)}

# A minor, i - VI - III - VII. Two bars per chord, so the cycle spans 8 bars
# and lines up with every section boundary above.
PROGRESSION = ["Am", "F", "C", "G"]
PROGRESSION_B = ["F", "C", "G", "Am"]
CHORDS = {
    "Am": [57, 60, 64],   # A3 C4 E4
    "F": [53, 57, 60],    # F3 A3 C4
    "C": [48, 52, 55],    # C3 E3 G3
    "G": [55, 59, 62],    # G3 B3 D4
}
BASS = {"Am": 33, "F": 29, "C": 36, "G": 31}  # A1 F1 C2 G1


def midi(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def t_axis(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def section_of(bar: int) -> str:
    for name, (b0, b1) in SECTIONS.items():
        if b0 <= bar < b1:
            return name
    return "aprime"


def chord_at(bar: int) -> str:
    # B lifts off by starting the same cycle on its relative major, which is
    # what makes the middle section feel like it has gone somewhere without
    # introducing chords the other layers do not know about.
    prog = PROGRESSION_B if section_of(bar) == "b" else PROGRESSION
    return prog[(bar // 2) % len(prog)]


def adsr(n: int, atk: float, dec: float, sus: float, rel: float) -> np.ndarray:
    """Envelope in samples. Kept simple; the character comes from the filters."""
    a, d, r = int(SR * atk), int(SR * dec), int(SR * rel)
    a, d = min(a, n), min(d, max(0, n - 1))
    r = min(r, max(0, n - a - d))
    env = np.full(n, sus, dtype=np.float64)
    if a:
        env[:a] = np.linspace(0.0, 1.0, a)
    if d:
        env[a:a + d] = np.linspace(1.0, sus, d)
    if r:
        env[n - r:] = np.linspace(sus, 0.0, r)
    return env


def saw(freq: float, n: int, detune: float = 0.0) -> np.ndarray:
    t = t_axis(n)
    out = 2.0 * ((t * freq) % 1.0) - 1.0
    if detune:
        out += 2.0 * ((t * freq * (1.0 + detune)) % 1.0) - 1.0
        out *= 0.5
    return out


def square(freq: float, n: int, duty: float = 0.5) -> np.ndarray:
    return np.where(((t_axis(n) * freq) % 1.0) < duty, 1.0, -1.0)


def lowpass(x: np.ndarray, cutoff: np.ndarray | float) -> np.ndarray:
    """One-pole low-pass that accepts a per-sample cutoff for filter sweeps."""
    fc = np.full(len(x), cutoff, dtype=np.float64) if np.isscalar(cutoff) else cutoff
    alpha = 1.0 - np.exp(-2.0 * np.pi * np.clip(fc, 20.0, SR / 2.2) / SR)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y += alpha[i] * (x[i] - y)
        out[i] = y
    return out


def place(dst: np.ndarray, src: np.ndarray, at: float) -> None:
    """Mix `src` into `dst` at time `at`, wrapping past the end.

    Wrapping is what makes the loop seamless: a tom tail that starts in the
    last bar has to continue into the first, exactly as it would on the second
    pass through the loop. Truncating it instead leaves a step at the seam -
    measured at 32x the stem's normal sample-to-sample movement, which is an
    audible click every 60 seconds.
    """
    i = int(SR * at) % len(dst)
    k = len(src)
    end = i + k
    if end <= len(dst):
        dst[i:end] += src
    else:
        head = len(dst) - i
        dst[i:] += src[:head]
        dst[:k - head] += src[head:]


def noise(n: int) -> np.ndarray:
    return RNG.uniform(-1.0, 1.0, n)


# ---------------------------------------------------------------------------
# STEMS
# ---------------------------------------------------------------------------
def stem_base() -> np.ndarray:
    """base_synth - bass plus chord stabs. Plays under every variant."""
    out = np.zeros(N)
    for bar in range(BARS):
        ch = chord_at(bar)
        sec = section_of(bar)
        # The intro states the bass on half notes only, so that section A
        # arriving with every beat filled actually registers as an arrival.
        beats = (0, 2) if sec == "intro" else (0, 1, 2, 3)
        for beat in beats:
            at = bar * BAR + beat * BEAT
            dur = BEAT * (0.9 if beat % 2 == 0 else 0.45)
            n = int(SR * dur)
            f = midi(BASS[ch]) * (2.0 if beat == 3 and bar % 4 == 3 else 1.0)
            v = saw(f, n, 0.004) * adsr(n, 0.004, 0.06, 0.55, 0.08)
            v = lowpass(v, 220.0 + 120.0 * np.linspace(1.0, 0.3, n))
            place(out, v * 0.55, at)
        # Chord stabs land on 2 and 4 from section A onward; the intro leaves
        # them out so the arrangement has somewhere to go.
        if sec != "intro":
            # B pushes the stabs onto every beat and opens the filter; A'
            # keeps A's placement but doubles an octave up, so the reprise is
            # recognisably A without being a copy of it.
            stab_beats = (0, 1, 2, 3) if sec == "b" else (1, 3)
            cutoff = 3200.0 if sec == "b" else 1800.0
            for beat in stab_beats:
                at = bar * BAR + beat * BEAT
                n = int(SR * BEAT * 0.8)
                acc = np.zeros(n)
                for note in CHORDS[ch]:
                    acc += saw(midi(note), n, 0.006)
                    if sec == "aprime":
                        acc += saw(midi(note + 12), n, 0.006) * 0.45
                acc *= adsr(n, 0.006, 0.10, 0.35, 0.18) / len(CHORDS[ch])
                acc = lowpass(acc, cutoff)
                place(out, acc * (0.34 if sec == "b" else 0.30), at)
    return out


def stem_arp() -> np.ndarray:
    """arp - 16th-note arpeggio. Twin Towers: tense, narrow."""
    out = np.zeros(N)
    step = BEAT / 4.0
    for bar in range(BARS):
        ch = chord_at(bar)
        sec = section_of(bar)
        notes = CHORDS[ch] + [CHORDS[ch][1] + 12]
        if sec == "b":
            notes = list(reversed(notes))
        for s in range(16):
            if sec == "intro" and s % 2:
                continue  # half density under the intro
            at = bar * BAR + s * step
            n = int(SR * step * 0.9)
            f = midi(notes[s % len(notes)] + (12 if (s // 4) % 2 else 0))
            v = square(f, n, 0.35) * adsr(n, 0.002, 0.03, 0.25, 0.04)
            v = lowpass(v, 2600.0)
            place(out, v * (0.26 if sec == "b" else 0.22), at)
    return out


def stem_pad() -> np.ndarray:
    """pad - long sustained chords. Gravity Chamber: floating, cold."""
    out = np.zeros(N)
    for bar in range(0, BARS, 2):
        ch = chord_at(bar)
        n = int(SR * BAR * 2.0)
        acc = np.zeros(n)
        for note in CHORDS[ch]:
            acc += saw(midi(note + 12), n, 0.012)
            acc += saw(midi(note), n, 0.008) * 0.6
        acc *= adsr(n, 0.55, 0.4, 0.75, 0.9) / (len(CHORDS[ch]) * 1.6)
        # Slow filter breathing keeps a static chord from sounding dead.
        lift = 1.6 if section_of(bar) == "b" else 1.0
        sweep = (700.0 + 500.0 * np.sin(np.linspace(0, np.pi, n))) * lift
        acc = lowpass(acc, sweep)
        place(out, acc * 0.5, bar * BAR)
    return out


def stem_percussion() -> np.ndarray:
    """percussion - toms and industrial hits. Explosive Yard: hot, aggressive."""
    out = np.zeros(N)
    for bar in range(BARS):
        for beat in range(4):
            at = bar * BAR + beat * BEAT
            # The intro keeps one kick a bar. Dropping only the snare and hat
            # barely moved the stem's energy - the kick carries it - so the
            # intro has to lose kicks too before it reads as an intro.
            kick_beats = (0,) if section_of(bar) == "intro" else (0, 2)
            if beat in kick_beats:
                n = int(SR * 0.22)
                f = 110.0 * np.exp(-np.linspace(0, 3.2, n))
                k = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-np.linspace(0, 7, n))
                place(out, k * 0.85, at)
            if beat in (1, 3) and section_of(bar) != "intro":
                n = int(SR * 0.18)
                s = noise(n) * np.exp(-np.linspace(0, 11, n)) * 0.5
                s += np.sin(2 * np.pi * 190 * t_axis(n)) * np.exp(-np.linspace(0, 9, n)) * 0.4
                place(out, lowpass(s, 4200.0) * 0.6, at)
            # Offbeat hat, held back in the intro so the section lands.
            if section_of(bar) != "intro":
                n = int(SR * 0.05)
                h = noise(n) * np.exp(-np.linspace(0, 16, n))
                place(out, h * 0.18, at + BEAT * 0.5)
    return out


def stem_glitch() -> np.ndarray:
    """glitch - stutter and bitcrush. Moving Maze: restless, rhythmic."""
    out = np.zeros(N)
    step = BEAT / 2.0
    for bar in range(BARS):
        ch = chord_at(bar)
        sec = section_of(bar)
        for s in range(8):
            if RNG.random() < (0.75 if sec == "intro" else 0.45):
                continue
            at = bar * BAR + s * step
            n = int(SR * step * 0.8)
            f = midi(CHORDS[ch][s % 3] + 12)
            v = square(f, n, 0.5) * adsr(n, 0.001, 0.02, 0.4, 0.02)
            # Bitcrush: quantise hard, then stutter by repeating a short slice.
            v = np.round(v * 5.0) / 5.0
            slice_n = max(1, n // 4)
            v = np.tile(v[:slice_n], int(np.ceil(n / slice_n)))[:n]
            # Hard square plus bitcrush aliases badly, and Vorbis overshoots
            # on decode: this stem measured peak 1.26 after encoding despite
            # being normalised to 0.82. Rolling off the top tames both.
            v = lowpass(v, 5200.0)
            place(out, v * 0.22, at)
    return out


def stem_drums_fill() -> np.ndarray:
    """Extra drum layer for the boss wave, per the dynamic music table."""
    out = np.zeros(N)
    for bar in range(BARS):
        for s in range(8):
            at = bar * BAR + s * (BEAT / 2.0)
            n = int(SR * 0.09)
            h = noise(n) * np.exp(-np.linspace(0, 13, n))
            place(out, lowpass(h, 7000.0) * 0.22, at)
        if bar % 4 == 3:  # fill across the last bar of every phrase
            for s in range(8):
                at = bar * BAR + s * (BEAT / 2.0)
                n = int(SR * 0.12)
                tom = np.sin(2 * np.pi * (240 - s * 14) * t_axis(n))
                tom *= np.exp(-np.linspace(0, 8, n))
                place(out, tom * 0.5, at)
    return out


def stinger(win: bool) -> np.ndarray:
    """Short end-of-run sting. docs/07 7.3: run ends fade 1.5 s then sting."""
    dur = 1.6
    n = int(SR * dur)
    out = np.zeros(n)
    notes = [57, 61, 64, 69] if win else [57, 56, 53, 48]
    for i, note in enumerate(notes):
        at = i * 0.1
        m = int(SR * (dur - at))
        v = saw(midi(note), m, 0.01) * adsr(m, 0.01, 0.3, 0.35, 0.8)
        place(out, lowpass(v, 2600.0 if win else 1100.0) * 0.32, at)
    return out


STEMS = {
    "base_synth": stem_base,
    "arp": stem_arp,
    "pad": stem_pad,
    "percussion": stem_percussion,
    "glitch": stem_glitch,
    "drums_fill": stem_drums_fill,
}


# libsndfile segfaults when handed a whole 60 s stereo buffer for Vorbis
# encoding in one call - reproducible with a plain sine and no project code:
# 1 s and 10 s write fine, 60 s dies. Feeding it in blocks avoids the bad path
# entirely, so every write goes through here.
WRITE_CHUNK = SR * 5


def write_ogg(path: Path, data: np.ndarray) -> int:
    with sf.SoundFile(str(path), "w", samplerate=SR, channels=data.shape[1],
                      format="OGG", subtype="VORBIS") as handle:
        for i in range(0, len(data), WRITE_CHUNK):
            handle.write(data[i:i + WRITE_CHUNK])
    info = sf.info(str(path))
    expected = len(data) / SR
    if abs(info.duration - expected) > 0.05 or info.channels != data.shape[1]:
        raise RuntimeError(
            f"{path.name}: tertulis {info.duration:.2f}s/{info.channels}ch, "
            f"diharapkan {expected:.2f}s/{data.shape[1]}ch"
        )
    return path.stat().st_size


def stereo(mono: np.ndarray, width: float = 0.25) -> np.ndarray:
    """Cheap width: delay one side by a few ms. Mono-safe enough for phones."""
    d = int(SR * 0.008 * width)
    left = mono
    right = np.concatenate([np.zeros(d), mono[:-d]]) if d else mono
    return np.stack([left, right], axis=1)


def normalize(x: np.ndarray, peak: float) -> np.ndarray:
    hi = float(np.max(np.abs(x)))
    return x * (peak / hi) if hi > 1e-9 else x


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="godot/audio/music")
    args = ap.parse_args()
    out_dir = (ROOT / args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"\nCHAIN RIDER - sintesis musik (docs/07 7.3)")
    print(f"  {BPM:.0f} BPM, A minor, {BARS} bar = {TOTAL:.0f} s, loop mulus")
    total_bytes = 0
    for name, fn in STEMS.items():
        mono = normalize(np.tanh(fn() * 1.2), 0.72)
        data = stereo(mono)
        path = out_dir / f"{name}.ogg"
        size = write_ogg(path, data.astype("float32"))
        total_bytes += size
        print(f"  {name:<14} {TOTAL:5.1f}s  {size / 1024:6.0f} KB")

    for win, label in ((True, "stinger_victory"), (False, "stinger_defeat")):
        data = stereo(normalize(stinger(win), 0.8))
        path = out_dir / f"{label}.ogg"
        size = write_ogg(path, data.astype("float32"))
        total_bytes += size
        print(f"  {label:<14}   1.6s  {size / 1024:6.0f} KB")

    print(f"\n  total musik {total_bytes / 1024 / 1024:.2f} MB "
          f"(budget docs/07 7.6: < 12 MB untuk SELURUH audio)\n")


if __name__ == "__main__":
    main()
