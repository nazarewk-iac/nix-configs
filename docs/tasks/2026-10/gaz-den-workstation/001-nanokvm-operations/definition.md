---
type: Task
description: Turn the verified NanoKVM operating knowledge into a skill and a doc, so any agent can screenshot, type, click and power a machine through the KVM without re-deriving the MCP recipe.
status: open
authored_by: agent
timestamp: 2026-11-18T14:11:34+01:00
---

# NanoKVM operations an agent can rely on

Part of [../definition.md](../definition.md).

## Why this comes first

The `gaz` run is driven by screenshots. Today that knowledge is a task document
written for a different device
([../../nanokvm-mcp-macos-control/definition.md](../../nanokvm-mcp-macos-control/definition.md)),
and there is no skill. So every new agent re-derives the endpoint, hunts for the
API key, and re-learns the timing rules by breaking them.

Two devices now exist with the same software:

| Device     | Host                    | Purpose                                 |
| ---------- | ----------------------- | --------------------------------------- |
| `kvm-fa56` | `gaz` (Lenovo C13 Yoga) | the machine this umbrella task converts |
| `kvm-2795` | `anji` (Mac mini)       | the Full Disk Access work               |
| `kvm-26e2` | `brys`                  | out-of-band console for the LLM box     |

## What to build

1. **A skill** at `.agents/skills/nanokvm/SKILL.md`. It must cover:
   - the MCP endpoint, auth header, and how to read the key **without** printing
     it or committing it;
   - the six tools and their argument shapes;
   - the timing rules: 2 s after an injection, poll the frame before the next
     action, never fire into a stale frame;
   - the HID health probe (`HIDIdleTime` on Linux guests, a screenshot diff on
     others), and the USB-gadget rebind as a last resort;
   - the one-line "black screen" procedure;
   - the safety rules: no destructive clicks, no key or password in a log, and
     screenshots stay under `/tmp/opencode/`.
2. **A doc** at `docs/nanokvm.md` with the long form: the device family, the
   version history (`2.5.2` today), the OTA defect and the offline install, and
   the per-device addresses.
3. **A small helper script**, only if it earns its place: one function to take a
   screenshot into a numbered file, because that call is repeated dozens of
   times per run. A git-ignored path is the wrong place for something the skill
   tells every agent to use, so it belongs in `packages/` if it is kept.

## Evidence to reuse

- `POST https://<kvm>/api/mcp`, JSON-RPC 2.0, `Authorization: Bearer <key>`,
  `Accept: application/json, text/event-stream`, `curl -k` for the self-signed
  certificate.
- Key at `/etc/kvm/mcp.json` on the device, field `apiKey`, mode `0600`.
- `tools/list` on `kvm-fa56` returns exactly:
  `cube_screenshot`, `cube_move_mouse`, `cube_click_mouse`, `cube_press_keys`,
  `cube_type_text`, `cube_scroll_mouse`.
- `cube_press_keys` takes `KeyboardEvent.code` names (`KeyQ`, `Meta`, `Space`),
  not characters.
- Absolute coordinates are normalised `0.0–1.0` and map to the console frame.
- On `kvm-fa56` today, `cube_screenshot` returns
  `screenshot capture is temporarily unavailable` — the HDMI source has no
  signal. `dmesg` shows `LT6911--:-- INT!!##`. Capture is **not** `/dev/video*`;
  it is the vendor `soph_vc_driver` pipeline.

## Observed on `kvm-fa56`, 2026-10-27

Three distinct faults, and they must not be confused:

| Symptom                                     | Evidence                                                                                                                                 | Meaning                                                          |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `cube_screenshot` fails at any timeout      | `retCode: -4`, `screenshot capture is temporarily unavailable`, `dmesg` `LT6911--:-- INT!!##`                                            | no HDMI signal: the source is off, asleep, or the display is off |
| `cube_press_keys` and `cube_type_text` fail | `write /dev/hidg0: i/o timeout`, `dwc2 4340000.usb: wakeup: signalling skipped: is not allowed by host`                                  | the USB HID gadget is wedged, or the host is not enumerating it  |
| a screenshot works, then stops              | one good frame, then `retCode -4`                                                                                                        | the guest display went to sleep; the link is fine                |
| both fail together                          | `retCode: -1`, `failed to capture screenshot`, `hidg0` timeout, `/sys/class/udc/*/state` `not attached`, `/proc/cvitek/vi` `VIDevFPS: 0` | the host is off or asleep, not the KVM; check host power first   |

What was tried, and what it cost:

- A **UDC rebind** (`echo "" > /sys/kernel/config/usb_gadget/g0/UDC; sleep 2; echo
4340000.usb > ...`) re-bound the gadget (`dwc2 … bound driver configfs-gadget`)
  but **did not restore HID**. The next keypress still timed out.
- The same rebind is documented to work on `kvm-2795`, so this is the harder
  variant from that document: **the host-side port needs a physical replug**.
- Video and HID are independent paths. A good picture does not prove the
  keyboard works. **Probe HID before planning a GUI step**, not after.

The practical rule this adds to the skill: on this device, always send one
harmless key (`ShiftLeft`) and require a success return **before** any step that
depends on typing. A `timeout after 50ms: write /dev/hidg0` return is the
signal to switch to a physical hand-off, not to retry.

### A powered-off host looks exactly like a dead KVM (`kvm-26e2`, 2026-11-18)

When `brys` was powered off, both paths failed at once: `cube_screenshot`
returned `retCode: -1` / `failed to capture screenshot`, every key and text
injection returned `timeout after 50ms: write /dev/hidg0: i/o timeout`, and
`dmesg` repeated `usb_gadget_wakeup` / `wakeup: signalling skipped: is not
allowed by host`. A UDC rebind re-bound the gadget and did not restore HID.

Three probes identify the host rather than the KVM:

1. `/sys/class/udc/*/state` — `configured` means the host enumerates the
   gadget; `not attached` means it does not.
2. `/proc/cvitek/vi` — `VIDevFPS: 0` and `VISofCh0Cnt: 0` mean no HDMI input
   frames reach the capture pipeline.
3. `/kvmapp/kvm/state` — `0` means the server is not streaming; `1` means it is.

On `kvm-26e2` the ATX power-LED input (`gpio504`) read `1` for the whole outage,
so it is **not** a reliable "host is on" signal. A power-key pulse (`gpio503`)
and a WoL magic packet did not start the host; the owner had to press the
physical button. `brys` also has a PSU latch that needs an AC disconnect, see
[`hosts/brys/README.md`](../../../../hosts/brys/README.md).

Two facts this corrects:

- **The MCP screenshot and a browser stream coexist.** With the browser holding
  the stream (`state=1`, `now_fps=10`), an MCP `cube_screenshot` returned
  `ok: true` and a 55 KB 1920x1080 JPEG. A failed screenshot is not evidence
  that another client holds the capture.
- **A UDC rebind cannot fix a host that is off.** The rebind only helps when the
  host is on and the gadget is wedged.

## Power control: not available on these devices

Verified with the owner on 2026-10-27: scripted power control exists only for
`brys` and the NAS mini-PCs `pwet`, `turo` and `yost`. For `gaz`, the mini-PCs and
`pryll` there is **no** power API, no ATX header wired to the KVM, and no relay.
`press-and-hold the power button` is therefore always a human action.

On `kvm-26e2` (`brys`) the Beta ATX pins are `gpio503` (power key), `gpio504`
(power LED, input) and `gpio505` (reset). A power-key pulse and a reset pulse did
not start `brys` on 2026-11-18, and the LED read `1` throughout. Treat ATX power
as best-effort: it is not a guaranteed recovery path, and it cannot clear the PSU
latch that `brys` has.

The skill must say this plainly, so no agent spends an hour looking for a power
endpoint that does not exist, and so every boot step is planned as a hand-off.

## Acceptance

- The skill is loadable and short enough to read in one screen.
- A fresh agent can take a screenshot and type text using only the skill.
- The key is never in the repository: `rg -n 'nag_mcp' .` returns nothing.
- The doc states the current capture limitation, and what it means.
