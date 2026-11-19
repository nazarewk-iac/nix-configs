---
type: Reference
description: The Sipeed NanoKVM Cube family — MCP control, capture and HID diagnostics, power control, and per-device notes.
timestamp: 2026-11-18T14:20:00+01:00
authored_by: agent
---

# NanoKVM

A NanoKVM is an out-of-band console: it captures the host's HDMI output and injects keyboard and
mouse over USB. It is the way into a machine whose network, display manager or boot is broken.

Three devices are in use. All run `2.5.2` and expose the MCP control API.

| Device     | Host   | Hardware | Purpose                                    |
| ---------- | ------ | -------- | ------------------------------------------ |
| `kvm-26e2` | `brys` | Beta     | out-of-band console for the LLM box        |
| `kvm-2795` | `anji` | Beta     | macOS recovery and Full Disk Access grants |
| `kvm-fa56` | `gaz`  | Alpha    | the Chromebook conversion                  |

Addresses are `https://<device>.lan.etra.net.int.kdn.im` and `ssh root@<device>.lan.etra.net.int.kdn.im`
(root, passwordless).

## Software and updates

`2.5.0` added the MCP server. `2.5.2` is the current version on all three devices.

The in-app OTA from `2.4.3` fails because the updater whitelists download `Content-Type` values and
Sipeed's CDN serves the package as `application/x-compressed`. The install must be done offline over
SSH. The full recipe, the hashes and the rollback step are in
[`docs/tasks/2026-10/nanokvm-mcp-update/done.md`](tasks/2026-10/nanokvm-mcp-update/done.md).

There is no persistent update log: syslog lives on tmpfs (`/tmp/messages`) and the `VPSS waitq is
full` flood rotates it away. Capture the console output during an update.

## MCP control

The MCP server runs inside `NanoKVM-Server`. Two gates must both pass, and both are read live:

1. `/etc/kvm/ai-control.mode` holds `mcp` (the other values are `off` and `picoclaw`).
2. `/etc/kvm/mcp.json` holds `{"apiKey":"nag_mcp_<base64url>"}` with mode `0600`.

The endpoint is `POST https://<device>/api/mcp`: Streamable HTTP, stateless, JSON-RPC 2.0. TLS is a
device-self-signed certificate, so use `curl -k`. Every request carries
`Authorization: Bearer <key>` and `Accept: application/json, text/event-stream`.

Read the key without printing or committing it:

```sh
export KEY=$(ssh root@kvm-26e2.lan.etra.net.int.kdn.im \
  "sed -n 's/.*\"apiKey\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' /etc/kvm/mcp.json")
```

`tools/list` returns six tools:

| Tool                | Arguments                                                                          |
| ------------------- | ---------------------------------------------------------------------------------- |
| `cube_screenshot`   | `quality` (51–60), `timeoutMs`                                                     |
| `cube_move_mouse`   | `mode` `absolute` (`x`, `y` normalised 0.0–1.0) or `relative` (`deltaX`, `deltaY`) |
| `cube_click_mouse`  | `mode`, `x`/`y` or none, `button` left/right/middle, `clicks` 1–5                  |
| `cube_press_keys`   | `keys`: `KeyboardEvent.code` names (`["Meta","Space"]`), optional `holdMs`         |
| `cube_type_text`    | `text`, optional `delayMs` (default 30)                                            |
| `cube_scroll_mouse` | `deltaY`                                                                           |

Screenshot, save the embedded JPEG, and review it:

```sh
curl -ksS -X POST https://kvm-26e2.lan.etra.net.int.kdn.im/api/mcp \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"cube_screenshot","arguments":{"quality":60}}}' \
  | jq -r '.result.content[]? | select(.type=="image") | .data' | base64 -d > /tmp/opencode/kvm.jpg
```

## Operating rules

- After every injection, wait about 2 s and take a new frame before the next action. The feed lags
  the injection, so an immediate screenshot shows the pre-action screen.
- Probe HID before planning a GUI step: send one harmless `ShiftLeft` and require a success return.
  A `timeout after 50ms: write /dev/hidg0` return means the host is not consuming the gadget; do not
  retry blindly.
- The capture is a vendor pipeline (`soph_vc_driver`), not `/dev/video*`. `dmesg` and
  `/proc/cvitek/vi` are the evidence.
- Keep screenshots under `/tmp/opencode/`. They show the user's real screen.
- Never commit the API key. Refer to it as `<key>`.
- Do not click destructive controls (erase, power, reboot) unless the task needs the exact one.

## Diagnostics

Four distinct faults, and they must not be confused:

| Symptom                                     | Evidence                                                                                                                                 | Meaning                                                          |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `cube_screenshot` fails at any timeout      | `retCode: -4`, `screenshot capture is temporarily unavailable`, `dmesg` `LT6911--:-- INT!!##`                                            | no HDMI signal: the source is off, asleep, or the display is off |
| `cube_press_keys` and `cube_type_text` fail | `write /dev/hidg0: i/o timeout`, `dwc2 4340000.usb: wakeup: signalling skipped: is not allowed by host`                                  | the USB HID gadget is wedged, or the host is not enumerating it  |
| a screenshot works, then stops              | one good frame, then `retCode -4`                                                                                                        | the guest display went to sleep; the link is fine                |
| both fail together                          | `retCode: -1`, `failed to capture screenshot`, `hidg0` timeout, `/sys/class/udc/*/state` `not attached`, `/proc/cvitek/vi` `VIDevFPS: 0` | the host is off or asleep, not the KVM; check host power first   |

### A powered-off host looks like a dead KVM

Measured on `kvm-26e2` on 2026-11-18 while `brys` was off: screenshots returned
`retCode: -1` / `failed to capture screenshot`, every injection timed out, and `dmesg` repeated
`usb_gadget_wakeup` / `wakeup: signalling skipped: is not allowed by host`.

Three probes identify the host, not the KVM:

1. `/sys/class/udc/*/state` — `configured` means the host enumerates the gadget; `not attached`
   means it does not.
2. `/proc/cvitek/vi` — `VIDevFPS: 0` and `VISofCh0Cnt: 0` mean no HDMI frames reach the capture
   pipeline.
3. `/kvmapp/kvm/state` — `0` means the server is not streaming; `1` means it is.

A UDC rebind (`echo "" > /sys/kernel/config/usb_gadget/g0/UDC`, sleep, write the controller back)
helps only when the host is on and the gadget is wedged. It cannot fix a host that is off.

The MCP screenshot and a browser stream **coexist**: with the browser holding the stream
(`state=1`, `now_fps=10`), an MCP `cube_screenshot` returned `ok: true` and a 55 KB frame. A failed
screenshot is not evidence that another client holds the capture.

### Black screen

1. Send one `ShiftLeft`, wait 2 s, take a frame. A guest display that slept wakes on input.
2. Repeat once.
3. If the frame is still black, run the three probes above before touching the KVM. A powered-off
   host is the common cause.

## Power control

The ATX header drives the host's power and reset pins. The pin numbers differ by hardware:

| Hardware | Power key | Power LED (input) | Reset key |
| -------- | --------- | ----------------- | --------- |
| Beta     | `503`     | `504`             | `505`     |
| Alpha    | `503`     | `504`             | `507`     |

`gpio504` reads `1` on `kvm-26e2` even when the host is off, so the LED proves nothing about the
host state. Use the three probes above instead.

Power control is not wired on every device. `gaz`, the NAS mini-PCs and `pryll` have no ATX header
or relay, so a power press is a human action. On `brys` a pulse did not start the machine during the
2026-11-18 outage: that host has a PSU latch that needs an AC disconnect, see
[`hosts-den/brys/README.md`](../hosts-den/brys/README.md).

**The reset pin is the recovery that works on `brys`.** When the host is on but dead (no network, no
HDMI, `udc` still `configured`), pulsing `gpio505` resets it without removing power, so the PSU latch
never engages. Measured 2026-11-18: after a `reboot` landed in the dead state, the reset brought the
host back in about 90 s, while a power pulse does nothing. Pulse it with
`echo out > /sys/class/gpio/gpio505/direction; echo 1 > /sys/class/gpio/gpio505/value; sleep 1;
echo 0 > /sys/class/gpio/gpio505/value` over SSH to `kvm-26e2`.

## Per-device notes

- **`brys`** (`kvm-26e2`, Beta): the console was the only view during the den migration. The host
  runs SDDM on Wayland with the `chili` theme; the greeter layout selector is dead (SDDM 0.21 does
  not populate it on Wayland) and the real layout is `pl`. Polish is QWERTY: a password types as
  usual, and only the AltGr layer differs (ą, ć, ę, ł, ń, ó, ś, ź, ż).
- **`anji`** (`kvm-2795`, Beta): a Mac mini; the KVM is the only path when macOS blocks SSH. No
  power header.
- **`gaz`** (`kvm-fa56`, Alpha): a Chromebook; video and HID are independent paths. Probe HID before
  any GUI step.

## References

- [MCP control of the anji GUI](tasks/2026-10/nanokvm-mcp-macos-control/definition.md) — the first
  agent-driven use.
- [The 2.5.2 update and MCP enablement](tasks/2026-10/nanokvm-mcp-update/done.md) — the OTA defect,
  the offline install and the key gates.
- [NanoKVM operations](tasks/2026-10/gaz-den-workstation/001-nanokvm-operations/definition.md) — the
  tool contract, timing rules and the original fault table.
- [Vision timing research](tasks/2026-10/nanokvm-vision-timing/research.md) — measured round trips
  and the boot windows.
- [brys power-off recovery](../hosts-den/brys/README.md) — the PSU latch and the KVM signature.
