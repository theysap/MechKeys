#!/usr/bin/env python3
"""
MechKeys sample generator.

Synthesises the entire bundled sound library from scratch. Nothing here is
sampled, recorded or downloaded: every waveform is generated from a physical
sketch of what a mechanical keyswitch actually does when you press it, so the
resulting assets are original work with no licensing encumbrance.

The model has four voices, mixed per profile:

  1. click      - the tactile/clicky jacket snapping. A high-Q resonant noise
                  burst with a near-instant attack and a short decay.
  2. tick       - keycap/stem contact. A mid-frequency burst, softer than the
                  click, that gives the sound its "texture".
  3. bottom-out - the stem slamming into the housing a few ms later. Broadband
                  thump, this is the body of the sound.
  4. modes      - plate and case resonance. Exponentially damped sinusoids at
                  slightly inharmonic frequencies; this is the "thock" tail.

Usage:
    python3 Tools/generate_sounds.py [--out Resources/Sounds] [--variants 5]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import wave
from dataclasses import dataclass, field, replace
from pathlib import Path

import numpy as np

SAMPLE_RATE = 48_000
BIT_DEPTH = 16


# --------------------------------------------------------------------------
# Synthesis primitives
# --------------------------------------------------------------------------


def _envelope(n: int, attack_ms: float, decay_ms: float, curve: float = 1.0) -> np.ndarray:
    """Percussive envelope: fast exponential rise, exponential fall."""
    t = np.arange(n) / SAMPLE_RATE
    attack = max(attack_ms, 0.01) / 1000.0
    decay = max(decay_ms, 0.5) / 1000.0
    rise = 1.0 - np.exp(-t / attack)
    fall = np.exp(-t / decay)
    env = rise * fall
    if curve != 1.0:
        env = env ** curve
    peak = env.max()
    return env / peak if peak > 0 else env


def _spectral_noise(
    rng: np.random.Generator,
    n: int,
    center_hz: float,
    bandwidth_oct: float,
    tilt_db_per_oct: float = 0.0,
) -> np.ndarray:
    """
    White noise shaped in the frequency domain.

    Cheaper and smoother than cascading biquads, and it lets each burst have a
    precisely controlled resonance without filter ringing artefacts at the very
    start of the buffer (which would smear the transient we care about).
    """
    noise = rng.standard_normal(n)
    spectrum = np.fft.rfft(noise)
    freqs = np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE)
    freqs = np.maximum(freqs, 1.0)

    # Log-gaussian band centred on `center_hz`.
    octaves = np.log2(freqs / center_hz)
    shape = np.exp(-0.5 * (octaves / max(bandwidth_oct, 0.05)) ** 2)

    if tilt_db_per_oct:
        tilt = 10.0 ** ((octaves * tilt_db_per_oct) / 20.0)
        shape = shape * tilt

    out = np.fft.irfft(spectrum * shape, n)
    peak = np.abs(out).max()
    return out / peak if peak > 0 else out


def _damped_modes(
    rng: np.random.Generator,
    n: int,
    fundamental: float,
    ratios: list[float],
    decay_ms: float,
    decay_spread: float = 0.55,
) -> np.ndarray:
    """Sum of exponentially damped sinusoids: the case/plate resonance tail."""
    t = np.arange(n) / SAMPLE_RATE
    out = np.zeros(n)
    for index, ratio in enumerate(ratios):
        freq = fundamental * ratio * rng.uniform(0.985, 1.015)
        if freq >= SAMPLE_RATE * 0.45:
            continue
        # Higher modes die away faster, as they do in a real case.
        mode_decay = (decay_ms / 1000.0) * (decay_spread ** index)
        amp = 1.0 / (1.0 + index * 1.35)
        phase = rng.uniform(0, 2 * math.pi)
        out += amp * np.sin(2 * math.pi * freq * t + phase) * np.exp(-t / mode_decay)
    peak = np.abs(out).max()
    return out / peak if peak > 0 else out


def _delay(signal: np.ndarray, ms: float, length: int) -> np.ndarray:
    """Place `signal` into a buffer of `length` samples, offset by `ms`."""
    out = np.zeros(length)
    offset = int(round((ms / 1000.0) * SAMPLE_RATE))
    if offset >= length:
        return out
    usable = min(len(signal), length - offset)
    out[offset:offset + usable] = signal[:usable]
    return out


# --------------------------------------------------------------------------
# Profile definitions
#
# One place, one table. Nothing profile-specific is hard-coded anywhere else in
# this file or in the app.
# --------------------------------------------------------------------------


@dataclass
class Voice:
    level: float
    center_hz: float
    bandwidth_oct: float
    attack_ms: float
    decay_ms: float
    delay_ms: float = 0.0
    tilt_db_per_oct: float = 0.0


@dataclass
class Profile:
    name: str
    description: str
    click: Voice
    tick: Voice
    bottom: Voice
    body_hz: float
    body_level: float
    body_decay_ms: float
    body_ratios: list[float] = field(default_factory=lambda: [1.0, 1.61, 2.47, 3.72, 5.1])
    # Perceived loudness of this switch relative to the others. Blues really
    # are louder than reds; the library should preserve that.
    loudness: float = 0.72
    # Extra high-shelf emphasis applied to the finished sample.
    brightness: float = 0.5


PROFILES: list[Profile] = [
    Profile(
        name="red",
        description="Linear, smooth, relatively quiet. Rounded bottom-out, soft transient.",
        click=Voice(level=0.10, center_hz=3600, bandwidth_oct=1.20, attack_ms=0.30, decay_ms=5.0),
        tick=Voice(level=0.30, center_hz=1900, bandwidth_oct=1.35, attack_ms=0.45, decay_ms=11.0, delay_ms=0.4),
        bottom=Voice(level=0.95, center_hz=700, bandwidth_oct=1.85, attack_ms=0.60, decay_ms=26.0, delay_ms=3.4,
                     tilt_db_per_oct=-2.0),
        body_hz=205,
        body_level=0.52,
        body_decay_ms=44,
        loudness=0.62,
        brightness=0.48,
    ),
    Profile(
        name="brown",
        description="Tactile, moderate attack, more textured than Red. No exaggerated click.",
        click=Voice(level=0.26, center_hz=4200, bandwidth_oct=1.05, attack_ms=0.18, decay_ms=6.5),
        tick=Voice(level=0.48, center_hz=2600, bandwidth_oct=1.15, attack_ms=0.30, decay_ms=13.0, delay_ms=0.5),
        bottom=Voice(level=0.92, center_hz=760, bandwidth_oct=1.80, attack_ms=0.55, decay_ms=28.0, delay_ms=3.6,
                     tilt_db_per_oct=-1.6),
        body_hz=198,
        body_level=0.56,
        body_decay_ms=48,
        loudness=0.70,
        brightness=0.60,
    ),
    Profile(
        name="blue",
        description="Tactile and clearly clicky. Sharp transient, strong high-frequency attack.",
        click=Voice(level=1.00, center_hz=5400, bandwidth_oct=0.62, attack_ms=0.08, decay_ms=8.5),
        tick=Voice(level=0.55, center_hz=3100, bandwidth_oct=0.95, attack_ms=0.16, decay_ms=15.0, delay_ms=0.3),
        bottom=Voice(level=0.86, center_hz=820, bandwidth_oct=1.70, attack_ms=0.45, decay_ms=30.0, delay_ms=3.9,
                     tilt_db_per_oct=-1.1),
        body_hz=232,
        body_level=0.60,
        body_decay_ms=56,
        loudness=0.92,
        brightness=0.92,
    ),
    Profile(
        name="black",
        description="Heavy linear. Deeper body, substantial bottom-out, less sharpness.",
        click=Voice(level=0.07, center_hz=3100, bandwidth_oct=1.35, attack_ms=0.40, decay_ms=4.5),
        tick=Voice(level=0.24, center_hz=1500, bandwidth_oct=1.45, attack_ms=0.55, decay_ms=10.0, delay_ms=0.5),
        bottom=Voice(level=1.00, center_hz=520, bandwidth_oct=1.95, attack_ms=0.75, decay_ms=38.0, delay_ms=4.2,
                     tilt_db_per_oct=-3.0),
        body_hz=148,
        body_level=0.74,
        body_decay_ms=72,
        loudness=0.78,
        brightness=0.32,
    ),
    Profile(
        name="yellow",
        description="Smooth linear, between Red and Black in weight. Clean, even attack.",
        click=Voice(level=0.11, center_hz=3350, bandwidth_oct=1.25, attack_ms=0.34, decay_ms=5.2),
        tick=Voice(level=0.33, center_hz=1750, bandwidth_oct=1.35, attack_ms=0.48, decay_ms=12.0, delay_ms=0.45),
        bottom=Voice(level=0.97, center_hz=620, bandwidth_oct=1.88, attack_ms=0.65, decay_ms=32.0, delay_ms=3.8,
                     tilt_db_per_oct=-2.4),
        body_hz=172,
        body_level=0.64,
        body_decay_ms=58,
        loudness=0.70,
        brightness=0.41,
    ),
]


# --------------------------------------------------------------------------
# Key categories
#
# Bigger keys are pitched down, hit harder, and (if stabilised) rattle.
# --------------------------------------------------------------------------


@dataclass
class Category:
    name: str
    pitch: float          # multiplies every frequency in the model
    level: float          # relative loudness
    stabilizer: float     # amount of stabiliser rattle, 0 = none
    body_decay: float = 1.0
    duration_ms: float = 170.0


CATEGORIES: list[Category] = [
    Category("standard", pitch=1.00, level=1.00, stabilizer=0.00),
    Category("space", pitch=0.70, level=1.14, stabilizer=0.85, body_decay=1.30, duration_ms=210.0),
    Category("enter", pitch=0.80, level=1.09, stabilizer=0.55, body_decay=1.18, duration_ms=195.0),
    Category("backspace", pitch=0.89, level=1.03, stabilizer=0.28, body_decay=1.08),
    Category("tab", pitch=0.93, level=0.99, stabilizer=0.18),
    Category("modifier", pitch=0.86, level=0.88, stabilizer=0.34, body_decay=1.05, duration_ms=180.0),
]


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def _render_voice(rng: np.random.Generator, voice: Voice, n: int, pitch: float, jitter: float) -> np.ndarray:
    if voice.level <= 0.0:
        return np.zeros(n)
    decay = voice.decay_ms * rng.uniform(1 - jitter, 1 + jitter)
    center = voice.center_hz * pitch * rng.uniform(1 - jitter * 0.5, 1 + jitter * 0.5)
    tail = max(n - int(voice.delay_ms / 1000.0 * SAMPLE_RATE), 1)
    burst = _spectral_noise(rng, tail, center, voice.bandwidth_oct, voice.tilt_db_per_oct)
    burst *= _envelope(tail, voice.attack_ms, decay)
    level = voice.level * rng.uniform(1 - jitter, 1 + jitter)
    return _delay(burst * level, voice.delay_ms * rng.uniform(0.9, 1.1), n)


def _apply_brightness(signal: np.ndarray, brightness: float) -> np.ndarray:
    """Gentle spectral tilt above 2 kHz. brightness 0.5 is neutral."""
    spectrum = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1.0 / SAMPLE_RATE)
    octaves = np.log2(np.maximum(freqs, 1.0) / 2000.0)
    gain_db = np.clip(octaves, 0.0, 3.2) * ((brightness - 0.5) * 7.0)
    return np.fft.irfft(spectrum * (10.0 ** (gain_db / 20.0)), len(signal))


def render_sample(profile: Profile, category: Category, seed: int, jitter: float = 0.07) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(category.duration_ms / 1000.0 * SAMPLE_RATE)
    pitch = category.pitch

    signal = np.zeros(n)
    signal += _render_voice(rng, profile.click, n, pitch, jitter)
    signal += _render_voice(rng, profile.tick, n, pitch, jitter)
    signal += _render_voice(rng, profile.bottom, n, pitch, jitter)

    # Case / plate resonance tail.
    body = _damped_modes(
        rng,
        n,
        profile.body_hz * pitch,
        profile.body_ratios,
        profile.body_decay_ms * category.body_decay * rng.uniform(1 - jitter, 1 + jitter),
    )
    body *= _envelope(n, 0.9, profile.body_decay_ms * category.body_decay * 1.6)
    signal += _delay(body * profile.body_level, profile.bottom.delay_ms, n)

    # Stabiliser rattle: a secondary, quieter bottom-out a few ms late, plus a
    # faint metallic ping. This is what makes a spacebar sound like a spacebar.
    if category.stabilizer > 0.0:
        rattle_delay = profile.bottom.delay_ms + rng.uniform(2.6, 5.4)
        rattle = _spectral_noise(rng, n, 1500 * pitch, 1.5, -1.5)
        rattle *= _envelope(n, 0.35, 9.0)
        signal += _delay(rattle * 0.26 * category.stabilizer, rattle_delay, n)

        ping = _damped_modes(rng, n, 2400 * pitch, [1.0, 1.48, 2.1], 22.0)
        signal += _delay(ping * 0.09 * category.stabilizer, rattle_delay, n)

    signal = _apply_brightness(signal, profile.brightness)

    # Trim the tail once it is inaudible, then fade out so the buffer cannot
    # click when it ends.
    peak = np.abs(signal).max()
    if peak > 0:
        threshold = peak * (10 ** (-62 / 20))
        above = np.where(np.abs(signal) > threshold)[0]
        if len(above):
            end = min(len(signal), above[-1] + int(0.004 * SAMPLE_RATE))
            signal = signal[:end]

    fade = int(0.003 * SAMPLE_RATE)
    if len(signal) > fade:
        signal[-fade:] *= np.linspace(1.0, 0.0, fade)

    # Normalise, then scale to the profile's relative loudness and the
    # category's relative weight. The target is capped so that a loud profile
    # on a heavy key (blue spacebar) cannot exceed full scale and clip.
    peak = np.abs(signal).max()
    if peak > 0:
        signal = signal / peak
    signal *= min(profile.loudness * category.level, 0.95)
    return signal


def _seed(base: int, *parts: object) -> int:
    """
    A stable per-sample seed.

    Deliberately not Python's `hash()`: string hashing is salted per process,
    so the generator produced a different library on every run and the
    committed samples could not be checked against it.
    """
    digest = hashlib.sha256("\x00".join(str(part) for part in parts).encode()).digest()
    return (int.from_bytes(digest[:4], "big") ^ base) % (2**31)


def write_wav(path: Path, signal: np.ndarray) -> int:
    data = (signal * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(BIT_DEPTH // 8)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(data.tobytes())
    return path.stat().st_size


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the MechKeys sound library.")
    parser.add_argument("--out", default="Resources/Sounds", type=Path)
    parser.add_argument("--variants", default=5, type=int, help="samples per profile/category")
    parser.add_argument("--seed", default=20260919, type=int)
    args = parser.parse_args()

    out_root: Path = args.out
    manifest: dict[str, object] = {
        "generator": "Tools/generate_sounds.py",
        "sampleRate": SAMPLE_RATE,
        "bitDepth": BIT_DEPTH,
        "channels": 1,
        "variants": args.variants,
        "seed": args.seed,
        "profiles": {},
    }

    total_files = 0
    total_bytes = 0

    for profile in PROFILES:
        entry: dict[str, object] = {"description": profile.description, "categories": {}}
        for category in CATEGORIES:
            names = []
            for variant in range(1, args.variants + 1):
                seed = _seed(args.seed, profile.name, category.name, variant)
                signal = render_sample(profile, category, seed)
                filename = f"{category.name}_{variant:02d}.wav"
                size = write_wav(out_root / profile.name / filename, signal)
                names.append(filename)
                total_files += 1
                total_bytes += size
            entry["categories"][category.name] = names
        manifest["profiles"][profile.name] = entry

    manifest_path = out_root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"Wrote {total_files} samples ({total_bytes / 1024:.0f} KB) to {out_root}")
    print(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()
