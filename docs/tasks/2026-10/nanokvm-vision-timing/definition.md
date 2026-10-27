---
type: Task
description: Decide whether a local vision model can act inside a time-sensitive NanoKVM window — firmware setup on a short keypress window, a boot-entry menu, copy-to-RAM — and build the cheaper mechanisms that remove the window instead of racing it.
status: open
authored_by: agent
timestamp: 2026-10-27T21:30:00+01:00
---

# Vision against a 2-second window

## Context

The three host tasks
([../gaz-den-workstation/](../gaz-den-workstation/definition.md),
[../minipc-den-host/](../minipc-den-host/definition.md),
[../pryll-mother-desktop/](../pryll-mother-desktop/definition.md)) all drive a
machine through a NanoKVM. Some steps are time-sensitive: firmware setup opens
for a short keypress window, a boot menu has a timeout, and a "copy to RAM"
entry must be chosen before the menu closes.

The fleet has vision models. The obvious idea is: screenshot the screen, ask a
vision model what it shows, act. The question is whether that loop fits in the
window.

Known inputs, from the `gaz` run on 2026-10-27:

- a screenshot is one MCP round trip, roughly 1 s, and the device-side capture
  itself lags the console;
- the operating rule is "wait 2 s after an injection, then shoot" — the feed lags
  the injection, and acting on a stale frame is how the `anji` attempt failed;
- the KVM's HID path on `kvm-fa56` is currently dead, and capture is
  intermittent — so the *device* is the slow and unreliable part, not the model;
- vision aliases and their measured decode rates: `vision-quick-fast`
  (`qwen3-vl-8b-instruct`, 8.4 t/s), `vision-std-fast` (`qwen3-vl-30b-a3b`,
  15.7 t/s), `vision-deep-slow` (`qwen3.8-27b`, 2.5 t/s).

A cold vision model also pays a load: models are loaded on first request, and a
swap is 30–120 s. A 2-second window cannot pay that once, let alone per frame.

## The two questions

1. **Does the loop fit?** Build the budget: capture, transfer, image prefill,
  decode of a short answer, and the action. Compare it to each real window. This
  is a measurement, not an argument.
2. **Should we race the window at all?** For most of these steps the window can
  be **removed** instead of raced. That is cheaper and works when the network,
  the model, or the KVM is slow.

## Removing the window (preferred, and mostly not vision at all)

| Step | Timing-free mechanism | Notes |
|---|---|---|
| Enter firmware setup | `systemctl reboot --firmware-setup` | uses the UEFI `OsIndications` variable; no keypress race, and it works when the machine is already in NixOS |
| Boot a specific entry | declarative `systemd-boot` default entry, and a long `boot.loader.timeout` | the owner's own machine should not need a menu choice at all |
| Boot the installer | `boot.loader.timeout = 600` in the installer, or a first install, or one-shot `systemd-boot` entry selection (`bootctl set-oneshot`) | a menu that waits 10 minutes costs nothing on a fresh install |
| "Copy to RAM" boot | an explicit boot entry in `configuration.nix` (`boot.loader.systemd-boot.extraEntries`) with the right kernel cmdline | becomes a menu entry that is default or selectable at leisure |
| Legacy firmware menus | **blind key spam** (`Esc`, `F2`, `Del` every 200 ms for 20 s) | safe: a stray key at the wrong moment is harmless, unlike a stray click |
| Reaching a menu at all when nothing shows | power cycle and watch `/api/events`-style console text, or the serial console if the device offers one | a serial console removes the graphics race entirely |

The rule: **if a step can be made deterministic, it must not be driven by
screenshots.** Vision is the fallback, not the plan.

## Where vision genuinely earns its place

- **Confirming state** before an irreversible action: "is this the installer
  menu, or the firmware screen?" — no window, high value.
- **Reading an unlabelled screen:** a Chromebook's developer-mode screen, a
  vendor firmware page with cryptic labels, a modal that is not in any doc.
- **Choosing among several entries** when the machine booted unattended and the
  menu timeout already expired into the wrong entry.
- **Detecting a stuck state:** a black frame, a frozen cursor, a kernel panic
  message that a human would recognise in a second.

These are all "one question, one answer, no timing pressure". That is the shape a
local vision model is good at, and it is what the `gaz` task already assumes.

## What to measure

1. **Frame-to-answer latency**, end to end, for one model that is already warm:
   time the MCP call, the image upload, the first token, and the last token. Do
   it 10 times for `vision-quick-fast` and 10 for `vision-std-fast`.
2. **Cold-start latency**: the same for a model that is not loaded, to show the
   load cost and justify a preload.
3. **Accuracy against a known screen**: take a set of KVM frames with known
   content (a boot menu, a firmware page, a kernel panic) and check that the
   small model reads the right thing. A fast wrong answer is worse than a slow
   right one here.
4. **The image-prefill cost** on this CPU box, since a 1080p frame is a large
   prompt and prefill is compute-bound.

## Acceptance

- A measured budget table: per-model end-to-end latency for one screenshot
  question, warm and cold.
- A decision per time-sensitive step: removed by a deterministic mechanism, or
  left to vision, with the measured margin stated.
- The deterministic mechanisms that are adopted are implemented in the relevant
  host task (installer ISO timeout, `extraEntries`, one-shot entries), not just
  described.
- The NanoKVM skill
  ([../gaz-den-workstation/001-nanokvm-operations/definition.md](../gaz-den-workstation/001-nanokvm-operations/definition.md))
  gains the rule: probe HID liveness and prefer key spam over a single timed
  keypress.
- If vision is rejected for a step, the cheaper mechanism is in place.

## Risks

| Risk | Mitigation |
|---|---|
| A model confirms the wrong screen and an operation proceeds | require two independent confirmations (two frames, or model plus a text assertion) before anything irreversible |
| A vision model is slow because it is cold | preload before the step, or accept and use the deterministic mechanism instead |
| Key spam lands in a menu and selects something unwanted | spam only keys that open or cancel a menu, never `Enter` or a letter |
| `systemctl reboot --firmware-setup` is unsupported on the hardware | verify per host; fall back to key spam, not to vision |
| Screenshots contain the user's data | same rule as everywhere: `/tmp/opencode/`, never committed |
