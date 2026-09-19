# Sound asset licensing

Every sound MechKeys ships is a recording of a real mechanical keyboard. All
120 files live inside the app bundle; nothing is downloaded at runtime and the
app makes no network requests.

## What is bundled

| | |
| --- | --- |
| **Files** | `Resources/Sounds/{red,brown,blue,black,yellow}/{standard,space,enter,backspace,tab,modifier}_{01..}.wav` |
| **Count** | 120 (5 profiles × 6 key categories, 3–5 variants each) |
| **Format** | WAV, mono, 48 kHz, 16-bit PCM |
| **Recordings by** | Thomas Lai (`tplai`), published as part of [kbsim](https://github.com/tplai/kbsim) |
| **Obtained from** | the [thock-soundpacks](https://github.com/kamillobinski/thock-soundpacks) registry |
| **Licence** | MIT — see [`tplai/kbsim` LICENSE.md](https://github.com/tplai/kbsim/blob/master/LICENSE.md) |
| **Attribution required** | Yes: the copyright notice must travel with the recordings |
| **Redistribution** | Permitted, including commercially |
| **Date retrieved** | 2026-09-19 |

The notice is bundled as `MechKeys.app/Contents/Resources/LICENSE-sounds.txt`,
which is what the MIT licence requires. `assets/SOURCES.json` pins the exact
pack identifiers, and `Tools/import_sounds.py` reproduces the conversion.

## Which recording became which profile

Each pack was chosen because the switch actually sounds like what the profile
claims to be:

| Profile | Switch | Why |
| --- | --- | --- |
| **Red** | Gateron Ink Red | Smooth linear, quiet, rounded |
| **Brown** | Drop Holy Panda | The definitive tactile — deep and dark |
| **Blue** | Kailh Box Navy | The definitive clicky — loud and sharp |
| **Black** | Gateron Ink Black | Heavy linear with a firm clack |
| **Yellow** | NovelKeys Cream | Smooth, creamy linear |

Switch names identify the recording. No manufacturer endorsement is implied and
MechKeys is not affiliated with any of them.

Each pack supplies five separate recordings of an ordinary key plus dedicated
spacebar, Return and Delete recordings. Tab and the modifiers have no recording
of their own and are the ordinary ones pitched down a fraction — a wider key,
but not a stabilised one.

## Processing

Deliberately minimal, so what ships is the recording rather than an effect
built on one. `Tools/import_sounds.py`:

- resamples 44.1 kHz to 48 kHz in the frequency domain, which is exact for a
  band-limited signal rather than the smear linear interpolation leaves on a
  transient this sharp;
- removes leading digital silence, so a keypress starts when it starts;
- applies 2 ms boundary fades, so no buffer can click at its edges;
- peak-normalises, then scales by the profile's relative loudness, so a Box
  Navy stays audibly louder than an Ink Black.

## What was rejected, and why

- **The "Thocky / Creamy / Marbly / Clacky" packs** circulating in the same
  ecosystem are excerpts from a YouTube keyboard-review video. The project that
  publishes them states that permission was granted for *that project only* and
  that reuse rights were not established. Redistributing them here would not be
  covered.
- **The Pixabay-sourced pack** in the upstream registry has an unidentified
  source item and no established permission to distribute the individual files.
- **Synthesised samples.** MechKeys originally shipped 150 samples generated
  from a physical model of a switch. They were licence-free and fully
  reproducible, but they did not sound authentic, which is the whole point of
  the app. The generator was removed when the recordings replaced it.

## If sounds are ever changed again

Anything added must be documented here with filename, source URL, creator,
licence, licence URL, date retrieved, and any attribution requirement — and
anything whose redistribution rights are not clearly established must not ship.
