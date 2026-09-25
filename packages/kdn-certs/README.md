# kdn-certs

The declarative certificate manager of the nix-configs tree. It walks the certificate declarations
of a flake, deduplicates them, and drives smallstep to generate and rotate them.

## What it does

The tree declares certificates as options, not as files. `kdn.certificates.certs.<name>` names one
leaf, and `kdn.ca-dag.cas.<name>` names one node of the CA graph. `kdn-certs` reads both, merges
them, and drives `step` and `step-ca` to produce the files.

## Command table

| Command | Job |
|---|---|
| `kdn-certs plan` | Walk every target, enumerate and deduplicate the declarations, print what would change. |
| `kdn-certs apply` | Generate or regenerate. Start `step-ca` on demand and tear it down after. |
| `kdn-certs ca init` | Initialize the CA graph from the top: root first, then each intermediate. |
| `kdn-certs ca sign <cert>` | Sign one leaf. Prompt for the YubiKey touch when the CA key needs it. |
| `kdn-certs ssh login <host>` | Generate an SSH user certificate to connect to a host. |
| `kdn-certs status` | Per certificate: valid, expiring or mismatched. |
| `kdn-certs doctor` | Discover zombie `step-ca` processes and stale PID files. |

## Global flags

| Flag | Default | Job |
|---|---|---|
| `--flake <path>` | `.` | The flake to walk. |
| `--dry-run` | off | Print the actions and change nothing. |
| `--force` | off | Regenerate every certificate. |
| `--json` | off | Print machine-readable output. |
| `--verbose` | off | Print each `nix eval` and each `step` command. |

## The walk

The CLI reads the den tree (`den.hosts`, `denHomeConfigurations`, `denDevenvShells`) and the legacy
tree (`nixosConfigurations`, `darwinConfigurations`, `homeConfigurations`). A missing option is an
empty set, never an error, so a target that adopts the tree partly is still walkable.

## The Go test suite

The suite lives under `internal/` as `*_test.go` files, plus `cmd/` tests. Every case mocks the
`nix eval` call and the `step` call behind an interface, so the suite needs no flake, no CA and no
network.

```bash
go test ./...
```

The Nix package exposes the suite as `passthru.tests.go-test`, aliased in `checks/default.nix` as
`kdn-certs-test`:

```bash
nix build '.#checks.x86_64-linux.kdn-certs-test'
```

## The runtime PATH

`buildGoModule` wraps the binary with `makeBinaryWrapper`, so `step`, `step-ca`, `nix` and `sops`
are on the runtime PATH. The package is self-contained under this directory, so an external adopter
can reuse it with a plain `pkgs.callPackage`.
