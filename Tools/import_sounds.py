#!/usr/bin/env python3
"""
Builds the MechKeys sound library from recordings of real switches.

Source: the `tplai` keyboard packs in the `thock-soundpacks` registry, which
are recordings of actual keyboards and are published under the MIT licence.
Five packs are used, chosen because they match what each MechKeys profile is
supposed to sound like:

    red     Gateron Ink Red        smooth linear, quiet
    brown   Drop Holy Panda        the definitive tactile
    blue    Kailh Box Navy         the definitive clicky
    black   Gateron Ink Black      heavy linear, deep
    yellow  NovelKeys Cream        smooth linear, between the two

Each pack supplies five separate recordings of an ordinary key, plus one each
of the spacebar, Return and Delete — which is exactly the shape MechKeys wants.

Processing is deliberately minimal, so what ships is the recording rather than
an effect built on top of one:

  * resampled 44.1 kHz to 48 kHz in the frequency domain, which is exact for a
    band-limited signal rather than the smear linear interpolation would leave
    on a transient this sharp;
  * leading digital silence removed, so a keypress starts when it starts;
  * two-millisecond boundary fades, so no buffer can click at its edges;
  * peak-normalised, then scaled by the profile's relative loudness, so that a
    Box Navy is still audibly louder than an Ink Black.

Usage:
    python3 Tools/import_sounds.py --packs <dir> [--out Resources/Sounds]
"""

from __future__ import annotations

import argparse
import json
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

TARGET_RATE = 48_000
BIT_DEPTH = 16


@dataclass
class ProfilePlan:
    """Which pack becomes which profile, and how loud it sits."""

    slug: str
    source: str
    # Relative loudness, preserving the designed relationship between profiles.
    loudness: float


PROFILES = [
    ProfilePlan("red", "Gateron Ink Red", 0.62),
    ProfilePlan("brown", "Drop Holy Panda", 0.70),
    ProfilePlan("blue", "Kailh Box Navy", 0.92),
    ProfilePlan("black", "Gateron Ink Black", 0.78),
    ProfilePlan("yellow", "NovelKeys Cream", 0.70),
]

# How each MechKeys category is filled from the pack's own categories.
#
# Tab and the modifiers have no recording of their own. They are wider keys
# than a letter but not stabilised like a spacebar, so they are the ordinary
# recordings pitched down a fraction — which is what being a slightly larger
# lump of plastic does to the sound.
CATEGORY_SOURCES = {
    "standard": ("default", 0.0, 5),
    "space": ("space", 0.0, 3),
    "enter": ("enter", 0.0, 3),
    "backspace": ("backspace", 0.0, 3),
    "tab": ("default", -0.3, 5),
    "modifier": ("default", -0.6, 5),
}

# Micro-variation used only to fill out a category that has a single
# recording. Small enough to read as the same key hit twice, not as two keys.
FILL_PITCH_CENTS = [0.0, -14.0, 11.0]
FILL_GAIN_DB = [0.0, -0.6, 0.4]


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        frames = handle.readframes(handle.getnframes())

    if width != 2:
        raise ValueError(f"{path}: expected 16-bit, got {width * 8}-bit")

    samples = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return samples, rate


def resample(samples: np.ndarray, source_rate: int, target_rate: int) -> np.ndarray:
    """
    Frequency-domain resampling.

    Exact for a band-limited signal: the spectrum is simply reinterpreted at
    the new length. Linear interpolation would round off the very transient
    that makes a switch sound like that switch.
    """
    if source_rate == target_rate:
        return samples

    target_length = int(round(len(samples) * target_rate / source_rate))
    spectrum = np.fft.rfft(samples)
    bins = len(spectrum)
    wanted_bins = target_length // 2 + 1

    if wanted_bins > bins:
        spectrum = np.concatenate([spectrum, np.zeros(wanted_bins - bins, dtype=complex)])
    else:
        spectrum = spectrum[:wanted_bins]

    resampled = np.fft.irfft(spectrum, target_length)
    # irfft normalises by the new length, so restore the original amplitude.
    return resampled * (target_length / len(samples))


def pitch_shift(samples: np.ndarray, cents: float) -> np.ndarray:
    """Resampling playback rate, which shifts pitch and duration together."""
    if abs(cents) < 0.01:
        return samples
    ratio = 2.0 ** (cents / 1200.0)
    length = max(1, int(round(len(samples) / ratio)))
    position = np.arange(length) * ratio
    lower = np.floor(position).astype(int)
    lower = np.clip(lower, 0, len(samples) - 2)
    fraction = position - lower
    return samples[lower] * (1 - fraction) + samples[lower + 1] * fraction


def trim_and_fade(samples: np.ndarray, rate: int) -> np.ndarray:
    """Remove digital silence at the front, and fade both edges."""
    peak = np.abs(samples).max()
    if peak <= 0:
        return samples

    # Only exact digital silence: anything audible is part of the recording.
    nonzero = np.flatnonzero(np.abs(samples) > 1e-6)
    if len(nonzero):
        samples = samples[nonzero[0]:]

    # Trim an inaudible tail so buffers are not longer than they need to be.
    threshold = np.abs(samples).max() * (10 ** (-60 / 20))
    above = np.flatnonzero(np.abs(samples) > threshold)
    if len(above):
        samples = samples[: min(len(samples), above[-1] + int(0.005 * rate))]

    fade = int(0.002 * rate)
    if len(samples) > fade * 2:
        samples[:fade] *= np.linspace(0.0, 1.0, fade)
        samples[-fade:] *= np.linspace(1.0, 0.0, fade)
    return samples


def write_wav(path: Path, samples: np.ndarray) -> int:
    data = np.clip(samples, -0.999, 0.999)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(BIT_DEPTH // 8)
        handle.setframerate(TARGET_RATE)
        handle.writeframes((data * 32767.0).astype("<i2").tobytes())
    return path.stat().st_size


def main() -> None:
    parser = argparse.ArgumentParser(description="Import recorded switch packs.")
    parser.add_argument("--packs", required=True, type=Path,
                        help="directory of <profile>/ pack folders with config.json")
    parser.add_argument("--out", default=Path("Resources/Sounds"), type=Path)
    args = parser.parse_args()

    manifest: dict[str, object] = {
        "generator": "Tools/import_sounds.py",
        "sampleRate": TARGET_RATE,
        "bitDepth": BIT_DEPTH,
        "channels": 1,
        "profiles": {},
    }

    total_files = 0
    total_bytes = 0

    for plan in PROFILES:
        pack = args.packs / plan.slug
        config = json.loads((pack / "config.json").read_text())
        sounds = config["sounds"]

        entry: dict[str, object] = {
            "source": plan.source,
            "license": config.get("license", {}).get("type"),
            "categories": {},
        }

        for category, (key, cents, wanted) in CATEGORY_SOURCES.items():
            files = sounds.get(key, {}).get("down", [])
            if not files:
                raise SystemExit(f"{plan.slug}: pack has no '{key}' recordings")

            rendered: list[np.ndarray] = []
            for index in range(wanted):
                if index < len(files):
                    # A genuinely separate recording.
                    source, extra_cents, extra_db = files[index], 0.0, 0.0
                else:
                    # Only one recording for this key, so fill the remaining
                    # slots with barely-shifted copies of it.
                    fill = index - len(files) + 1
                    source = files[index % len(files)]
                    extra_cents = FILL_PITCH_CENTS[fill % len(FILL_PITCH_CENTS)]
                    extra_db = FILL_GAIN_DB[fill % len(FILL_GAIN_DB)]

                samples, rate = read_wav(pack / source)
                samples = resample(samples, rate, TARGET_RATE)
                samples = pitch_shift(samples, cents * 100 + extra_cents)
                samples = trim_and_fade(samples, TARGET_RATE)
                samples *= 10 ** (extra_db / 20)
                rendered.append(samples)

            # One normalisation across the whole category, so the variants keep
            # the level differences they were recorded with.
            peak = max(np.abs(s).max() for s in rendered)
            scale = (plan.loudness / peak) if peak > 0 else 0.0

            names = []
            for index, samples in enumerate(rendered, start=1):
                name = f"{category}_{index:02d}.wav"
                total_bytes += write_wav(args.out / plan.slug / name, samples * scale)
                names.append(name)
                total_files += 1
            entry["categories"][category] = names

        manifest["profiles"][plan.slug] = entry
        print(f"{plan.slug:8} <- {plan.source}")

    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\nWrote {total_files} samples ({total_bytes / 1024:.0f} KB) to {args.out}")


if __name__ == "__main__":
    main()
