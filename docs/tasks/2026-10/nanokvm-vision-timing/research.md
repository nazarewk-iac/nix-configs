---
type: Research
description: The latency budget of a screenshot-to-action loop over the NanoKVM, the measured speed of the vision tier, and the declarative mechanisms that remove each short boot window instead of racing it.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T21:35:00+01:00
---

# Research: can a vision model act inside the window

## 1. The device side, measured today

From the `gaz` run on 2026-10-27 (see
[../gaz-den-workstation/001-nanokvm-operations/definition.md](../gaz-den-workstation/001-nanokvm-operations/definition.md)):

| Observation | Value |
|---|---|
| `cube_screenshot` round trip (MCP call to JPEG) | about 1 s when it works |
| Capture availability | intermittent: one good frame, then `retCode -4`, `screenshot capture is temporarily unavailable` |
| Cause of one failure mode | the guest display went to sleep (no HDMI signal) |
| Required settle time after an injection | 2 s, because the feed lags the injection |
| HID injection | **dead** on `kvm-fa56` at the time: `write /dev/hidg0: i/o timeout` |
| Any UDC rebind result | gadget re-bound, HID still dead; a physical replug is the documented fix |

The important conclusion for this task: **the slowest and least reliable element
in the loop is the KVM, not the model.** A plan that assumes a 200 ms round trip
is wrong by an order of magnitude, and a plan that assumes the keyboard works at
all is wrong on this device today.

## 2. The model side

From `.agents/skills/kdn-llms/SKILL.md` (measured decode rates on `brys`):

| Alias | Model | Decode |
|---|---|---|
| `vision-quick-fast` | qwen3-vl-8b-instruct | 8.4 t/s |
| `vision-std-fast` | qwen3-vl-30b-a3b | 15.7 t/s |
| `vision-deep-slow` | qwen3.8-27b | 2.5 t/s |

Two costs sit before the decode:

1. **Load.** A model is started on its first request. A swap is 30–120 s on this
  box, longer under CPU pressure. Nothing preloads the vision models today.
2. **Image prefill.** A 1920x1080 JPEG becomes a large prompt; prefill is
  compute-bound and on this box is the expensive half.

So a cold call is a minute, and a warm call is "a screenshot plus a prefill plus a
short answer". The measurement in this task exists to put numbers on both, because
neither is currently known.

## 3. The real windows

| Step | Window | Source of the window |
|---|---|---|
| Firmware setup (F2/Del/Esc) | often 1–3 s after POST | the firmware |
| Vendor boot menu | 3–10 s | the firmware |
| `systemd-boot` menu | `boot.loader.timeout` — and **the config can make it wait forever** | our own config |
| Legacy BIOS menu (`Ctrl+L` on ChromeOS firmware) | a few seconds | firmware |

Only the first two are genuinely outside our control on a machine whose firmware
we do not control. The rest are ours.

## 3b. `systemd-boot` knobs that exist in this nixpkgs

Verified in `.flake.patches/nixpkgs/.../boot/loader/systemd-boot/systemd-boot.nix`:

```nix
timeout = if config.boot.loader.timeout == null then "menu-force" else config.boot.loader.timeout;
```

So `boot.loader.timeout = null` writes `menu-force`, which **waits with no
timeout**. That single line deletes the boot-menu race for any host we own.
`boot.loader.systemd-boot.extraEntries` is an attribute set of
`<name>.conf` → text, so a purpose-built entry (`copy to RAM`, a one-off
installer entry) is a declarative artifact, not a keypress.

`bootctl set-oneshot <entry>` selects the next boot's entry once, which is the
supported way to boot "that other entry, this time" without touching the menu.

## 4. Firmware setup without a keypress

`systemctl reboot --firmware-setup` asks the firmware to show its setup UI on the
next boot, using the UEFI `OsIndications` mechanism. It removes the POST keypress
race entirely, and it is the correct mechanism whenever the machine is already
running Linux.

Open: whether each host's firmware advertises support
(`OsIndicationsSupported` with the setup bit). That is a per-host check, and the
fallback is key spam, not vision.

## 5. Blind key spam is safe; blind clicking is not

For a menu we cannot see, repeatedly sending `Esc`, `F2`, `Del` (or `Ctrl+L` on
ChromeOS firmware) every 200 ms for 20 s is harmless: a stray Escape at the wrong
moment cancels a menu, and a stray F2 during POST either works or is ignored.
There is no destructive outcome.

The same is **not** true of blind clicks or `Enter`: a stray `Enter` can select
"Erase disk" on a menu. So the rule for a time-critical step is: spam only keys
that open or cancel, never a confirming key, and confirm visually afterwards.

## 6. Where the model is actually usable

Two shapes work for a local vision model:

1. **One question, one answer, no deadline.** "Which of these menu entries is
   highlighted?" / "Is this the installer or the firmware page?" — the answer
   arrives in a couple of seconds and nothing moves meanwhile.
2. **Post-hoc confirmation.** "The action was supposed to open the file panel; is
   the file panel open?" — this is the pattern the `anji` attempt used, and it is
   what caught the stale-frame problem.

Two shapes do **not** work: a tight poll-act loop, and anything that must happen
inside a 1–3 s firmware window on a cold model.

## 7. The recommended split

| Step | Mechanism |
|---|---|
| Enter firmware setup on a host we control | `systemctl reboot --firmware-setup` |
| Choose the installer or a special entry | `boot.loader.timeout = null` (menu-force) + `extraEntries` + `bootctl set-oneshot` |
| Legacy/ChromeOS firmware menus | blind key spam of the opening key, then a screenshot to confirm |
| Confirm the resulting screen | `vision-quick-fast`, warm, one question |
| Detect a hang or a panic | `vision-std-fast` on a single frame, or a text match on the console if a serial console exists |

Vision is the confirmation layer, not the actuator.

## 7b. What "copy to RAM" really needs

Booting an installer with `copytoram` (or the NixOS equivalent of loading the
squashfs into RAM) is a kernel-cmdline property, so it belongs in the entry, not
in a menu choice. Two consequences:

- it is an `extraEntries` artifact, and
- it changes RAM requirements at boot, which matters on a 16 GB machine and on a
  machine whose RAM is not yet known.

That is a config decision, made once, not a step to drive.

## 8. Not verified

- Whether `systemctl reboot --firmware-setup` succeeds on the Chromebook's stock
  firmware (ChromeOS firmware may not implement it) or on the mini-PCs.
- The image-prefill cost of a 1080p frame on this CPU box.
- Whether any NanoKVM firmware version supports a scripted key macro (the MCP tool
  list has no such tool today).
- Whether a serial console is available on the NanoKVM for these devices. If it
  is, it replaces most of the graphics work.
