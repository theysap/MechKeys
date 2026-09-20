# Changelog

All notable changes to MechKeys are recorded here. Versions are the commit
subjects, in `vX.Y.Z` form.

## v1.0.1

### Added

- **A check that theysap.com is still serving this repository's install
  script.** The one-line installer in the README points at
  `theysap.com/install/mechkeys`, which serves its own copy of
  `Scripts/install.sh` rather than redirecting here. Nothing made the two
  stay identical, and a drifted copy is a pipe-to-bash script doing something
  other than what this repository says it does — the one kind of drift that
  must not go unnoticed. The new workflow fetches the served copy and diffs
  it, on any push touching the script and again daily, since the served side
  can change with no commit here at all. A mismatch fails and prints the
  diff; being unreachable only warns, because a transient network failure
  should not redden an unrelated build. It also warns if the copy stops being
  served as `text/plain`, since the README's promise is that you can read it
  before piping it into a shell.

  As of this commit that URL returns **404**, so the check warns rather than
  fails. Until it is published, every new user gets the Gatekeeper wall that
  a `curl` install avoids entirely — macOS quarantines what a browser
  downloads, not what `curl` fetches.

## v1.0.0

The first stable release. `v0.10.0` has the substance of what changed; this
marks it as finished and settles the two things that were still unverified.

### Added

- **Traffic lights on the update panel**, drawn inside the glass rather than
  taken from the window: the panel has no title bar for AppKit's own buttons
  to sit in, because the glass card is what defines its shape. All three are
  there, but only the red one does anything — there is nothing to minimise a
  320-point notice into and nothing to zoom it to — so the other two are
  drawn in the grey macOS itself uses for a disabled window button rather
  than in full colour. It also means *Downloading* and *Installing*, the two
  states that offered no button at all, now have a way out. Escape closes the
  panel too, which had to be wired up by hand: AppKit routes Escape to
  `performClose:`, which looks for a real close button and beeps when it
  cannot find one.

### Fixed

- **A race in the offline render that made CI fail at random**, and had done
  since `v0.7.0` — two of the last three tagged builds died on it. The
  measurement harness started every voice with an empty queue and *then*
  scheduled a buffer into one with `.interrupts`. An `AVAudioPlayerNode`
  processes `play()` asynchronously, so on a machine slow enough to lose the
  race the interrupt reached the node before its own start had been handled
  and the buffer was dropped, rendering silence. It passed on a developer
  machine every time and failed on a CI runner about half the time, in
  whichever tests happened to lose. The buffer is now scheduled first and
  that one voice started after, which is the documented order. The error
  raised when a render comes out silent also says how many frames it got and
  what was in the buffer cache, because "the graph rendered only silence" on
  its own sent one investigation down three wrong paths.

### Changed

- **The disk image window is a plain grainy off-white field.** The graphite
  keyboard row that hung from its top edge is gone: it competed with the app
  icon sitting right below it, and the app icon is the only mark the window
  needs. The grain is generated per *point* and written across each
  `scale × scale` block of pixels, so the 1x and 2x representations carry
  texture of the same physical size rather than the Retina one looking twice
  as fine. The generator is seeded with a fixed value, so re-rendering
  committed artwork produces a byte-identical file instead of a spurious
  diff.

### Verified

Neither of these was provable when the code was written, and both are load
bearing, so they were settled before tagging:

- **An update keeps the Accessibility grant.** Building twice and replacing
  `/Applications/MechKeys.app` in place produced a byte-identical designated
  requirement — `identifier "com.mechkeys.app" and certificate root = H"…"` —
  and cost no permission. This is the whole reason releases are signed with a
  stable identity rather than ad-hoc.
- **The updater installs.** `UpdateInstaller.install` was run for real against
  a local release: downloaded, checksum-verified, mounted, copied out,
  quarantine stripped, the running bundle replaced with `replaceItemAt`, the
  image unmounted and the new copy relaunched. The bundle went from 1.0.0 to
  2.0.0 with nothing left mounted behind it.

## v0.10.0

An in-app updater, the release signing it turns into a correctness
requirement, and thirteen keys that never made a sound.

### Added

- **Check for Updates**, in the menu bar popover and in Configure → General.
  MechKeys reads its own latest release tag from the GitHub API, and the
  answer arrives in a floating Liquid Glass panel: *You're up to date*,
  *Update available* with **Download & Restart**, or *Update failed* with
  **Retry**. It is a panel rather than part of the popover because the popover
  closes the instant anything else takes focus, so a check started from the
  menu bar has nowhere in it to put a result.
- **Installing an update in place.** The disk image is downloaded, checked
  against the `SHA256SUMS.txt` published beside it — and discarded if they
  disagree — then mounted, stripped of its quarantine flag, and swapped over
  the running bundle. The relaunch waits for the old process to exit, because
  two copies would mean two event taps and two sounds per keypress. The first
  launch afterwards says which version landed.
- **Automatic checking**, a few seconds after launch and every six hours,
  silent unless it finds something. `Check for updates automatically` in
  Configure → General turns it off, and with it off MechKeys makes no network
  request at all unless asked.
- **The running version** at the bottom of the popover. It is
  `CFBundleShortVersionString`, written from `VERSION`, which is the release
  tag — so what the menu bar says matches what GitHub lists.
- **`Scripts/make-release-certificate.sh`**, which issues the stable
  self-signed identity every release is signed with and prints the three
  repository secrets the workflow reads. `build-app.sh` takes any identity
  through `SIGNING_IDENTITY`, and the release workflow imports either that or
  a Developer ID into a throwaway keychain.
- **`--update-panel up-to-date|available|downloading|failed`** puts each
  answer on screen without waiting for a release that happens to be newer or a
  download that happens to fail, and `MECHKEYS_UPDATE_FEED` points the whole
  path at a local server.
- **A disk image window that looks like something.** A drawn background —
  a graphite keyboard row hung from the top edge, one key struck, the app
  icon's two sound arcs coming off it — with MechKeys and the Applications
  folder arranged on an arrow between them. `Scripts/make-dmg-background.swift`
  renders it at 1x and 2x, `Scripts/make-dmg-layout.sh` drives Finder once to
  produce the window layout, and both results are committed, so `make-dmg.sh`
  and the build machine never touch Finder or need automation permission.
- **A CI guard against publishing an unsigned release.** A tagged build now
  fails outright if neither a Developer ID nor a self-signed certificate is
  configured, rather than quietly shipping an ad-hoc image that would take
  away the keyboard access of everyone who updates to it.
- 28 tests covering version comparison, the release feed, checksum parsing,
  retry routing, the post-update announcement and the top-row keys. 86 in
  total.

### Fixed

- **`MechKeys --diagnose` blamed the wrong thing.** Accessibility is granted
  to the *responsible* process, and a binary exec'd from a shell is the
  terminal's responsibility, not its own — so running the command in a
  terminal reported whether the terminal had permission and concluded "no
  access" about an app that was working. It now notices it was not launched
  by launchd, says so, and stops issuing a verdict it cannot support.
- **`Scripts/make-dev-certificate.sh` never worked**, so neither did the fix
  it exists to apply. It packaged the identity with an empty PKCS#12
  passphrase, and OpenSSL and Apple's Security framework encode an empty
  password differently before computing the MAC — an empty byte string on one
  side, the two-byte UTF-16 terminator on the other. `security import` failed
  with "MAC verification failed during PKCS12 import (wrong password?)",
  which points at the one thing that was not wrong. It now uses a random
  passphrase, thrown away at the end of the script. It also no longer runs
  `sudo security add-trusted-cert`: codesign signs perfectly well with an
  untrusted self-signed certificate, and the designated requirement it
  produces — `certificate root = H"…"` — is the stable one either way. Trust
  only decided whether `security find-identity -v` listed the identity, so
  `build-app.sh` looks it up without `-v` and nothing is added to the System
  trust store. The script needs no password at all now.
- **F1, F2 and F7 to F12 made no sound**, and the reason is not obvious: on
  an Apple keyboard the brightness, media and volume keys are not key-downs
  at all. The hardware reports them as `NX_SYSDEFINED` events, which a tap
  asking for `keyDown` never sees — which is exactly why F3 to F6 worked and
  the eight keys around them did not. The tap now asks for them too.
  `CGEventType` has no case for that event, so the mask asks for it by number
  and the callback matches it by raw value. Reading which key it was needs
  `NSEvent`, because `CGEvent` exposes no field for `data1`; that is the only
  allocation in the monitor, and an ordinary keystroke never reaches it. Caps
  Lock and the power key are deliberately excluded — the first has an aux
  code *and* a `flagsChanged` and would sound twice, and the second is Touch
  ID on most Macs.
- **Shift, Control, Option, Command and Caps Lock were silent** for a much
  duller reason: modifier sounds were simply off by default. The default is
  now on, with the switch still in Configure → Keys for anyone who finds them
  tiring. Note that a changed default reaches **fresh installs only** —
  settings written by an earlier build already carry
  `playModifierSounds: false`, and decoding deliberately prefers a stored
  value over a changed default. There is no migration, because a stored
  `false` cannot be told apart from a deliberate one.
- The top row draws from the ordinary sample pool. There is no recording of
  its own to reach for — the upstream packs contain four recordings in total,
  of an ordinary key, the spacebar, Return and Delete, and nothing under any
  name for a modifier or a function key. `assets/LICENSES.md` records that, so
  the next person does not go looking.

### Changed

- **The privacy claim is now precise rather than absolute.** README,
  `TECHNICAL.md` §2 and the in-app privacy list said MechKeys made no network
  requests of any kind, which the updater makes untrue. They now say what it
  does request — one public releases document, and an image only when asked —
  and that nothing is sent.
- **Releases are signed with a stable identity, not ad-hoc.** This is not
  cosmetic: macOS keys the Accessibility grant to the code signature, and an
  updater that replaces the bundle would have revoked the user's keyboard
  access on every update, silently, with the switch still on in System
  Settings. An ad-hoc signature carries the binary's hash and changes every
  build; a certificate-backed one does not. Self-signed is enough for this —
  it does not remove the Gatekeeper wall, which only notarisation does, but
  the two problems are separate and this is the half that can be fixed for
  free. `TECHNICAL.md` §9.1 has the table.
- **Modifier and function keys are described accurately** in the key-category
  summaries and in the Configure → Keys footer, which until now told the user
  that modifier sounds were off by default.
- `CURRENT.md`, the working notes for the next session, is gitignored. It was
  only ever untracked by habit.

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
