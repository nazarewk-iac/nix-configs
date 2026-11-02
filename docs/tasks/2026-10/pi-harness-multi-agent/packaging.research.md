---
type: Research
description: How to pin, bump and configure Pi declaratively on NixOS and in a devenv, including an extension that nixpkgs does not package.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T11:45:00+01:00
---

# Pi coding agent: packaging, pinning, configuration (draft)

Research date: 2026-10-28. Read-only on the repo; no build was run.
Versions in play:

| Thing                                                | Version                                     | Source                                                                                        |
| ---------------------------------------------------- | ------------------------------------------- | --------------------------------------------------------------------------------------------- |
| nixpkgs in this repo (`.flake.patches/nixpkgs/repo`) | `pi-coding-agent` 1.1.0                     | `.flake.patches/nixpkgs/repo/pkgs/by-name/pi/pi-coding-agent/package.nix`                     |
| nixpkgs pinned by the flake                          | rev `256551e45f63`, lastModified 2026-08-26 | `flake.lock`                                                                                  |
| nixpkgs master / nixos-unstable (fetched)            | `pi-coding-agent` 1.4.0                     | raw.githubusercontent.com/NixOS/nixpkgs/{master,nixos-unstable}/…/pi-coding-agent/package.nix |
| upstream latest                                      | `v1.4.0`, released 2026-10-21               | `packages/coding-agent/CHANGELOG.md:1`                                                        |

## 1. The bump path (1.1.0 → 1.4.0)

**Good news: nixpkgs already carries the bump.** `NixOS/nixpkgs` PR #577126
(`1.3.0 -> 1.4.0`) merged 2026-10-22, and both `master` and `nixos-unstable` now
read `version = "1.4.0"`. A diff of the local 1.1.0 file against nixpkgs
`master` shows exactly four field changes plus one list edit — nothing else:

1. `version = "1.1.0"` → `"1.4.0"`
2. `src.hash` `sha256-lwjspkMGrW+8Fl/yBEDEFsHZJA57OKOhmVQmi6zfej4=` →
   `sha256-N9NOpiiZTbOMDMV+CxvJAgtLjJJ1/8NJBGS0cFHkhsc=`
3. `npmDepsHash` `sha256-GOh5WG+rRgzoy/yVHY5PoEKJZGQcEGhISrDDJxkP8W4=` →
   `sha256-aBzVz78IxZQlzPYC72Ufa2YFtkow6nZR24YBYZrv9W0=`
4. `modelData` (the `@earendil-works/pi-ai` tgz) hash
   `sha256-bKqzPOxXSA7QLFf+N0KKAwp3zCoGYoFLQ1pc+JMq2Ck=` →
   `sha256-tA4rqLtvwzKQj4uW6DfcLR/ftF65zTgvWu0RFGKYHjw=` … the `url` needs **no**
   edit, it interpolates `${finalAttrs.version}`.
5. `postInstall` workspace copy list: drop
   `@earendil-works/pi-client:packages/client` and
   `@earendil-works/pi-protocol:packages/protocol`, add
   `@earendil-works/pi-durable:packages/durable` and
   `@earendil-works/pi-env:packages/env`.

A literal diff of the two files touches only those hunks (verified). No other
option, hook, `preConfigure`/`buildPhase` line, or `meta` field differs.

### Why the list edit is required

Workspaces at each tag (GitHub tree API, `git/trees/<tag>?recursive=1`):

| tag    | packages/                                                                                                    |
| ------ | ------------------------------------------------------------------------------------------------------------ |
| v1.1.0 | agent, ai, chord, client, codemode, coding-agent, durable, env, evals, mcp, protocol, server, telemetry, tui |
| v1.4.0 | agent, ai, chord, codemode, coding-agent, durable, env, evals, mcp, telemetry, tui                           |

`client`, `protocol` and `server` were removed between the tags. `postInstall`
does `rm "$nm/$pkg"` (no `-f`), so keeping `pi-client`/`pi-protocol` in the loop
**fails the build** at 1.4.0, not merely warns. The `env`/`durable` additions
match what nixpkgs master ships.

### `npm-shrinkwrap.json`: the premise is wrong, nothing changes

The CHANGELOG entry "Removed `npm-shrinkwrap.json` from the published package"
sits under `## [1.0.0] - 2026-10-01` (CHANGELOG line 322) — i.e. **before**
1.1.0. It refers to the _published npm tarball_, not the git tree. Neither tag
has a root `npm-shrinkwrap.json`; both have `package-lock.json` (tree listing,
`shrinkwrap: []` for both tags). `buildNpmPackage` therefore hashed
`package-lock.json` at 1.1.0 and still does at 1.4.0. `npmDepsHash` semantics are
unchanged; only its value moves.

### What the derivation still gets right at 1.4.0 (checked, not assumed)

- `modelData` mechanism: `packages/ai` `build:offline` is byte-identical at both
  tags (`check:model-data && tsc && rm -rf dist/providers/data && cp -r
src/providers/data dist/providers/data`). The published `pi-ai-1.4.0.tgz`
  (837 kB, fetched) contains `package/dist/providers/data/*.json`, so
  `tar --strip-components=4` into `packages/ai/src/providers/data` still lands
  the files flat in the right place.
- `build:offline` chain at 1.4.0 builds telemetry, chord, tui, codemode, mcp, ai
  (`build:offline`), durable, env, agent, coding-agent.
- `bin.pi` is `dist/bundle/cli.js` at both tags, and the coding-agent `build`
  runs `scripts/build-coding-agent-bundle.mjs` (esbuild). Unchanged shape.
- `engines.node` is `>=22.19.0` at both tags; nixpkgs' build node satisfies it.

### Route A (preferred, least maintenance): let nixpkgs carry it

The repo pins `inputs.nixpkgs.url = github:nazarewk-iac/nixpkgs/nixos-unstable`
(`flake.nix:4`) with `nixpkgs-upstream` = `NixOS/nixpkgs/nixos-unstable`
(`flake.nix:3`). Because #577126 is in `nixos-unstable`, a normal input update
(`nix run .#update`) brings 1.4.0 with no local package at all. Do **not**
hand-edit `.flake.patches/nixpkgs/repo/**` — that tree is generated by
`.flake.patches/update.py` from `flake.lock` revs plus
`.flake.patches/config.toml` patches, so an edit there is lost on the next
update.

If you cannot bump nixpkgs yet, register the already-merged PR as a patch:

```toml
# .flake.patches/config.toml
[patch.nixpkgs.pi-coding-agent-1.4.0]
url = "https://github.com/NixOS/nixpkgs/pull/577126.patch?full_index=1"
```

then `nix run .#update -- g:patches`. (`.agents/skills/flake-patches/SKILL.md`)

### Route B (in-repo package, what a bump should follow)

See §2. Use this only when the flake's nixpkgs must stay pinned.

## 2. The in-repo package route

Repo conventions found:

- `packages/<name>/` holds a derivation; consumed two ways:
  - as `pkgs.kdn.<name>` from `packages/default.nix`
    (`llama-cpp`, `ik-llama-cpp`, `kagi-cli/package.nix`, `lnav/package.nix`, …);
  - as `pkgs.callPackage ../../../packages/<name> { }` from a den aspect — the
    **preferred** den route. `modules/den/aspects/mcp-snoop.nix:16` states the
    rule: _"The package comes from a plain `callPackage`. The slot reads
    `pkgs.kdn.mcpsnoop`, so a consumer must add this repository's overlay first.
    A relative path needs no overlay."_ Same pattern in `jj.nix`, `toolset.nix`,
    `program-firefox.nix`, `mcp-basic-memory.nix`, `llm-proxy.nix`.
- File name is either `default.nix` (dir package) or `package.nix` (`kagi-cli`,
  `lnav`, `llama-cpp`, plus nixpkgs' own `package.nix`).

`llama-cpp` is the closest precedent in intent: nixpkgs' version is too old, so
the repo builds its own from source and documents "remove when upstream catches
up". A Pi bump should follow exactly that.

Concrete layout to add:

```
packages/pi-coding-agent/
├── package.nix      # verbatim copy of nixpkgs' package.nix, bumped (§1 items 1-5)
└── README.md        # why: "flaked nixpkgs is 1.1.0; delete when it ships 1.4.0"
```

`package.nix` needs no local patches: every argument
(`buildNpmPackage`, `fetchFromGitHub`, `fetchurl`, `nix-update-script`,
`versionCheckHook`, `writableTmpDirAsHomeHook`, `makeBinaryWrapper`, `ripgrep`,
`fd`, `stdenvNoCC`) resolves from `pkgs`. Keep `passthru.updateScript` — it
already bumps `modelData` via `--custom-dep modelData`.

Wire it in `packages/default.nix` (next to `kagi-cli`, i.e. the `package.nix`
group) for non-den consumers:

```nix
pi-coding-agent = pkgs.callPackage ./pi-coding-agent/package.nix { };
```

And switch the aspect (currently `pkgs.pi-coding-agent`, `dev-llm-pi.nix:36`):

```nix
kdn.apps.pi.package.original = pkgs.callPackage ../../../packages/pi-coding-agent { };
```

**Alternative worth recording:** upstream ships its own flake
(`github:earendil-works/pi`, `flake.nix` + `nix/package.nix` at v1.4.0) that
exposes `packages.<system>.default` (attribute name `pi`) and
`overlays.default`. It uses `importNpmLock` + `install-lock/`, and it is
_stricter_ than nixpkgs (see §6). Adding `inputs.pi = github:earendil-works/pi`
and pointing the package at `inputs.pi.packages.${system}.default` avoids all
four hashes, and this repo already threads `__inputs__` into
`packages/default.nix` (`basic-memory`, `opencode-compat-proxy` do exactly that).
It is the lowest-maintenance option after a nixpkgs bump, but it adds a flake
input and duplicates what nixpkgs will soon have.

## 3. Config surface via Nix

Agent dir facts (Pi `docs/configuration.md` and `docs/environment-variables.md`
at v1.4.0):

- Agent dir defaults to `~/.pi/agent` (**not** `~/.pi`). The existing aspect's
  `dirs.data = [ "/.pi" ]` already covers it, sessions included.
- `PI_CODING_AGENT_DIR` overrides the agent dir; `PI_CODING_AGENT_SESSION_DIR`
  and `setting sessionDir` override only session storage; `PI_PACKAGE_DIR`
  overrides the package dir ("useful for Nix/Guix store paths"); `PI_OFFLINE`
  disables catalog refresh and other network activity.
- Resource lists live in `<agent-dir>/settings.json` and accept absolute paths
  and `~`: `extensions`, `skills`, `prompts`, `themes`, `packages`.

| File                        | Declarative today?                  | How                                                                                                                                                                                                                                                           |
| --------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<agent-dir>/settings.json` | yes                                 | `home.file.".pi/agent/settings.json".source = (pkgs.formats.json {}).generate …`. Caveat: `pi install` and `/settings` **write** this file, and `pi install` writes there by default — a store symlink turns those into EROFS errors.                         |
| `<agent-dir>/models.json`   | yes                                 | same, `pkgs.formats.json {}`. A `brys`-style endpoint: `providers.brys = { baseUrl = "…/v1"; api = "openai-completions"; apiKey = "$BRYS_API_KEY"; models = [ … ]; }` (schema: `docs/models-configuration.md`).                                               |
| `<agent-dir>/mcp.json`      | yes                                 | same; docs v1.4.0 `docs/mcp.md`.                                                                                                                                                                                                                              |
| `<agent-dir>/extensions/`   | yes, but do **not** symlink into it | put the `.ts` in the store and name its absolute path in `settings.extensions`. Docs (`packages.md`) say _"List dot-prefixed or symlinked resource roots directly when traversal through a glob would not discover them."_ An explicit path is the safe form. |
| `<agent-dir>/skills/`       | yes                                 | same as extensions: absolute store paths in `settings.skills` (a skill is a dir with `SKILL.md`).                                                                                                                                                             |
| `<agent-dir>/prompts/`      | yes                                 | absolute store paths in `settings.prompts` (one `.md` per `/command`).                                                                                                                                                                                        |
| `<agent-dir>/AGENTS.md`     | yes                                 | `home.file.".pi/agent/AGENTS.md".source = …`. Also `SYSTEM.md`, `APPEND_SYSTEM.md`, `AGENTS.override.md`.                                                                                                                                                     |
| `<agent-dir>/auth.json`     | **no**                              | written at runtime by `/login`; never manage it.                                                                                                                                                                                                              |

`PI_CODING_AGENT_DIR` as the lever: pointing it at a pure store path makes the
whole dir read-only, which breaks `auth.json`, sessions and `pi install`. The
working shape is one of:

1. keep the agent dir as the persisted writable `~/.pi/agent` and symlink only
   the _config_ files into it (what the repo does for Claude Code:
   `files.config = [ "/.claude.json" ]` in `dev-llm-claude-code.nix`); or
2. set `PI_CODING_AGENT_DIR` to a persisted path (e.g. under
   `~/.local/share/pi/agent`) and still symlink the config files in.

The API key never enters the store: `models.json` `apiKey` accepts `$NAME`
(env interpolation) or `!command` evaluated at request time — e.g.
`"apiKey": "!cat /run/configs/llms/llama-server/api-keys/default"` matches the
`apiKeyFile` this repo already uses for `oams`
(`hosts/oams/devenv.nix`, `kdn.llm.client.upstreams.brys.apiKeyFile`).

## 4. devenv route

Devenv options confirmed from the pinned devenv option reference
(`env`: "Environment variables to be exposed inside the developer environment",
open submodule; `files`: "A set of files that will be linked into devenv
root"):

```nix
# kdn.pi.devenv (mirroring kdn.opencode.devenv, modules/den/aspects/opencode.nix:48)
{ pkgs, ... }: {
  packages = [ piBin ];                       # wrapper, see below
  env.PI_CODING_AGENT_DIR = "${config.devenv.root}/.pi/agent";
  files.".pi/agent/settings.json".text = builtins.toJSON {
    extensions = [ "${extPlugin}/index.ts" ];
    skills     = [ "${skillPdf}" ];
    prompts    = [ "${promptReview}" ];
  };
  files.".pi/agent/models.json".text = builtins.toJSON {
    providers.brys = {
      baseUrl = "https://brys.priv.nb.net.int.kdn.im/v1";
      api = "openai-completions";
      apiKey = "!cat /run/configs/llms/llama-server/api-keys/default";
      models = [ { id = "deepseek-v4-flash"; } { id = "qwen3.8-flash-next"; } ];
    };
  };
  enterTest = ''test -x "$(command -v pi)"'';
}
```

Package on PATH: reuse `kdn.opencode`'s wrapper idea — a
`pkgs.writeShellScriptBin "pi"` that exports whatever the `models.json` `$NAME`
form needs and then `exec`s the real binary:

```nix
piBin = pkgs.writeShellScriptBin "pi" ''
  export BRYS_API_KEY="$(cat /run/configs/llms/llama-server/api-keys/default)"
  exec ${lib.getExe piPackage} "$@"
'';
```

Keep the key out of the store by reading the file at runtime (never
`env.BRYS_API_KEY = <literal>`), or skip the wrapper entirely with the
`!command` form above. `files` writes into the project (git-visible), so prefer
`.pi/agent/` there and symlink/point `PI_CODING_AGENT_DIR` at it; the
`auth.json` and sessions stay in the project dir, which is fine in a devenv.

## 5. Extensions not in nixpkgs

Runtime facts (Pi `docs/extensions.md:38`, `docs/packages.md`):

- `jiti` loads a local `.ts` with no build step — a single file, or a dir with
  `index.ts`.
- npm deps of a **local** extension are the author's problem: _"Local packages
  are not installed or modified, so their dependency tree remains the package
  author's responsibility."_ Pi only aliases the five host-provided modules
  (`pi-ai`, `pi-agent-core`, `pi-coding-agent`, `pi-tui`, `typebox`); a third-party
  import must exist in `node_modules` next to the file. The `sandbox` example is
  exactly that case (`examples/extensions/sandbox/{index.ts,package.json,package-lock.json}`,
  needs `npm install`).

Shape A — dependency-free `.ts` in the store:

```nix
ext = pkgs.writeTextFile {
  name = "pi-zellij-pane.ts";
  destination = "/index.ts";
  text = builtins.readFile ./pi-zellij-pane.ts;   # or an inline ''
};
# settings: extensions = [ "${ext}/index.ts" ];
```

Shape B — extension with npm deps:

```nix
ext = pkgs.buildNpmPackage {
  pname = "pi-ext-foo";
  version = "1.0.0";
  src = ./ext-foo;                 # index.ts + package.json + package-lock.json
  npmDepsHash = "sha256-…";
  dontNpmBuild = true;             # no compile step; jiti runs the .ts
  dontNpmPrune = true;
  npmRebuildFlags = [ "--ignore-scripts" ];
  installPhase = ''mkdir -p $out && cp -r index.ts package.json node_modules $out/'';
};
# settings: extensions = [ "${ext}/index.ts" ];
```

A **zellij-pane delegation tool needs Shape A**: it shells out to `zellij action`
through `node:child_process`, so it imports only Node builtins (the repo already
puts `zellij` in the shell via the `zellij` aspect). Shape B is only needed if it
pulls a library (e.g. `zod`); then the `package.nix` above is the answer and the
lockfile comes from the extension's own repo.

Resolution check: `jiti` resolves relative to the file, so `node_modules` must
sit in the _same_ store directory as `index.ts` (Shape B copies both to `$out`).
A plain `writeText` of a file that imports a package will fail at load time.

## 6. Darwin / Linux differences

- **Native clipboard/TUI helpers are prebuilt and checked in.** At both tags the
  tarball carries `packages/tui/native/{darwin,linux,win32}/prebuilds/<os>-<arch>/*.node`
  (darwin-arm64, darwin-x64, linux-arm64, linux-x64, win32-arm64, win32-x64).
  Nothing is compiled during the Nix build, so `npmRebuildFlags = [ "--ignore-scripts" ]`
  is compatible with both platforms. Do not enable `build:native:*`; the scripts
  want `cc`/`xcrun` and a macOS SDK.
- **Linux helper dlopens `libxcb.so.1`.** `packages/tui/native/linux/README.md`
  says it reads X11 via `libxcb.so.1` and that _"coding-agent falls back to
  command-line tools when native reads are unavailable."_ The nixpkgs derivation
  adds only `ripgrep`/`fd` to PATH and does **not** add `libxcb`,
  `wl-clipboard` or `xclip`; upstream's `nix/package.nix` at v1.4.0 does add
  `libxcb` (buildInputs, with `autoPatchelfHook`) and
  `wl-clipboard`/`xclip` (PATH). **Unverified at runtime:** whether the dlopen
  succeeds on NixOS without `libxcb` in the loader search path. The documented
  fallback means the worst case is degraded native X11 read/paste, not a crash.
  If native clipboard matters, add `libxcb` to the wrapper's
  `LD_LIBRARY_PATH` and `wl-clipboard`/`xclip` to PATH in the in-repo copy.
- That Darwin `postInstall` block removing
  `@anthropic-ai/sandbox-runtime/**/vendor/seccomp` is still present in nixpkgs
  master at 1.4.0; it only deletes ELF files that would trip `audit-tmpdir` on
  Darwin. Keep it on a copy; `rm -rf` is a no-op if the dep is gone.
- `@silvia-odwyer/photon-node` is **wasm only** (`photon_rs_bg.wasm`, no `os`/
  `cpu` fields — checked in the 0.3.4 tarball), so it is platform-neutral. No
  Windows/Darwin native addon needs handling in the derivation.
- `x86_64-darwin` is unsupported by nixpkgs `26.11` (already dropped and filtered
  in `flake.nix`), so the only Darwin target is `aarch64-darwin`; upstream's own
  flake keeps a `nixpkgs-26.05-darwin` input for x86_64 and is irrelevant here.

## Unverified / open

- Whether `PI_PACKAGE_DIR` is needed for a store install. Upstream's own
  derivation does not set it; nixpkgs does not either. Both simply exec the
  bundled `dist/bundle/cli.js`.
- Whether `pi`/`/settings` rewrite `settings.json` atomically (matters only if it
  is a symlink). Docs say personal installs are written there; treat a symlinked
  `settings.json` as read-only by design.
- `pi update` behaviour under a Nix install (CHANGELOG mentions managed-install
  markers). `PI_SKIP_VERSION_CHECK=1` is set by the nixpkgs wrapper; the
  self-update path is not exercised in a store install.
