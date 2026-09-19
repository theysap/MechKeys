<div align="center">

<img src="docs/images/icon.png" width="128" alt="MechKeys icon">

# MechKeys

**Mechanical keyboard sounds for macOS.**

Choose what switch your Mac sounds like, then decide how acoustically dampened
it feels. It lives in the menu bar, and it never records what you type.

<img src="docs/images/popover.png" width="320" alt="The menu bar popover: switch, dampening, volume and Test Sound">

</div>

---

## What it does

MechKeys plays a short mechanical keypress sound for every key you press,
anywhere in macOS — Safari, Terminal, VS Code, Slack, Notes, a Spotlight query.

**Five switch profiles**, each with its own transient, body and ring:

| Profile | Character | |
|---|---|---|
| **Red** | `tap / clack` | Linear and smooth. Quiet, rounded bottom-out, soft transient. |
| **Brown** | `tick / clack` | Tactile with a little texture. Moderate attack, no exaggerated click. |
| **Blue** | `CLICK` | Tactile and clicky. The loudest and sharpest, with a strong high-frequency attack. |
| **Black** | `thock` | Heavy linear. Deep body, substantial bottom-out, less sharpness. |
| **Yellow** | `clack` | Smooth linear, between Red and Black in perceived weight. |

They are original synthesised sounds inspired by the character of common switch
types, not affiliated with or endorsed by any manufacturer.

### The dampening control is the point

This is the part that is not just a preset picker. The slider models packing a
keyboard with foam, silicone and plate gaskets — and it is neither a delay nor
a volume control.

```
Dampening

Sharp ─────────────●──────────── Muted
                   42%
```

| Position | What you hear |
|---|---|
| **0%** | Undampened. Full high-frequency energy, sharp transient, a long ring. |
| **25%** | Lightly dampened. Softened transient, top end pulled back a little. |
| **50%** | Noticeably smoother. Reduced sharpness and resonance, fuller and rounder. |
| **75%** | Strongly softened. Highs substantially reduced, very little ring left. |
| **100%** | Heavily dampened. Soft attack, filtered highs, minimal ringing — a muffled thud. |

Underneath, one slider position drives six DSP parameters at once: a low-pass
that sweeps logarithmically from 19 kHz down to 1.25 kHz, a high shelf, a
parametric cut aimed at *that profile's own* ring, a low-mid shelf that puts
body back, gentle compression, and transient softening applied to the sample
itself. All six are exposed under **Advanced** if you want to set them by hand.

Measured on the shipping signal chain, end to end: the proportion of energy
above 3 kHz falls from 0.48 to 0.010 — about **46×** — monotonically, while the
level does not follow it down, and the sound still starts in the very first
sample. Those three properties are asserted by tests on every run, because
"not a volume control" and "not a delay" are claims that are easy to make and
easy to quietly break.

### Different keys, different sounds

The spacebar is pitched down and rattles like a stabilised key. Return is
heavier, Delete and Tab sit in between. Modifiers are silent by default —
they fire constantly while you type, and a sound on every one gets tiring fast.

Each category has its own level and pitch trim, and can be switched off
entirely.

### It does not sound like a loop

Five separate recordings per key, never the same one twice in a row, with up to
±2 dB of level and ±18 cents of pitch on each press. Turn variation to zero and
it means it: the same sample, every time.

<div align="center">
<img src="docs/images/configure.png" width="560" alt="The configuration window, Sound tab">
</div>

## Requirements

- macOS 26 or later
- Apple silicon

MechKeys is a menu bar application. It has no Dock icon.

## Installing

One line. It checks this Mac can run MechKeys, verifies the download against
the checksum published beside it, and puts the app in Applications:

```sh
curl -fsSL https://theysap.com/install/mechkeys | bash
```

Nothing is blocked on first launch this way: macOS attaches its quarantine flag
to what a *browser* downloads, not to what `curl` fetches, so the app opens
straight away.

That script is [`Scripts/install.sh`](Scripts/install.sh) in this repository,
and theysap.com serves a copy of it as plain text, so you can read it before
piping it into a shell. `MECHKEYS_VERSION` pins a version, and
`MECHKEYS_NO_LAUNCH=1` skips the launch at the end.

### Or by hand

Download the `.dmg` from [Releases](../../releases), open it, and drag MechKeys
into Applications. Every release also publishes the same image under a fixed
name, so [`releases/latest/download/MechKeys.dmg`](../../releases/latest/download/MechKeys.dmg)
is always the newest build.

### That first launch is blocked. Here is how to get past it

A `.dmg` downloaded in a browser carries the quarantine flag, so macOS will
refuse to open what is inside it, with *"Apple could not verify 'MechKeys' is
free of malware that may harm your Mac or compromise your privacy."* The only
buttons are **Done** and **Move to Bin**.

That wording is alarming and the dialog offers no way forward, so to be plain
about what it means: macOS is not reporting that it found anything. It is
reporting that it cannot tell who built the app. MechKeys is **ad-hoc signed
and not notarised**, because notarising requires a paid Apple Developer ID.
`codesign -dvv` reports `Signature=adhoc` with no authority, and `spctl -a`
returns `rejected` — so Gatekeeper refuses, exactly as designed. The
Control-click → Open shortcut that used to bypass this was removed in macOS 15.

**To open it, once:**

1. Double-click MechKeys, and click **Done** on the warning.
2. Open **System Settings → Privacy & Security** and scroll down to Security.
   It now says *"MechKeys was blocked to protect your Mac."*
3. Click **Open Anyway**, authenticate, and confirm.

Or, if you would rather do it in one line — this is exactly what the steps above
amount to, removing the quarantine flag macOS attached to the download:

```sh
xattr -dr com.apple.quarantine /Applications/MechKeys.app
```

**This is a first-launch problem only**, and it does not arise at all if you
install with the `curl` line above.

### Making it stop happening

Only one thing removes that dialog, and it is **notarisation** — which needs a
paid Apple Developer Program membership. Signing alone does not do it:

| | First launch of a downloaded copy |
|---|---|
| Ad-hoc signed — **what is published today** | Refused: *"Apple could not verify…"*, with only Done and Move to Bin |
| Developer ID signed, not notarised | Still refused. A signature on its own has not been enough since macOS 10.15 |
| Developer ID signed **and notarised** | *"…is an app downloaded from the Internet. Are you sure you want to open it?"* → **Open** |

The build and the release workflow already do the whole of it — signing,
notarising, stapling, and importing the certificate on a clean CI runner —
given the right repository secrets.
[TECHNICAL.md](TECHNICAL.md#91-distribution-and-the-gatekeeper-wall) has the
exact steps.

Then open the popover from the menu bar icon and turn on **Launch at Login**.

## Permissions

MechKeys asks for exactly one permission, and it is unavoidable.

| Permission | Asked when | What it is for | Without it |
|---|---|---|---|
| **Accessibility** | First launch | Creating the listen-only event tap that reports *that* a key was pressed | No sounds at all. Everything else — profiles, Test Sound, settings — still works |
| **Login item** | You turn on *Launch at Login* | Starts the app when you log in, through `SMAppService` | Start it yourself |

macOS gates `CGEvent.tapCreate` behind Accessibility, and there is no other
supported way for a process to learn that a key was pressed in another
application. There is no narrower permission to ask for.

**What MechKeys does with it:**

- The tap is created **listen-only**. macOS will not let a listen-only tap
  modify, block or inject keystrokes even if it tried to.
- Inside the callback the keycode becomes one of six categories — standard,
  space, enter, backspace, tab, modifier — and then goes out of scope.
- The value handed to the audio system is that six-case enum. `KeyEvent` has
  three fields, and there is nowhere in it to put a character. Nothing
  downstream *can* log one.
- Switching MechKeys off does not mute it. The event tap is torn down.

In particular:

- **No microphone.** MechKeys plays audio; it does not record any.
- **No Screen Recording, Camera, or Full Disk Access.** It reads its own
  bundle and writes one `UserDefaults` key.
- **No network access of any kind.** No analytics, no crash reporting, no
  update check, no account. The app makes no requests at all, so there is
  nowhere for anything to go even in principle.
- **The App Sandbox is deliberately off**, because a sandboxed process is not
  permitted to create a `CGEventTap` at all. The hardened runtime is on.

Changed your mind? System Settings → Privacy & Security → **Accessibility** →
MechKeys.

## Settings

The popover carries the three things worth changing mid-task. **Configure…**
opens the rest.

| Tab | What is in it |
|---|---|
| **Sound** | Switch profile, dampening and its six advanced DSP parameters, master volume |
| **Keys** | Modifier sounds, and per-category enable / level / pitch for all six key categories |
| **Behaviour** | Key-repeat handling, minimum interval, variation amount, overlapping voices |
| **General** | Permission status, launch at login, privacy summary, reset, quit |

Everything applies immediately. **Save & Close** confirms and dismisses the
window — MechKeys keeps running in the menu bar. **Revert Changes** undoes
everything since the window was opened, from a snapshot taken when it opened.
**Quit MechKeys** exits entirely.

<div align="center">
<img src="docs/images/onboarding.png" width="440" alt="The first-run welcome screen">
</div>

## How it works

A keypress has to become a sound fast enough that the two feel simultaneous, so
the work is arranged to happen everywhere except on the key path.

```
key down
   │
   ▼
CGEventTap (.listenOnly)          ← its own thread, its own run loop
   │  classify → KeyCategory, check two rate limits, return
   ▼
audio queue
   │  pick a pre-processed buffer, pick a free voice, schedule
   ▼
persistent AVAudioEngine graph
```

The event callback does no allocation, no file I/O and no audio work — it is
also the latency budget for the whole app, and macOS disables a tap that takes
too long to respond. The audio graph is built once at launch and stays alive;
there is no per-keypress player node and no per-keypress file read.

The dampening chain is split in two, by necessity. Transient softening and
ring-out reshape the one-shot itself, so they are pre-rendered offline into a
buffer cache whenever the relevant settings change. The filters, compression
and limiting live on a shared bus, so moving the slider is a handful of
parameter writes and takes effect on the very next keypress.

### Further in

[**TECHNICAL.md**](TECHNICAL.md) covers the whole of it: the event path and what
is deliberately not retained, the audio graph, the dampening curve and why each
parameter is eased the way it is, why the EQ sits after the compressor, how the
samples are synthesised, and how the audio claims in this README are measured
without a speaker.

## Building

Only the Command Line Tools are needed; Xcode is not.

```sh
swift build                 # build
./Scripts/test.sh           # run the tests
./Scripts/build-app.sh      # assemble dist/MechKeys.app
./Scripts/make-dmg.sh       # package dist/MechKeys-<version>.dmg
```

To sign with a real identity, set `DEVELOPER_ID_APPLICATION` before building:

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
./Scripts/build-app.sh
```

Without it the bundle is ad-hoc signed, which runs — but macOS keys the
Accessibility grant to the code signature, and an ad-hoc signature changes on
every build, so **each rebuild has to be granted permission again**.

### The sounds

All 150 bundled samples are synthesised by
[`Tools/generate_sounds.py`](Tools/generate_sounds.py) from a physical sketch of
a keyswitch. Nothing is recorded, sampled or downloaded, so there is no
licensing encumbrance on any of it — see [assets/LICENSES.md](assets/LICENSES.md).

```sh
python3 Tools/generate_sounds.py    # needs numpy
```

They are committed so that a clone builds without Python. The generator is
deterministic, and CI checks the committed `.wav` files are byte for byte what
it produces.

### Development

```sh
./Scripts/install-hooks.sh                                  # format, build and test before each commit
dist/MechKeys.app/Contents/MacOS/MechKeys --popover         # the popover, in an ordinary window
dist/MechKeys.app/Contents/MacOS/MechKeys --configure       # straight to the configuration window
dist/MechKeys.app/Contents/MacOS/MechKeys --onboarding      # the first-run flow again
```

Those flags exist because capturing a menu bar popover otherwise needs
screen-recording permission, which makes the UI awkward to inspect any other
way. The images in this README were taken with them.

Note that view-local state lives in `ViewState` rather than `@State`: `@State`
became a macro in the macOS 26 SDK and its plugin ships only with Xcode, not
with the Command Line Tools.

[QA.md](QA.md) has the manual checklist for what the tests cannot reach — real
keyboards, real audio devices, and behaviour over hours.

## Contributing

Commit subjects are the version the commit brings the project to — `v0.4.0`,
`v1.0.0` — with the explanation in the body. The `commit-msg` hook enforces it,
and `CHANGELOG.md` is kept up to date alongside.

## License

MIT. See [LICENSE](LICENSE).
