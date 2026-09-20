# Manual QA checklist

Automated tests cover the settings model, key classification, the DSP, and the
rendered output of the audio graph (`./Scripts/test.sh`, 86 tests). This file
covers what they cannot: real keyboards, real audio devices, and the way the
app behaves over hours rather than milliseconds.

Run through this before tagging a release.

## Setup

- [ ] `./Scripts/test.sh` passes
- [ ] `swift format lint --recursive --strict Sources Tests` is clean
- [ ] `./Scripts/build-app.sh` produces `dist/MechKeys.app`
- [ ] `MechKeys.app/Contents/Resources/LICENSE-sounds.txt` is present
- [ ] `./Scripts/make-dmg.sh` produces a disk image that mounts

## First run

- [ ] App launches with no Dock icon
- [ ] Menu bar icon appears
- [ ] Welcome window appears on first launch and is frontmost
- [ ] "Get Started" leads to the permission screen
- [ ] "Open Accessibility Settings" opens the right System Settings pane
- [ ] Granting permission advances the flow without clicking anything
- [ ] "Skip for now" works, and the app stays quiet afterwards
- [ ] "Start MechKeys" closes onboarding and the app starts listening
- [ ] Welcome window does **not** appear on the second launch

## Menu bar

- [ ] Popover opens on click
- [ ] Toggle switches sound on and off immediately
- [ ] Icon fills when on, outlines when off
- [ ] Switching the icon-state preference off stops it filling
- [ ] Test Sound plays with the current settings
- [ ] Keyboard Access row shows the correct status and opens System Settings
- [ ] Launch at Login checkbox reflects System Settings, both ways
- [ ] Configure… opens the window and brings it to the front
- [ ] Quit MechKeys exits, and sounds stop

## Typing, system-wide

Type in each and confirm sound:

- [ ] Safari
- [ ] Chrome
- [ ] Terminal
- [ ] Ghostty
- [ ] VS Code
- [ ] Slack
- [ ] Discord
- [ ] Notes
- [ ] Mail
- [ ] Spotlight
- [ ] A password field — macOS secure input disables the tap; confirm the app
      recovers afterwards rather than staying silent

## Every key makes a sound

The point of this section is the keys that are easy to miss. Run it on a
laptop keyboard, where the top row is media keys by default.

- [ ] Shift, Control, Option, Command, Caps Lock and fn all sound, left and right
- [ ] A modifier sounds once when pressed, and not again when released
- [ ] Holding Shift while typing does not re-sound the Shift
- [ ] Caps Lock sounds going on *and* going off, exactly once each
- [ ] **F1 and F2** (brightness) sound, and still change the brightness
- [ ] **F7, F8, F9** (media) sound, and still control playback
- [ ] **F10, F11, F12** (volume) sound, and still change the volume
- [ ] F3, F4, F5, F6 sound
- [ ] Holding F12 to ramp the volume does not machine-gun in Silent mode
- [ ] Caps Lock does not sound twice
- [ ] The power / Touch ID key does **not** sound
- [ ] With "Use F1, F2, etc. as standard function keys" switched **on** in
      System Settings, the whole top row still sounds
- [ ] Turning "Play modifier sounds" off silences the modifiers and nothing else

## Key categories

- [ ] Space is deeper and has a stabiliser rattle
- [ ] Return is heavier than a letter
- [ ] Delete is slightly deeper
- [ ] Tab is close to a letter, a touch deeper
- [ ] Modifiers are silent by default
- [ ] Enabling modifier sounds makes Shift/Control/Option/Command audible
- [ ] Caps Lock sounds on both press and release
- [ ] Disabling a category in Keys silences exactly that category
- [ ] Per-category level and pitch trims are audible

## Settings behaviour

- [ ] Profile change takes effect on the very next keypress
- [ ] Dampening change takes effect immediately
- [ ] Volume change takes effect immediately
- [ ] Dragging the dampening slider does **not** trigger sounds by itself
- [ ] Advanced → manual mode is audibly a no-op at the moment it is switched on
- [ ] "Match Slider" restores the curve values
- [ ] Revert Changes restores everything from when the window opened
- [ ] Save & Close keeps the app running in the menu bar
- [ ] Reset Settings restores defaults but keeps onboarding done
- [ ] All settings survive a quit and relaunch

## Dampening, by ear

- [ ] 0% is sharp and ringing
- [ ] 100% is a soft thud with almost no ring
- [ ] 100% is **not** simply quieter than 0%
- [ ] No sound is delayed at any position
- [ ] No crunch or distortion at the muted end
- [ ] Every profile stays recognisable across the whole slider
- [ ] Each profile sounds like the switch it is named after

## Robustness

- [ ] Very fast typing does not crash or stutter
- [ ] Holding a key does not flood the audio engine (Silent, the default)
- [ ] Throttled and Every repeat behave as described
- [ ] Mashing many keys at once degrades gracefully
- [ ] Connecting AirPods keeps sound working
- [ ] Disconnecting AirPods keeps sound working
- [ ] Switching output device in Sound settings keeps sound working
- [ ] Unplugging an external monitor with speakers keeps sound working
- [ ] Sleep and wake keeps sound working
- [ ] Fast user switching keeps sound working
- [ ] Running for several hours keeps sound working

## Performance

- [ ] CPU is ~0% when idle and not typing
- [ ] CPU stays low during sustained fast typing
- [ ] Memory is stable over a long session, with no growth while typing
- [ ] No audible latency between keypress and sound

## Accessibility

- [ ] VoiceOver reads the menu bar icon state
- [ ] VoiceOver reads every slider's label and value
- [ ] VoiceOver reads the profile rows and which is selected
- [ ] VoiceOver reads the keyboard access status
- [ ] Every control is reachable by keyboard

## Diagnostics

- [ ] `MechKeys --diagnose` run **from a terminal** prints the responsible-process
      warning and does not claim "no access" outright
- [ ] The same command, with the terminal granted Accessibility, agrees with
      the popover

## Updates

Each answer can be put on screen without waiting for a real release:
`dist/MechKeys.app/Contents/MacOS/MechKeys --update-panel up-to-date|available|downloading|failed`.
The full path is exercised against a local server with `MECHKEYS_UPDATE_FEED`
pointing at a `releases/latest` JSON document.

- [ ] The version at the bottom of the popover matches `VERSION` and the tag
- [ ] **Check for Updates…** opens the panel; the popover closes behind it
- [ ] With no newer release: "You're up to date", naming the running version
- [ ] With a newer release: the version is named, **Download & Restart** is offered
- [ ] **Later** closes the panel and does not ask again until the next check
- [ ] Offline: "Update failed", and **Retry** tries again rather than doing nothing
- [ ] A corrupted image is refused on the checksum and reported, not installed
- [ ] A real update replaces `/Applications/MechKeys.app` and restarts it
- [ ] Exactly one MechKeys is running afterwards, and it is the new version
- [ ] The panel confirms the new version on that first launch, once only
- [ ] **Keyboard access is still granted after the update** — the whole point
      of signing releases with a stable identity. Confirm with `--diagnose`
- [ ] Settings survive the update
- [ ] Escape closes the panel; Return presses the prominent button
- [ ] Turning off "Check for updates automatically" stops the background check
- [ ] The panel reads correctly in light and dark appearance

## The disk image window

`open dist/MechKeys-<version>.dmg` and look at it. Regenerate with
`swift Scripts/make-dmg-background.swift`, `tiffutil`, then
`./Scripts/make-dmg-layout.sh` — never by hand on a mounted image.

- [ ] The background picture appears, not a plain white window
- [ ] MechKeys is on the left, Applications on the right, on the drawn arrow
- [ ] Both filenames are legible against the background
- [ ] The picture is not cropped, and there is no scroll bar
- [ ] The toolbar and sidebar are hidden
- [ ] It is sharp on a Retina display — the @2x representation is being used
- [ ] Dragging the app onto the folder installs it

## Install and distribution

- [ ] `curl -fsSL https://theysap.com/install/mechkeys | bash` installs a working app
- [ ] The installer refuses on Intel, and on macOS older than 26
- [ ] The installer refuses on a checksum mismatch
- [ ] Installing over a running copy quits it first and the new one launches
- [ ] `MECHKEYS_VERSION` pins an older release
- [ ] `MECHKEYS_NO_LAUNCH=1` skips the launch
- [ ] A notarised build opens with no Gatekeeper warning
- [ ] `codesign -dvv` on a release reports an `Authority`, never `Signature=adhoc`
- [ ] Two consecutive releases report the same `certificate root` in
      `codesign -d -r-`, which is what the Accessibility grant is pinned to
- [ ] Launch at login actually launches it at login
