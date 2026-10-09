---
type: Task
description: A nixos-rebuild switch on brys leaves caddy stuck on the old config because `caddy reload` cannot find the TLS key; the reload fails and switch-to-configuration reports status 4.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-10T02:00:00+02:00
---

# Caddy reload fails: the TLS key is not found

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

Every `nixos-rebuild switch` on brys finishes with status 4. One cause is the
caddy reload: the new config is written, `systemctl reload caddy` runs, and the
reload fails. Caddy keeps the old config, so a changed vhost or cert does not
apply until a manual restart. The user hit this and restarted caddy by hand.

Observed on brys (systemd `Status` of the caddy unit):

```
loading new config: ... provision tls: loading certificates:
open /llm-key: no such file or directory
```

and in the journal:

```
Reloading Caddy...
using config from file /etc/caddy/caddy_config
adapted config to JSON
Reload operation timed out. Killing reload process.
Reload failed for Caddy.
```

## Root cause

The caddy config loads the TLS private key from the systemd credential that
`LoadCredential = llm-key:/run/secrets/kdn/brys/llm.key` creates. The config
references it with the Caddy env placeholder `{$CREDENTIALS_DIRECTORY}/llm-key`.
See [research.md](research.md) for the full analysis.

`ExecReload` runs `caddy reload --config /etc/caddy/caddy_config --adapter
caddyfile --force`. That command **adapts the Caddyfile in its own process**,
which expands `{$CREDENTIALS_DIRECTORY}`. The reload process does not have
`CREDENTIALS_DIRECTORY` in its environment, so the placeholder expands to empty
and the path becomes `/llm-key`. The reload then fails (and `caddy reload`
retries until systemd kills it).

`ExecStart` does not hit this: it is `caddy run`, which expands the placeholder
in-process with the credential env present.

## Fix

Reference the credential by its stable absolute path
`/run/credentials/caddy.service/llm-key` instead of
`{$CREDENTIALS_DIRECTORY}/llm-key`. The path is the same file, is stable for the
`caddy.service` unit, and needs no environment variable, so both `run` and
`reload` work.

Changed in `modules/den/aspects/llm.nix` (the `services.caddy` block). The
removed universal slot carried the same line.

## Acceptance criteria

- `systemctl reload caddy` on brys exits 0 and leaves no error in the unit
  `Status`.
- A `nixos-rebuild switch` that changes the caddy config applies it without a
  manual restart.
- The key stays out of the Nix store (still a systemd credential).

## References

- [research.md](research.md) — the RCA and the reproduction.
- `modules/den/aspects/llm.nix` — the caddy vhost and `LoadCredential`.
- `.flake.patches/nixpkgs/repo/nixos/modules/services/web-servers/caddy/default.nix`
  — `ExecStart`/`ExecReload` and `etcConfigFile`.
