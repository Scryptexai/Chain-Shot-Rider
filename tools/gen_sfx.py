#!/usr/bin/env python3
"""Synthesise every SFX cue in docs/07 into godot/audio/sfx/*.wav.

There are no audio assets in this repo and no licensed sound library reachable
from the sandbox, so the cues are built from oscillators and filtered noise
instead. That turns out to fit the project rather than fight it:

  * it is deterministic - a fixed seed means the committed WAVs are
    byte-reproducible, so a regenerated file diffs clean or not at all;
  * it is tiny - 35 mono 22 kHz clips land near half a megabyte against the
    12 MB budget in docs/07 section 7.6;
  * the cue sheet already describes each sound in synthesis terms ("sub-bass
    60 Hz + transient click 4 kHz"), so the spec maps onto code directly.

Pitch is NOT baked in. The bounce ladder in section 7.2 climbs fourteen
semitones, and shipping fourteen renders of the same ting would be wasteful and
would make the ladder impossible to retune. AudioDirector applies pitch_scale
at play time; the variations here only cover timbre.

Usage:  python3 tools/gen_sfx.py [--out godot/audio/sfx]
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import wave
import zlib
from pathlib import Path

SR = 22050  # docs/07 section 7.6: SFX are mono 22 kHz
ROOT = Path(__file__).resolve().parent.parent
SEED = 20260929  # same epoch as the sim's determinism seed

Signal = list[float]


# ---------------------------------------------------------------------------
# DSP PRIMITIVES
# ---------------------------------------------------------------------------
def silence(dur: float) -> Signal:
    return [0.0] * int(SR * dur)


def sine(sig: Signal, freq, amp=1.0, phase=0.0) -> Signal:
    """Add a sine. `freq` may be a constant or a callable of normalised time."""
    n = len(sig)
    ph = phase
    for i in range(n):
        f = freq(i / n) if callable(freq) else freq
        ph += 2.0 * math.pi * f / SR
        a = amp(i / n) if callable(amp) else amp
        sig[i] += math.sin(ph) * a
    return sig


def saw(sig: Signal, freq, amp=1.0) -> Signal:
    """Add a naive saw. Aliasing is audible as grit, which suits the growls."""
    n = len(sig)
    ph = 0.0
    for i in range(n):
        f = freq(i / n) if callable(freq) else freq
        ph = (ph + f / SR) % 1.0
        a = amp(i / n) if callable(amp) else amp
        sig[i] += (2.0 * ph - 1.0) * a
    return sig


def noise(sig: Signal, rng: random.Random, amp=1.0) -> Signal:
    n = len(sig)
    for i in range(n):
        a = amp(i / n) if callable(amp) else amp
        sig[i] += rng.uniform(-1.0, 1.0) * a
    return sig


def lowpass(sig: Signal, cutoff) -> Signal:
    """One-pole low-pass. `cutoff` may sweep, which is how the whooshes move."""
    out = [0.0] * len(sig)
    y = 0.0
    n = len(sig)
    for i in range(n):
        fc = cutoff(i / n) if callable(cutoff) else cutoff
        alpha = 1.0 - math.exp(-2.0 * math.pi * max(20.0, fc) / SR)
        y += alpha * (sig[i] - y)
        out[i] = y
    return out


def highpass(sig: Signal, cutoff: float) -> Signal:
    out = [0.0] * len(sig)
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
    y = 0.0
    for i, s in enumerate(sig):
        y += alpha * (s - y)
        out[i] = s - y  # original minus low band
    return out


def decay(power: float = 3.0, start: float = 0.0):
    """Exponential fade to zero - the shape almost every percussive cue needs."""
    def f(t: float) -> float:
        if t < start:
            return 0.0
        u = (t - start) / max(1e-6, 1.0 - start)
        return math.exp(-power * u)
    return f


def attack_decay(atk: float, power: float = 3.0):
    """Fast rise then exponential fall, so transients do not click on."""
    def f(t: float) -> float:
        if t < atk:
            return t / max(1e-6, atk)
        u = (t - atk) / max(1e-6, 1.0 - atk)
        return math.exp(-power * u)
    return f


def sweep(a: float, b: float, curve: float = 1.0):
    """Glide from a to b across the clip."""
    return lambda t: a + (b - a) * (t ** curve)


def mix(*sigs: Signal) -> Signal:
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i, v in enumerate(s):
            out[i] += v
    return out


def saturate(sig: Signal, drive: float = 1.0) -> Signal:
    return [math.tanh(s * drive) for s in sig]


def normalize(sig: Signal, peak: float = 0.9) -> Signal:
    hi = max((abs(s) for s in sig), default=0.0)
    if hi < 1e-9:
        return sig
    k = peak / hi
    return [s * k for s in sig]


def declick(sig: Signal, atk_ms: float = 0.5, rel_ms: float = 8.0) -> Signal:
    """Ramp the edges so clips do not tick on start or cut off hard.

    Attack and release are deliberately asymmetric. A symmetric 3 ms fade
    sounds harmless but destroys percussive cues: their peak sits inside the
    first millisecond, so the ramp mauls the transient - the audit measured
    ui_tap at 0.18 peak against a 0.60 target before this was split. Half a
    millisecond is enough to kill the discontinuity while leaving the attack
    intact; the tail can afford a longer fade.
    """
    n = len(sig)
    a = min(int(SR * atk_ms / 1000.0), n // 8)
    r = min(int(SR * rel_ms / 1000.0), n // 4)
    for i in range(a):
        sig[i] *= i / a
    for i in range(r):
        sig[-1 - i] *= i / r
    return sig


def write_wav(path: Path, sig: Signal) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for s in sig:
        v = int(max(-1.0, min(1.0, s)) * 32767)
        frames += struct.pack("<h", v)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    return path.stat().st_size


# ---------------------------------------------------------------------------
# CUES  (lengths and character come straight from docs/07 section 7.1)
# ---------------------------------------------------------------------------
def cue_shot(rng, v):
    """0.18 s - sub-bass 60 Hz thump plus a 4 kHz click transient."""
    sub = sine(silence(0.18), sweep(80 + v * 6, 48), attack_decay(0.005, 5.0))
    click = highpass(lowpass(noise(silence(0.18), rng, decay(16.0)),
                             sweep(9000, 3000)), 2200)
    body = sine(silence(0.18), sweep(420 + v * 30, 160), decay(14.0))
    return normalize(saturate(mix([s * 0.70 for s in sub],
                                  [c * 2.00 for c in click],
                                  [b * 0.30 for b in body]), 1.25), 0.92)


def cue_bounce(rng, v):
    """0.12 s - metallic ting. Runtime pitch_scale climbs the ladder."""
    base = 1200 + v * 140
    sig = silence(0.12)
    # Inharmonic partials are what make it read as metal rather than a bell.
    for mult, amp in ((1.0, 1.0), (2.76, 0.5), (5.40, 0.28), (8.93, 0.14)):
        sine(sig, base * mult, lambda t, a=amp: a * math.exp(-11.0 * t))
    return normalize(declick(sig), 0.85)


def cue_kill(rng, v):
    """0.08 s - small dry pop with a little noise."""
    pop = sine(silence(0.08), sweep(300 + v * 25, 90), attack_decay(0.004, 9.0))
    air = highpass(noise(silence(0.08), rng, decay(40.0)), 2200)
    return normalize(mix(pop, [a * 0.3 for a in air]), 0.72)


def cue_combo(rng, tier):
    """0.60 s - rising three-note major arpeggio, one tier up per milestone."""
    root = 523.25 * (2 ** (tier / 12.0))  # C5 transposed per tier
    sig = silence(0.60)
    for i, semi in enumerate((0, 4, 7)):  # major triad
        f = root * (2 ** (semi / 12.0))
        start = i * 0.11
        voice = silence(0.60)
        sine(voice, f, lambda t, s=start: (0.0 if t < s / 0.60 else
                                           0.55 * math.exp(-5.0 * (t - s / 0.60))))
        sine(voice, f * 2.0, lambda t, s=start: (0.0 if t < s / 0.60 else
                                                 0.18 * math.exp(-7.0 * (t - s / 0.60))))
        sig = mix(sig, voice)
    return normalize(declick(sig), 0.88)


def cue_explosion(rng, v):
    """0.90 s - heavy boom, sub 40 Hz plus debris tail."""
    sub = sine(silence(0.90), sweep(70 + v * 5, 34, 0.5), attack_decay(0.01, 4.0))
    body = lowpass(noise(silence(0.90), rng, decay(5.0)), sweep(1800, 180, 0.6))
    debris = highpass(noise(silence(0.90), rng, decay(2.2, 0.12)), 1800)
    crack = highpass(noise(silence(0.90), rng, decay(55.0)), 2600)
    return normalize(saturate(mix(sub, [b * 0.8 for b in body],
                                  [d * 0.22 for d in debris],
                                  [c * 1.25 for c in crack]), 1.4), 1.0)


def cue_chainspark(rng, v):
    """0.15 s - short sizzle; depth adds pitch at runtime."""
    s = highpass(noise(silence(0.15), rng, decay(18.0)), 3000 + v * 800)
    tone = sine(silence(0.15), sweep(2400, 4200), decay(16.0))
    return normalize(mix([x * 0.8 for x in s], [t * 0.25 for t in tone]), 0.6)


def cue_slowmo_enter(rng, _):
    """0.40 s - descending whoosh with a closing filter."""
    air = lowpass(noise(silence(0.40), rng, attack_decay(0.05, 2.0)),
                  sweep(5000, 400, 0.7))
    drop = sine(silence(0.40), sweep(320, 70, 0.8), decay(2.5))
    return normalize(mix([a * 0.7 for a in air], [d * 0.6 for d in drop]), 0.85)


def cue_slowmo_exit(rng, _):
    """0.25 s - rising whoosh and a snap on the way out."""
    air = lowpass(noise(silence(0.25), rng, sweep(0.2, 1.0, 2.0)),
                  sweep(600, 7000, 1.6))
    snap = highpass(noise(silence(0.25), rng, decay(70.0, 0.75)), 3000)
    rise = sine(silence(0.25), sweep(180, 700, 1.5), sweep(0.25, 0.6))
    return normalize(mix([a * 0.5 for a in air], [s * 0.7 for s in snap],
                         [r * 0.4 for r in rise]), 0.78)


def cue_heartbeat(rng, _):
    """0.70 s - double thump, the classic lub-dub spacing."""
    sig = silence(0.70)
    for start, amp in ((0.00, 1.0), (0.22, 0.75)):
        beat = silence(0.70)
        sine(beat, sweep(90, 45),
             lambda t, s=start / 0.70, a=amp:
             (0.0 if t < s else a * math.exp(-26.0 * (t - s))))
        sig = mix(sig, beat)
    return normalize(lowpass(sig, 260), 0.8)


def cue_breach(rng, v):
    """0.50 s - low alarm over a dull impact. The fail sound; it must land."""
    alarm = sine(silence(0.50), sweep(420 - v * 30, 300), sweep(0.5, 0.15, 0.5))
    thud = sine(silence(0.50), sweep(120, 42), attack_decay(0.008, 5.0))
    grit = lowpass(noise(silence(0.50), rng, decay(9.0)), 700)
    knock = highpass(noise(silence(0.50), rng, decay(80.0)), 2400)
    return normalize(saturate(mix([a * 0.45 for a in alarm], thud,
                                  [g * 0.3 for g in grit],
                                  [k * 0.66 for k in knock]), 1.3), 0.97)


def cue_perfect_clear(rng, _):
    """1.20 s - bright rising chord plus shimmer."""
    sig = silence(1.20)
    for i, semi in enumerate((0, 4, 7, 12)):
        f = 523.25 * (2 ** (semi / 12.0))
        start = i * 0.08
        v = silence(1.20)
        sine(v, f, lambda t, s=start / 1.20:
             (0.0 if t < s else 0.42 * math.exp(-2.6 * (t - s))))
        sig = mix(sig, v)
    shimmer = highpass(noise(silence(1.20), rng, decay(3.0)), 6000)
    return normalize(mix(sig, [s * 0.12 for s in shimmer]), 0.86)


def cue_kill_milestone(rng, v):
    """0.90 s - short fanfare with a rustle underneath."""
    sig = silence(0.90)
    for i, semi in enumerate((0, 7, 12)):
        f = 392.00 * (2 ** ((semi + v * 2) / 12.0))
        start = i * 0.09
        voice = silence(0.90)
        saw(voice, f, lambda t, s=start / 0.90:
            (0.0 if t < s else 0.30 * math.exp(-4.0 * (t - s))))
        sig = mix(sig, voice)
    sig = lowpass(sig, 3200)
    rustle = highpass(noise(silence(0.90), rng, decay(3.5, 0.15)), 4000)
    return normalize(mix(sig, [r * 0.14 for r in rustle]), 0.86)


def cue_bullet_expire(rng, v):
    """0.30 s - descending fizz with a short tail."""
    fizz = highpass(noise(silence(0.30), rng, decay(7.0)), 2500)
    fall = sine(silence(0.30), sweep(900 - v * 100, 180, 1.3), decay(6.0))
    return normalize(mix([f * 0.5 for f in fizz], [f * 0.5 for f in fall]), 0.55)


def cue_steer_warn(rng, _):
    """0.10 s - thin repeating beep."""
    sig = sine(silence(0.10), 1760, attack_decay(0.01, 6.0))
    return normalize(declick(sig), 0.45)


def cue_ui_tap(rng, v):
    """0.06 s - dry click."""
    click = highpass(noise(silence(0.06), rng, decay(55.0)), 1800)
    body = sine(silence(0.06), 900 + v * 200, attack_decay(0.003, 20.0))
    return normalize(mix([c * 0.6 for c in click], [b * 0.5 for b in body]), 0.6)


def cue_boss_roar(rng, _):
    """2.00 s - low growl under a riser. The only cue over one second."""
    growl = silence(2.00)
    saw(growl, lambda t: 55.0 * (1.0 + 0.06 * math.sin(t * 34.0)), sweep(0.5, 0.75))
    saw(growl, lambda t: 82.5 * (1.0 + 0.05 * math.sin(t * 21.0)), sweep(0.3, 0.45))
    growl = lowpass(growl, sweep(300, 1400, 0.8))
    riser = lowpass(noise(silence(2.00), rng, sweep(0.05, 0.9, 2.2)),
                    sweep(400, 6000, 2.0))
    boom = sine(silence(2.00), sweep(120, 38), attack_decay(0.01, 3.0))
    return normalize(saturate(mix(growl, [r * 0.35 for r in riser],
                                  [b * 0.7 for b in boom]), 1.5), 1.0)


# name -> (builder, variation count)
CUES = {
    "shot": (cue_shot, 3),
    "bounce": (cue_bounce, 4),
    "kill": (cue_kill, 5),
    "combo_milestone": (cue_combo, 4),
    "explosion": (cue_explosion, 3),
    "chain_spark": (cue_chainspark, 2),
    "slowmo_enter": (cue_slowmo_enter, 1),
    "slowmo_exit": (cue_slowmo_exit, 1),
    "heartbeat": (cue_heartbeat, 1),
    "breach": (cue_breach, 2),
    "perfect_clear": (cue_perfect_clear, 1),
    "kill_milestone": (cue_kill_milestone, 3),
    "bullet_expire": (cue_bullet_expire, 2),
    "steer_warn": (cue_steer_warn, 1),
    "ui_tap": (cue_ui_tap, 2),
    "boss_roar": (cue_boss_roar, 1),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="godot/audio/sfx")
    args = ap.parse_args()
    out = (ROOT / args.out).resolve()

    total = 0
    count = 0
    print("\nCHAIN RIDER - sintesis SFX (docs/07)")
    for name, (fn, variants) in CUES.items():
        for v in range(variants):
            # zlib.crc32, not hash(): Python randomises str hashing per
            # process, so hash(name) silently reseeded every run and the
            # "byte-reproducible" claim above was false. Cue measurements
            # drifted between runs until this was caught.
            rng = random.Random(SEED + zlib.crc32(name.encode()) + v * 977)
            sig = declick(fn(rng, v))
            path = out / f"{name}_{v + 1}.wav"
            total += write_wav(path, sig)
            count += 1
        print(f"  {name:<18} {variants} varian  {len(sig) / SR:.2f}s")
    print(f"\n  {count} file, {total / 1024:.0f} KB total "
          f"(budget docs/07 7.6: < 12 MB)\n")


if __name__ == "__main__":
    main()
