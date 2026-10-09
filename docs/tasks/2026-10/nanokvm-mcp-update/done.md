---
type: Solution
description: The OTA failed because 2.4.3 whitelists download Content-Types and Sipeed's CDN answers the 2.5.2 package as `application/x-compressed`. Fixed by an offline install over SSH; MCP then enabled and proven.
task: definition.md
authored_by: agent
timestamp: 2026-10-10T02:30:00+02:00
---

# Solution

## Root cause

The 2.4.3 app OTA downloads the package with a `utils.Download` helper that **whitelists the HTTP
`Content-Type`** to `application/octet-stream`, `application/zip`, `application/gzip`. Sipeed's CDN
(Qiniu / openresty) serves `nanokvm_2.5.2.tar.gz` as **`application/x-compressed`**, which is not
on that whitelist. The download aborts with `unsupported content type` after three retries, before
`/kvmapp` is touched.

Evidence:
- The package itself is fine. Downloaded from the device: `Content-Type: application/x-compressed`,
  size `16594889` = manifest, sha256 `cffd68bf…` = the GitHub release sha256, untars cleanly.
- No install side-effects: `/root/old/version` was a stale `2.3.6`, `/kvmapp/version` stayed
  `2.4.3`, no `/root/.kvmcache`, no partial `2.5.2` tree.
- Not disk (6.5 GB free on `/`), not RAM, not DNS, not TLS — all verified good from the device.
- The failing attempt predates log retention: syslog lives on tmpfs `/tmp/messages` and the kernel
  `VPSS waitq is full` flood rotated it away. There is **no persistent update log** by default
  (logrus writes to stdout).

This is an upstream defect (CDN MIME versus the client whitelist). It will keep failing over OTA.

## Fix — offline install over SSH, no reflash

2.4.3 ships the offline package under a second, non-whitelisted code path, but the web route needs
an admin login. Did the equivalent directly as root instead, keeping the old tree for rollback:

```sh
# download from the preview channel (the stable `latest.json` still advertises 2.4.3)
cd /root/update
curl -sSfL -o nanokvm_2.5.2.tar.gz https://cdn.sipeed.com/nanokvm/preview/nanokvm_2.5.2.tar.gz
sha256sum nanokvm_2.5.2.tar.gz          # cffd68bfac0d83de0f722036aea52c971d58a3a0ed3315e1dc3146276530b909
python3 -c "import tarfile; tarfile.open('nanokvm_2.5.2.tar.gz').extractall()"   # busybox tar has no -z

/etc/init.d/S95nanokvm stop
mv /kvmapp /root/old-2.4.3
mv /root/update/nanokvm_2.5.2 /kvmapp
chmod -R go+rX /kvmapp
/etc/init.d/S95nanokvm start
```

After: `/kvmapp/version` = `2.5.2`, ports 80/443 served by the new `/tmp/server/NanoKVM-Server`
(md5 matches `/kvmapp/server/NanoKVM-Server`). `/kvmapp/picoclaw` was identical to the new bundle,
so nothing local was lost. Rollback: `mv /kvmapp <new>; mv /root/old-2.4.3 /kvmapp; restart`.

One gotcha: `S95nanokvm stop` runs `killall NanoKVM-Server`, but a stale listener briefly kept
the port; re-check `ss -tlnp` and confirm the serving PID's `/proc/<pid>/exe` matches the new
binary.

## Enabling MCP (added in 2.5.0, not 2.5.2)

The MCP server runs **inside** `NanoKVM-Server` at **`POST/GET /api/mcp`** — Streamable HTTP,
stateless, JSON. Not stdio. Two gates must both pass:

1. Control mode must be `mcp`. File `/etc/kvm/ai-control.mode` holds `off`, `mcp`, or `picoclaw`
   (default `picoclaw`). Set: `printf 'mcp\n' > /etc/kvm/ai-control.mode`.
2. An API key in `/etc/kvm/mcp.json` (`{"apiKey":"nag_mcp_<base64url>"}`, mode `0600`). Requests
   carry `Authorization: Bearer nag_mcp_…`. The key is normally generated and regenerated through
   the admin web Settings; a device-local random key works identically. **The key is not stored in
   this repo.**

Both files are read live; no restart needed.

Verified handshake from the device: `initialize` → `serverInfo nanokvm-cube-remote-control v1.0.0`
with an `Mcp-Session-Id`. `tools/list` returns:
`cube_screenshot`, `cube_type_text`, `cube_press_keys`, `cube_move_mouse`, `cube_click_mouse`,
`cube_scroll_mouse`. `cube_screenshot` returns a live JPEG of the `anji` console.

## Follow-ups (not blocking)

- Upstream: report the `application/x-compressed` whitelist mismatch, and the inconsistent manifest
  units (stable `latest.json` uses `size`, preview uses `size_bytes`).
- Point syslog off tmpfs, or set `logger.file` in `/etc/kvm/server.yaml`, so the next failure leaves
  evidence behind the `VPSS waitq is full` flood.
- To wire the KVM into an agent as a tool, register the MCP endpoint with a Bearer key; keep the key
  in the sops secret store, not in the repo.
