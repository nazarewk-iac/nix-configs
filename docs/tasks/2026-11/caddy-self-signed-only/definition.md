---
type: Task
description: Make every Caddy vhost use the internal KDN CA only, and stop Caddy's automatic HTTPS from requesting public ACME certificates on brys, oams and etra.
status: done
authored_by: agent
timestamp: 2026-11-12T13:20:00+01:00
---

# Caddy must never request a public certificate

## Context

The fleet trusts one certificate authority: the self-signed KDN root in
`data/ca/ca.pub`. Every Caddy vhost is meant to load a leaf that the KDN CA signed, through
`tls <certPath> <key>` in `extraConfig`.

On 2026-11-12 the owner saw Caddy issue ACME challenges. The logs showed a second, unintended
behaviour: Caddy's **automatic HTTPS** was still on, so any site address with no `tls` directive
started a Let's Encrypt order.

## Root cause

The universal workstation profile wrote

```nix
kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.${config.kdn.hostName}.kdn.im";
```

on the line before it disabled the stack. The write was dead for Grafana (nothing listened on
`127.0.0.1:2342`), but the monitoring module still added a Caddy virtual host for
`grafana.<host>.kdn.im` with no `tls` line. Caddy then treated it as an automatic-HTTPS site and
requested a public certificate. Measured on brys and oams:

- `http-01` and `tls-alpn-01` attempts against `acme-v02.api.letsencrypt.org` and the staging
  directory, every few hours, all timing out (the name resolves to a public address that does not
  reach the host);
- Let's Encrypt rate limiting after five failed authorizations for the identifier.

The den port of the same profile already dropped the write
(`modules/den/aspects/profile-workstation.nix`), but brys and oams still use the universal module.

## Proposed approach

1. Remove the dead `caddy.grafana` write from the universal workstation profile.
2. Turn Caddy's automatic HTTPS off in every module that enables Caddy
   (`auto_https off` in `services.caddy.globalConfig`): the den `web-exposure` aspect, the den
   `service-caddy` aspect, and the universal `services/caddy` module. A vhost with an explicit
   `tls` line keeps serving HTTPS; a vhost without one can no longer start an ACME order.
3. Do not add a Grafana vhost when the monitoring stack is disabled.

## Out of scope

- Replacing the internal CA, or rotating the existing leaves.
- Public exposure and public certificates: see
  [`../moss-ingress-and-sso/definition.md`](../moss-ingress-and-sso/definition.md).

## Solution

[done.md](done.md)
