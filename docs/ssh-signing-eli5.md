---
type: Guide
description: A plain-language explanation of SSH certificates (user and host) and how to use them on both the client and the server side in this repo.
timestamp: 2026-10-12T22:39:55+02:00
authored_by: agent
---

# SSH certificates, ELI5

**The normal way.** Each server keeps a list of allowed keys in `authorized_keys`. Each client keeps
a copy of each server key in `known_hosts`. Add one machine, and you must copy a key to every other
machine. The lists grow and grow.

**The certificate way.** One office — the Certificate Authority (CA) — holds one key pair. The office
puts a stamp on keys. Everyone trusts the stamp, not the key. Two stamps exist:

- A **user certificate** says "this is kdn". The server reads the stamp and lets kdn in. No
  `authorized_keys` line.
- A **host certificate** says "this server is really brys". The client reads the stamp and trusts the
  server. No pinned key in `known_hosts`.

A stamp is short-lived, so a stolen stamp expires.

## The picture

```
              CA (one key pair, offline or on a YubiKey)
               |                            |
     signs your key                signs the server key
               |                            |
    user certificate                host certificate
      (says: kdn)                     (says: brys)
               |                            |
  client shows it ----------------> server checks it (TrustedUserCAKeys)
  client checks it <--------------- server shows it (HostCertificate)
```

## Client side (oams)

One time:

1. Run `kdn-certs ssh login brys`. The CA signs your public key and writes
   `~/.ssh/id_ed25519-cert.pub`.
2. The drop-in `~/.ssh/config.d/50-kdn-ssh-ca.config` names the certificate and the CA trust file.
3. The trust file `~/.ssh/known_hosts.d/50-kdn-ssh-ca` holds one line:
   `@cert-authority * <CA public key>`.

Then log in:

```
ssh brys
```

Renew the certificate when it expires (default 8 hours):

```
kdn-certs ssh login brys
```

## Server side (brys)

The `ssh-ca` aspect writes these `sshd_config` lines:

| Line | Job |
|---|---|
| `TrustedUserCAKeys <CA public key>` | Accept each user certificate the CA signs. |
| `HostKey <private key>` + `HostCertificate <cert>` | Show the host certificate to each client. |

To add a host in this repo:

1. Add `"ssh-ca"` to the host `denLib.imports` aspects.
2. Declare one leaf:

```nix
kdn.certificates.certs.ssh-host-<name> = {
  ca = "kdn"; type = "ssh-host";
  commonName = "<name>";
  principals = [ "<name>" "<name>.lan.etra.net.int.kdn.im" ];
  directory = "hosts/<name>/certs";
  certFile = "ssh_host_ed25519-cert.pub";
  keyFile = "ssh_host_ed25519.key";
  keySource = "managed";
};
```

3. Sign it with `nix run .#kdn-certs -- apply`. Then activate the host.

## Two facts that bite

- **The stamp expires.** A user certificate lives 8 hours by default. A host certificate lives 90
  days.
- **A trailing dot is a different name.** OpenSSH does not strip the dot. The host certificate must
  name `brys.lan.etra.net.int.kdn.im.` as well as `brys.lan.etra.net.int.kdn.im`. The repo now does
  this for each FQDN principal.

The full operator guide is [ssh-signing.md](ssh-signing.md).
