---
type: Solution
description: The kdn-certs Go CLI walks every den and legacy target, deduplicates the declarations, and drives smallstep. The Go suite is exposed as passthru.tests.go-test and aliased kdn-certs-test.
timestamp: 2026-09-25T19:20:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

The tree held no CLI that read the certificate declarations. A certificate was a file pair, and the
manual script `hack/kdn-ca-sign.sh` signed one leaf at a time by hand. Nothing enumerated the
declarations, deduplicated them, or decided when a certificate needed regeneration.

## Solution

`packages/kdn-certs/` holds the `kdn-certs` CLI. It is Go, built with `buildGoModule`, following
`packages/kdn-ssh-access/` (self-contained, no `kdnConfig` dependency) and `packages/kdnctl/` (the
cobra + charmbracelet stack).

### Package layout

```
packages/kdn-certs/
├── default.nix     buildGoModule + makeBinaryWrapper + installShellFiles
├── go.mod          cobra + charmbracelet (log, lipgloss, bubbles)
├── go.sum
├── main.go
├── cmd/            one file per command (cobra)
├── internal/       decl, iso8601, dag, dedup, mismatch, walk, smallstep, sops
└── README.md
```

`buildGoModule` wraps the binary with `makeBinaryWrapper`, so `step`, `step-ca`, `nix` and `sops`
are on the runtime PATH. `postInstall` installs the shell completions from
`kdn-certs completion <shell>`. The package is registered in `packages/default.nix` before the
`# AUTO_PACKAGE_PLACEHOLDER #` line, so `nix run .#kdn-certs` resolves with no `apps` entry.

### Command table

`plan`, `apply`, `ca init`, `ca sign`, `ssh login`, `status`, `doctor`, plus the global flags
`--flake`, `--dry-run`, `--force`, `--json` and `--verbose`. `--json` prints machine-readable
output; the table is the default.

### The walk

`internal/walk` reads every declaration site: `den.hosts`, `denHomeConfigurations`,
`denDevenvShells`, and the legacy `nixosConfigurations`, `darwinConfigurations` and
`homeConfigurations`. Every read uses `builtins.attrByPath [ "kdn" "certificates" ] { }` semantics
through the `--apply` expression, so a missing option is an empty set, never an error. The
`devenv` read is one level shorter, because `den.devenv.mkShell` returns `.config` alone.

### Dedup, ISO 8601, DAG order and mismatch

- `internal/dedup` collapses the declarations by `(ca, type, commonName, directory, certFile)`.
- `internal/iso8601` parses `YYYY` through `YYYY-MM-DDThh:mm:ss`, with a trailing `Z`, and applies
  the lowest-value rule.
- `internal/dag` sorts the CA graph topologically. A cycle and a dangling parent are hard errors.
- `internal/mismatch` regenerates on a stale `notBefore`, an issuer CN mismatch, or `--force`.

### The Go test suite

The suite lives under `internal/` as `*_test.go` files, plus `cmd/` tests. Every case mocks the
`nix eval` call and the `step` call behind an interface, so the suite needs no flake, no CA and no
network. It covers the eight cases of design § 8.1: ISO 8601 parsing, DAG order, DAG cycle, dedup,
mismatch detection, missing-option tolerance, `--dry-run`, and flag parsing.

The suite is exposed as `passthru.tests.go-test` (a second `buildGoModule` with `doCheck = true`),
aliased in `checks/default.nix` as `kdn-certs-test`, and added to `bundle-pkgs` in
`checks/bundles.nix`.

## Verification steps

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#packages.x86_64-linux.kdn-certs'` | the binary builds |
| `nix run --no-eval-cache '.#kdn-certs' -- --help` | prints the command table |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-certs-test'` | the Go suite passes |
| `nix run --no-eval-cache '.#kdn-certs' -- plan --flake . --dry-run` | walks the real flake, prints `no certificates declared` |

## Follow-up notes

**`vendorHash` is filled.** The value is `sha256-IxYf6IDDLYRlbGY2R+wvsD7MTWdOUJh1PcKinLgvv4s=`.

## Amendment — the generation loop is wired

`kdn-certs apply` now drives the real loop. The earlier cut printed the plan and returned an error
without `--dry-run`, because the sign flow needs a CA. The loop is the remaining work of the
sub-task, and it landed here.

### What the loop does

`internal/generate` runs one pass over the deduplicated certificates:

1. Walk the declarations and merge the CA graph (`walk.MergeCAs`).
2. Sort the graph topologically (`dag.Sort`). A cycle and a dangling parent stay hard errors.
3. For each certificate, read the committed public certificate (`internal/certinfo`) and decide the
   mismatch (`internal/mismatch`): a stale `notBefore`, an issuer-CN mismatch, `--force`, or a
   missing file.
4. On a regeneration: decrypt the CA key on demand, generate the leaf key when `keySource =
   "managed"`, sign the public certificate with `step`, and SOPS-encrypt the private key next to it.

`--dry-run` prints the plan and writes nothing. The loop processes the certificates in the
deterministic `dedup.Result.Sorted` order, so a second run with no change is idempotent.

### The `step` invocation

`step certificate create <cn> <cert> --key <key> --ca <ca.crt> --ca-key <ca.key>` signs the
caller's key bytes, so the CLI owns them and SOPS-encrypts them. The managed key comes from
`step crypto keypair --kty EC --curve P-256 --no-password --insecure`. A managed key is written
plain only to a temporary directory, encrypted, and removed. The `--san` flag is repeated once per
name: a comma-joined list is read as one DNS name. The CA key is always SOPS-sourced
(`<directory>/<keyFile>.sops`); `sops` prompts for the YubiKey touch inside the decrypt when the key
is encrypted to YubiKey identities.

An SSH leaf (`ssh-user`, `ssh-host`) is refused by the TLS signer with a clear error. The SSH sign
flow needs the `step ca` SSH provisioner and belongs to sub-task 005.

### The test-CA integration check

`internal/generate/generate_test.go` drives the loop against a **test CA** that lives under the
test's own temporary directory, outside `data/`. Its key is encrypted to a test age identity, so
the suite signs with no YubiKey and the real CA key is never read. The test asserts that the public
certificate verifies against the test CA, that the private key is a raw/binary SOPS file, that the
leaf issuer is the declared CA common name, and that a second run regenerates nothing.

The plain `go test ./...` suite has no `step`, `sops` or `age` on PATH, so the integration test
skips. The `kdn-certs-test-ca` check provides them and sets `KDN_CERTS_TEST_CA=1`. It is exposed as
`passthru.tests.go-test-ca`, aliased in `checks/default.nix`, and added to `bundle-pkgs`.

### Verification steps (amendment)

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-certs-test'` | the mocked Go suite passes |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-certs-test-ca'` | the test-CA loop signs and verifies |
| `nix run --no-eval-cache '.#kdn-certs' -- apply --flake . --dry-run` | walks the real flake, prints `no certificates declared` |

## Amendment — `ca init` is implemented

The earlier cut of `ca init` printed the topological order and created nothing. Decision D-B gave it
a real job: create the fresh managed KDN root CA.

`internal/cainit` runs one pass over the merged CA graph:

1. Merge the CA graph (`walk.MergeCAs`) and sort it topologically (`dag.Sort`).
2. For each CA with `keySource = "managed"`: generate the key
   (`step crypto keypair --kty EC --curve P-256 --no-password --insecure`), create the self-signed
   root or the intermediate (`step certificate create ... --key ... --profile root-ca|intermediate-ca
   --no-password --insecure`), widen the public certificate to mode 0644, and SOPS-encrypt the key.
3. An `external` CA is left alone: its key pre-exists and the CLI only reads it.
4. A CA whose public certificate already exists is skipped, unless `--force` is set. So a second run
   is idempotent and a root CA is never regenerated by accident.

An intermediate decrypts its parent's SOPS key on demand, so a multi-level DAG works. `--dry-run`
prints the plan and writes nothing.

`smallstep.CreateCA` now passes `--key`, so `step` signs the caller's key bytes instead of generating
its own. The caller then owns the key and SOPS-encrypts it.

`internal/cainit/cainit_test.go` covers the loop with fakes: a managed root, an external CA left
alone, the idempotent skip, `--force`, `--dry-run`, an intermediate that reads its parent, a cycle
and a dangling parent. `internal/cainit/cainit_integration_test.go` drives the real `step` and `sops`
against a temporary unattended CA and asserts that the root verifies against itself, that the public
certificate is mode 0644, that the key decrypts, and that a second run is idempotent. `cmd/ca_test.go`
covers `ca init --dry-run` and `ca init --json`.

### Verification steps (ca init)

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-certs-test'` | the mocked Go suite passes |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-certs-test-ca'` | the test-CA `ca init` creates and verifies a root |
| `nix run --no-eval-cache '.#kdn-certs' -- ca init --flake . --dry-run` | lists the `kdn` CA and writes nothing |
| `nix run --no-eval-cache '.#kdn-certs' -- ca init --flake .` | creates `data/ca/kdn.crt` and `data/ca/kdn.key.sops` with no YubiKey |
