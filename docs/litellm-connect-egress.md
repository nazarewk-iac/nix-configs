---
type: Guide
description: How the LiteLLM container reaches a SaaS upstream (Requesty) through a bound HTTP CONNECT proxy instead of a raw TLS relay, why the relay failed, and how to reuse the pattern for any confined container that needs authenticated internet egress.
timestamp: 2026-11-08T11:50:00+01:00
---

# Container SaaS egress via an HTTP CONNECT proxy

## The problem a raw TLS relay cannot solve

The LiteLLM container runs `privateNetwork`, so it has **no internet route**. The
first attempt used a `socat OPENSSL` relay on the bridge: the guest connects
plaintext to `10.233.100.1:8445`, socat opens TLS to `router.requesty.ai:443`.
It failed with HTTP 404. Cause: the client's **`Host` header is the relay
address** (`10.233.100.1:8445`) and the **SNI** is likewise the relay, so a
vhost-routed upstream (Requesty) serves its default vhost. A raw byte tunnel
cannot rewrite `Host`/SNI.

## Why an HTTP CONNECT proxy works

`HTTPS_PROXY=http://10.233.100.1:8888` makes the client issue
`CONNECT router.requesty.ai:443` to the proxy. The proxy dials **that hostname**,
then relays bytes; the client performs the **TLS handshake end-to-end with
Requesty**, so SNI and `Host` are correct. The proxy never sees plaintext and
never rewrites anything — it only opens and forwards the tunnel.

Result (measured): from inside the container, `proxy=200` to Requesty, while a
direct request is `000` (no own egress) — the proxy is the only way out.

## Implementation (hosts/etra/litellm.nix)

- Service `litellm-requesty-proxy` runs `tinyproxy -d` with
  `/etc/kdn/litellm-proxy.conf`, `DynamicUser`, sandboxed.
- Bind **only** `hostAddress` (`10.233.100.1`) on the litellm bridge, so only the
  guest (and not the LAN) can reach it. Firewall `ve-litellm` opens just that port.
- Container env:
  ```
  HTTPS_PROXY=http://10.233.100.1:8888
  HTTP_PROXY =http://10.233.100.1:8888
  NO_PROXY   =10.233.100.1        # local relays (brys/oams/redis) bypass the proxy
  ```
- Requesty deployments use `api_base = https://router.requesty.ai/v1` (direct URL;
  the proxy is chosen by env, not by the URL).

Config:
```
Port 8888
Listen 10.233.100.1
Timeout 600
Allow 10.233.100.2      # tinyproxy Allow/Deny are CLIENT-IP ACLs, not dest filters
ConnectPort 443         # CONNECT only on 443 (HTTPS)
LogLevel Info
```

## Gotchas (learned the hard way)

1. **`Allow` is a client-IP ACL.** It does **not** restrict the destination host.
   Use `Allow <guest-ip>` (here `localAddress`) and `ConnectPort 443` to bound
   the method/port. tinyproxy cannot hostname-filter CONNECT; the layer-3
   firewall + the fact that the proxy is the only egress is the real bound.
2. **Changing the proxy config does not restart the unit** on `nixos-rebuild
   switch` (no `restartTriggers`). `systemctl restart litellm-requesty-proxy`
   after editing, or add `restartTriggers` / `wantedBy`.
3. **The keys/config the container reads are the closure's files.** Adding a
   client key to the sops file needs a **container restart** (it bind-mounts the
   decrypted file). Restart `container@litellm` after a sops change.
4. `NO_PROXY` must list the bridge host so the local socat relays
   (`:8443`/`:8444`/`:6379`) are not sent through the proxy.

## Reusing the pattern

For any confined container that needs *authenticated* internet egress:

1. Run a CONNECT proxy on the bridge host address (tinyproxy/squid).
   `Allow <guest-ip>`, `ConnectPort <port>`; no auth needed (bridge-only).
2. Open only that port on the container's veth in the firewall.
3. Set `HTTPS_PROXY`/`HTTP_PROXY` in the container, with `NO_PROXY` for every
   local/bridge address it must reach directly.
4. Keep the client's URLs absolute (`https://real-host/...`); the proxy is chosen
   by env, so nothing else changes.

This avoids giving the container a route, avoids border-router NAT, and keeps a
single auditable egress point. Prefer it over a raw `socat OPENSSL` relay for any
TLS service that routes by `Host`.
