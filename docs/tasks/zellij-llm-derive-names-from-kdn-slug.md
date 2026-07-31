---
type: Task
description: Make zellij-llm derive its session (and tab/pane) names from kdn-slug internally by default, with a CLI override, instead of requiring the caller to pass --session.
status: open
authored_by: agent
timestamp: 2026-07-31T12:30:00+02:00
---

# zellij-llm should derive names from kdn-slug by default

Today every `zellij-llm` subcommand (`spawn`, `spawn-and-watch`, `peek`, `list`) requires the
caller to compute a session name first with `kdn-slug names --type session` and pass it via
`--session`. That is boilerplate the tool can do itself.

## What to do

- `zellij-llm` should call `kdn-slug` **internally** to derive the default `--session` (and,
  where relevant, tab/pane) names, so the common case is just `zellij-llm spawn --pane '...'`
  with no `--session`.
- Keep `--session` (and any name flags) as an **explicit override** — when passed, use the
  given value verbatim and do not call `kdn-slug`.
- Respect the same `kdn-slug` knobs that matter for correctness (`--sep`, `--repo-sep`,
  `--max-len`), either by forwarding flags or by choosing safe defaults.
- **Pass tags through to `kdn-slug`.** `zellij-llm` should accept tag arguments and forward
  them to `kdn-slug` as repeatable `--tag <slug>` flags (kdn-slug's convention — see
  `packages/llm/kdn-slug/kdn-slug.sh` `# @option --tag*`, appended trailing components in the
  order given). This lets callers disambiguate a derived session/tab name without hand-building
  the whole string.

## Hard constraint discovered 2026-07-31

The **zellij IPC socket path has a 103-byte limit** (`/tmp/zellij/contract_version_1/<session>`).
The default `kdn-slug names --type session` output
(`llm:<host>_<org>_<repo>:<full-uuid-session-id>`) is **too long** and zellij refuses it:

```
Error: the IPC socket path is too long (107 bytes, max 103)
  /tmp/zellij/contract_version_1/llm:github.com_nazarewk-iac_nix-configs:4957d6cb-...
```

So the derived default **must** fit the socket limit — e.g. apply a `--max-len`, shorten the
repo slug, and/or truncate the UUID by default when deriving for zellij specifically. This is
the main reason to centralize name derivation inside `zellij-llm` rather than leaving it to each
caller: the tool knows the zellij-specific length ceiling, the caller shouldn't have to.

**Do NOT solve this by making `zellij-llm` use its own `ZELLIJ_SOCKET_DIR`.** The fix is a
shorter *session name* that fits the default socket path — not relocating the socket to a
private dir. Using a custom socket dir would fragment sessions (the tool's sessions wouldn't be
visible under the user's normal `zellij list-sessions` / default socket) and mask the real
length problem. Shorten the name; keep the default socket location.

## Acceptance

- `zellij-llm spawn --pane 'build'` works with **no** `--session` and produces a session name
  that fits zellij's socket-path limit.
- Passing `--session <name>` still overrides and is used verbatim.
- Unit tests in `packages/llm/zellij-llm/zellij_llm_test.py` cover the derive-vs-override paths
  and the length-limit handling.

## Pointers

- `packages/llm/zellij-llm/zellij-llm.sh`, `packages/llm/zellij-llm/default.nix`,
  `packages/llm/zellij-llm/zellij_llm_test.py`
- `packages/llm/kdn-slug/kdn-slug.sh` (name generator, `--type`, `--sep`, `--repo-sep`,
  `--max-len`)
- Related: [[zellij-llm-docs-clarity]]
