---
type: Solution
description: Reference the TLS key by its literal systemd credential path instead of {$CREDENTIALS_DIRECTORY}, so `caddy reload` works without the credential env; verified on brys.
task: definition.md
authored_by: agent
timestamp: 2026-10-10T02:20:00+02:00
---

# Fix the caddy reload by using the literal credential path

## Root cause analysis

The LLM vhost's Caddyfile loaded the TLS private key with the Caddy env
placeholder:

```
tls <cert> {$CREDENTIALS_DIRECTORY}/llm-key
```

The key is a systemd credential (`LoadCredential = llm-key:/run/secrets/...`),
created at `/run/credentials/caddy.service/llm-key`.

`ExecReload` is `caddy reload --config /etc/caddy/caddy_config --adapter
caddyfile --force`. The `caddy reload` CLI **adapts the Caddyfile in its own
process**, and Caddy expands `{$VAR}` during adaptation. That process does not
have `CREDENTIALS_DIRECTORY` in its environment, so the placeholder expands to
empty and the path becomes `/llm-key`. The running caddy then fails to load the
cert (`open /llm-key: no such file or directory`), `caddy reload` retries until
the reload timeout, and systemd kills it ("Reload operation timed out").
Caddy keeps the old config, so a changed vhost never applies.

`ExecStart` (`caddy run`) adapts in-process with the credential env present, so
a fresh start worked. Only the reload was broken.

Full analysis and the reproduction: [research.md](research.md).

## Solution

Reference the key by its stable absolute path:

```
tls <cert> /run/credentials/caddy.service/llm-key
```

The path is the same file, is stable for the `caddy.service` unit, and needs no
environment variable, so both `run` and `reload` work. The key stays a systemd
credential and never enters the Nix store.

Changed in `modules/den/aspects/llm.nix` (`services.caddy` extraConfig). The
removed universal slot carried the same line.

## Verification steps

On brys before the fix:

```
$ sudo systemctl reload caddy
Job for caddy.service failed.
$ systemctl show caddy -p Status
Status: "loading new config: ... open /llm-key: no such file or directory"
```

Reproduction that isolates the env:

```
# no env -> hangs / fails
sudo env -u CREDENTIALS_DIRECTORY caddy reload --config /etc/caddy/caddy_config ...
# with env -> exit 0
sudo bash -c "CREDENTIALS_DIRECTORY=/run/credentials/caddy.service caddy reload ..."
# literal path, no env -> exit 0
sudo env -u CREDENTIALS_DIRECTORY caddy reload --config /tmp/caddy_test_config ...
```

After the fix, on brys (new `llms-frontier`, `/run/current-system` =
`fkrl5715...-llms-frontier`):

```
$ grep tls /etc/caddy/caddy_config
tls .../llm.pub /run/credentials/caddy.service/llm-key
$ sudo systemctl reload caddy; echo $?
0
$ systemctl show caddy -p Status
(empty)
$ systemctl is-active caddy
active
```

## Follow-up notes

- **`nixos-rebuild` with `--build-host` (`remote=brys+b`) fails the
  specialisation check.** `nixos-rebuild-ng` builds the main `.#brys` system on
  the remote host and then checks `<main>/specialisation/llms-frontier` on the
  local filesystem; the main system was not copied locally, so it reports
  "specialisation not found". Build locally (`remote=brys`) instead, or ensure
  the main system is in the local store first. Worth its own task.
- **The other status-4 cause is unrelated:** `kdn-atuin-login-root.service`
  fails at login (the pre-existing key mismatch). It is still failed and is not
  part of this task.
- **A Caddyfile change now builds cleanly.** The earlier Lix strictness error
  (`Caddyfile-formatted/Caddyfile` placeholder) appears only when building the
  `config.services.caddy.configFile` attribute directly; the full system build
  handles it. Not a regression from this fix.
