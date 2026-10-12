---
type: How-To
description: Generate zellij-web login tokens on the host, and connect from an Android phone (Firefox) or another Linux machine over the NetBird VPN.
timestamp: 2026-10-12T16:30:00+02:00
---

# Zellij web access

The zellij web interface serves terminal sessions over HTTPS. It runs on four hosts:
`oams`, `brys`, `etra` and `moss`. Each host runs the server as the systemd **user** service
`zellij-web`, as user `kdn`, on port `8082`, bound to `0.0.0.0`.

You need three things to connect:

1. A route to the host: the NetBird (a VPN, Virtual Private Network) interface `nb-priv`.
2. Trust of the TLS (Transport Layer Security) certificate: the root CA (Certificate
   Authority) from `data/ca/kdn.crt`.
3. A login token, created on the host.

## How the client reaches the server

The firewall on each host opens port `8082` only on the interface `nb-priv`. That interface
is a NetBird client named `priv` (`modules/universal/networking/netbird/default.nix` names
each interface `nb-<name>`; `modules/universal/profile/machine/baseline/default.nix` enables
`clients.priv`). Traffic from `nb-priv` is otherwise trusted (`hosts/etra/default.nix`).

Clients resolve `<host>.priv.nb.net.int.kdn.im` through NetBird's built-in DNS. The hosts
keep it enabled (`NB_DISABLE_DNS = "false"`). A client outside the NetBird network can
neither resolve nor reach the name.

So the reachability story is the same for a phone and a Linux machine: first join the
NetBird network, then open `https://<host>.priv.nb.net.int.kdn.im:8082/`.

## Generate a token on the host

Log in to the host, as the user that runs the sessions (`kdn`). Run the commands there.
The token CLI belongs to zellij 0.45.1.

Create a normal token (full interact):

```console
$ zellij web --create-token
```

Create a named token:

```console
$ zellij web --create-token --token-name phone
```

Create a read-only token. It can only watch existing sessions:

```console
$ zellij web --create-read-only-token --token-name watch
```

The token shows **once**. Copy it now. zellij stores only a hash of it, so you cannot read
it back later.

Manage tokens:

```console
$ zellij web --list-tokens        # names and creation dates, never the values
$ zellij web --revoke-token phone
$ zellij web --revoke-all-tokens
```

The tokens live in the web server's local database under `~/.local/share/zellij`. The
configuration persists that directory (`modules/den/aspects/zellij.nix`, comment "The web
server keeps its login tokens here"), so tokens survive a reboot. Revoke a token whenever
a device is lost.

Check the server:

```console
$ zellij web --status
```

## Connect from Firefox on an Android phone

1. Install the NetBird app from the Play Store (Google Play). Log in to the same NetBird
   account the hosts use. Confirm the tunnel is connected.
2. Install the root CA on the phone. Save `data/ca/kdn.crt` to the phone first, for
   example with `scp` or a messaging app. Then open:
   **Settings → Security → More connection settings → Encryption & credentials → Install
   a certificate → CA certificate**, and pick the file. Menu names differ per vendor.
3. Firefox on Android can use the OS certificate store. Since Android 14 the system lets
   apps trust user-installed CA certificates, and Firefox uses them. If the phone runs an
   older Android, expect Firefox to reject the certificate and use the SSH tunnel below.
4. Open Firefox and browse to:

   ```text
   https://<host>.priv.nb.net.int.kdn.im:8082/
   ```

5. Enter the login token on the welcome screen.
6. Optional: install the page as an app (PWA, Progressive Web App) from the Firefox menu.
   The web client switches to a mobile layout on its own, with an on-screen keyboard and
   pane pickers.

## Connect from another Linux machine

1. Join the same NetBird network with the NetBird client.
2. Install the root CA system-wide, so curl (the CLI transfer tool) and the browsers trust
   it. On Debian-like systems, copy `data/ca/kdn.crt` and run:

   ```console
   $ sudo cp kdn.crt /usr/local/share/ca-certificates/kdn.crt
   $ sudo update-ca-certificates
   ```

   On NixOS, add the file to `security.pki.certificateFiles`.

3. For a browser that uses the NSS (Network Security Services) database, for example
   Chrome, add the CA there too:

   ```console
   $ mkdir -p "$HOME/.pki/nssdb"
   $ certutil -d sql:"$HOME/.pki/nssdb" -A -t "C,," -n "KDN certificates root CA" -i kdn.crt
   ```

4. Browse to `https://<host>.priv.nb.net.int.kdn.im:8082/` and enter the token.

Or skip the browser and attach from a terminal:

```console
$ zellij attach https://<host>.priv.nb.net.int.kdn.im:8082/<session> --token <TOKEN> --ca-cert kdn.crt
```

Add `--remember` to store the credentials for four weeks. Add `--insecure` only when you
skip certificate checks, which is not needed with the CA installed.

## SSH tunnel fallback

Without NetBird, forward the port through SSH (Secure Shell) to the host:

```console
$ ssh -L 8443:localhost:8082 kdn@<host>
```

Browse to `https://localhost:8443/`. The certificate names
`<host>.priv.nb.net.int.kdn.im`, not `localhost`, so the browser shows a name-mismatch
warning. Accept it only on a link you trust, or keep NetBird as the normal path.

## Per-host notes

All four hosts use the same settings: port `8082`, interface `nb-priv`, user `kdn`, bind
`0.0.0.0`. Each host has its own leaf certificate `zellij-web`, CN/SAN
`<host>.priv.nb.net.int.kdn.im`, signed by the CA node `kdn.ca-dag.cas.kdn`. The public
root is `data/ca/kdn.crt` (CN "KDN certificates root CA"). The private key is
SOPS-encrypted at `hosts/<host>/certs/zellij.key.sops` and decrypted at runtime by
sops-nix; the systemd unit reads the decrypted path. No other host (for example `gaz`)
runs the web interface.

## Certificate lifetime and renewal

Each `zellij-web` leaf is valid for 90 days (the TLS default `2160h` in
`packages/kdn-certs/internal/generate/generate.go`; the earlier `step` default of 24 hours expired
all four leaves the day after the first issuance, fixed 2026-10-12). Renew before expiry:

1. On a machine holding the unattended YubiKey (oams or brys), inside this repo:

   ```console
   $ nix run .#kdn-certs -- apply            # or `--dry-run` to list reasons first
   ```

   An expired leaf reports reason `expired` and is re-signed with a fresh key.
2. Commit the changed `hosts/<host>/certs/zellij.pub` and `zellij.key.sops`.
3. Activate each affected host (`nixos-rebuild switch`), then restart the user service — the
   activation may leave the old process holding the old certificate:

   ```console
   $ ssh <host> systemctl --user restart zellij-web
   ```

4. Verify:

   ```console
   $ curl -s --cacert data/ca/kdn.crt -o /dev/null -w '%{http_code}\n' https://<host>.priv.nb.net.int.kdn.im:8082/
   $ openssl s_client -connect <host>:8082 -servername <host>.priv.nb.net.int.kdn.im </dev/null 2>/dev/null | openssl x509 -noout -enddate
   ```

## Sources

- `modules/den/aspects/zellij.nix` and `modules/universal/programs/zellij/default.nix` —
  the web aspect and module: user service, options, firewall, token storage comment. The
  host blocks use `kdn.programs.zellij.web`.
- `hosts/{oams,brys,etra,moss}/default.nix` — per-host web block and certificate block.
- `modules/universal/networking/netbird/default.nix` — interface naming `nb-<name>`.
- `modules/universal/profile/machine/baseline/default.nix` — enables `clients.priv` and
  NetBird DNS.
- <https://zellij.dev/documentation/web-client.html> — token flags, URL scheme, mobile
  support, `zellij attach` over HTTPS.
