---
type: Research
description: An evaluation-verified inventory of every consumer, key path, and hard coupling of the default sops file.
authored_by: agent
timestamp: 2026-09-09T10:24:48+02:00
---

# Default sops file inventory

Task: [generalization-008-sops-default-inventory.md](definition.md).
Hub: [../generalization-plan.md](../definition.md). Feeds checkpoint 009.

This pass changes no module. It records four lists, and it verifies every absent-file cell by
evaluation.

## Question

What depends on the default sops file `default.unattended.sops.yaml`, on its key layout, and on
its path? Which consumers stop evaluation when the derived secret set is empty?

## Verdict

1. **Two absent-file modes exist, and only one of them keeps the tree evaluable.** Mode A turns
   the allow switch off. Mode B leaves the allow switch on and removes the file. Mode B always
   stops evaluation inside the discovery engine. So 009 must pair the absent folder with
   `kdn.security.secrets.allow = false`.
2. **Mode A already evaluates for the hosts in the tree today.** `nixosConfigurations.oams`,
   `nixosConfigurations.moss`, and `darwinConfigurations.anji` all produce a `toplevel` drvPath
   with the allow switch off. `nixosConfigurations.etra` does not.
3. **The tailscale defect is real, and the current tree hides it.** The option `type` at
   `modules/universal/networking/tailscale/default.nix:17` fails as task 008 states. It fails only
   when something forces the option. `modules/universal/profile/machine/baseline/default.nix:347`
   sets `kdn.networking.tailscale.enable = false`, and no host turns it on. So `toplevel` never
   forces the option value. One extra definition (`enable = true`) turns the latent defect into a
   hard `toplevel` failure. An adopter hits it at once.
4. **Two more unguarded module-level consumers exist**, both of the same shape as tailscale:
   `modules/universal/networking/netbird/default.nix:83` (an option `default`) and
   `modules/universal/services/nextcloud-client-nixos/default.nix:18-20` (a top-level `let`).
5. **The host `etra` holds five unguarded consumers** — three of the default file, two of
   `dns.sops.yaml`. It is the only host that fails mode A.
6. **Four sites pin the default file path**, not three: three in
   `modules/universal/profile/default-secrets/default.nix` plus one in
   `modules/universal/profile/remote-builders/default.nix:195`.
7. **No slot reads the default sops file.** `modules/slots/ca/default.nix` mentions `.key.sops`
   file names only, and it never touches `config.sops.*` or `kdn.security.secrets.*`.

## Context — how the mechanism works

### The four `files.*` entries that read the default file

Each entry declares a `namePrefix` (the attr name by default) and a `keyPrefix`. The engine at
`modules/universal/security/secrets/sops/default.nix:80-123` derives one sops-nix secret per
discovered key, named `<namePrefix>/<key-without-keyPrefix>`.

| Entry | Declared at | `keyPrefix` | Secret count | Secret name shape |
|---|---|---|---|---|
| `default` | `modules/universal/profile/default-secrets/default.nix:20-22` | `""` | 65 | `default/<full key>` |
| `networking` | `modules/universal/profile/default-secrets/default.nix:23-28` | `networking` | 47 | `networking/<key>` |
| `anonymization` | `modules/universal/profile/default-secrets/default.nix:83-88` | `anonymization` | 1 | `anonymization/<key>` |
| `ssh` | `modules/universal/profile/remote-builders/default.nix:193-198` | `nix/ssh` | 2 | `ssh/<user>/<file>` |

The `default` entry has an empty `keyPrefix`, so it maps the whole file a second time under the
`default/` name prefix. That is why one key reaches the tree under two names — for example
`networking/wlan/<ssid>/password` and `default/networking/wlan/<ssid>/password`.

Measured on `nixosConfigurations.oams`: 115 of the 117 `config.sops.secrets` entries come from the
default file. The other 2 come from `llms.nonsensitive.sops.yaml`.

### The two derived sets

- `config.kdn.security.secrets.sops.secrets` — `modules/universal/security/secrets/sops/default.nix:145-157`.
  It splits each secret name on `/` and merges the parts into a nested attrset.
- `config.kdn.security.secrets.sops.placeholders` — same file, lines 129-143. Same split, but the
  leaf is a sops-nix placeholder string.

Both defaults start from `safeSopsSecrets` (line 11), which is `config.sops.secrets` in the nixos,
darwin, and home-manager module types, and `{ }` elsewhere.

`modules/universal/security/secrets/sops/default.nix:223-230` assigns `sops.secrets` under
`lib.mkIf config.kdn.security.secrets.allow`. `allowed` is `allow && enable`
(`modules/universal/security/secrets/default.nix:17-21`).

### The two absent-file modes

| Mode | Trigger | Behaviour | Tag |
|---|---|---|---|
| A | `kdn.security.secrets.allow = false` | Both derived sets are `{ }`. The engine never reads the file, so the file may also be absent. | verified |
| B | `allow = true` and the path does not exist | `lib/sops/default.nix:41` calls `builtins.readFile`. Evaluation stops with `opening file '<path>': No such file or directory`. | verified |

Mode A plus an absent file also evaluates: `oams` produces a `toplevel` drvPath with the allow
switch off and all four `sopsFile` paths redirected to a path that does not exist.

## Method

The harness lives in `/tmp/sopsinv`. It creates no file in the repo tree, and the working copy
stays clean.

- `nix-instantiate --eval --argstr … <file>` auto-calls a top-level function, so a `getFlake`
  against the working tree needs no `--impure` flag.
- Each probe calls `extendModules` on the real host attr and adds one module:
  `{ kdn.security.secrets.allow = lib.mkForce false; }`.
- A probe forces the narrowest expression that reads the derived set, through
  `builtins.deepSeq`.
- `builtins.tryEval` is **not** usable here. Lix catches `AssertionError` and `ThrownError` only,
  so an `attribute '<x>' missing` error escapes it. Each row therefore needs its own process.
- `lib.mkForce` does **not** silence a bad definition. `lib/modules.nix` discharges every
  definition when it computes an option value, so it also forces a lower-priority definition.
  Source-level stubs are the only way past an unguarded host definition. So this pass probes the
  etra rows one option at a time instead.

Positive control: each probe also ran with `allow = true`, and each one returns a value.
`nixosConfigurations.brys` fails in both modes on an assertion that has no link to sops
(`Kubernetes cluster is pinned to unsupported version!`). That host gives no signal here.

## List 1 — the key schema

65 keys, grouped by top-level key. An adopter must supply this layout to reuse the affected
modules. Each row names the shape the consumer expects.

| Top-level key | Key shape | Count | Value shape the consumer expects | Read by |
|---|---|---|---|---|
| `tailscale` | `tailscale/default/auth_keys/<name>` | 3 | attrset of names; each leaf needs `.path` | `modules/universal/networking/tailscale/default.nix:11,17,33` |
| `netbird` | `netbird/<client>/<type>/setup-key`, `netbird/<client>/env` | 5 | attrset keyed by client, then by type; leaf needs `.path` | `modules/universal/networking/netbird/default.nix:83,249,262` |
| `atuin` | `atuin/username`, `atuin/password`, `atuin/key` | 3 | three strings; each needs `.path` | `modules/universal/programs/atuin/default.nix:249-251` |
| `nextcloud` | `nextcloud/nixos/{url,username,password}` | 3 | three strings; each needs `.path` | `modules/universal/services/nextcloud-client-nixos/default.nix:18-20` |
| `nix` | `nix/access-tokens/<host>` | 1 | attrset of host names; leaf is a placeholder string | `modules/universal/profile/default-secrets/default.nix:56` |
| `nix` | `nix/ssh/<user>/id_*` and `nix/ssh/<user>/id_*.pub` | 2 | attrset keyed by user, then by file name; leaf needs `.path` | `modules/universal/profile/remote-builders/default.nix:19` |
| `anonymization` | `anonymization/<entry>/pattern` | 1 | attrset of entries; the leaf is a file on disk under `basePath` | consumed at runtime by `kdn-anonymize`, not at evaluation |
| `networking` | `networking/wlan/<ssid>/password` | 15 | attrset keyed by SSID; each leaf needs `.password.path` | `modules/universal/profile/machine/basic/default.nix:113` |
| `networking` | `networking/hosts/<name>` | 1 | attrset of names; each leaf is a placeholder string | `modules/universal/profile/default-secrets/default.nix:33` |
| `networking` | `networking/iperf-server/rsa/{priv,pub}`, `networking/iperf-server/users.csv`, `networking/iperf-server/users/<user>` | 4 | `.path` on three leaves, plus an attrset of user names | `modules/universal/services/iperf3/default.nix:37,39,64` |
| `networking` | `networking/ipv4/network/<...>` | 4 | nested placeholder strings, plus one `.path` | `hosts/etra/default.nix:389` |
| `networking` | `networking/ipv6/network/<name>/<...>/{address,netmask,network}` | 17 | nested placeholder strings, plus one `.path` | `hosts/etra/default.nix:11,219,247,253,268,285,391` |
| `networking` | `networking/anonymization/<entry>/pattern` | 4 | file on disk under `basePath` | consumed at runtime, not at evaluation |
| `networking` | `networking/ssh_config/<name>`, `networking/ssh_hosts` | 2 | file on disk under `basePath` | consumed at runtime, not at evaluation |

Two shapes matter most for 009, because a consumer indexes them by a literal name:

- `tailscale/default/auth_keys/*` — the consumer calls `builtins.attrNames` on the parent, so the
  parent must exist as an attrset.
- `networking/iperf-server/users/*` — the consumer calls `builtins.attrNames` then
  `builtins.head`, so the parent must hold at least one entry.

## List 2 — the consumers

`Guard` names the condition that stops the read. `Guard position` states where the read sits.
`Mode A` is the verified behaviour with the allow switch off.

| # | File and line | Key path it reads | Guard | Guard position | Mode A behaviour | Tag |
|---|---|---|---|---|---|---|
| 1 | `modules/universal/networking/tailscale/default.nix:11` | `secrets.default.tailscale.default.auth_keys` | none | top-level `let` | fails when Nix forces the option | **verified** |
| 2 | `modules/universal/networking/tailscale/default.nix:17` | the same value, through `builtins.attrNames` | none | option `type` (`lib.types.enum`) | fails when Nix forces the option | **verified** |
| 3 | `modules/universal/networking/tailscale/default.nix:33` | `authKeys."<key>".path` | `lib.mkIf cfg.enable`, then `lib.mkIf (cfg.auth_key != null)` | inside `config` | fails; row 2 fails first | **verified** |
| 4 | `modules/universal/networking/netbird/default.nix:83` | `secrets.default.netbird` | none | submodule option `default` (`readOnly`) | fails when Nix forces the option | **verified** |
| 5 | `modules/universal/networking/netbird/default.nix:246,249,257,259,262` | `nbCfg.secrets."<type>".setup-key.path`, `nbCfg.secrets.env.path` | `lib.mkIf config.kdn.security.secrets.allowed` (line 242) | inside `config` | evaluates | **verified** |
| 6 | `modules/universal/profile/machine/basic/default.nix:113` | `secrets.networking.wlan` | `lib.mkIf config.kdn.security.secrets.allowed` (line 114) | inside `config` | evaluates | **verified** |
| 7 | `modules/universal/services/iperf3/default.nix:37` | `secrets.default.networking.iperf-server.rsa.priv.path` | `lib.mkIf config.kdn.security.secrets.allowed` (line 30) | inside `config` | evaluates | **verified** |
| 8 | `modules/universal/services/iperf3/default.nix:39` | `secrets.default.networking.iperf-server."users.csv".path` | same as row 7 | inside `config` | evaluates | **verified** |
| 9 | `modules/universal/services/iperf3/default.nix:64` | `secrets.default.networking.iperf-server.users` | same as row 7 | inside `config` | evaluates | **verified** |
| 10 | `modules/universal/programs/atuin/default.nix:249` | `config.sops.secrets."default/atuin/username"` | `lib.mkIf config.kdn.security.secrets.allowed` (line 227) | inside `config` | evaluates | **verified** |
| 11 | `modules/universal/programs/atuin/default.nix:250` | `config.sops.secrets."default/atuin/password"` | same as row 10 | inside `config` | evaluates | **verified** |
| 12 | `modules/universal/programs/atuin/default.nix:251` | `config.sops.secrets."default/atuin/key"` | same as row 10 | inside `config` | evaluates | **verified** |
| 13 | `modules/universal/services/nextcloud-client-nixos/default.nix:18` | `config.sops.secrets."default/nextcloud/nixos/url"` | `lib.mkIf cfg.enable` (line 38) only; the `allowed` test sits at the enable site, `modules/universal/profile/machine/baseline/default.nix:360` | top-level `let`; `config` forces it | evaluates on the current hosts; fails when a consumer sets `enable = true` | **verified** |
| 14 | `modules/universal/services/nextcloud-client-nixos/default.nix:19` | `config.sops.secrets."default/nextcloud/nixos/username"` | same as row 13 | top-level `let` | same as row 13 | **verified** |
| 15 | `modules/universal/services/nextcloud-client-nixos/default.nix:20` | `config.sops.secrets."default/nextcloud/nixos/password"` | same as row 13 | top-level `let` | same as row 13 | **verified** |
| 16 | `modules/universal/profile/remote-builders/default.nix:19` | `secrets.ssh or { }` | `kdnConfig.util.hasSops && config.kdn.security.secrets.allowed`, plus an `or { }` fallback | top-level `let` | evaluates | **verified** |
| 17 | `modules/universal/profile/default-secrets/default.nix:33` | `placeholders.networking.hosts` | `lib.mkIf config.kdn.security.secrets.allowed` (line 32) | inside `config` | evaluates | **verified** |
| 18 | `modules/universal/profile/default-secrets/default.nix:56` | `placeholders.default.nix.access-tokens` | same as row 17 | inside `config` | evaluates | **verified** |
| 19 | `modules/universal/managed/default.nix:151` | `config.sops.templates` (iterate, no index) | `lib.mkIf config.kdn.security.secrets.allowed` (line 150) | inside `config` | evaluates; the shape is safe on `{ }` | **verified** |
| 20 | `hosts/etra/default.nix:11`, read at `219,247,253,268,285` | `placeholders.networking.ipv6.network.<name>.<net>` | none | inside `config`, as `kdn.networking.router.*` definitions | fails | **verified** |
| 21 | `hosts/etra/default.nix:389` | `config.sops.secrets."networking/ipv4/network/isp/uplink/address/client"` | none | inside `config` | fails | **verified** |
| 22 | `hosts/etra/default.nix:391` | `config.sops.secrets."networking/ipv6/network/isp/prefix/etra/address/gateway"` | none | inside `config` | fails | **verified** |

Rows 20-22 are the reason `nixosConfigurations.etra` does not evaluate in mode A.

### Guard position beats guard

Rows 3, 5, and 13 show why the task asks for the position column:

- Row 3 carries `lib.mkIf cfg.enable`, and it is still unsafe, because row 2 in the same file
  reads the same value from an option `type`.
- Row 5 carries the correct guard, and the option `default` it reads (row 4) carries none. The
  guard saves the tree only because Nix never forces the option.
- Row 13 carries no `allowed` test of its own. The profile at
  `modules/universal/profile/machine/baseline/default.nix:360` supplies one, so the module is
  safe in this repo and unsafe in an adopter repo.

## List 3 — the unguarded consumers

These rows fail in mode A. The work list for 009, in order of fix effort — cheapest first.

| Rank | Site | Failure | Fix shape | Effort |
|---|---|---|---|---|
| 1 | `modules/universal/networking/netbird/default.nix:83` | `attribute 'default' missing` | Change the `let` to `config.kdn.security.secrets.sops.secrets.default.netbird or { }`. The next line already tests membership with `?`. | `or` fallback — one line |
| 2 | `modules/universal/services/nextcloud-client-nixos/default.nix:18-20` | `attribute '"default/nextcloud/nixos/password"' missing` | Move the three reads behind the module's own `lib.mkIf config.kdn.security.secrets.allowed`, or add an assertion that states the requirement. | guard move — one block |
| 3 | `modules/universal/networking/tailscale/default.nix:11,17` | `attribute 'default' missing`, raised from an option `type` | Make the `let` use `or { }`, and relax the `type` from `lib.types.enum` to `nullOr str` plus an assertion. An `enum` over discovered data cannot stay lazy. | lazier option type — two edits |
| 4 | `hosts/etra/default.nix:389,391` | `attribute '"networking/ipv4/…"' missing` | Read through a helper that returns a placeholder path when the secret is absent, or move both definitions behind `lib.mkIf config.kdn.security.secrets.allowed`. | guard move — two lines |
| 5 | `hosts/etra/default.nix:11` (read at `219,247,253,268,285`) | `attribute 'networking' missing` | The five reads feed `kdn.networking.router.networks.*` address and prefix strings. A guard cannot cover them, because the router needs the values. This host needs its personal network data in the personal data folder, and it needs a documented "no personal data, no router" state. | real restructure |

Rank 5 is the only row that needs design work. Ranks 1 to 4 are mechanical.

## List 4 — the hard couplings

### Sites that pin the default file path

Four sites, not three. Every one interpolates `kdnConfig.self`, so the file must sit at the flake
root.

| # | Site | Entry |
|---|---|---|
| 1 | `modules/universal/profile/default-secrets/default.nix:21` | `default` |
| 2 | `modules/universal/profile/default-secrets/default.nix:25` | `networking` |
| 3 | `modules/universal/profile/default-secrets/default.nix:85` | `anonymization` |
| 4 | `modules/universal/profile/remote-builders/default.nix:195` | `ssh` |

### Sites that pin a key layout

| Site | Coupling |
|---|---|
| `modules/universal/profile/default-secrets/default.nix:23-27` | `keyPrefix = "networking"` plus `basePath = "/run/configs"`, so the on-disk layout equals the key layout |
| `modules/universal/profile/default-secrets/default.nix:83-88` | `keyPrefix = "anonymization"`, same on-disk rule |
| `modules/universal/profile/remote-builders/default.nix:195` | `keyPrefix = "nix/ssh"`, plus the `id_` prefix and `.pub` suffix tests at lines 10-15 |
| `modules/universal/profile/machine/basic/default.nix:113` | expects a `password` leaf under `networking/wlan/<ssid>` |
| `modules/universal/profile/machine/basic/default.nix:98` | hardwires the derived file name `default.unattended.sops.env`, which repeats the sops file base name |
| `modules/universal/services/iperf3/default.nix:37-64` | expects `rsa/priv`, `users.csv`, and a non-empty `users/` attrset |
| `modules/universal/profile/default-secrets/default.nix:56` | expects `nix/access-tokens/<host>` |
| `lib/sops/default.nix:37-39` | throws unless the file name ends with `.sops.yaml` |

### Other sops files at the flake root

These are outside the default file, and they show the same path coupling. 009 must move them too.

| Site | File |
|---|---|
| `hosts/etra/default.nix:398,405` | `dns.sops.yaml` |
| `hosts/oams/default.nix:315` | `llms.nonsensitive.sops.yaml` |
| `hosts/brys/default.nix:419` | `llms.nonsensitive.sops.yaml` |
| `hosts/brys/llm-minimal.nix:217` | `llms.nonsensitive.sops.yaml` |
| `hosts/brys/default.nix:445`, `hosts/brys/llm-minimal.nix:241` | `hosts/brys/certs/llm.key.sops`, a raw encrypted blob under the flake root |

## Adjacent findings

These consumers read a different sops file, and the mechanism is identical. They matter to 009
because they break `etra` before any default-file row does.

| Site | Key path | Guard | Mode A behaviour | Tag |
|---|---|---|---|---|
| `hosts/etra/default.nix:401` | `placeholders.dns.knot-dns.keys` (file `dns`) | none | fails; this is the first failure of `etra` in mode A | **verified** |
| `hosts/etra/default.nix:408` | `secrets.dns-kea` (file `dns-kea`) | none | fails | **verified** |
| `modules/universal/networking/router/default.nix:45,63` | `config.sops.templates."knot/sops-key.admin.conf"` | none | fails when Nix forces it; the template comes from `cfg.tsig.keyTpls`, which row 401 feeds | **verified** |

The `llms` file entries in `hosts/oams` and `hosts/brys` read **no** derived value at evaluation
time. They declare the file and then use the on-disk paths under `/run/configs/llms/` at runtime.
That is the pattern 009 should copy.

## Verification transcript

All commands ran from `/tmp/sopsinv`. `probe.nix` and `flags.nix` call `extendModules` and force
one expression.

Baseline and mode A, per host:

```
oams  allow=true   toplevel  -> /nix/store/…-nixos-system-oams-….drv
oams  allow=false  toplevel  -> /nix/store/…-nixos-system-oams-….drv
moss  allow=false  toplevel  -> OK
anji  allow=false  toplevel  -> /nix/store/…-darwin-system-….drv
etra  allow=false  toplevel  -> error: attribute 'dns' missing
                                at hosts/etra/default.nix:401:55
brys  allow=true   toplevel  -> error: Failed assertions: … Kubernetes cluster …
brys  allow=false  toplevel  -> the same assertion error (no sops signal)
```

The guard sweep, one evaluation per mode on `oams`:

```
allow=true   {"allowed":true, "cnt_secrets":117,"cnt_templates":3,
              "svc_wlan":true,"svc_iperf3":true,"svc_atuin_login":true,
              "svc_nextcloud":true,"tpl_access_tokens":true,
              "managed_currentFiles_len":3,"nextcloud_enable":true}
allow=false  {"allowed":false,"cnt_secrets":0,  "cnt_templates":0,
              "svc_wlan":false,"svc_iperf3":false,"svc_atuin_login":false,
              "svc_nextcloud":false,"tpl_access_tokens":false,
              "managed_currentFiles_len":0,"nextcloud_enable":false}
```

That pair verifies rows 5 to 12 and 17 to 19 at once. With the allow switch on, every guarded site
produces its systemd unit or its template. With the switch off, every one of them disappears, and
no read fails.

Per-row failures, mode A:

```
oams  config.kdn.networking.tailscale.auth_key
  -> error: attribute 'default' missing
     at modules/universal/networking/tailscale/default.nix:11:55
     … while calling the 'attrNames' builtin
       at modules/universal/networking/tailscale/default.nix:17:42

oams  config.kdn.networking.netbird.clients.priv.secrets
  -> error: attribute 'default' missing
     at modules/universal/networking/netbird/default.nix:83:70

oams  toplevel + { kdn.networking.tailscale.enable = lib.mkForce true; }
  -> error: attribute 'default' missing   (through line 32:24 -> 17:42)

oams  toplevel + { kdn.services.nextcloud-client-nixos.enable = lib.mkForce true; }
  -> error: attribute '"default/nextcloud/nixos/password"' missing
     at modules/universal/services/nextcloud-client-nixos/default.nix:20:52

etra  config.kdn.networking.router.addr.public.ipv4.path
  -> error: attribute '"networking/ipv4/network/isp/uplink/address/client"' missing
     at hosts/etra/default.nix:389:29

etra  config.kdn.networking.router.addr.public.ipv6.path
  -> error: attribute '"networking/ipv6/network/isp/prefix/etra/address/gateway"' missing
     at hosts/etra/default.nix:391:29

etra  config.kdn.networking.router.tsig.keaSecrets
  -> error: attribute 'dns-kea' missing
     at hosts/etra/default.nix:408:88

etra  placeholders.networking.ipv6.network.etra.lan
  -> error: attribute 'networking' missing        (allow=true: OK)
```

Per-row successes, mode A:

```
oams  config.kdn.profile.remote-builders.buildMachines  -> OK
oams  config.sops.secrets                               -> OK  (empty)
oams  config.sops.templates                             -> OK  (empty)
```

Mode B, and mode A with the file absent:

```
oams  allow=true  + all four sopsFile paths -> /tmp/sopsinv/absent.sops.yaml
  -> error: opening file '/tmp/sopsinv/absent.sops.yaml': No such file or directory
     at lib/sops/default.nix:34:5, reached from
        modules/universal/security/secrets/sops/default.nix:83:25

oams  allow=false + the same four redirected paths
  -> OK
```

The last pair is the decisive result for 009: the tree evaluates with the file absent, and
only with the allow switch off.

## Follow-up notes for 009

1. **Set the allow switch from the presence of the personal data folder.** Mode B proves the
   discovery engine cannot survive an absent path. A `builtins.pathExists` test on the folder, fed
   into `kdn.security.secrets.allow`, gives mode A for free.
2. **Fix list 3 ranks 1 to 3 before the folder move.** They are module-level defects. They affect
   an adopter today, and they need no folder.
3. **`etra` needs its own decision.** Rank 5 cannot take a guard. Treat the router network data as
   personal data with a required-input contract, not as an optional read.
4. **Add a check.** A `checks.<sys>` entry that evaluates one host with `allow = false` catches
   every regression in list 3. `oams` and `anji` pass today, so the check starts green.
5. **`lib.mkForce` is not an escape hatch for an unguarded definition.** An override cannot bypass
   a bad host definition, because `lib/modules.nix` discharges every definition. Patch the source,
   or probe one option at a time.
