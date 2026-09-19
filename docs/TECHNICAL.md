# MechKeys, technically

How the keyboard is watched, how the audio is built, and how dampening
actually works.

---

## 1. Permissions

MechKeys asks for exactly one permission, and it is unavoidable: **Accessibility**.

macOS gates `CGEvent.tapCreate` behind it, and there is no other supported way
for a process to learn that a key was pressed in another application. There is
no narrower permission to request.

What MechKeys deliberately does **not** request:

| Permission | Why not |
| --- | --- |
| Microphone | MechKeys plays audio, it does not record any. |
| Screen Recording | It never reads the screen. |
| Camera | Nothing to see. |
| Full Disk Access | It reads its own bundle and writes one `UserDefaults` key. |
| Input Monitoring | Not needed for a listen-only session tap. |

**The App Sandbox is deliberately off.** A sandboxed process is not permitted to
create a `CGEventTap` at all, so sandboxing MechKeys would mean it could never
hear a keystroke. The hardened runtime *is* on, which is what notarisation
requires and what the tap is happy with.

### The grant is keyed to the code signature

macOS records the Accessibility grant against the application's signature. An
ad-hoc signature (`codesign -s -`) is different on every build, so each rebuild
looks like a new application and has to be granted again. A Developer ID
identity is stable and does not have this problem — set
`DEVELOPER_ID_APPLICATION` when building.

---

## 2. The keyboard path

```
key down
   │
   ▼
CGEventTap (.listenOnly, .cgSessionEventTap)   ← own thread, own run loop
   │
   ├── keycode ──▶ KeyClassifier ──▶ KeyCategory (one of six)
   │                                      │
   │   keycode goes out of scope here ────┘
   │
   ├── repeat-mode and minimum-interval checks
   │
   ▼
KeyEvent { category, isRepeat, timestamp }
   │
   ▼
audio queue (DispatchQueue, .userInteractive)   ← callback returns immediately
```

### Why a dedicated thread

The tap's run loop source runs on a `Thread` of its own at
`.userInteractive`, not on the main run loop. Servicing it from the main run
loop would put every keystroke behind whatever SwiftUI happened to be doing,
and macOS disables a tap that takes too long to respond.

### What the callback does

Classify, check two rate limits, hand over a six-case enum, return. It performs
no allocation, no I/O and no audio work. `play` only enqueues onto the audio
queue; it never blocks the caller.

### Rate limiting

Two separate guards:

- **Repeat mode** — `silent` (the default) drops autorepeat events entirely,
  `throttled` lets them through subject to the interval, `everyRepeat` lets
  them all through.
- **Minimum interval** — a floor on the gap between any two sounds, 5–200 ms,
  defaulting to 22 ms. This is what stops an autorepeat storm or a deliberate
  mash from flooding the voice pool.

`everyRepeat` deliberately skips the floor, because that is what the setting
means.

### Privacy, by construction

`KeyEvent` has three fields: a six-case enum, a `Bool` and a `TimeInterval`.
There is nowhere in it to put a character or a keycode, so nothing downstream
*can* log one. Nothing is buffered, written to disk or transmitted, and the app
makes no network requests at all. Switching MechKeys off tears the tap down
rather than muting it.

---

## 3. Audio architecture

```
  [player 0] ─┐
  [player 1] ─┼─▶ bus ─▶ dynamics ─▶ EQ (4 bands) ─▶ limiter ─▶ mixer ─▶ out
  [player n] ─┘
```

One `AVAudioEngine`, built once at launch and alive for the life of the
process. There is no per-keypress player, no per-keypress file read and no
per-keypress node creation.

### The voice pool

`maximumVoices` (default 16) `AVAudioPlayerNode`s, all connected to the bus
mixer, all left in the *playing* state for the lifetime of the engine.
Scheduling a buffer on an already-playing node starts it immediately; calling
`play()` per keypress would add avoidable milliseconds.

A keypress claims whichever voice has been free longest. Under normal typing
one always is; under a deliberate mash the oldest is stolen with
`.interrupts`, so the new sound starts now rather than queueing behind the old
one.

### The buffer cache

Every sample is pre-processed and held as an `AVAudioPCMBuffer`, keyed by
category. The cache holds five variants × three micro-pitch renditions per
category — about 90 buffers, a few megabytes.

It is rebuilt only when something it depends on changes: profile, transient
reduction, resonance reduction, variation, or a per-category pitch trim. Those
inputs are quantised, and rebuilds are debounced by 60 ms, so dragging the
dampening slider re-renders once when the drag settles rather than sixty times
a second.

### Output device changes

`AVAudioEngineConfigurationChange` arrives when the user switches to AirPods,
unplugs a monitor, or changes the default output. The engine has already
stopped by then and the old connections reference a format that no longer
exists, so the graph is rebuilt from scratch. If the device is still coming up
— a Bluetooth device mid-connect, or a wake from sleep — restart is retried
with backoff up to five times.

### Latency

The budget is spent where it is visible: the event callback does almost
nothing, and the audio it triggers is a buffer that already exists. What
remains is the output device's own buffer, which MechKeys does not change —
that is a system-wide setting shared with every other application, and taking
it over for a keyboard sound effect would be rude.

---

## 4. Dampening

Dampening models packing a keyboard with foam, silicone and plate gaskets. It
is **not** a delay and **not** a volume cut.

### One curve, two anchor points

All six DSP values come from a single interpolation in `DampeningCurve`
between a *sharp* anchor (0%) and a *muted* anchor (100%). No profile-specific
or position-specific DSP number exists anywhere else in the codebase.

| Parameter | 0% | 100% |
| --- | --- | --- |
| High-frequency cutoff | 19 kHz | 1.25 kHz |
| High shelf gain | +1.5 dB | −23 dB |
| Transient softening | 0 | 0.88 |
| Resonance reduction | 0 | 0.92 |
| Compression | 0 | 0.80 |
| Low-mid body | 0 dB | +5 dB |

The cutoff is interpolated **logarithmically**, because pitch perception is
logarithmic; a linear sweep would do almost nothing for the first half of the
slider and then collapse.

Three parameters are eased rather than linear:

- **Transient softening leads** (`t^0.82`) — the first movement of the slider
  should already take the edge off the attack.
- **Body lift lags** (`t^1.45`) — otherwise low dampening just sounds boomy.
- **Resonance reduction lags** (`t^1.35`) — measured: choking the case ring
  removes low-frequency tail *faster* than the filter removes treble, so
  without this the sound got fractionally brighter between 0% and 12%.

### Split across two places, for a reason

| Where | What | Why there |
| --- | --- | --- |
| **Offline, in the buffer cache** | Transient softening, ring-out | These reshape the one-shot itself. Doing the attack softening with a compressor would need lookahead, and lookahead is latency. |
| **Live, on the shared bus** | Low-pass, high shelf, resonance notch, low-mid shelf, compression, limiting | Parameter writes, so they take effect on the very next keypress with no rebuild. |

**Transient softening** attenuates the first sample by the reduction amount and
recovers to unity across a 7 ms window on a smoothstep curve. The onset stays
at sample zero — the sound arrives less sharply, never later. The smoothstep
matters: a corner in the gain curve would itself be audible as a click.

**Ring-out** multiplies everything after 9 ms by an extra exponential decay,
with a time constant that sweeps down to 18 ms at full reduction.

### The resonance notch is per profile

A Blue rings at about 5.4 kHz and a Black at about 2.1 kHz. One fixed notch
would dampen one and hollow out the other, so each profile carries its own
`ProfileVoicing` — resonance frequency, Q, body frequency, brightness and
transient sensitivity — and the chain aims at those.

### Order matters: EQ after dynamics

The EQ sits *after* the compressor. With it in front, gain-riding a sharp
transient generated harmonics that landed **above** the low-pass corner, and
high-frequency energy rose again past 75% dampening instead of continuing to
fall — audible as crunch on a setting that is supposed to be a soft thud.
Moving the EQ after the dynamics took the end-to-end treble reduction from 16×
to 168×, monotonic throughout.

### Loudness compensation, and the limiter

Filtering away the top end makes a sound quieter, and a dampening control that
also turns the volume down is indistinguishable from the volume control. So
makeup gain rises to +7.5 dB across the slider.

That gain, plus the low-mid shelf, can push a loud profile past full scale —
measured at 1.007 on a Blue keypress. An `AUPeakLimiter` sits last in the chain
as the honest fix. Pre-emptively turning everything down to leave headroom
would make the app quiet for the sake of a case that only occurs at the
extremes.

### How this is verified

`DampeningRenderTests` drives the real graph through `AVAudioEngine`'s offline
manual rendering mode — no output device, no speaker, no audio hardware — and
measures the result with an FFT. It asserts that:

- treble falls monotonically across the slider, by more than 100× end to end;
- level does **not** fall proportionally, so it is not a volume control;
- the onset moves by under a millisecond, so it is not a delay;
- the five profiles keep their brightness ordering;
- large keys are deeper than ordinary ones;
- nothing clips;
- a manual DSP override reaches the output.

These are measurements of the shipping signal chain, not assertions about it.

---

## 5. Natural variation

Repeating one recording is the single thing that makes key sounds feel fake.

Per keypress: one of five variants, never the same one twice in a row (a single
re-roll — forcing a change every time would itself be a detectable pattern),
with up to ±2 dB of level and ±18 cents of pitch.

The pitch renditions are pre-rendered into the cache, so pitch variation costs
nothing at playback time. At variation 0 the slider reads *Identical* and means
it: the same sample, every time.

---

## 6. Settings

One `Codable` `AppSettings` struct, stored as a single JSON blob in
`UserDefaults`. A single blob rather than a scatter of `@AppStorage` keys,
because that is what makes an atomic snapshot — and therefore "Revert Changes"
— possible.

- Every value is clamped on assignment and again on decode, so an out-of-range
  number can never reach an audio unit.
- Decoding is tolerant: a settings file written by an older build loads, with
  anything missing falling back to its default, rather than being thrown away.
- `launchAtLogin` is **not** in the struct. That state belongs to
  `SMAppService`; the app mirrors it, because the user can also change it in
  System Settings and a stored copy would only be something to disagree with.

---

## 7. Distribution

`Scripts/build-app.sh` assembles the bundle by hand — the project is a Swift
package, not an Xcode project. It copies the binary, bundles the 150 samples
into `Contents/Resources/Sounds`, renders the icon, writes `Info.plist` with
`LSUIElement`, and signs with the hardened runtime.

`Scripts/make-dmg.sh` packages it, optionally signs and notarises.

**Notarisation** is what stops Gatekeeper refusing the app on someone else's
Mac. Without it every download is met with "Apple could not verify MechKeys is
free of malware", and the only way past is Privacy & Security → Open Anyway. It
needs a paid Developer ID. The build works without one and skips the step.

Releases are tagged `vX.Y.Z`; the workflow checks the tag matches `VERSION`,
publishes the versioned image plus a fixed-name `MechKeys.dmg` (so
`releases/latest/download/MechKeys.dmg` is a permanent link), and a
`SHA256SUMS.txt` that `Scripts/install.sh` verifies against.

---

## 8. Build constraints worth knowing

**`@State` is unavailable without Xcode.** In the macOS 26+ SDK, `@State` is a
Swift macro backed by a `SwiftUIMacros` compiler plugin that ships only inside
Xcode, not the Command Line Tools. MechKeys builds with either, so view-local
state uses `ViewState`, a one-value `ObservableObject` held by `@StateObject`,
which has the same lifetime and the same `$`-projected `Binding`. Every other
SwiftUI property wrapper works normally.

**`AVAudioUnitDynamicsProcessor` does not exist.** AVFoundation ships
convenience subclasses for EQ, reverb, delay and distortion, but not dynamics.
The compressor and the limiter are instantiated from their Audio Unit component
descriptions and reached through `auAudioUnit.parameterTree`; the older
`AudioUnitSetParameter` route is deprecated as of macOS 27.
