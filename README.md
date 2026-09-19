# MechKeys

Mechanical keyboard sounds for macOS.

Pick what your Mac sounds like, then decide how acoustically dampened it feels.
MechKeys lives in the menu bar, plays a short mechanical keypress sound for
every key you press, and never records what you type.

```
curl -fsSL https://theysap.com/install/mechkeys | bash
```

---

## Features

- **Five switch profiles** — Red, Brown, Blue, Black and Yellow — each with its
  own transient, body and ring.
- **A dampening control that is actually acoustic.** Not a delay, not a volume
  cut: a real signal chain that softens the attack, rolls off the top end,
  stops the case ringing and puts low-mid body back. End to end it removes
  about 99.4% of the energy above 3 kHz.
- **Different sounds for different keys.** The spacebar is deeper and rattles
  like a stabilised key; Return is heavier; Delete and Tab sit in between.
  Modifiers are silent by default.
- **Natural variation.** Five recordings per key, never the same one twice in a
  row, with a fraction of a decibel and a fraction of a semitone of movement
  each press.
- **Low latency.** A keypress does no allocation, no file I/O and no node
  creation — the processed buffer already exists and is simply scheduled.
- **Private by construction.** The event tap is listen-only, keycodes are
  reduced to one of six categories inside the callback and discarded, and
  nothing is stored or transmitted. No network access at all.
- **Everything configurable**, down to the six individual DSP parameters behind
  the dampening slider.

## Requirements

- macOS 26 or later
- Apple silicon
- Accessibility permission (see below)

MechKeys is a menu bar application. It has no Dock icon.

## Installation

```bash
curl -fsSL https://theysap.com/install/mechkeys | bash
```

The script checks the machine, downloads the latest disk image, verifies it
against the published SHA-256 checksum, and installs into `/Applications` (or
`~/Applications` if you are not an admin). Downloading this way also avoids the
quarantine flag a browser download picks up.

Pin a version with `MECHKEYS_VERSION=1.0.0`, and skip the launch at the end
with `MECHKEYS_NO_LAUNCH=1`.

You can read the script before running it — it is
[`Scripts/install.sh`](Scripts/install.sh) in this repository, and the URL above
serves that file as plain text.

Or download the `.dmg` from the [releases page](https://github.com/theysap/MechKeys/releases)
and drag the app to Applications.

## Accessibility permission

macOS requires Accessibility permission for any application that watches the
keyboard system-wide. MechKeys asks for it on first launch, and the menu bar
popover shows the status at any time.

**System Settings → Privacy & Security → Accessibility → MechKeys.**

What MechKeys does with that permission:

- It creates a **listen-only** event tap. macOS will not let a listen-only tap
  modify, block or inject keystrokes even if it tried to.
- Inside the callback the keycode is turned into one of six categories —
  standard, space, enter, backspace, tab, modifier — and then goes out of
  scope.
- The value handed to the audio system is that six-case enum. There is nowhere
  in it to put a character.
- Nothing is written to disk, buffered, or sent anywhere. MechKeys makes no
  network requests.
- Switching MechKeys off does not merely mute it: the event tap is torn down.

## Usage

Click the keyboard icon in the menu bar for the three things worth changing
mid-task: the switch, the dampening and the volume. **Configure…** opens the
full window.

| Tab | What is in it |
| --- | --- |
| **Sound** | Switch profile, dampening (with the six advanced DSP parameters), master volume |
| **Keys** | Modifier sounds, and per-category enable / level / pitch for all six key categories |
| **Behaviour** | Key-repeat handling, minimum interval, variation amount, overlapping voices |
| **General** | Permission status, launch at login, privacy summary, reset, quit |

Everything applies immediately. **Save & Close** confirms and dismisses the
window — MechKeys keeps running in the menu bar. **Revert Changes** undoes
everything since the window was opened. **Quit MechKeys** exits entirely.

## Sound profiles

Acoustic profiles inspired by the character of common switch types. They are
original synthesised sounds and are not affiliated with, endorsed by, or
sponsored by any switch manufacturer.

| Profile | Character | Description |
| --- | --- | --- |
| **Red** | tap / clack | Linear and smooth. Quiet, rounded bottom-out, soft transient. |
| **Brown** | tick / clack | Tactile with a little texture. Moderate attack, no exaggerated click. |
| **Blue** | CLICK | Tactile and clicky. The loudest and sharpest, with strong high-frequency attack. |
| **Black** | thock | Heavy linear. Deep body, substantial bottom-out, less sharpness. |
| **Yellow** | clack | Smooth linear, between Red and Black in perceived weight. |

Measured spectral centroid runs Blue → Brown → Red → Yellow → Black, brightest
to darkest, which is the ordering a test asserts on every run.

## Dampening

The slider models what happens when you pack a keyboard with foam, silicone and
plate gaskets.

```
Dampening

Sharp ─────────────●──────────── Muted
                   42%
```

| Position | What you hear |
| --- | --- |
| 0% | Undampened. Full high-frequency energy, sharp transient, a long ring. |
| 25% | Lightly dampened. Softened transient, top end pulled back a little. |
| 50% | Noticeably smoother. Reduced sharpness and resonance, fuller and rounder. |
| 75% | Strongly softened. Highs substantially reduced, very little ring left. |
| 100% | Heavily dampened. Soft attack, filtered highs, minimal ringing — muffled and thuddy. |

It is **not** a delay and **not** a volume control. Loudness compensation rises
with the slider precisely so that the two ends are comparable in level, and a
test measures both properties on every run: high-frequency energy falls
monotonically by more than 100×, level does not, and the onset of the sound
moves by less than a millisecond.

The six parameters behind it — cutoff, high shelf, transient softening,
resonance reduction, compression and low-mid body — are all exposed under
**Advanced**, with a manual mode for setting them directly.

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for how the chain is built.

## Privacy

- No typed text, characters or key sequences are read, stored or transmitted.
- No clipboard, document or application content is accessed.
- No analytics, no telemetry, no cloud service, no network requests.
- No microphone, camera, screen recording or full disk access is requested —
  MechKeys plays audio, it does not record any.
- Everything happens locally, in one process, with no helper and no server.

## Audio assets

All 150 bundled samples are **synthesised from scratch** by
[`Tools/generate_sounds.py`](Tools/generate_sounds.py) from a physical sketch of
a keyswitch: a click transient, a keycap tick, a bottom-out thump, damped case
resonance modes, and stabiliser rattle on the large keys. Nothing is recorded,
sampled or downloaded, so there is no licensing encumbrance on any of it.

5 profiles × 6 key categories × 5 variants, mono 48 kHz 16-bit, about 2.5 MB in
total, all inside the app bundle. The generator is deterministic, and CI checks
that the committed `.wav` files are exactly what it produces.

Regenerate them with:

```bash
python3 Tools/generate_sounds.py
```

See [assets/LICENSES.md](assets/LICENSES.md).

## Licensing

MIT. See [LICENSE](LICENSE).

## Development

A Swift package. No third-party dependencies — Apple frameworks only.

```
Sources/MechKeysCore/    everything, so it can be unit tested
  App/                   scene, delegate, controller
  Audio/                 engine, DSP, library, variation
  Keyboard/              event tap, classification, permission
  MenuBar/               popover and icon
  Models/                settings, profiles, key categories
  Onboarding/            first-run flow
  Settings/              configuration window
  Support/               logging, observation, shared views
Sources/MechKeys/        @main shim
Tests/                   58 tests in 9 suites
Tools/                   the sound generator
Scripts/                 build, package, install, test
```

Requires Swift 6.2 and the macOS 26 SDK. Xcode is not needed — the Command Line
Tools are enough.

## Building

```bash
# Debug
swift build

# Release
swift build -c release

# The application bundle, into dist/
./Scripts/build-app.sh

# A disk image, into dist/
./Scripts/make-dmg.sh
```

`build-app.sh` assembles the bundle by hand: it copies the binary, bundles the
sound library, renders `AppIcon.icns` from
[`Scripts/make-icon.swift`](Scripts/make-icon.swift), writes `Info.plist`, and
signs with the hardened runtime.

Set `DEVELOPER_ID_APPLICATION` to sign with a real identity. Without it the
bundle is ad-hoc signed, which runs locally but means **macOS asks for
Accessibility permission again after every rebuild** — the grant is keyed to
the code signature, and an ad-hoc signature changes each time.

## Testing

```bash
./Scripts/test.sh
```

The script passes the Swift Testing macro plugin path, which the Command Line
Tools do not search by default.

No test requires audio hardware. The dampening tests drive the real
`AVAudioEngine` graph through its offline manual rendering mode and measure the
output with an FFT, so the claims in this README about the dampening chain are
checked on every run rather than asserted.

## Troubleshooting

**No sound when I type.** Check the menu bar popover. If Keyboard Access says
*Required*, grant it in System Settings → Privacy & Security → Accessibility.
If you rebuilt from source, the ad-hoc signature changed and macOS treats it as
a different application — remove the old MechKeys entry from that list and add
the new one.

**It stopped working after a while.** macOS disables an event tap that takes
too long to respond, and during secure input (a password field). MechKeys
re-enables it automatically; if it does not, toggle it off and on.

**No sound after switching to AirPods.** MechKeys rebuilds its audio graph when
the output device changes and retries a few times if the device is still
connecting. If it stays silent, toggle MechKeys off and on.

**Sounds lag behind my typing.** Lower *Minimum Interval* in Behaviour, and
check that nothing else is holding the audio device at a large buffer size.

**Holding a key floods the sound.** Behaviour → Key Repeat → *Silent*, which is
the default.

**Launch at login says "Unavailable".** `SMAppService` needs a real application
bundle; it cannot register a binary run straight out of `.build`. Run the built
`MechKeys.app`.
