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
  report. If System Settings demands Touch ID or an admin password to change grants, stop and
  report.
