---
type: Task
description: Add the kdn-certs Go CLI, which walks every den and legacy target, deduplicates the cert declarations, and drives the smallstep generation.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
parent: ../definition.md
---

# 004 — cert CLI

Parent task: [../definition.md](../definition.md). Design: [../design.md](../design.md).

## Context

`packages/kdn-certs/` holds the `kdn-certs` CLI. It reads the certificate declarations from a flake,
computes what to generate, and drives `step` and `step-ca`. The design spec freezes the name, the
language and the command table. This sub-task is a plan. It writes no code.

The aspect that ships the CLI is sub-task [003 — CA manager](../003-ca-manager/definition.md).

The CLI reads two trees. The den tree holds the migrated hosts. The old tree holds the universal
hosts. Sub-task [000 — universal augmentation](../000-universal-augmentation/definition.md)
augments the old-tree hosts with the `kdn.certificates` aspect, so the same option path appears in
both trees.

No entity receives the aspect through `den.default` global injection. `den.default` is deliberately
not used. Every den host, user, home and standalone devenv shell names the aspect in its own
`includes`. The old-tree hosts use the
`denLib.imports { class = "nixos"; aspects = [ "certificates" ]; }` line from sub-task 000. The CLI
reads the resolved option path, so it does not depend on how the aspect arrives.

## The package

The CLI is **Go**, so it is reusable outside this repository. It follows `packages/kdn-ssh-access/`
(self-contained source, no `kdnConfig` dependency) and `packages/kdnctl/` (the cobra +
charmbracelet stack).

`packages/kdn-certs/default.nix` follows the `buildGoModule` recipe:

```nix
{
  lib,
  buildGoModule,
  makeBinaryWrapper,
  installShellFiles,
  step-cli,
  step-ca,
  nix,
  sops,
  ...
}:
let
  runtimeDeps = [
    step-cli
    step-ca
    nix
    sops
  ];
in
buildGoModule (finalAttrs: {
  pname = "kdn-certs";
  version = "0.0.1";
  meta.mainProgram = "kdn-certs";

  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    "^cmd$"
    "^cmd/.*\.go$"
    "^internal$"
    "^internal/.*\.go$"
    ''^main\.go$''
  ];

  vendorHash = "sha256-…"; # fill after the first build

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  subPackages = [ "." ];

  postInstall = ''
    installShellCompletion --cmd ${finalAttrs.meta.mainProgram} \
      --bash <("$out/bin/${finalAttrs.meta.mainProgram}" completion bash) \
      --fish <("$out/bin/${finalAttrs.meta.mainProgram}" completion fish) \
      --zsh <("$out/bin/${finalAttrs.meta.mainProgram}" completion zsh)
  '';

  postFixup = ''
    wrapProgram "$out/bin/${finalAttrs.meta.mainProgram}" \
      --prefix PATH : ${lib.strings.escapeShellArg (lib.makeBinPath runtimeDeps)}
  '';
})
```

The layout mirrors `tools/kdnctl/`:

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

The UI stack (the repo's `tools/kdnctl/go.mod` already pins the charmbracelet family):

| Concern | Library |
|---|---|
| Command tree, flags, completions | `github.com/spf13/cobra` + `github.com/spf13/pflag` |
| Structured logging | `github.com/charmbracelet/log` |
| Pretty output (tables, colors) | `github.com/charmbracelet/lipgloss` |
| Progress (spinner, bar) | `github.com/charmbracelet/bubbles` (`progress`, `spinner`) |

`--json` prints machine-readable output. The pretty UI is the default for a terminal; a pipe or
`--json` gets plain output, so the CLI stays scriptable.

The plan registers the package in `packages/default.nix` before the `# AUTO_PACKAGE_PLACEHOLDER #`
line, alphabetically sorted:

```nix
kdn-certs = pkgs.callPackage ./kdn-certs { };
```

`nix run .#kdn-certs` then resolves through `packages.<system>`. It needs no `apps` entry.

## Command table

| Command | Job |
|---|---|
| `kdn-certs plan` | Walk every target, enumerate and deduplicate the declarations, print what would change, with progress. |
| `kdn-certs apply` | Generate or regenerate. Start `step-ca` on demand and tear it down after. |
| `kdn-certs ca init` | Initialize the CA DAG from the top: root first, then each intermediate. |
| `kdn-certs ca sign <cert>` | Sign one leaf. Prompt for the YubiKey touch when the CA key needs it. |
| `kdn-certs ssh login <host>` | Generate an SSH user cert to connect to a host. Pick the SSH CA, set the principals and prompt for the YubiKey touch. |
| `kdn-certs status` | Per cert: valid, expiring or mismatched. |
| `kdn-certs doctor` | Discover zombie `step-ca` processes and stale PID files. |

## Global flags

| Flag | Default | Job |
|---|---|---|
| `--flake <path>` | `.` | The flake to walk. |
| `--dry-run` | off | Print the actions and change nothing. |
| `--force` | off | Regenerate every cert, whatever the mismatch test says. |
| `--json` | off | Print machine-readable output. |
| `--verbose` | off | Print each `nix eval` command and each `step` command. |

## The walk

The walk reads every declaration site. A missing option is an empty set, never an error. Use
`builtins.attrByPath [ "kdn" "certificates" ] { } cfg` semantics at every read.

The walk reads the den tree and the old tree. Sub-task
[000 — universal augmentation](../000-universal-augmentation/definition.md) gives the old-tree hosts
the same option path. No entity receives the aspect through `den.default` global injection;
`den.default` is deliberately not used. Each entity names the aspect in its own `includes`.

### 1. den hosts

```bash
nix eval --json "$flake#den.hosts"
```

This returns the host set, per system. For each host name, read the host configuration:

```bash
nix eval --json "$flake#denConfigurations.<host>.config.kdn.certificates or {}"
```

### 2. den home configurations

```bash
nix eval --json "$flake#denHomeConfigurations"
```

For each name, read `.config.kdn.certificates or {}`.

### 3. den devenv shells

```bash
nix eval --json "$flake#denDevenvShells"
```

For each name, read `.kdn.certificates or {}`. A `mkShell` result returns `.config` alone, so the
read is one level shorter than the host read. See `modules/den/classes/devenv.nix:75`.

### 4. The old tree

Sub-task [000 — universal augmentation](../000-universal-augmentation/definition.md) augments the
old-tree hosts with the `kdn.certificates` aspect. The CLI reads the three legacy outputs in the
same way:

```bash
nix eval --json "$flake#nixosConfigurations.<host>.config.kdn.certificates or {}"
nix eval --json "$flake#darwinConfigurations.<host>.config.kdn.certificates or {}"
nix eval --json "$flake#homeConfigurations.<user>.config.kdn.certificates or {}"
```

A host that sub-task 000 does not augment returns an empty set. The walk must not fail on it.

### 5. devenv sub-profiles

The root `devenv.nix` is not a flake output. Read `config.profiles.hostname` and
`config.profiles.user` from it. Use the devenv `evalModules` entry
(`<devenv>/src/modules/top-level.nix`) or `devenv eval`.

### 6. The CA DAG

Read the CA DAG from the same targets, den and old:

```bash
nix eval --json "$flake#denConfigurations.<host>.config.kdn.ca-dag.cas or {}"
nix eval --json "$flake#nixosConfigurations.<host>.config.kdn.ca-dag.cas or {}"
nix eval --json "$flake#darwinConfigurations.<host>.config.kdn.ca-dag.cas or {}"
```

The CLI merges every CA DAG into one graph. A CA name that appears twice with different attributes
is a hard error.

## Deduplication

The dedup key is `(ca, type, commonName, directory, certFile)`. Two declarations with one key are
one cert. The CLI keeps the first and reports the duplicate under `--verbose`.

## ISO 8601 parsing

`minGenerationDate` is ISO 8601 with arbitrary precision. Parse these forms:

- `YYYY`
- `YYYY-MM`
- `YYYY-MM-DD`
- `YYYY-MM-DDThh:mm`
- `YYYY-MM-DDThh:mm:ss`
- any of the above with a trailing `Z`

A missing component takes its lowest value. So `2026` means `2026-01-01T00:00:00Z`. Compare each
parsed value against the certificate `notBefore`.

## Mismatch and rotation

Regenerate a cert when one of three conditions holds:

1. `cert.notBefore < minGenerationDate`.
2. The cert issuer CN does not match the declared CA `commonName`.
3. `--force` is set.

## DAG order

Topologically sort the CA nodes by `parent`. Process the roots first, then each intermediate, then
the leaves. A cycle in `parent` is a hard error. A `parent` that names no CA is a hard error.

## The Go test plan

The suite lives under `packages/kdn-certs/internal/` as `*_test.go` files, plus `cmd/` tests. Expose
it as `passthru.tests.go-test` (a `runCommand` that runs `go test ./...`), as
`packages/kdn-ssh-access` exposes its own `passthru`. Alias it in `checks/default.nix`:

```nix
kdn-certs-test = pkgs.kdn.kdn-certs.passthru.tests.go-test;
```

The plan adds the name to `bundle-pkgs` in `checks/bundles.nix`.

Cover these cases:

| Case | What it proves |
|---|---|
| ISO 8601 parsing | Every form above, plus the lowest-value rule. |
| DAG topological order | Roots, then intermediates, then leaves. |
| DAG cycle | A cycle fails loudly. |
| Dedup | Two declarations with one key become one cert. |
| Mismatch detection | A stale `notBefore` and a wrong issuer CN both trigger a regeneration. |
| Missing-option tolerance | A target with no `kdn.certificates` returns an empty set and no error. |
| Old-tree tolerance | A legacy target that sub-task 000 does not augment returns an empty set and no error. |
| `--dry-run` | The command prints the plan and writes no file. |
| Flag parsing | `--flake`, `--force`, `--json` and `--verbose` reach the command. |

Keep every case offline. Mock the `nix eval` call and the `step` call behind an interface, so the
suite needs no flake and no CA. A test CA with an unattended key is allowed, so the suite signs
without a YubiKey.

## Acceptance

- `nix run .#kdn-certs -- --help` prints the command table.
- `nix run .#kdn-certs -- plan --flake . --dry-run` lists the declarations and writes no file.
- `nix build '.#checks.<system>.kdn-certs-test'` passes.
- `bundle-pkgs` holds `kdn-certs-test`.

## Out of scope

- The `kdn.ca-manager` aspect and the server lifecycle. See [003](../003-ca-manager/definition.md).
- The CA DAG option shape. See [001 — CA DAG](../001-ca-dag/definition.md).
- The leaf option shape. See [002 — cert declarations](../002-cert-declarations/definition.md).
- SSH trust. See [005 — SSH CA](../005-ssh-ca/definition.md).
