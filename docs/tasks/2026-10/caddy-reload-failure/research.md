---
type: Research
description: Root cause of the caddy reload failure — the Caddyfile uses {$CREDENTIALS_DIRECTORY}, which the ExecReload process does not have, so the placeholder expands empty.
task: definition.md
authored_by: agent
timestamp: 2026-10-10T02:00:00+02:00
---

# RCA: caddy reload fails to find the TLS key

## The setup

The LLM server aspect (`modules/den/aspects/llm.nix`) runs a caddy vhost in
front of the loopback compat proxy. The TLS private key is a systemd credential:

```nix
caddy.serviceConfig.LoadCredential = [ "llm-key:${cfg.certs.keyFile}" ];
services.caddy.virtualHosts.${cfg.domain}.extraConfig = ''
  tls ${cfg.certs.certFile} {$CREDENTIALS_DIRECTORY}/llm-key
  reverse_proxy 127.0.0.1:${toString cfg.compatProxy.port}
'';
```

`cfg.certs.keyFile` is `/run/secrets/kdn/brys/llm.key`, decrypted from sops by
the `kdn-llm-leaf-key` service. `LoadCredential` copies it to
`/run/credentials/caddy.service/llm-key` and grants the caddy service user
access (the file carries an ACL, `-r--r-----+`).

The nixpkgs caddy module (`.../caddy/default.nix`) writes the generated
Caddyfile to `/etc/caddy/caddy_config` and sets:

```
ExecStart  = caddy run    --config /etc/caddy/caddy_config --adapter caddyfile
ExecReload = caddy reload --config /etc/caddy/caddy_config --adapter caddyfile --force
```

## The failure

`systemctl reload caddy` runs `ExecReload`. The `caddy reload` CLI reads the
Caddyfile and **adapts it to JSON in its own process** (journal: "using config
from file", "adapted config to JSON"). Caddy expands `{$VAR}` placeholders
during adaptation. If `CREDENTIALS_DIRECTORY` is not in that process's
environment, `{$CREDENTIALS_DIRECTORY}/llm-key` becomes `/llm-key`, and the
running caddy then fails to open the cert:

```
Status: "loading new config: ... loading certificates: open /llm-key: no such file or directory"
```

`caddy reload` does not exit on this; it retries, and systemd kills it after the
reload timeout ("Reload operation timed out. Killing reload process."). Caddy
keeps the previous config, so the change silently does not apply.

`ExecStart` is `caddy run`, which adapts in-process with the credential
environment present. So a fresh start works and only the reload is broken.

## Reproduction (brys, 2026-10-10)

```bash
CADDY=/nix/store/...-caddy-2.11.4/bin/caddy

# A) no env -> hangs until killed, and would produce /llm-key
sudo env -u CREDENTIALS_DIRECTORY "$CADDY" reload \
  --config /etc/caddy/caddy_config --adapter caddyfile --force   # hangs

# B) with env -> succeeds
sudo bash -c "CREDENTIALS_DIRECTORY=/run/credentials/caddy.service $CADDY reload \
  --config /etc/caddy/caddy_config --adapter caddyfile --force"  # exit 0
```

And with the literal path in the config, no env is needed:

```bash
sudo sed 's|{\$CREDENTIALS_DIRECTORY}/llm-key|/run/credentials/caddy.service/llm-key|' \
  /etc/caddy/caddy_config > /tmp/caddy_test_config
sudo env -u CREDENTIALS_DIRECTORY "$CADDY" reload \
  --config /tmp/caddy_test_config --adapter caddyfile --force   # exit 0
```

## Why not pass the env instead

An alternative is to override `ExecReload` with a wrapper that exports
`CREDENTIALS_DIRECTORY`. It works, but it hardcodes the same unit path and adds
a script. The literal path is one line, fixes both `run` and `reload`, and keeps
the key a credential. The only cost is that the unit name (`caddy.service`) is
implied by the path, which the nixpkgs module already fixes.

## Note on systemd

systemd documents `CREDENTIALS_DIRECTORY` for the main process and the `Exec*`
commands. Whatever the exact reason it is absent for `ExecReload` here, the
literal path removes the dependency on it entirely.
