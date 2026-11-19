---
type: Reference
description: Every formatter, linter and parser in this repository, the one place that registers each formatter, the disagreements that were removed, and the rules for adding a format.
timestamp: 2026-11-19T06:05:00+01:00
authored_by: agent
---

# Formatter convergence

One file registers every formatter: [`treefmt.nix`](../treefmt.nix). Three consumers read it, so
they cannot disagree:

- `nix fmt` and `checks.<system>.treefmt` — `flake.nix` loads the file as the treefmt-nix module and
  exposes `formatter.<system>`.
- `jj fix` — `devenv.nix` runs the `treefmt-wrapper` package, which carries the generated
  `treefmt.toml`. The `patterns` list comes from the same module.
- `checks.<system>.markdown-format` — `checks/default.nix` evaluates the module through
  `treefmt-nix.lib.evalModule` and reads `settings.formatter.prettier` and `settings.excludes`.

There is no `.prettierrc`, `.prettierignore`, `.editorconfig`, `pyproject.toml`, `ruff.toml`,
`taplo.toml`, `.golangci.yml` or `.markdownlint.json` in this repository. Every option lives in
`treefmt.nix`.

## Inventory

`treefmt` 2.6.0 runs these programs. The nixpkgs attribute is what `programs.<name>.package`
resolves to; the version is the pinned nixpkgs pin, not a separate one.

| Tool          | nixpkgs attr | Version | Formats                | Where it runs                                                                        | Config                     |
| ------------- | ------------ | ------- | ---------------------- | ------------------------------------------------------------------------------------ | -------------------------- |
| `nixfmt`      | `nixfmt`     | 1.5.0   | `*.nix` (619 files)    | `nix fmt`, `jj fix`, `checks.treefmt`, `kdn-nix-fmt`, the Helix `nix` formatter      | `treefmt.nix`              |
| `prettier`    | `prettier`   | 3.9.10  | `*.md` (764), `*.json` | `nix fmt`, `jj fix`, `checks.treefmt`, `checks.markdown-format`, `fmt-agent-docs.sh` | `treefmt.nix` (`settings`) |
| `ruff format` | `ruff`       | 0.17.4  | `*.py` (73), `*.pyi`   | `nix fmt`, `jj fix`, `checks.treefmt`                                                | `treefmt.nix`              |
| `gofumpt`     | `gofumpt`    | 0.12.0  | `*.go` (155)           | `nix fmt`, `jj fix`, `checks.treefmt`, the Helix `go` formatter                      | `treefmt.nix`              |
| `shfmt`       | `shfmt`      | 3.14.1  | `*.sh` (88), `*.bash`  | `nix fmt`, `jj fix`, `checks.treefmt`                                                | `treefmt.nix` (`-i 2`)     |
| `taplo`       | `taplo`      | 0.10.0  | `*.toml` (5)           | `nix fmt`, `jj fix`, `checks.treefmt`                                                | `treefmt.nix`              |
| `yamlfmt`     | `yamlfmt`    | 0.21.0  | `*.yaml` (13), `*.yml` | `nix fmt`, `jj fix`, `checks.treefmt`                                                | `treefmt.nix`              |
| `treefmt`     | `treefmt`    | 2.6.0   | the multiplexer        | `nix fmt`, `jj fix`, `checks.treefmt`                                                | generated `treefmt.toml`   |

Checks that do not format, and stay:

| Tool                                                | Kind      | Where it runs                                        |
| --------------------------------------------------- | --------- | ---------------------------------------------------- |
| `kdn-journal doctor --parse-only`                   | parser    | `checks.kdn-journal-parse`                           |
| `kdn-okf doctor --parse-only`                       | parser    | `checks.kdn-okf-parse`, `checks.okf-memory-validate` |
| `okf-memory validate --strict --drift`              | validator | `checks.okf-memory-validate`                         |
| `ai-xf-validate --level 2`                          | validator | `checks.ai-xf-validate`                              |
| `okf-rs validate`, `lint`, `links --broken --check` | validator | `checks.okf-rs-check`                                |
| `okflint validate`                                  | validator | `checks.okflint-validate`                            |
| `okph validate --strict`                            | validator | `checks.okph-validate`                               |
| `okf-guard scan`                                    | scanner   | `checks.okf-guard-test`                              |
| `certs-expiry.py --check`                           | validator | `checks.kdn-certs-expiry`                            |

Linters are installed for people but gate nothing: `shellcheck` in `dev-shell`, `golangci-lint` in
`dev-golang`, `ruff` and `flake8` in `dev-python`. A linter must not run in `treefmt`, because a
lint fix can change meaning and a formatter must not.

## Disagreements found, and what changed

1. **Markdown tables: two tools, different padding.** `hack/align-md-tables.py` padded table cells
   with `len()`, while prettier pads them with terminal width. The two disagreed on 26 tracked
   documents (an emoji counts as one character in Python and two columns in prettier). The rule
   `.agents/rules/agent-journal.md` told every agent to run the aligner after an edit.
   **Resolved:** the aligner is deleted. `hack/fmt-agent-docs.sh` now pipes each journal through
   `treefmt --stdin`, so a journal gets the same prettier and the same options as `nix fmt`.

2. **The journal formatter was a no-op under a formatter.** `hack/fmt-agent-docs.sh` ran
   `nix fmt -- <files>` first. Prettier reads `.gitignore` by default, and this repository's
   `.gitignore` is an allowlist that hides `.cache/`, so prettier dropped every journal and the run
   changed nothing. Only the aligner did work. **Resolved:** the script uses `treefmt --stdin` with a
   bare `.md` path. That path only selects the formatter and the exclude rules; it is not ignored,
   so prettier runs. The reason is a comment in the script.

3. **The Markdown gate covered a quarter of the tree.** `checks.markdown-format` gated `docs/`,
   `.agents/`, `README.md` and `AGENTS.md` only, while `nix fmt` formats every `*.md`. 148 tracked
   Markdown files were outside the gate. **Resolved:** the check takes the file set from
   `settings.formatter.prettier.includes` filtered by `settings.excludes`, with a local glob matcher
   for `treefmt` (doublestar) semantics. The set is now the same as `nix fmt`.

4. **The gate restated the prettier options.** It passed `--prose-wrap` and `--print-width` as
   flags, and `treefmt` passes `--config <prettierrc>`. A new setting would have reached one and not
   the other. **Resolved:** the check reads the evaluated options and swaps `--write` for `--check`.
   It also runs `settings.formatter.prettier.command`, so it cannot run another build of prettier.

5. **Generated `index.md` files flip-flopped.** `kdn-okf generate-index` ends a file with a blank
   line; prettier removes it. 216 of the 219 tracked `index.md` files carry the generator marker, and
   all 63 unformatted generated files differed by that one line only, so every regeneration and
   every `nix fmt` rewrote the other. **Resolved:** `index.md` and `**/index.md` are excluded,
   because the generator owns that layout.

6. **`jj fix` had a second file set.** `devenv.nix` listed the extensions by hand, and the list
   missed `*.pyi`, `*.envrc` and `*.envrc.*` that treefmt already formats. **Resolved:** the
   `patterns` list is derived from the evaluated `treefmt.nix` module. The output is now the 14 globs
   of the seven programs.

7. **A second prettier sat on the shell `PATH`.** `devenv.nix` installed `pkgs.prettier` with a
   comment that `jj fix` calls a bare `prettier`. It does not: it calls the wrapper, which carries
   absolute store paths. **Resolved:** the package and the comment are gone.

8. **Nix had a second formatter.** `packages/kdn-nix-fmt` chose `alejandra` or `nixfmt` by git
   remote and shipped both. **Resolved:** it calls `nixfmt` only, and `alejandra` is gone from its
   `runtimeDeps`. `flake.nix`, `docs/nix-dev.md` and `.agents/rules/nix-conventions.md` no longer
   say that Nix formatting lives outside `treefmt.nix`.

9. **`**/index.md` does not exclude the root file.** treefmt matches with doublestar, where `**/`
   needs one directory. The check's matcher and treefmt disagreed on `index.md`. **Resolved:** the
   excludes list holds both `index.md` and `**/index.md`, and the matcher now requires one directory
   for `**/`.

## Still red, and the decision

`checks.<system>.treefmt` (the treefmt-nix check) was red on 37 files when this change was measured
on 2026-11-19. None of them is Markdown, and none was touched by the changes above. They are
pre-existing debt in the other formatters. A parallel track had already started the sweep while this
change was written; refresh the list with `nix build --no-eval-cache -L
'.#checks.x86_64-linux.treefmt'`. One sweep fixes them:

```bash
nix fmt
nix build --no-eval-cache -L '.#checks.x86_64-linux.treefmt'
```

- Nix, 26 files: `data/desktop-sway-kanshi.nix`, `data/syncthing.nix`, `hosts/anji/default.nix`,
  `hosts-den/pryll/default.nix`, `hosts/etra/default.nix`, `hosts/etra/litellm.nix`,
  `hosts/moss/default.nix`, `lib/llm.nix`, twelve files under `modules/den/aspects/`,
  `modules/den-pkgs/default.nix`, `modules/den-pkgs/pin-module.nix`,
  `modules/slots/opencode/default.nix`, `modules/universal/security/secrets/age/default.nix`,
  `modules/universal/services/rosec/default.nix`, `modules/universal/services/syncthing/default.nix`.
- Python, 5 files: `hack/certs-expiry.py`, `hack/keepassxc-to-rosec.py`,
  `modules/den/aspects/security-secrets-sops/kdn-sops-secrets.py`,
  `packages/kdn-disko-zfs/kdn_disko_zfs/cli.py`, `packages/kdn-disko-zfs/tests/test_core.py`.
- Shell, 5 files: `hack/okf-check.sh`, `hack/r9700-power.sh`,
  `modules/universal/services/rosec/rosec-conflicts.sh`, `packages/kdn-keepass/kdn-keepass.sh`,
  `packages/llm/zellij-llm/zellij-llm.sh`.
- Go, 1 file: `tools/kdnctl/cmd/host.go`.

The sweep is not part of this change: it rewrites 37 files of unrelated work, and the repository's
rule is that a wiring change does not carry a formatting sweep. The Markdown family is green now
because that family is the one this change touches: the gate widened from 616 files to every tracked
Markdown file that `nix fmt` also formats, and the 3 files it then reported were formatted.

`checks.<system>.treefmt` is not a member of any bundle. Add it to `bundle-core` in
`checks/bundles.nix` only after the sweep, otherwise that bundle turns red on all 37 files.

One limitation is recorded, not fixed: prettier reads `.gitignore` as an ignore file, so it skips
the tracked files that the allowlist hides — `.mcp.json`, `hosts/*/meta.json`, `lsp/conf/nix.json`
and the `package.json` files of `packages/pi-coding-agent-extensions/`. Six of them are unformatted.
`nix fmt` and `checks.treefmt` agree on skipping them, and telling prettier to ignore `.gitignore`
would make `nix fmt` format them while the treefmt check (which runs `git add .` in its copy) stays
blind to them. The real fix is a `.gitignore` that does not use an allowlist, which is a separate
change.

The user toolsets carry formatters that this repository must not use: `alejandra` in
`dev-nix.nix` and `modules/universal/development/nix/`, and `black`, `isort`, `autopep8`, `yapf`,
`python-lsp-black` in `dev-python.nix`. They serve other repositories. Do not run them here.

## Rules for adding a format later

1. Add the program to `treefmt.nix`: `programs.<name>.enable`, the include globs and the options.
   Do not add a second program for a format that already has one; delete the old one in the same
   change.
2. If a check must gate the format, read `settings.formatter.<name>` and `settings.excludes` through
   `treefmt-nix.lib.evalModule`. Never state a directory, an option or an ignore path in the check.
   `markdown-format` in `checks/default.nix` is the pattern.
3. To keep a path out of the formatter, add it to `settings.excludes` with a reason. `nix fmt`,
   `jj fix` and every gate then agree, because they read the same list. Never add an in-flight list
   to a check.
4. Delete an `excludes` entry when its reason ends (a track landed, a fixture moved). A generated
   file stays excluded: the generator owns its layout, and two writers always flip-flop.
5. A rule, a skill or a doc names `nix fmt` and the reason, never a tool flag. A second command in a
   rule becomes a second source of truth.
6. Verify with
   `nix build --no-eval-cache -L '.#checks.<system>.markdown-format'`,
   `nix fmt -- --fail-on-change <sample>` and, for a new family,
   `nix build --no-eval-cache -L '.#checks.<system>.treefmt'`.

## Verification of this change

```bash
# the registry, from the one place that defines it: every program, binary, include glob and option
nix eval --raw '.#packages.x86_64-linux.treefmt-config' | xargs cat

nix build --no-eval-cache -L '.#checks.x86_64-linux.markdown-format'   # green, whole tree
nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-journal-parse' # green, task tree parses
nix build --no-eval-cache -L '.#checks.x86_64-linux.okflint-validate'  # green, okf-base.yaml still valid
nix fmt -- --fail-on-change .agents/rules .agents/skills checks AGENTS.md README.md
```

The `--fail-on-change` sample is scoped on purpose: `docs/` holds task files that another track is
writing at the same moment, and a formatter run there races with that write.
