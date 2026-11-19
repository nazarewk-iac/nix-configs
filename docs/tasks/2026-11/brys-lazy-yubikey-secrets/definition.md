---
type: Task
description: brys must boot and run without its YubiKey plugged in, and decrypt YubiKey-gated sops secrets lazily on first use (once the key is present), instead of failing at activation. sops-nix decrypts eagerly at boot and does not meet this.
status: open
authored_by: agent
timestamp: 2026-11-09T20:00:00+01:00
---

# brys: secrets must degrade gracefully without the YubiKey, decrypt on demand

## Context

`hosts/brys` has a service `kdn-llm-leaf-key.service` ("Decrypt brys LLM leaf private key into
/run/secrets") that failed right after activation:

```
order for SOPS to recover the file, at least one key has to be successful, but none were
kdn-llm-leaf-key.service: Main process exited, code=exited, status=128
```

The YubiKey is not currently plugged into brys, so the sops recipient that lives on the YubiKey
cannot decrypt. It is fine that the _secret_ is unavailable — but the host and the rest of the fleet
work must not fail because of it. The current model is **sops-nix decrypts every secret at
activation** (`sops-install-secrets.service`, ordered before the services), so a missing YubiKey
turns into a failed unit (and `degraded` state) at boot/switch.

**Requirement:**

1. **Degrade gracefully** — brys boots and reaches `running` even with no YubiKey. A service that
   needs a YubiKey-gated secret should fail (or wait) _only that service_, not the whole activation,
   and never leave the system `degraded` merely because the key is unplugged.
2. **Decrypt on usage** — when a consumer actually needs the secret and the YubiKey is now present,
   decryption happens on demand (and is retried), rather than all-or-nothing at boot.

**sops-nix does not meet this.** `sops-install-secrets` is an eager, boot-time, fail-the-activation
decryptor with no per-secret lazy/on-demand path and no "wait for key" semantics.

## What to research / decide

- Mechanisms for **on-demand secret materialisation** gated by a physical key:
  - `systemd` socket/`ExecCondition` activation of a per-secret unit that runs `sops -d` only when a
    consumer starts, and retries/skips when the key is absent.
  - `systemd-creds` / credential loading (`LoadCredential=`) per-service, instead of a global
    `sops-install-secrets`.
  - age/PIV agent that unlocks the age identity when the YubiKey is touched, with `sops -d` called
    per consumer.
  - A small FUSE or tmpfiles+oneshot that populates `/run/secrets/<name>` lazily and re-runs on
    YubiKey insertion (udev/netlink or a timer).
- How to express "this secret is YubiKey-gated" in `data/` so a consumer's dependency is a
  _runtime_ wait, not a build/activation requirement.
- Keeping the non-YubiKey secrets eager (they should not regress) while making the YubiKey-gated ones
  lazy.
- Whether to replace `sops-install-secrets` for these secrets, or wrap it per-service.

## Acceptance criteria

- With the YubiKey unplugged: brys reaches `running` (not `degraded`); `kdn-llm-leaf-key` (or its
  successor) is `inactive`/waiting, not `failed`; `llama-swap` and the rest still run.
- Plug the YubiKey and touch it: the gated secret appears in `/run/secrets` without a reboot, and the
  waiting consumer starts.
- Non-YubiKey secrets still decrypt eagerly at activation (no regression).
- The behaviour is documented, and a unit that needs a gated secret neither blocks boot nor marks the
  system degraded.

## Related

- `hosts/brys` `kdn-llm-leaf-key.service`; `modules/universal/security/secrets/{sops,age}`;
  `hosts/etra/litellm-keys.sops.yaml` (a non-YubiKey example that must stay eager).
- The pinned-pkgs `status.md` note that the interactive `sops` CLI is no longer age-wrapped — the
  lazy-decrypt design should not depend on that CLI wrapper.
