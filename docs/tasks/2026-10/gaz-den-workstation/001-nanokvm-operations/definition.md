---
type: Task
description: Turn the verified NanoKVM operating knowledge into a skill and a doc, so any agent can screenshot, type, click and power a machine through the KVM without re-deriving the MCP recipe.
status: open
authored_by: agent
timestamp: 2026-10-27T19:35:00+01:00
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

| Device | Host | Purpose |
|---|---|---|
| `kvm-fa56` | `gaz` (Lenovo C13 Yoga) | the machine this umbrella task converts |
| `kvm-2795` | `anji` (Mac mini) | the Full Disk Access work |
| `kvm-26e2` | `brys` | out-of-band console for the LLM box |

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

## Acceptance

- The skill is loadable and short enough to read in one screen.
- A fresh agent can take a screenshot and type text using only the skill.
- The key is never in the repository: `rg -n 'nag_mcp' .` returns nothing.
- The doc states the current capture limitation, and what it means.
