---
type: Solution
description: The four universal hosts oams, brys, etra and moss adopt kdn.certificates through the denLib.imports augmentation line and read certPath/keyPath in kdn.programs.zellij.web; the key-readability gap is closed by the owner option (D-A) and the missing kdn CA node by a shared managed CA (D-B); the real leaf signing run stays pending on the YubiKey.
timestamp: 2026-09-25T22:15:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

The zellij web certificate was a manual file pair. Each of the four hosts oams, brys, etra and moss
set `certFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.pub"` and
`keySopsFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.key.sops"` in its own
`kdn.programs.zellij.web` block (`hosts/oams/default.nix:347`, `hosts/brys/default.nix:484`,
`hosts/etra/default.nix:448`, `hosts/moss/default.nix:45`). A person produced both files by hand with
`hack/kdn-ca-sign.sh`, which decrypts `data/ca/ca.key.sops`, runs `openssl`, and SOPS-encrypts the
private key.

Nothing enumerated the certificate, and no consumer could read a certificate path. The four hosts are
universal (old-tree) hosts, so they declare no `kdn.certificates` option until sub-task 000's
augmentation line adds it.

## Solution

Each of the four hosts gained three things:

1. **The augmentation line** from [000-universal-augmentation](../000-universal-augmentation/done.md)
   in its own `imports`, wrapped in `{ imports = …; }` because `denLib.imports` returns a list:

   ```nix
   {
     imports = kdnConfig.self.denLib.imports {
       class = "nixos";
       aspects = [
         "ca-dag"
         "certificates"
       ];
     };
   }
   ```

   `den.default` is deliberately unused. Each host names the aspect itself.

2. **The explicit `repoRoot`** (decision D-A, option B): `kdn.certificates.repoRoot = kdnConfig.self;`.
   The aspect holds no implicit default, so the value is explicit even in this repository.

3. **The leaf declaration** from the frozen design § 4 and § 9:

   ```nix
   kdn.certificates.certs.zellij-web = {
     ca = "kdn";
     type = "tls-server";
     commonName = "<host>.priv.nb.net.int.kdn.im";
     sans = [ "<host>.priv.nb.net.int.kdn.im" ];
     directory = "hosts/<host>/certs";
     certFile = "zellij.pub";
     keyFile = "zellij.key";
     keySource = "managed";
   };
   ```

The `kdn.programs.zellij.web` block on each host now reads the two derived values and drops
`keySopsFile`:

```nix
certFile = config.kdn.certificates.certs.zellij-web.certPath;
keyFile = config.kdn.certificates.certs.zellij-web.keyPath;
```

`certPath` is a store path, so it feeds `certFile`. `keyPath` is the decrypted runtime path, so it
feeds `keyFile`. The storage rule is unchanged: the public certificate is `<directory>/<certFile>`,
plain and committed; the private key is `<directory>/<keyFile>.sops`, raw/binary SOPS.

No aspect code changed. No `.sops.yaml` rule changed. No `data/ca/` file changed. No real certificate
file was created.

## Verification steps

The declaration and the service read the two paths on all four hosts. Each command exits 0:

| Command | Result |
|---|---|
| `nix eval --no-eval-cache --json '.#nixosConfigurations.<host>.config.kdn.certificates.certs.zellij-web'` | the exact leaf values, with `certPath` a store path and `keyPath` `/run/secrets/kdn/certificates/zellij-web.key` |
| `nix eval --no-eval-cache --json '.#nixosConfigurations.<host>.config.home-manager.users.kdn.systemd.user.services.zellij-web.Service.ExecStart'` | `… --cert /nix/store/<hash>-source/hosts/<host>/certs/zellij.pub --key /run/secrets/kdn/certificates/zellij-web.key` |
| `nix run .#kdn-certs -- plan --flake .` | four `zellij-web  kdn  tls-server  missing` rows |

The toplevel `drvPath` is **pending on the real key files**. The exact command

```
NIX_CONFIG='netrc-file = /dev/null' nix eval --no-eval-cache --raw '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'
```

fails on all four hosts with:

```
Failed assertions:
- Cannot find path '/nix/store/<hash>-source/hosts/<host>/certs/zellij.key.sops' set in
  sops.secrets."kdn/certificates/zellij-web.key".sopsFile
```

The cause is sops-nix's `validateSopsFiles` default (`true`), which checks every `sops.secrets` file
at evaluation time. The migration introduces the `sops.secrets` entry, so the toplevel now needs the
`.sops` file that `kdn-certs apply` will write. With a temporary, uncommitted
`sops.validateSopsFiles = false` override, all four toplevels evaluate:

| Host | `drvPath` (validation off) |
|---|---|
| oams | `/nix/store/ki295xi992spcn26g2459qih52gwgfi0-nixos-system-oams-26.11.20260908.d6524aa.drv` |
| brys | `/nix/store/ahr1agx0aj3xwy8l0vb1cp62w0kkycr9-nixos-system-brys-26.11.20260908.d6524aa.drv` |
| etra | `/nix/store/p6gh63aba3j70186ywpy5ypvzpjpklyb-nixos-system-etra-26.11.20260908.d6524aa.drv` |
| moss | `/nix/store/56v669nf1v8z9s0hcdjsiq15gfy56cm2-nixos-system-moss-26.11.20260908.d6524aa.drv` |

So the code is complete and the toplevels evaluate once the four `.sops` files exist.

`nix run .#kdn-certs -- apply --flake . --dry-run` reported a second gap, now closed by decision
D-B. The leaf names `ca = "kdn"`, and no target declared `kdn.ca-dag.cas.kdn`. `data/ca/ca-dag.nix`
now declares the node once, and the four hosts import it. `kdn-certs apply --dry-run` no longer
reports a missing CA; the leaf is `missing` because its own key pair does not exist yet. See
Follow-up notes 2 and 3.

## Follow-up notes

**1 — The pending user step: the YubiKey signing run.** The four real pairs
`hosts/<host>/certs/zellij.{pub,key.sops}` do not exist. `kdn-certs apply` generates the key, signs
the certificate, writes the public certificate, and SOPS-encrypts the private key. The signing step
prompts for the YubiKey touch, because the `kdn` CA key is SOPS-encrypted to YubiKey identities. Run
`kdn-certs apply` at a YubiKey, then the four toplevels evaluate and acceptance steps 3 and 4
(`openssl verify` and the idempotent second run) pass.

**2 — The key-readability gap — RESOLVED (decision D-A).** The `kdn.certificates` sops wiring wrote
the key as a root-only secret: `owner = null`, `uid = 0`, `mode = "0400"`, path
`/run/secrets/kdn/certificates/zellij-web.key`. The zellij web service is
`systemd.user.services.zellij-web`, a **user** service, so it could not read a root-only file. The
old universal module solved this with a root oneshot `systemd.services.kdn-zellij-web-key` that
`chown`ed the decrypted key to `kdn`; the migration dropped `keySopsFile`, so that oneshot was gone
(measured: `systemd.services ? kdn-zellij-web-key` is `false`).

The user chose option (a) on 2026-09-25, an approved amendment to the frozen leaf shape. The leaf
option set gained `owner` (`nullOr str`, default `null`). When set, the aspect writes
`sops.secrets.<name>.owner = <owner>`; the `nixos` sops module then derives the group from the owner
(`users.<owner>.group`), and the `darwin` module keeps its `staff` default. The `homeManager` sops
module declares no `owner`, so that class ignores the value. The four hosts set `owner = "kdn"`, so
the zellij web user service reads the key. Measured on all four hosts:
`{ owner = "kdn"; group = "users"; mode = "0400"; path = "/run/secrets/kdn/certificates/zellij-web.key"; }`.

**3 — The missing `kdn` CA node — RESOLVED (decision D-B).** `kdn-certs apply` needed
`kdn.ca-dag.cas.kdn` to resolve the leaf's `ca = "kdn"`. No target declared it, so `apply` refused.
The user chose a **fresh managed CA** on 2026-09-25. `data/ca/ca-dag.nix` declares the node once, and
the four hosts import it: `kdn.ca-dag.cas.kdn` = root, `commonName = "KDN certificates root CA"`,
`directory = "data/ca"`, `certFile = "kdn.crt"`, `keyFile = "kdn.key"`, `keySource = "managed"`,
`ssh = true`. `kdn-certs ca init` now creates it for real: it generates the key, creates the
self-signed root, writes `data/ca/kdn.crt`, and SOPS-encrypts the key to `data/ca/kdn.key.sops`. The
`.sops.yaml` rule `data/ca/kdn\.key\.sops$` names the two unattended YubiKey identities only
(`yk-oams-unattended`, `yk-brys-unattended`), so `ca init` needs no touch and no PIN. The old
`data/ca/ca.pub` and `data/ca/ca.key.sops` are untouched. The rotation to a touch-required CA is
follow-up [007-ca-rotation](../007-ca-rotation/definition.md).

`data/ca/kdn.crt` verifies against itself and `data/ca/kdn.key.sops` holds exactly the two
unattended recipients. `kdn-certs apply` (leaf signing) still needs the unattended YubiKey identity
to decrypt the CA key, so the four leaf pairs stay pending on the user's run.

**4 — `den-eval-instantiate` is unverified on this host** (environmental `aarch64-darwin` pull), as
recorded in 001, 002 and 003. The host edits do not touch that check.
