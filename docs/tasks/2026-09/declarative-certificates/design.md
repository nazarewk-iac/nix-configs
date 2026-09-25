---
type: Design
description: The full design of the declarative certificate tree — four den aspects, the CA DAG and leaf option sets, the kdn-certs CLI, the smallstep lifecycle, the SSH-CA wiring and the test plan.
task: definition.md
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
---

# Declarative certificates — design

[definition.md](definition.md) states the problem and the goals. [research.md](research.md) holds
the evidence. This file expands the frozen spec into the design that the seven sub-tasks build.

---

## 0 — Scope: plan only

This task delivers a plan. No implementation is in scope. The seven sub-tasks below carry the work.
No aspect code, no CLI code, no host edit and no `.sops.yaml` change happens in this task. The plan
is the deliverable.

| # | Directory | Job |
|---|---|---|
| 000 | `000-universal-augmentation` | Verify the § 2.1 augmentation line for the universal hosts. |
| 001 | `001-ca-dag` | The `kdn.ca-dag` aspect. |
| 002 | `002-cert-declarations` | The `kdn.certificates` aspect. |
| 003 | `003-ca-manager` | The `kdn.ca-manager` aspect and the smallstep lifecycle. |
| 004 | `004-cert-cli` | The `kdn-certs` CLI. |
| 005 | `005-ssh-ca` | The `kdn.ssh-ca` aspect. |
| 006 | `006-zellij-migration` | The zellij web declaration on the four universal hosts. |

---

## 1 — The four aspects

All four aspects live in `modules/den/aspects/`. Each one joins the registry in
`modules/den/lib.nix`, next to `ca = ./aspects/ca.nix;` at `modules/den/lib.nix:38`.

| Aspect | Classes | Role | Emits |
|---|---|---|---|
| `kdn.ca-dag` | `nixos`, `darwin`, `homeManager`, `devenv` | The CA graph as data | nothing |
| `kdn.certificates` | `nixos`, `darwin`, `homeManager`, `devenv` | The leaf option set and consumption | `certPath`, `keyPath` |
| `kdn.ca-manager` | `devenv` | The CLI and the CA DAG in a shell | the `kdn-certs` package |
| `kdn.ssh-ca` | `nixos`, `darwin`, `homeManager` | SSH login trust | server and client settings |

Each aspect follows the three aspect rules: no entity argument, no `enable` option, no custom
module argument. An empty option set is the no-op. `checks/standalone.nix` enforces all three.

### 1.1 `kdn.ca-dag` is separate from `kdn.ca`

`kdn.ca` trusts a CA as a system CA. It has the `nixos` class only. It mounts
`/etc/kdn/ca/<name>.pub` and adds each file to `security.pki.certificateFiles`
(`modules/den/aspects/ca.nix:100-105`). It never generates a key and never signs a certificate.

`kdn.ca-dag` declares the graph. It emits no configuration, holds no system trust and starts no
process. The two aspects have different classes, different jobs and different option trees. Do not
redeclare `options.kdn.ca` in the same class tree. The new tree uses the name `kdn.ca-dag`, so the
two trees cannot clash.

### 1.2 `kdn.ca-manager` is separate from `kdn.ca-dag`

`kdn.ca-dag` is the data layer. It is available in four classes. A host that consumes a certificate
needs the DAG data, not the signer. So the data layer stays inert:

- An empty `kdn.ca-dag.cas` is a true no-op.
- A consumer that reads the DAG pays no package build.
- `kdn.ca-manager` stays devenv-only, while `kdn.ca-dag` stays in four classes.

---

## 2 — Aspect reach: explicit includes per entity

The design does **not** use `den.default` global injection. Every entity names the aspect in its own
`includes`:

- A den host names `kdn.certificates` and `kdn.ca-dag` in its `includes` list.
- A den user names them in its `includes` list.
- A den home names them in its `includes` list.
- A standalone devenv shell names them in its `includes` list, or uses
  `denLib.imports { aspects = [ "certificates" "ca-dag" ]; }`.

`den.default` is declared at `<den>/modules/aspects/defaults.nix:15-19`. It injects into the entity
kinds `host`, `user` and `home` on the `flakeModule` route (`modules/den/flake-module.nix`). It
exists but this design deliberately does not use it. One global line would hide which entity needs
which aspect. An explicit include keeps every consumer visible.

### 2.1 Universal hosts use the augmentation line

The old-tree hosts oams, brys, etra and moss do not migrate to den in this task. They adopt one
aspect at a time through the den library route:

```nix
imports = [ (denLib.imports { class = "nixos"; aspects = [ "certificates" ]; }) ];
```

`denLib.imports` returns a list of plain modules. The list drops straight into a universal host's
`imports = [ … ];`. The library route (`modules/den/lib.nix`) needs no den adoption. Sub-task
`000-universal-augmentation` verifies the mechanism, documents the caveats (option-declaration
clashes, `den.default` absent on the library route, `standalone-aspects` constraints) and shows the
exact `imports` line. Sub-task `006-zellij-migration` depends on it.

### 2.2 Standalone-devenv caveat

**UNVERIFIED:** whether a host-derived devenv shell reaches an aspect that a host names. A bare
`den.lib.aspects.resolve` never reads `den.default` (`checks/den-mvp/devenv/default.nix:8-11`). So
each standalone devenv shell names `kdn.certificates` and `kdn.ca-dag` by hand:

- `checks/den-mvp/devenv/default.nix` — the standalone shell list.
- A host aspect list, where a host needs the CLI in its own shell.

Record this as a risk until a measurement settles it. The result belongs in the task worklog.

---

## 3 — The CA DAG option set

One CA node is `kdn.ca-dag.cas.<name>`:

| Option | Type | Default | Meaning |
|---|---|---|---|
| `type` | `"root"` or `"intermediate"` | required | The node class in the DAG. |
| `parent` | `null` or a CA name | `null` | The parent CA. A root names no parent. |
| `commonName` | string | required | The subject common name of the CA. |
| `directory` | string | `"data/ca"` | The repo-relative directory of the CA files. |
| `certFile` | string | `"${name}.crt"` | The public certificate filename. |
| `keyFile` | string | `"${name}.key"` | The private key filename. |
| `keySource` | `"external"` or `"managed"` | required | `managed` means the CLI generates the key. |
| `provisioner` | `null` or string | `null` | The smallstep provisioner name. |
| `ssh` | bool | `false` | The CA also signs SSH certificates. |
| `minGenerationDate` | `null` or ISO 8601 string | `null` | The oldest allowed generation date. |

The public certificate is `<directory>/<certFile>`. The private key is always SOPS-sourced:
`<directory>/<keyFile>.sops`, a raw/binary SOPS file. `keySource` records who made the key, not its
storage form. `managed` means the CLI generated the key. `external` means the key came from outside
and the CLI only reads it.

The DAG rule: `parent` builds one directed acyclic graph. A `parent` that names no CA is a hard
error. A cycle in `parent` is a hard error. The CLI sorts the graph. This aspect declares the data
only.

The existing tree already holds `data/ca/ca.pub` and `data/ca/ca.key.sops`. The default `directory`
is `data/ca`, so the declaration points at the same files that exist today. The root CA node is
`kdn` with `keySource = "external"`.

### 3.1 CA private-key custody

The CA private key is SOPS-sourced, exactly like `data/ca/ca.key.sops` today. Real CA operations
stay YubiKey-touch confirmed for now. The `kdn-certs` CLI must prompt for the touch when it signs
with a CA whose key is encrypted to YubiKey identities. The prompt is part of the sign flow, not a
manual side step.

More decryption candidates can join later for automation. The recipient set is a `.sops.yaml`
concern, not a code concern. The CLI reads whatever `.sops.yaml` allows.

A **test CA** may use an unattended key. Its recipient is a test identity, so the test suite signs
with no YubiKey. The test CA lives outside `data/`, for example under `checks/` or a temporary
directory. See § 8.1.

---

## 4 — The leaf option set

One leaf is `kdn.certificates.certs.<name>`:

| Option | Type | Default | Meaning |
|---|---|---|---|
| `ca` | string | required | A CA name from `kdn.ca-dag.cas`. |
| `type` | `"tls-server"`, `"tls-client"`, `"ssh-user"` or `"ssh-host"` | required | The certificate kind. |
| `commonName` | string | required | The subject common name of the leaf. |
| `sans` | list of strings | `[ ]` | TLS subjectAltNames. |
| `principals` | list of strings | `[ ]` | SSH principals. |
| `directory` | string | `"hosts/<hostName>/certs"` | The repo-relative directory of the leaf files. |
| `certFile` | string | `"${name}.pub"` | The public certificate filename. |
| `keyFile` | string | `"${name}.key"` | The private key filename. |
| `keySource` | `"external"` or `"managed"` | required | `managed` means the CLI generates the key. |
| `minGenerationDate` | `null` or ISO 8601 string | `null` | The oldest allowed generation date. |

### 4.1 The storage rule

| File | Path | Form | Committed |
|---|---|---|---|
| Public certificate | `<directory>/<certFile>` | PEM, plain | yes |
| Private key | `<directory>/<keyFile>.sops` | raw/binary SOPS | yes |

The aspect exposes two derived values for a consumer:

- `config.kdn.certificates.certs.<name>.certPath` — a store path that holds the public certificate.
- `config.kdn.certificates.certs.<name>.keyPath` — the decrypted runtime path of the private key.

`certPath` is a store path, so it is safe to read at build time. `keyPath` is the runtime path under
`/run/secrets`, so no store path holds the secret. The zellij web service reads both. See § 9.

### 4.2 No `enable` option

No aspect declares an `enable` option. The `standalone-aspects` check forbids a reachable one. An
empty attr set is the no-op. Inclusion is the switch.

---

## 5 — The `kdn-certs` CLI

### 5.1 Package

The CLI lives at `packages/kdn-certs/`. It is **Go**, built with `buildGoModule`, following
`packages/kdn-ssh-access/` (self-contained, no `kdnConfig` dependency) and `packages/kdnctl/` (the
cobra + charmbracelet stack).

The package is self-contained under `packages/kdn-certs/`, so an external adopter can reuse it:

```
packages/kdn-certs/
├── default.nix
├── go.mod
├── go.sum
├── main.go
├── cmd/            # one file per command (cobra)
├── internal/       # walk, dedup, dag, iso8601, smallstep, sops
└── README.md
```

CLI and UI stack (the repo's `tools/kdnctl/go.mod` already pins the charmbracelet family):

| Concern | Library |
|---|---|
| Command tree, flags, completions | `github.com/spf13/cobra` + `github.com/spf13/pflag` |
| Structured logging | `github.com/charmbracelet/log` |
| Pretty output (tables, colors) | `github.com/charmbracelet/lipgloss` |
| Progress (spinner, bar) | `github.com/charmbracelet/bubbles` (`progress`, `spinner`) |

`buildGoModule` wraps the binary with `makeBinaryWrapper`, so `step`, `step-ca`, `nix` and `sops`
are on the runtime PATH. `postInstall` installs the shell completions from
`kdn-certs completion <shell>`, exactly as `packages/kdnctl/default.nix` does. The package is
registered in `packages/default.nix` before the `# AUTO_PACKAGE_PLACEHOLDER #` line, alphabetically
sorted. `nix run .#kdn-certs` then resolves through `packages.<system>` with no `apps` entry.

`--json` prints machine-readable output. The pretty UI is the default for a terminal; a pipe or
`--json` gets plain output, so the CLI stays scriptable.

### 5.2 Command table

| Command | Job |
|---|---|
| `kdn-certs plan` | Walk every target, enumerate and deduplicate the declarations, print what would be generated or regenerated, with progress. |
| `kdn-certs apply` | Generate or regenerate. Start `step-ca` on demand and tear it down after. |
| `kdn-certs ca init` | Initialize the CA DAG from the top: root first, then each intermediate. |
| `kdn-certs ca sign <cert>` | Sign one leaf. Prompt for the YubiKey touch when the CA key needs it. |
| `kdn-certs ssh login <host>` | Generate an SSH user certificate to connect to a host. Pick the SSH CA and set the principals. |
| `kdn-certs status` | Per certificate: valid, expiring or mismatched. |
| `kdn-certs doctor` | Discover zombie `step-ca` processes and stale PID files. |

### 5.3 Global flags

| Flag | Default | Job |
|---|---|---|
| `--flake <path>` | `.` | The flake to walk. |
| `--dry-run` | off | Print the actions and change nothing. |
| `--force` | off | Regenerate every certificate, whatever the mismatch test says. |
| `--json` | off | Print machine-readable output. |
| `--verbose` | off | Print each `nix eval` command and each `step` command. |

### 5.4 The walk algorithm

The walk reads every declaration site. A missing option is an empty set, never an error.

1. `nix eval --json <flake>#den.hosts` → the host set, per system.
2. For each host: `nix eval --json <flake>#denConfigurations.<host>.config.kdn.certificates or {}`.
3. `nix eval --json <flake>#denHomeConfigurations` → the homes; read `.config.kdn.certificates or {}`.
4. `nix eval --json <flake>#denDevenvShells` → the shells; read `.kdn.certificates or {}`. A
   `mkShell` result returns `.config` alone, so this read is one level shorter than the host read.
5. Walk the legacy tree in the same way: `nixosConfigurations`, `darwinConfigurations`,
   `homeConfigurations`. A universal host that adopted the aspect through the § 2.1 augmentation
   line appears here, so the walk finds its declarations too.
6. devenv sub-profiles: read `config.profiles.hostname` and `config.profiles.user` from the root
   `devenv.nix`. The root shell is not a flake output. Use the devenv `evalModules` entry
   (`<devenv>/src/modules/top-level.nix`) or `devenv eval`.
7. The CA DAG: read `kdn.ca-dag.cas` from the same targets. Merge every DAG into one graph. A CA
   name that appears twice with different attributes is a hard error.

Every read uses `builtins.attrByPath [ "kdn" "certificates" ] { } cfg` semantics. A missing option
is an empty set, never an error.

### 5.5 Deduplication

The dedup key is `(ca, type, commonName, directory, certFile)`. Two declarations with one key are
one certificate. The CLI keeps the first and reports the duplicate under `--verbose`.

### 5.6 ISO 8601 parsing

`minGenerationDate` is ISO 8601 with arbitrary precision. Parse these forms:

- `YYYY`
- `YYYY-MM`
- `YYYY-MM-DD`
- `YYYY-MM-DDThh:mm`
- `YYYY-MM-DDThh:mm:ss`
- any form above with a trailing `Z`

A missing component takes its lowest value. So `2026` means `2026-01-01T00:00:00Z`. Compare each
parsed value against the certificate `notBefore`.

### 5.7 Mismatch and rotation

Regenerate a certificate when one of three conditions holds:

1. `cert.notBefore < minGenerationDate`.
2. The certificate issuer CN does not match the declared CA `commonName`.
3. `--force` is set.

### 5.8 DAG order

Topologically sort the CA nodes by `parent`. Process the roots first, then each intermediate, then
the leaves. A cycle in `parent` is a hard error. A `parent` that names no CA is a hard error.

---

## 6 — The smallstep on-demand lifecycle

`step-ca` runs only while one sign operation needs it. The lifecycle has four steps:

1. Start `step-ca` as a transient process. Use a `systemd-run --user` unit, or a subprocess with a
   temporary `ca.json`.
2. Sign the requested leaf or intermediate.
3. Terminate the process.
4. Clean the temporary `ca.json` and the PID file.

`step certificate create --ca … --ca-key …` and `step ca certificate --offline` both work with no
network. So the lifecycle needs no listening port and no long-lived daemon.

A crash can leave a `step-ca` process or a stale PID file behind. `kdn-certs doctor` finds both. It
scans the process table for a `step-ca` process and scans the CA directory for a stale PID file. It
reports each hit and removes it with `--force`. `kdn-certs apply` runs the same scan on startup,
before it signs anything. So a leftover process cannot hold the CA port or the CA lock.

---

## 7 — The SSH-CA wiring

`kdn.ssh-ca` covers the classes `nixos`, `darwin` and `homeManager`. It declares no `enable`
option. An empty declaration is the no-op.

### 7.0 Two consumers: interactive logins and automation

The SSH CA serves two classes of consumer.

| Class | Consumer | Certificate | Lifetime |
|---|---|---|---|
| Interactive | a person through `ssh` or `kdn-*` | a user certificate with principals | short, hours |
| Automation | CI, remote builders and agents | a user or host certificate | longer, days |

Interactive logins use short-lived user certificates with principals. `ssh` and the `kdn-*` tools
consume them. Automation cannot manage long-lived `authorized_keys` files, so it consumes
certificates instead. Different validity per class is allowed. The design sets one lifetime per
class, not one lifetime for all.

### 7.1 Server side

The aspect writes two settings into `services.openssh.settings`:

- `TrustedUserCAKeys` names the SSH CA public key. A user certificate that the CA signs then logs
  in, with no per-user `authorized_keys` line.
- `HostCertificate` names the host certificate. The server presents it to every client.

The CA public key comes from `kdn.ca-dag.cas.<name>` with `ssh = true`. The host certificate comes
from `kdn.certificates.certs.<name>` with `type = "ssh-host"`.

### 7.2 Client side

The aspect trusts the CA on the client in one of two ways:

- An `@cert-authority` line in `known_hosts`. This trusts every host certificate the CA signs.
- `CertificateFile` in the ssh drop-in. This names the user certificate the client presents.

The drop-in file is `~/.ssh/config.d/50-kdn-ssh-ca.config`. The directory is the shared drop-in
directory. `program-ssh-client` includes it through
`programs.ssh.includes = [ "~/.ssh/config.d/*.config" ]`
(`modules/den/aspects/program-ssh-client.nix:24`). `ssh-access` writes `40-kdn-ssh-access.config`
into the same directory (`modules/den/aspects/ssh-access.nix:182`). The `50-` number sorts this
file after the `40-` file.

### 7.3 The `kdn-certs ssh login <host>` flow

The command does four steps:

1. Read the target host and its SSH CA from the certificate declarations.
2. Generate a user key pair, or reuse a named one.
3. Sign a user certificate with the SSH CA. Set the principals to the login names of the target. Use
   the short interactive lifetime.
4. Write the certificate next to the key and print the `ssh` command.

The command never writes a server file. It only prepares the client side. Automation uses the same
signing path with the longer automation lifetime and no interactive prompt, when the CA key allows
it.

### 7.4 Orthogonality with `kdn-ssh-access`

`kdn-ssh-access` is orthogonal. It picks routes and identities. It does not decide trust. The
`kdn.ssh-ca` aspect decides trust only. Do not couple the two aspects. Do not read a
`kdn.ssh-access` option from `kdn.ssh-ca`, and do not read a `kdn.ssh-ca` option from
`kdn.ssh-access`.

### 7.5 Risk — nix-darwin `services.openssh.settings`

**UNVERIFIED:** whether nix-darwin declares `services.openssh.settings`. The `nixos` class sets the
two settings with no doubt. The `darwin` class may not expose the same option. If the option is
absent, the `darwin` class must write the equivalent `sshd_config` fragment another way, or it must
drop the server half. Verify this before the `darwin` work starts. Record the result in the task
worklog.

---

## 8 — The testing plan

### 8.1 CLI Go test suite

The suite lives under `packages/kdn-certs/internal/` as `*_test.go` files, plus `cmd/` tests. Expose
it as `passthru.tests.go-test` (a `runCommand` that runs `go test ./...`), as
`packages/kdn-ssh-access` exposes its own `passthru`. Alias it in `checks/default.nix` as
`kdn-certs-test`. Add the name to `bundle-pkgs` in `checks/bundles.nix`.

| Case | What it proves |
|---|---|
| ISO 8601 parsing | Every form above, plus the lowest-value rule. |
| DAG topological order | Roots, then intermediates, then leaves. |
| DAG cycle | A cycle fails loudly. |
| Dedup | Two declarations with one key become one certificate. |
| Mismatch detection | A stale `notBefore` and a wrong issuer CN both trigger a regeneration. |
| Missing-option tolerance | A target with no `kdn.certificates` returns an empty set and no error. |
| `--dry-run` | The command prints the plan and writes no file. |
| Flag parsing | `--flake`, `--force`, `--json` and `--verbose` reach the command. |

Keep every case offline. Mock the `nix eval` call and the `step` call behind an interface, so the
suite needs no flake and no CA. The sign cases that need a real CA use a **test CA with an
unattended key**. The test CA lives outside `data/`, under `checks/` or a temporary directory. Its
recipient is a test identity, so the suite signs with no YubiKey. The real CA key stays YubiKey-touch
confirmed.

### 8.2 den aspect checks

Add one area file `checks/den-mvp/assertions/certificates.nix`. The loader
`checks/den-mvp/assertions/default.nix` scans the directory, so the new file joins the suite with
no edit to a shared file. It holds one bare-consumer subject per class.

`den-eval-instantiate` forces every aspect-class pair. The registry adds `ca-dag`, `certificates`,
`ca-manager` and `ssh-ca`, so the coverage table grows by their pairs.

### 8.3 The standalone gate

`checks/standalone.nix` must pass for all four aspects: no reachable `enable`, no `kdnConfig`, no
`modules/universal` and no `modules/meta`, and `pkgs`-only targets.

### 8.4 The `git add` trap

`builtins.readDir` reads the flake source, and the `git+file:` fetcher hides an untracked file. A
brand-new area file stays invisible until git tracks it. Run
`git ls-files -- checks/den-mvp/assertions/` and confirm the new file before trusting a result.

---

## 9 — The zellij migration

The first real consumer is the zellij web certificate. Two manual pieces go away:

1. `hack/kdn-ca-sign.sh`.
2. The four manual file pairs `hosts/<host>/certs/zellij.pub` and
   `hosts/<host>/certs/zellij.key.sops`, on oams, brys, etra and moss.

One declaration replaces them on each of the four hosts:

```nix
kdn.certificates.certs.zellij-web = {
  ca = "kdn";
  type = "tls-server";
  commonName = "<host>.<zone>";
  sans = [ "<host>.<zone>" ];
  directory = "hosts/<host>/certs";
  certFile = "zellij.pub";
  keyFile = "zellij.key";
  keySource = "managed";
};
```

The four hosts are universal hosts. Each one adopts the aspect through the § 2.1 augmentation line
before the declaration takes effect. Sub-task `006-zellij-migration` depends on sub-task
`000-universal-augmentation` for this reason.

The `kdn` CA signs the leaf. Its `ssh` flag is off, because this leaf is TLS only. `kdn-certs
apply` generates the key, signs the certificate, writes the public certificate, and SOPS-encrypts
the private key.

The zellij web service reads the two exposed paths:

```nix
kdn.programs.zellij.web = {
  certFile = config.kdn.certificates.certs.zellij-web.certPath;
  keyFile = config.kdn.certificates.certs.zellij-web.keyPath;
  user = "kdn";
};
```

`certPath` is a store path, so it feeds `certFile`. `keyPath` is the decrypted runtime path, so it
feeds `keyFile` and not `keySopsFile`. The current host files set
`certFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.pub"` and
`keySopsFile = "${kdnConfig.self}/hosts/<host>/certs/zellij.key.sops"` at
`hosts/oams/default.nix:347`, `hosts/brys/default.nix:484`, `hosts/etra/default.nix:448` and
`hosts/moss/default.nix:45`. Those four blocks change to the two `certPath`/`keyPath` reads.

The storage rule stays the same. The public certificate is `<directory>/<certFile>` and it is
committed plain. The private key is `<directory>/<keyFile>.sops` and it is committed as raw/binary
SOPS.

### 9.1 Acceptance test

1. All four host toplevels evaluate:
   `nix eval .#nixosConfigurations.{oams,brys,etra,moss}.config.system.build.toplevel.drvPath`.
2. The service reads `certPath` and `keyPath`:
   `nix eval .#nixosConfigurations.oams.config.systemd.user.services.zellij-web.serviceConfig.ExecStart`.
3. The certificate verifies against the CA:
   `openssl verify -CAfile data/ca/ca.pub hosts/oams/certs/zellij.pub`.
4. `kdn-certs apply` is idempotent. A second run changes no file.

---

## 10 — Risks and open questions

| # | Risk | State |
|---|---|---|
| 1 | A host-derived devenv shell may not reach an aspect that the host names | **UNVERIFIED** — name the aspects in the standalone shells by hand |
| 2 | nix-darwin may not declare `services.openssh.settings` | **UNVERIFIED** — verify before the `darwin` work |
| 3 | A new leaf key needs its own `creation_rules` entry above the generic rule | design rule — see [research.md](research.md) § 3 |
| 4 | A crash may leave a zombie `step-ca` process or a stale PID file | `kdn-certs doctor` owns the cleanup |
| 5 | The CA private key needs a YubiKey touch | the CLI prompts for the touch; the leaf work is automated |
| 6 | The universal-host augmentation line may clash on option declarations | `000-universal-augmentation` verifies it and records the caveats |

---

## 11 — Out of scope

- No change to `kdn.ca`, which trusts a CA as a system CA.
- No change to `kdn-ssh-access`.
- No online CA and no SSH path through Cloudflare.
- No `enable` option.
- No automatic activation. The CLI runs on demand.
- No migration of oams, brys, etra or moss to den. They adopt one aspect at a time through the § 2.1
  augmentation line.
- No migration of the `llm` certificate on brys. That is a later consumer.
- No implementation. This task delivers the plan only. See § 0.
