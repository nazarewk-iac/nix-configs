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

**The generation is not wired yet.** `kdn-certs apply` prints the plan and returns an error without
`--dry-run`, because the sign flow needs a real CA and a YubiKey touch. The `internal/smallstep`
package holds the `step` driver and the zombie scan; the per-certificate generation loop is the
remaining work. This is reported as a follow-up, not a blocker: the design's acceptance for this
sub-task is the walk, the dedup, the rotation test and the CLI surface.

**`vendorHash` is filled.** The value is `sha256-IxYf6IDDLYRlbGY2R+wvsD7MTWdOUJh1PcKinLgvv4s=`.
