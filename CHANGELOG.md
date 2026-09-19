# Changelog

All notable changes to MechKeys are recorded here. Versions are the commit
subjects, in `vX.Y.Z` form.

## v0.2.0

The application itself: menu bar, configuration window, onboarding, and a
build that produces a real `.app`.

### Added

- **Menu bar popover** with the three controls worth reaching for mid-task —
  switch, dampening, volume — plus Test Sound, keyboard-access status and
  launch at login.
- **Configuration window** in four tabs (Sound, Keys, Behaviour, General),
  built on `Form`/`.formStyle(.grouped)`. Everything applies live; "Save &
  Close" confirms and dismisses, and "Revert Changes" undoes the whole
  session's edits from a snapshot taken when the window opened.
- **Advanced dampening**: all six DSP parameters exposed behind a disclosure,
  with a manual-override mode seeded from the curve so switching to it is
  audibly a no-op.
- **Onboarding**: three screens — what it is, the one permission it needs,
  and done.
- **`Scripts/build-app.sh`** assembles `MechKeys.app` by hand from the Swift
  package: bundles all 150 samples into `Contents/Resources/Sounds`, renders
  the icon from `Scripts/make-icon.swift`, writes `Info.plist` with
  `LSUIElement`, and signs with the hardened runtime. No App Sandbox — a
  sandboxed process cannot create a `CGEventTap` at all.

### Changed

- **Swift 6.2 tools, Swift 6 language mode, macOS 26 minimum.** The interface
  is built on Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)` and
  `.glassProminent`), which does not exist before macOS 26. Built and run
  against the 26 and 27 SDKs.
- **`@Observable` throughout** instead of `ObservableObject`/`@Published`,
  with a `follow` helper re-arming `withObservationTracking` for the non-UI
  parts that react to settings changes.
- **Launch at login** now mirrors `SMAppService` rather than being persisted.
  The system owns that state, and the user can switch it off in System
  Settings; storing our own copy only created something to disagree with.
- Permission polling moved from `Timer` to a cancellable `Task`, which also
  lets the type clean up from a nonisolated `deinit`.

### Fixed

- Window activation no longer yanks focus from whatever the user is typing
  into. Only the first-launch welcome window insists; the configuration
  window, opened mid-task from the menu bar, activates politely.

## v0.1.0

Foundation: the sound library and the core engine.

### Added

- **Original sample library.** `Tools/generate_sounds.py` synthesises all 150
  bundled samples from a physical model of a keyswitch (click transient,
  keycap tick, bottom-out thump, damped case resonance, stabiliser rattle).
  Nothing is recorded, sampled or downloaded, so the assets carry no licensing
  encumbrance. 5 profiles × 6 key categories × 5 variants, mono 48 kHz 16-bit,
  ~2.5 MB total.
- **Sound profiles** — Red, Brown, Blue, Black, Yellow — each with a fixed
  acoustic fingerprint (`ProfileVoicing`) that the dampening chain reads, so
  filters are aimed at the frequency a given profile actually rings at.
- **Dampening model.** `DampeningParameters` plus a single `DampeningCurve`
  that interpolates all six DSP values from one 0…1 slider position, with a
  logarithmic cutoff sweep and loudness makeup so the control cannot be
  mistaken for a volume knob.
- **Audio engine.** Persistent `AVAudioEngine` graph: a pool of player nodes
  into a shared bus with a 4-band EQ and Apple's `AUDynamicsProcessor`.
  Transient shaping and ring-out are pre-rendered offline into a buffer cache;
  filters and compression are live parameter writes. A keypress allocates
  nothing and touches no disk. Survives output-device changes.
- **Keyboard monitor.** Listen-only `CGEventTap` on its own thread. Keycodes
  are classified to one of six categories inside the callback and discarded;
  nothing is stored, logged or transmitted.
- **Settings model.** One `Codable` `AppSettings` with range clamping,
  tolerant decoding, per-category overrides and snapshot/revert support.
- **Permissions and launch-at-login** via `AXIsProcessTrusted` and
  `SMAppService`, with polling that stops once permission is granted.
