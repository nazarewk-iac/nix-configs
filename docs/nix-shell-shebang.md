---
type: Reference
description: Use a nix-shell shebang so a script builds its own dependencies (or the package under test) onto PATH and runs standalone with no devenv shell.
timestamp: 2026-07-30T16:23:55+02:00
---

# `nix-shell` shebang scripts

> **See also:** [testing.md](testing.md) applies this pattern to pytest suites;
> [nix-dev.md](nix-dev.md) for general Nix dev workflows;
> [.agents/rules/packaging-python.md](../.agents/rules/packaging-python.md) for the
> `mkPythonScript` packaging convention these scripts live alongside.

A `nix-shell` shebang lets a script declare its own runtime dependencies inline and run
standalone — `./script` just works, with no `devenv shell` active and nothing pre-installed on
PATH. Nix builds exactly the declared closure, drops its `bin/`s on PATH, and execs the
interpreter.

## Shape

```bash
#!/usr/bin/env nix-shell
#!nix-shell -i bash -p argc jujutsu git
set -eEuo pipefail
# … normal bash from here …
```

- **Line 1** is the kernel shebang (`/usr/bin/env nix-shell`).
- **Line 2** (`#!nix-shell …`) is nix-shell's own directive line:
  - `-i bash` — the interpreter to exec once the shell is built (`python3`, `bash`, …).
  - `-p <pkg> …` — packages to put on PATH. Accepts Nix expressions too, e.g.
    `-p "python3.withPackages(ps: [ps.pytest])"` or `-p "(callPackage ./default.nix { })"`.

## Coexisting with `writeShellApplication` / `mkPythonScript` packaging

The same source file can be both a standalone nix-shell script **and** the source for a packaged
derivation. When `writeShellApplication` (or `mkPythonScript`) wraps the file, it prepends its
own generated shebang and `set -euo pipefail`/`runtimeInputs` ahead of your content — so the
`#!/usr/bin/env nix-shell` / `#!nix-shell …` lines end up as **inert comments** in the packaged
build, and your own `set -eEuo pipefail` merely duplicates the wrapper's. This is why
`packages/llm/kdn-slug/kdn-slug.sh` carries the shebang header yet still packages cleanly: the
header only matters when the file is executed directly, outside the Nix package.

Net effect: you get a zero-build edit/test loop (run the file directly) *and* a proper packaged
artifact (built via `default.nix`), from one source file.

## When to reach for it

- A repo script that must run outside any devenv shell (CI one-liners, ad-hoc tooling).
- A **test file** that should build the package-under-test fresh onto PATH before running — see
  [testing.md](testing.md).
- Any script with a small, explicit tool closure where you'd otherwise document "you need X, Y,
  Z installed" — encode that closure in the shebang instead.
