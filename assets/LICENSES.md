# Sound asset licensing

Every sound MechKeys ships is **original work, generated from scratch** by
[`Tools/generate_sounds.py`](../Tools/generate_sounds.py). No recording,
sample, or third-party asset of any kind is bundled, downloaded or used.

| | |
| --- | --- |
| **Files** | `Resources/Sounds/{red,brown,blue,black,yellow}/{standard,space,enter,backspace,tab,modifier}_{01..05}.wav` |
| **Count** | 150 (5 profiles × 6 key categories × 5 variants) |
| **Format** | WAV, mono, 48 kHz, 16-bit PCM |
| **Source** | `Tools/generate_sounds.py`, this repository |
| **Creator** | Aashish Paruvada |
| **Licence** | MIT, the same as the rest of the project — see [`LICENSE`](../LICENSE) |
| **Attribution required** | No |
| **Redistribution** | Permitted, including commercially |
| **Date created** | 2026-09-19 |

## How they are made

Each sample is synthesised from a physical sketch of what a mechanical
keyswitch does when it is pressed, rather than being recorded:

1. **Click** — the tactile jacket snapping. A high-Q resonant noise burst with
   a near-instant attack and a short decay.
2. **Tick** — keycap and stem contact. A softer mid-frequency burst that gives
   the sound its texture.
3. **Bottom-out** — the stem hitting the housing a few milliseconds later. A
   broadband thump, and the body of the sound.
4. **Case modes** — plate and case resonance, as exponentially damped sinusoids
   at slightly inharmonic frequencies. This is the "thock" tail.
5. **Stabiliser rattle** — on the spacebar, Return and the modifiers, a second
   quieter bottom-out a few milliseconds late plus a faint metallic ping.

Per-profile voicings and per-category pitch and weight live in one table at the
top of the generator. The seeding is deterministic (SHA-256 of the profile,
category and variant names), so the library is reproducible byte for byte, and
CI verifies that the committed files are exactly what the generator produces.

## Why not recordings

Recorded keyboard samples are the obvious route and were considered. They were
rejected because:

- Redistribution rights for keyboard recordings found online are frequently
  unclear, and an application that ships them inherits that uncertainty.
- A recording cannot be re-voiced. Synthesis means the resonance frequency of
  each profile is a known number, which is what lets the dampening chain aim
  its filters at the right place per profile instead of applying one fixed
  curve to everything.
- 150 consistent variants would otherwise be a recording session with a
  controlled room, five keyboards and careful level matching.

If recorded samples are ever added, they must be documented in this file with
filename, source URL, creator, licence, licence URL, date retrieved, and any
attribution requirement — and anything whose redistribution rights are not
clearly established must not ship.
