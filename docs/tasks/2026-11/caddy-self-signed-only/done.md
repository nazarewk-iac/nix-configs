---
type: Solution
description: Remove the dead Grafana vhost and set `auto_https off` in every Caddy-owning module, so no vhost can start a public ACME order; verified by evaluation on brys, oams and etra.
task: definition.md
authored_by: agent
timestamp: 2026-11-12T13:20:00+01:00
---

# Self-signed CA only: the fix

## Changes

| File | Change |
| --- | --- |
| `modules/universal/profile/machine/workstation/default.nix` | Remove `kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.<host>.kdn.im"`. It was dead (the next line disables the stack) and it created a vhost with no TLS. |
| `modules/den/aspects/web-exposure.nix` | Set `services.caddy.globalConfig = "auto_https off"` next to `services.caddy.enable = true`. |
| `modules/den/aspects/service-caddy.nix` | Same. |
| `modules/universal/services/caddy/default.nix` | Same. |
| `modules/universal/monitoring/prometheus-stack/default.nix` | Create the Grafana vhost only when `cfg.enable` holds; document that the vhost carries no TLS of its own. |
| `modules/den/aspects/monitoring.nix` | Document the same on the `caddy.grafana` option. |

`services.caddy.globalConfig` is a `types.lines` option, so the aspect value and the nixpkgs
module value (log settings, ports) concatenate.

## Why `auto_https off` and not a per-vhost switch

Automatic HTTPS is a property of the whole Caddy process, not of one site. A per-vhost fix only
covers the vhosts that exist today; the next consumer that writes a `virtualHosts` entry without a
`tls` line starts a new ACME order. `auto_https off` makes the policy true for every vhost, now and
later. A vhost that carries `tls <cert> <key>` still serves HTTPS, because the `tls` directive
explicitly enables it.

## Verification

Evaluated on the three Caddy hosts (C8):

```bash
nix eval --raw .#nixosConfigurations.brys.config.services.caddy.globalConfig
# -> "auto_https off" plus the nixpkgs log block
nix eval --json .#nixosConfigurations.brys.config.services.caddy.virtualHosts --apply builtins.attrNames
# -> ["brys.priv.nb.net.int.kdn.im","llama-swap...","prometheus..."]   (no grafana entry)
```

The same two commands on `oams` and `etra` give the same result: no `grafana.<host>.kdn.im`
vhost, and `auto_https off` present.

Aspect checks:

```bash
nix build --no-eval-cache -L .#checks.x86_64-linux.den-eval-services
# den eval services: 48 of 48 assertions pass
nix build --no-eval-cache -L .#checks.x86_64-linux.den-eval-coverage-gaps
# den eval coverage-gaps: 7 of 7 assertions pass
nix build --no-eval-cache -L .#checks.x86_64-linux.den-eval-toolset-small
# den eval toolset-small: 14 of 14 assertions pass
```

`den-eval-machine-profiles` fails on a pre-existing breakage that this change does not touch:
`checks/den-mvp/assertions/machine-profiles.nix` reads `boot.initrd.systemd.enable`, which the
current nixpkgs removed.

## What the owner must do to activate it

Build and activate `brys`, `oams` and `etra`. After activation the ACME retry loop stops. Existing
Let's Encrypt state in `/var/lib/caddy` (an account key, an order) is harmless; delete
`/var/lib/caddy/.local/share/caddy` only if it must be gone.
