---
type: Task
description: Expose homelab services to the public internet through moss as the single public entrypoint, behind one authentication/SSO layer, with etra as the internal routing hub.
status: open
authored_by: agent
timestamp: 2026-11-07T14:05:34+01:00
---

# Public ingress through moss behind SSO

## Context

Today every service is reachable only on the LAN or over NetBird. The end state
is a single public access point on `moss` that fronts the homelab, with two
primary goals and one secondary goal.

Status: far-future. Do not refine details until the prerequisites land.

## Goals

1. **Public access point through `moss`.** One public entrypoint; the homelab's
   public IP address stays hidden behind it. `moss` is the only host with a
   publicly reachable address.
2. **Comprehensive authentication before exposure.** Nothing is exposed to the
   internet until a single authentication/SSO layer guards all of it. This is the blocker:
   the exact authentication/SSO product and the policy are undecided.
3. **`etra` as the internal entrypoint.** `etra` routes all other services
   through itself, so `moss` only needs one upstream (etra) and internal
   topology stays behind it.

## Shape (tentative)

- `moss` runs a reverse proxy. It picks the certificate per exposed
  service: an internal-CA leaf for internal/mesh-only endpoints, a public
  certificate for anything served to the internet.
- The traffic path is: `internet → moss (auth + TLS) → etra → service`.
  `etra` stays the internal routing hub; `moss` is the public edge.
- Optional early step: expose the same HTTP(S) ports from `moss` **over NetBird
  only** and validate TLS, routing, and auth middleware before opening any port
  to the internet. This validation is optional.

## Open questions / blockers

- Which authentication/SSO system (e.g. an OIDC provider plus a forward-auth proxy),
  and whether it sits on `moss` or on `etra`.
- A per-service policy or one global gate.
- Which services need public exposure in the first round.
- Certificate automation for public certs (ACME) and how it coexists with the
  internal CA on the same host.
- Where DNS/records for public names live.

## Out of scope

- Implementation. The per-host `:443` exposure work and the `etra` routing hub
  must land first.
