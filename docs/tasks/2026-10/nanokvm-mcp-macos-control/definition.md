---
type: Task
description: Drive the `anji` Mac mini GUI through the NanoKVM MCP endpoint, so an agent can do hardware-path clicks like a Full Disk Access grant when the network or macOS itself fights back.
status: in-progress
authored_by: agent
timestamp: 2026-10-16T04:53:23+02:00
---

# Control the `anji` macOS GUI over the NanoKVM MCP

## Purpose

`anji` is headless. When the network is down, or macOS itself blocks the path we normally use
(a TCC denial that only a GUI click can fix), the only way in is the keyboard, video and mouse
injector: the Sipeed NanoKVM Cube at `kvm-2795`. This task records the capability to operate
`anji`'s GUI from that hardware path — granting Full Disk Access, clicking recovery-adjacent
dialogs, and reading what is actually on screen.

The device update and MCP enablement are solved in [../nanokvm-mcp-update/definition.md](../nanokvm-mcp-update/definition.md).
This file records how an agent uses it.

## MCP access recipe

- The MCP server lives inside `NanoKVM-Server` on the device: **`POST https://kvm-2795.lan.etra.net.int.kdn.im/api/mcp`**
  — Streamable HTTP, JSON-RPC 2.0, stateless. TLS is device-self-signed; pass `-k` to curl.
- Auth: header `Authorization: Bearer <key>`. The key is on the device at `/etc/kvm/mcp.json`
  (mode `0600`, field `apiKey`). Read it with root ssh; never copy it into the repo:

  ```sh
  export KEY=$(ssh root@kvm-2795.lan.etra.net.int.kdn.im \
    "sed -n 's/.*\"apiKey\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' /etc/kvm/mcp.json")
  ```

- Tools (from `tools/list`, verified 2026-10-16):

  | Tool | What it does |
  |---|---|
  | `cube_screenshot` | Live JPEG of the `anji` console. Params: `quality` (51–60), `timeoutMs`. |
  | `cube_move_mouse` | Move pointer. `mode`: `absolute` with `x`,`y` normalized 0.0–1.0, or `relative` with `deltaX`,`deltaY`. |
  | `cube_click_mouse` | Click. `mode` `absolute` needs `x`,`y`; `button` left/right/middle; `clicks` 1–5. |
  | `cube_press_keys` | One shortcut. `keys`: array of `KeyboardEvent.code` names (e.g. `["Meta","Space"]`); optional `holdMs`. |
  | `cube_type_text` | Short text. `text`, optional `delayMs` (default 30). |
  | `cube_scroll_mouse` | Wheel. `deltaY`. |

- Example call — take a screenshot and save it (the JSON-RPC result embeds base64 JPEG):

  ```sh
  curl -skS -X POST https://kvm-2795.lan.etra.net.int.kdn.im/api/mcp \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"cube_screenshot","arguments":{"quality":60}}}'
  ```

## Operating notes

- After every key/mouse action: `sleep 2`, then screenshot, review, then act. The feed lags the
  injection — a screenshot taken immediately after an action shows the pre-action screen (the
  first run was cancelled for exactly this reason). If the screen looks unchanged or half-typed,
  wait another 2s and screenshot again before acting.
- If the video feed is black at start, the display may be asleep: send one `Shift` keypress, wait
  2s, screenshot; repeat once; if still black, report.
- Save screenshots incrementally as `/tmp/opencode/nanokvm/NN-name.jpg`. The agent model may lack
  image input; review with OCR (`tesseract` via a small shell helper) plus pixel diffs between
  shots to prove an action landed.
- To reach an exact System Settings pane without fighting shortcuts:
  `ssh kdn-anji open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"`.

## Constraints

- **Never commit the API key** — not into the repo, not into a worklog entry, not into a report.
  Refer to it as `<key>`. Keep it only in a shell variable exported from the command substitution
  above.
- **Screenshots show the user's real screen.** Treat them as user data: keep them under
  `/tmp/opencode/`, do not commit them, do not describe secrets they may reveal.
- **Do not click destructive things.** No "Erase", no "Allow" on any prompt that is not the Full
  Disk Access flow, no reboot/power controls. If the screen state looks wrong after an action,
  press Escape, screenshot, and stop to report.
- If the Mac shows a lock screen, there is no login password available to the agent — stop and
  report. System Settings demands the admin password to change grants; the agent may type it from
  the secret store (`pass show hosts/anji/users/kdn/password`, fetched into a shell variable only —
  never printed, never on a command line, built into the `type_text` JSON with `jq --arg`).

## Findings from the 2026-10-16 grant attempt (run 2)

- Outcome: **BLOCKED(password)** for the FDA grant of
  `/nix/store/f0b9dbw2gl596cm03pvdsss72381qhlp-bash-5.3p15/bin/bash` (sha256
  `0fba4021f093052f39b68e789f12be8e96c0680837679971a5be9ff6679c8821`, the shebang of the current
  system's `activate` and of the newest `anji-ext-unlock-start`). The pane reached, the "+" click
  worked, and macOS 26 answered with a modal sheet: *"Privacy & Security is trying to modify your
  system settings. Enter your password to continue with Privacy & Security"* (user
  `Krzysztof Nazarewski`, buttons Modify Settings / Cancel). No Touch ID on a Mac mini. Reproduced
  twice (initial + one retry). The agent path needs the owner to type the login password.
- Cmd+Space did **not** open Spotlight on `anji` (three tries, verified by screenshot diff — only
  the clock changed). The Apple menu (logo at ≈(27,14) of 1920x1080) and menu-bar app menus do
  open with absolute clicks, so key/mouse injection itself works.
- `cube_press_keys` names are KeyboardEvent codes: `KeyQ` works, lowercase `q` does not.
- Absolute click coordinates map 1:1 to the 1920x1080 console feed (normalized 0.0–1.0).
- Small "+" / "-" controls under the FDA app list are too small for default OCR: crop the region,
  `magick -resize 400%`, `tesseract --psm 6` (found at (854,857) of 1920x1080).
- TCC automation prompts — e.g. triggered by `osascript` over SSH — appear as modal sheets on the
  **console GUI**, stacked over whatever panel is open, and swallow clicks there. Run no AppleScript
  needing Automation permission mid-KVM-session. The stray prompt was cancelled; it left no grant
  (0 `kTCCServiceAppleEvents` rows for System Events).
- Calendar's "What's New" onboarding auto-opened once on the shared desktop and had to be quit;
  a stray Dock-area click can launch GUI apps on an unattended Mac.

## Findings from the 2026-10-16 password run (run 3) — PARTIAL, not granted

- The owner password **can** be injected through `cube_type_text` into the auth sheet: with the
  sheet fully rendered and the field clicked at (960,614), dots appear in the field band
  (x≈853–967 for 12 chars). The grant path is end-to-end possible; it just did not complete.
- The dominant failure is **input latency on the cube side**: the sheet renders 5–10s after "+",
  and queued keys/clicks during that window land on whatever was on screen (the sidebar search
  accumulated stray characters — later cleared; verified never to have contained the password).
  A "2s then screenshot" cadence is NOT sufficient for this sheet; poll until the frame matches
  the expected state before every next event.
- Two submissions were consumed (max allowed): the first typed during sheet rendering (focus
  uncertain), the second had a stray probe character before the password. The sheet rejects with
  no visible error and does not clear the field — distinguish "rejected" from "never received"
  only with per-step frame confirmation.
- Stuck keyboard / dead-keyboard state was fixed twice by USB-gadget rebind on the cube:
  `echo "" > /sys/kernel/config/usb_gadget/g0/UDC; sleep 1.5; echo 4340000.usb > .../UDC`
  (video + network unaffected; Mac re-enumerates HID in ~2s).
- Ground truth for key delivery: `ioreg -c IOHIDSystem | grep HIDIdleTime` over SSH resets on each
  injected key even under a modal sheet.
- Anji's keyboard layout is **Polish Pro**; harmless for an alphanumeric secret, but symbol-heavy
  passwords would need scan-code care.
- The un-filed grant target and TCC state are unchanged (0 rows for the path; everything else
  untouched).
