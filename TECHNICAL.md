# TECHNICAL.md

How MechKeys works, and why it is built the way it is.

Two constraints shape nearly everything here. The first is latency: a sound
that arrives late does not read as *late*, it reads as *wrong*, and the
tolerance is on the order of ten milliseconds. The second is that the app has
to hold a permission people are reasonably suspicious of, which means the
design has to make misuse structurally impossible rather than merely promise
it.

Where a number appears below it was measured, on the development machine
(Apple silicon, macOS 27.0), not estimated. The audio figures come from
`DampeningRenderTests`, which measures the shipping signal chain on every test
run.

---

## Contents

1. [The keyboard path](#1-the-keyboard-path)
2. [Privacy, by construction](#2-privacy-by-construction)
3. [Permissions](#3-permissions)
4. [The audio graph](#4-the-audio-graph)
5. [Dampening](#5-dampening)
6. [The sample library](#6-the-sample-library)
7. [Natural variation](#7-natural-variation)
8. [Settings](#8-settings)
9. [Building and packaging](#9-building-and-packaging)
10. [Testing without a speaker](#10-testing-without-a-speaker)
11. [Build constraints worth knowing](#11-build-constraints-worth-knowing)
12. [Known limits](#12-known-limits)

---

## 1. The keyboard path

```
key down / flags changed / system defined
   │
   ▼
CGEventTap (.listenOnly, .cgSessionEventTap)   ← own thread, own run loop
   │
   ├── keycode ──▶ KeyClassifier ──▶ KeyCategory (one of six)
   │                                      │
   │   the keycode goes out of scope here ┘
   │
   ├── repeat mode, then minimum interval
   │
   ▼
KeyEvent { category, isRepeat, timestamp }
   │
   ▼
audio queue (DispatchQueue, .userInteractive)  ← the callback has already returned
```

### 1.1 Three kinds of event, because three kinds arrive

A tap that asks only for `keyDown` hears most of a keyboard and not all of it:

| Event | Keys |
|---|---|
| `keyDown` | letters, digits, punctuation, arrows, Escape, Tab, Return, Delete, space, and F3–F6 (Mission Control, Spotlight, Dictation, Focus) |
| `flagsChanged` | Shift, Control, Option, Command, Caps Lock, fn — these *only* ever arrive this way, and twice: once pressed, once released |
| `NX_SYSDEFINED` | brightness, media transport and volume — **F1, F2 and F7–F12 on an Apple keyboard** |

The third is easy to miss, and was: those eight keys made no sound at all,
while the four beside them did. The hardware does not report them as key
presses. `CGEventType` has no case for `NX_SYSDEFINED` (14) either, so it
cannot be matched in a `switch` — the raw value still arrives intact, and the
mask has to ask for it by number.

Reading which aux key it was needs the event's `data1`, and `CGEvent` exposes
no field for it, so that one path converts to `NSEvent`. It is the only
allocation in the monitor, and it is not on the hot path: an ordinary
keystroke never reaches it.

Two aux keys are deliberately ignored. Caps Lock has an aux code *and* a
`flagsChanged`, so honouring both would sound it twice; and the power key is
Touch ID on most Macs, which nobody presses to type.

### 1.2 Why a thread of its own

The tap's run loop source runs on a `Thread` at `.userInteractive`, not on the
main run loop. Servicing it from the main run loop would put every keystroke
behind whatever SwiftUI happened to be doing — and macOS *disables* a tap whose
callback takes too long, so a slow path is not merely laggy, it is fatal.

### 1.3 What the callback is allowed to do

Classify, check two rate limits, hand over a six-case enum, return. No
allocation, no I/O, no audio work, no locks held across anything slow. `play`
only enqueues onto the audio queue; it never blocks the caller.

The one lock is an `NSLock` around three settings values the callback reads.
Uncontended, so on the order of tens of nanoseconds; it exists because those
values are written from the main thread.

### 1.4 Classification is layout-independent

The keycodes are the Carbon `kVK_*` constants. They describe the *physical*
key, not the character it produces — keycode 49 is the spacebar on QWERTY,
AZERTY and Dvorak alike. That is exactly the right level of detail: the app
needs to know how big the key under the finger is, and nothing else.

Modifiers arrive as `flagsChanged`, which fires on both press and release. Only
the press should sound, so the event's flags are checked for that modifier's
bit. Caps Lock is special-cased: it latches rather than holds, so both the on
and the off press are real presses of a real key.

### 1.5 Rate limiting

Two separate guards, because they answer different questions:

- **Repeat mode** — `silent` (the default) drops autorepeat events entirely,
  `throttled` lets them through subject to the interval, `everyRepeat` lets
  them all through.
- **Minimum interval** — a floor on the gap between any two sounds, 5–200 ms,
  defaulting to 22 ms. This is what stops an autorepeat storm, or a deliberate
  mash, from flooding the voice pool.

`everyRepeat` deliberately skips the floor, because that is what the setting
means.

### 1.6 Recovering from a disabled tap

macOS disables a tap that is too slow, and during secure input — any password
field. Both arrive as `tapDisabledByTimeout` / `tapDisabledByUserInput`, and
the documented recovery is to re-enable, which the callback does immediately.

## 2. Privacy, by construction

The interesting property is not that MechKeys promises not to log keystrokes.
It is that it has nowhere to put one.

`KeyEvent` has three fields: a six-case enum, a `Bool` and a `TimeInterval`.
The keycode exists only as a local inside the callback and is never returned,
stored or copied. Everything downstream — the controller, the engine, the
buffer cache — is typed in terms of `KeyCategory`, so no amount of later
carelessness can leak a character, because the character is not there to leak.

On top of that:

- The tap is `.listenOnly`. That is enforced by the kernel, not by us: a
  listen-only tap cannot modify, drop or inject events even if the code tried.
- The tap also sees `flagsChanged` and `NX_SYSDEFINED` (§1.1). The same rule
  holds for both: which modifier, or which media key, is read to decide
  whether to make a sound and then discarded. Neither is stored, and neither
  can reach the audio side, which is typed in `KeyCategory`.
- Nothing is written to disk except one `UserDefaults` key holding the
  settings.
- The app makes exactly **one kind of network request**: a `GET` to GitHub's
  public releases API when it checks for an update, and — only if the user
  presses Download & Restart — the disk image and checksums that release
  publishes. Nothing is sent: no identifiers, no version report, no analytics,
  no account. `Sources/MechKeysCore/Update/` is the whole of it, and it is the
  only code in the project that opens a socket. Turning off "Check for updates
  automatically" means nothing is requested at all unless the user asks.
- Switching MechKeys off calls `stop()` on the monitor, which disables the tap,
  removes its run loop source and lets the thread exit. Off means the tap is
  gone, not muted.
- Logging goes through `os.Logger` and records lifecycle events only —
  "monitor started", "audio configuration changed". No log statement in the
  keyboard path takes a keycode as an argument.

## 3. Permissions

MechKeys asks for exactly one permission, and it is unavoidable:
**Accessibility**. macOS gates `CGEvent.tapCreate` behind it, and there is no
other supported way for a process to learn that a key was pressed in another
application. There is no narrower permission to request.

What is deliberately **not** requested:

| Permission | Why not |
|---|---|
| Microphone | MechKeys plays audio; it does not record any |
| Screen Recording | It never reads the screen |
| Camera | Nothing to see |
| Full Disk Access | It reads its own bundle and writes one defaults key |
| Input Monitoring | Not needed for a listen-only session tap |

### 3.1 The App Sandbox is off, deliberately

A sandboxed process is not permitted to create a `CGEventTap` at all, so
sandboxing MechKeys would mean it could never hear a keystroke. The hardened
runtime *is* enabled, which is what notarisation requires and what the tap is
perfectly happy with.

### 3.2 The grant is keyed to the code signature

macOS records the Accessibility grant against the application's **signature**,
not its name or its path. An ad-hoc signature (`codesign -s -`) contains a hash
of the binary, so it differs in every build — and each rebuild is therefore a
different application as far as TCC is concerned.

The failure this produces is genuinely confusing, because nothing reports it:
the switch stays on in System Settings, pointing at a build that no longer
exists, while the build you just made is refused. The app says it has no
permission; the system says it was granted. Both are telling the truth about
different binaries.

Any *stable* identity fixes it, because the designated requirement changes
shape:

```
ad-hoc:  identifier "com.mechkeys.app" and cdhash H"…"            ← new every build
signed:  identifier "com.mechkeys.app" and certificate root = H"…"  ← per certificate
```

`Scripts/make-dev-certificate.sh` creates a self-signed code-signing
certificate once, and `build-app.sh` picks it up automatically, so permission
is granted once and then left alone across rebuilds. A Developer ID does the
same for distribution builds, and `Scripts/make-release-certificate.sh` does it
for CI without one.

**This is why releases cannot be ad-hoc signed.** The updater (§9.3) replaces
the bundle in place, so an ad-hoc release would revoke the user's keyboard
access on every single update, silently and with the switch still on in System
Settings. A stable release identity is a prerequisite for shipping an updater
at all, not a nicety.

To clear a grant that is pointing at a build that is gone:

```sh
tccutil reset Accessibility com.mechkeys.app
```

### 3.3 Diagnosing it from the inside

`MechKeys --diagnose` prints what the process itself can see: its bundle
identity, its code signature, `AXIsProcessTrusted`, and whether an event tap
can actually be created. Nothing outside the process can answer those
questions, because TCC decides per process and per signature.

**Read it with one caveat, which the report now states itself.** TCC answers
for the *responsible* process, and a binary exec'd from a shell is the
terminal's responsibility rather than its own. So typing
`MechKeys --diagnose` into a terminal reports whether **the terminal** has
Accessibility, and will say "no access" about an app that is working
perfectly — the exact confusion the command exists to dispel. A GUI launch is
re-parented to launchd, so `getppid() == 1` distinguishes the two cases, and
the report warns and softens its verdict when it is not the responsible
process. To check the real thing, look at Keyboard Access in the popover.

### 3.4 Detecting the grant

There is no notification for "the user just granted Accessibility", so the
status is polled — but only while it is missing, by a `Task` that cancels
itself the moment permission arrives and never runs again. Returning from
System Settings is the likeliest moment for it to have changed, so
`NSApplication.didBecomeActiveNotification` triggers an immediate check rather
than waiting for the next tick.

The system prompt is shown at most once. After that the button opens System
Settings directly, because a second prompt for a permission the user has
already been asked about is just nagging.

## 4. The audio graph

```
  [player 0] ─┐
  [player 1] ─┼─▶ bus ─▶ dynamics ─▶ EQ (4 bands) ─▶ limiter ─▶ mixer ─▶ out
  [player n] ─┘
```

One `AVAudioEngine`, built once at launch and alive for the life of the
process. There is no per-keypress player, no per-keypress file read, and no
per-keypress node creation — the anti-pattern that makes most implementations
of this idea audibly late.

### 4.1 The voice pool

`maximumVoices` (default 16) `AVAudioPlayerNode`s, all connected to the bus
mixer, all left in the *playing* state for the lifetime of the engine.
Scheduling a buffer on an already-playing node starts it immediately; calling
`play()` per keypress would add avoidable milliseconds.

A keypress claims whichever voice has been free longest, tracked as an array of
"free at" host times. Under normal typing one always is. Under a deliberate
mash the oldest is stolen with `.interrupts`, so the new sound starts *now*
rather than queueing behind the old one — at sixteen voices and ~170 ms
samples, that is about 94 keys per second before stealing begins.

### 4.2 The buffer cache

Every sample is pre-processed and held as an `AVAudioPCMBuffer`, keyed by
category: five variants × three micro-pitch renditions per category, about 90
buffers and a few megabytes.

It is rebuilt only when an input it depends on changes — profile, transient
reduction, resonance reduction, variation, or a per-category pitch trim. Those
inputs are quantised into a `PreparationSignature`, and rebuilds are debounced
by 60 ms, so dragging the dampening slider re-renders once when the drag
settles rather than sixty times a second.

This is the trick that keeps the key path free: by the time a key is pressed,
the fully processed audio already exists and is simply scheduled.

### 4.3 Output device changes

`AVAudioEngineConfigurationChange` arrives when the user switches to AirPods,
unplugs a monitor, or changes the default output. The engine has already
stopped by then, and the old connections reference a format that no longer
exists, so the graph is rebuilt from scratch rather than reconnected. If the
device is still coming up — a Bluetooth device mid-connect, or a wake from
sleep — the restart is retried with backoff, up to five times.

### 4.4 Latency

The budget is spent where it is visible. What remains is the output device's
own buffer, which MechKeys does not touch: that is a system-wide setting shared
with every other application, and commandeering it for a keyboard sound effect
would be rude.

## 5. Dampening

Dampening models packing a keyboard with foam, silicone and plate gaskets. It
is **not** a delay and **not** a volume cut, and both of those are enforced by
tests rather than by good intentions.

### 5.1 One curve, two anchor points

All six values come from a single interpolation in `DampeningCurve` between a
*sharp* anchor and a *muted* anchor. No profile-specific or position-specific
DSP number exists anywhere else in the codebase.

| Parameter | 0% | 100% |
|---|---|---|
| High-frequency cutoff | 19 kHz | 1.25 kHz |
| High shelf gain | +1.5 dB | −23 dB |
| Transient softening | 0 | 0.88 |
| Resonance reduction | 0 | 0.92 |
| Compression | 0 | 0.80 |
| Low-mid body | 0 dB | +5 dB |

The cutoff is interpolated **logarithmically**, because pitch perception is
logarithmic. A linear sweep would do almost nothing for the first half of the
slider and then collapse.

Three parameters are eased rather than linear, and each easing is there for a
measured reason:

- **Transient softening leads** (`t^0.82`) — the first movement of the slider
  should already take the edge off the attack, or the control feels dead at the
  bottom.
- **Body lift lags** (`t^1.45`) — otherwise low dampening just sounds boomy.
- **Resonance reduction lags** (`t^1.35`) — measured: choking the case ring
  removes low-frequency tail *faster* than the filter removes treble, so
  without this the sound got fractionally *brighter* between 0% and 12%, which
  is the opposite of what the control claims. The brief at that position is
  "slightly less resonance", so it should barely have started.

### 5.2 Split across two places, for a reason

| Where | What | Why there |
|---|---|---|
| **Offline, in the buffer cache** | Transient softening, ring-out | These reshape the one-shot itself. Softening an attack with a compressor would need lookahead, and lookahead is latency |
| **Live, on the shared bus** | Low-pass, high shelf, resonance notch, low-mid shelf, compression, limiting | Parameter writes, so they take effect on the very next keypress with no rebuild |

**Transient softening** attenuates the first sample by the reduction amount and
recovers to unity across a 7 ms window on a smoothstep curve. The onset stays
at sample zero — the sound arrives less sharply, never later. The smoothstep
matters: a corner in the gain curve would itself be audible as a click.

**Ring-out** multiplies everything after 9 ms by an extra exponential decay,
with a time constant sweeping down to 18 ms at full reduction.

### 5.3 The resonance notch is per profile

A Blue rings at about 5.4 kHz and a Black at about 2.1 kHz. One fixed notch
would dampen one and hollow out the other, so each profile carries its own
`ProfileVoicing` — resonance frequency, Q, body frequency, brightness, and how
strongly transient shaping bites on it — and the chain aims at those.

### 5.4 The EQ sits after the compressor

This order is not arbitrary, and the obvious order is wrong.

With the EQ in front, gain-riding a sharp transient generated harmonics that
landed **above** the low-pass corner, with nothing after them to remove it. The
measured high-frequency energy ratio stopped falling past 75% dampening and
rose again — audible as crunch on a setting that is supposed to be a soft thud.
Filtering last removes them. The end-to-end treble reduction went from about
16× to about 46×, and became monotonic across the whole slider.

### 5.5 Loudness compensation, and the limiter

Filtering away the top end makes a sound quieter, and a dampening control that
also turns the volume down is indistinguishable from the volume control. So
makeup gain rises to +7.5 dB across the slider.

Makeup rises to +16 dB at the muted end. With the recordings, +7.5 dB left the
muted end at 0.21 of the sharp end's level — still audibly a volume cut. At
+16 dB it sits at 0.52.

That gain, plus the low-mid shelf, can push a loud profile past full scale. An
`AUPeakLimiter` sits last in the chain as the honest fix. Pre-emptively turning everything down
to leave headroom would make the app quiet for the sake of a case that only
occurs at the extremes.

### 5.6 The measured result

At 0%, 25%, 50%, 75% and 100% dampening, on a Blue, the proportion of energy
above 3 kHz:

```
0.556   0.369   0.167   0.0272   0.00069
```

Monotonic, and a little over 800× end to end. RMS level across the same sweep
stays within about a factor of two (0.038 → 0.020), which is what stops the
control being a volume knob. The sound begins in the first sample at every
position; what changes is how quickly the attack reaches full amplitude.

## 6. The sample library

120 recordings: 5 profiles × 6 key categories, three to five variants each,
mono 48 kHz 16-bit, about 1.1 MB, all inside the app bundle. Nothing is
downloaded, ever.

They are **recordings of real keyboards** by Thomas Lai (`tplai`), published as
part of kbsim and obtained from the thock-soundpacks registry under the MIT
licence. Each profile is the switch it claims to be:

| Profile | Switch |
|---|---|
| red | Gateron Ink Red |
| brown | Drop Holy Panda |
| blue | Kailh Box Navy |
| black | Gateron Ink Black |
| yellow | NovelKeys Cream |

Each pack supplies five separate recordings of an ordinary key plus dedicated
spacebar, Return and Delete recordings — which is exactly the shape MechKeys
wants. Tab and the modifiers have no recording of their own and are the
ordinary ones pitched down a fraction: a wider key, but not a stabilised one.

### 6.1 Processing

`Tools/import_sounds.py`, and deliberately minimal, so what ships is the
recording rather than an effect built on one:

- resampled 44.1 kHz to 48 kHz **in the frequency domain**, which is exact for
  a band-limited signal. Linear interpolation would round off the very
  transient that makes a switch sound like that switch;
- leading digital silence removed, so a keypress starts when it starts;
- 2 ms boundary fades, so no buffer can click at its edges;
- peak-normalised, then scaled by the profile's relative loudness, so a Box
  Navy stays audibly louder than an Ink Black.

### 6.2 What was rejected

The same ecosystem circulates a set of "Thocky / Creamy / Marbly / Clacky"
packs. They are excerpts from a YouTube keyboard-review video, and the project
publishing them states that permission covers *that project only* and that
reuse rights were not established. They are not used here. Neither is the
registry's Pixabay-sourced pack, whose source item is unidentified.

### 6.3 What was replaced

MechKeys originally shipped 150 samples synthesised from a physical model of a
switch: a click transient, a keycap tick, a bottom-out thump, damped case
resonance modes and stabiliser rattle. That library was licence-free and
byte-reproducible, and it is documented in the history around `v0.1.0`.

It was replaced because it did not sound authentic, which is the entire point
of the app. Synthesis had one real advantage worth recording — each profile's
resonance frequency was a *known* number, which §5.3 relies on. That is now
recovered by measuring the recordings instead: the values in `ProfileVoicing`
are the dominant peak between 1.5 and 9 kHz, the energy centroid below 600 Hz,
the normalised spectral centroid, and the time to peak, taken from the bundled
files rather than chosen.

## 7. Natural variation

Replaying one recording is the single thing that makes key sounds feel fake.

Per keypress: one of five variants, never the same one twice in a row — a
single re-roll, not a guarantee, because forcing a different sample every time
is itself a detectable pattern — with up to ±2 dB of level and ±18 cents of
pitch.

The pitch renditions are pre-rendered into the cache, so pitch variation costs
nothing at playback time. The PRNG is SplitMix64: a handful of integer
operations with no syscall behind it, which matters when it runs on the audio
queue for every key.

At variation 0 the slider reads *Identical* and means it: the same sample every
time. It used to still rotate between samples, which made the label a lie.

## 8. Settings

One `Codable` `AppSettings` struct, stored as a single JSON blob in
`UserDefaults` — a single blob rather than a scatter of `@AppStorage` keys,
because that is what makes an atomic snapshot, and therefore "Revert Changes",
possible.

- Every value is clamped on assignment *and* again on decode, so an
  out-of-range number can never reach an audio unit.
- Decoding is tolerant: settings written by an older build load, with anything
  missing falling back to its default. A strict decoder would throw the whole
  file away and silently reset the user's setup over one renamed field.
- `[KeyCategory: KeyCategorySettings]` encodes as a real JSON object rather
  than a flat alternating array, via `CodingKeyRepresentable`.
- `launchAtLogin` is **not** in the struct. That state belongs to
  `SMAppService`; the app mirrors it, because the user can also change it in
  System Settings and a stored copy would only be something to disagree with.

## 9. Building and packaging

The project is a Swift package, not an Xcode project, and
`Scripts/build-app.sh` assembles the bundle by hand: copy the binary, bundle
the 120 samples into `Contents/Resources/Sounds`, render `AppIcon.icns` from
`Scripts/make-icon.swift`, write `Info.plist` with `LSUIElement`, sign with the
hardened runtime.

`Scripts/make-dmg.sh` packages it, optionally signs and notarises.

The disk image window — the background picture and where the two icons sit —
is **committed, not built**. Arranging a Finder window means driving Finder
through Apple events, which asks for automation permission and has no chance
of working on a build machine. So it is done once, by hand:

```sh
swift Scripts/make-dmg-background.swift
(cd Scripts/dmg && tiffutil -cathidpicheck background.png background@2x.png -out background.tiff)
./Scripts/build-app.sh
./Scripts/make-dmg-layout.sh      # drives Finder, writes Scripts/dmg/DS_Store
```

`make-dmg.sh` then copies `background.tiff` and `DS_Store` into every image
and never goes near Finder. Three things about this are easy to get wrong:

- **The volume name is fixed, not versioned.** `.DS_Store` refers to the
  background through an alias that embeds the volume name
  (`MechKeys:.background:background.tiff`), so a versioned volume would break
  the picture.
- **`hdiutil`, not `diskutil`.** `hdiutil create` warns that it is deprecated
  in favour of `diskutil image create from`, but diskutil silently drops
  `.DS_Store` — which *is* the window layout — and the image comes out looking
  like a plain folder.
- **The background is light on purpose.** Finder's icon view exposes text
  size, label position, a background picture and a background colour, and no
  text *colour* at all. The labels are a fixed dark grey, so a dark background
  would make both filenames nearly invisible.

### 9.1 Distribution, and the Gatekeeper wall

**Notarisation** is what stops Gatekeeper refusing the app on someone else's
Mac. Without it every browser download is met with "Apple could not verify
MechKeys is free of malware", and the only way past is Privacy & Security →
Open Anyway. Signing alone is not enough and has not been since macOS 10.15.

It needs a paid Developer ID. The build works without one and skips the step.
With one:

```sh
# 1. Keychain Access → Certificate Assistant → Request a Certificate from a
#    Certificate Authority, saved to disk. Upload it at developer.apple.com
#    under Certificates → + → Developer ID Application. Download and open the
#    result, then confirm it is installed:
security find-identity -v -p codesigning

# 2. An app-specific password for notarytool, from appleid.apple.com, stored
#    under a profile name:
xcrun notarytool store-credentials mechkeys \
    --apple-id you@example.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx

# 3. A signed, notarised, stapled image, locally:
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export NOTARY_KEYCHAIN_PROFILE=mechkeys
./Scripts/build-app.sh && ./Scripts/make-dmg.sh
```

In CI the same thing happens from repository secrets: the `.p12` is carried
base64-encoded, imported into a throwaway keychain for the length of the job,
and deleted afterwards. `security set-key-partition-list` is not optional —
without it `codesign` stops to ask for permission and the job hangs until it
times out.

**Without a Developer ID**, the Gatekeeper wall and the permission problem come
apart, and only the second one has a free fix:

| | First launch of a download | Accessibility after an update |
|---|---|---|
| Ad-hoc | Blocked, "Apple could not verify…" | **Lost, every time** |
| Self-signed, stable | Blocked, the same way | Survives |
| Developer ID + notarised | Opens normally | Survives |

`Scripts/make-release-certificate.sh` produces the middle row: a self-signed
certificate valid for twenty years, packaged as a `.p12`, printed as the three
secrets the workflow reads — `SELF_SIGNED_IDENTITY`,
`SELF_SIGNED_CERTIFICATE_P12` and `SELF_SIGNED_CERTIFICATE_PASSWORD`. It is
used only when there is no Developer ID.

Two things about it are worth knowing. `codesign` will happily sign with a
certificate whose root nothing trusts, so no trust settings are needed on the
runner — but `security find-identity -v` lists *valid* identities only and will
not show it, which is why the workflow hands `build-app.sh` the identity name
through `SIGNING_IDENTITY` rather than letting it search. And re-issuing that
certificate produces a new leaf, which every existing user would have to grant
Accessibility against again: it is a long-lived secret, and losing it is not a
small thing.

### 9.2 Updating in place

`Sources/MechKeysCore/Update/` reads the latest release from the GitHub API,
compares its tag against `CFBundleShortVersionString` — the same string
`build-app.sh` writes out of `VERSION` — and, when the user asks, downloads the
disk image, verifies it against the `SHA256SUMS.txt` published beside it,
mounts it, and replaces the running bundle with `replaceItemAt`.

Decisions worth recording:

- **Versions are compared numerically, not as text.** `0.10.0` sorts before
  `0.9.0` as a string, which is exactly the comparison this project needs next.
- **A release with no checksums is not offered.** The app is not notarised, so
  there is no ticket and no Developer ID for macOS to check on its behalf. What
  can be checked is that the image came over HTTPS from the release and hashes
  to the digest published with it, and an image that does not is discarded
  rather than installed.
- **Drafts, pre-releases and non-version tags are skipped.**
- **A repository with no releases answers 404**, which is reported as "up to
  date" rather than as a failure.
- **The versioned image is preferred** over the fixed-name `MechKeys.dmg`,
  although the two are byte-identical: the versioned name is the one that says
  which release it came from, in the log and in the checksum lookup.
- **Quarantine is stripped from the staged copy** before it goes into place.
  Everything out of a downloaded image carries it, and the replaced app would
  be refused on relaunch.
- **The relaunch waits for this process to exit.** Two MechKeys would mean two
  event taps and two sounds per keypress, and the new copy cannot take the tap
  while the old one holds it.
- **The download is a `URLSessionDownloadTask`, not `URLSession.bytes`.** The
  latter means iterating the image one byte at a time and holding all of it in
  memory to no purpose.
- **What just happened is recorded, not remembered.** The bundle is replaced
  and restarted, so nothing survives in memory; the version each launch ran as
  is written to `UserDefaults`, and a launch that finds a newer one announces
  the update. That key is deliberately *not* part of `AppSettings`, which
  "Revert Changes" snapshots and restores.

The answer appears in a floating Liquid Glass panel rather than in the popover,
because the popover closes the moment anything else takes focus — including the
panel. A check started from the menu bar has nowhere in the popover to put its
result.

`--update-panel up-to-date|available|downloading|failed` puts each answer on
screen without waiting for a release that happens to be newer or a download
that happens to fail. `MECHKEYS_UPDATE_FEED` points the whole path — check,
download, verify, install, relaunch — at a local server.

### 9.3 Releases

Tagged `vX.Y.Z`. The workflow checks the tag matches `VERSION`, runs the tests,
builds, signs, notarises, and publishes the versioned image plus a fixed-name
`MechKeys.dmg` — GitHub only serves `releases/latest/download/<name>` for an
asset whose filename is identical in every release, which a versioned one can
never be — and a `SHA256SUMS.txt` that `Scripts/install.sh` verifies against.

Worth being clear-eyed about what that checksum buys: it proves the download is
the file that was published, and nothing about who published it.

## 10. Testing without a speaker

86 tests in 15 suites, none of which need audio hardware.

The interesting ones are `DampeningRenderTests`, which drive the **real**
`AVAudioEngine` graph — the same nodes, the same parameters, the same buffer
cache — through `AVAudioEngine`'s offline manual rendering mode, and measure
the output with an FFT. So the claims in §5 are measurements of the shipping
signal chain, not assertions about it.

They check that treble falls monotonically and by more than an order of
magnitude, that level does not follow it, that the onset does not move, that
the five profiles keep their brightness ordering, that large keys are deeper
than ordinary ones, that nothing clips, and that a manual DSP override reaches
the output.

Four defects were found this way and would not have been found otherwise: the
clipping in §5.5, the post-filter harmonics in §5.4, the brightness inversion
in §5.1, and — worst of the lot — §11's dead audio-unit parameters, which had
silently disabled the compressor, the limiter and the makeup gain entirely.

### 10.1 Two measurement mistakes worth recording

Both produced confident, wrong numbers, and both are the kind of thing that
quietly invalidates a test suite:

- **A sparse DFT.** Sampling 64 frequencies and calling it a spectrum aliases
  badly on broadband material. It reported Black as brighter than Yellow, which
  contradicts the samples' own spectral centroids. Replaced with a real
  16384-point FFT via vDSP.
- **A Hann window.** Correct for a continuous signal, wrong here: a Hann window
  is null at sample zero, so it attenuated the attack — precisely the part that
  distinguishes a clicky profile from a soft one. These one-shots already start
  and end at zero, so no window is needed at all.

### 10.2 Determinism

Offline rendering schedules the buffer "as soon as possible", which lands it in
whichever render block comes next — an 85 ms step at a 4096-frame block size.
Rendering only the window length then clipped the tail by that much, and every
derived measurement moved run to run. The fix is to render a generous budget
and take a fixed-length window from the first non-silent sample.

Separately, the suite is `.serialized`: Swift Testing runs suites in parallel
by default, and several `AVAudioEngine` graphs rendering at once contend enough
to jitter the offline scheduling.

## 11. Build constraints worth knowing

**`@State` is unavailable without Xcode.** In the macOS 26+ SDK, `@State` is a
Swift macro backed by a `SwiftUIMacros` compiler plugin that ships only inside
Xcode, not the Command Line Tools. MechKeys builds with either, so view-local
state uses `ViewState`, a one-value `ObservableObject` held by `@StateObject`,
which has the same lifetime and the same `$`-projected `Binding`. Every other
SwiftUI property wrapper works normally.

**`AVAudioUnitDynamicsProcessor` does not exist.** AVFoundation ships
convenience subclasses for EQ, reverb, delay and distortion, but not for
dynamics. The compressor and the limiter are instantiated from their Audio Unit
component descriptions and reached through `auAudioUnit.parameterTree`; the
older `AudioUnitSetParameter` route on `.audioUnit` is deprecated as of
macOS 27.

**An `AUParameter` cached before the unit is attached is dead.** This one cost
real time and is worth stating plainly. `AVAudioUnitEffect` exposes a perfectly
valid-looking `parameterTree` the moment it is constructed — seven parameters,
correct addresses, correct ranges, writes accepted without error. It is not the
tree the running unit reads from. Every write to those cached references was
silently discarded, which meant the compressor, the peak limiter and the whole
loudness-compensation system had never once taken effect. Nothing failed and
nothing logged; the makeup gain could be set anywhere from 0 to 40 dB with
*byte-identical* rendered output, which is what finally gave it away.

Parameters are therefore resolved from `auAudioUnit.parameterTree` on every
write. Writes happen on settings changes, never per keypress, so the lookup
costs nothing that matters.

**`kAXTrustedCheckOptionPrompt` cannot be touched from a nonisolated context.**
It is imported as a global `var` of a non-Sendable type, which Swift 6 refuses.
The key's spelling is API and cannot change, so it is written out as a string
literal.

## 12. Known limits

- **Secure input silences it.** While a password field has focus, macOS
  disables the event tap. This is correct and non-negotiable; the tap is
  re-enabled afterwards.
- **Ad-hoc signed builds lose Accessibility permission on every rebuild.** See
  §3.2. Not fixable without a Developer ID.
- **No per-application rules.** Sounds are on everywhere or nowhere.
- **Output device buffer size is not managed.** See §4.4 — deliberate.
- **Apple silicon only** in the published build, though nothing in the code is
  architecture-specific.
