# Changelog

All notable changes to MechKeys are recorded here. Versions are the commit
subjects, in `vX.Y.Z` form.

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
