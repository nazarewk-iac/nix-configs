# Pi coding-agent extensions, as one attrset of **unpacked source directories**.
#
# Each value is a store path holding the extension's source tree. Pi loads an extension by path
# (`--extension <dir>`), so a consumer passes the path directly:
#
#   pi --extension ${pkgs.pi-coding-agent-extensions.pi-orchestrator}
#
# ## Why a separate set, and not one package per extension
#
# These are TypeScript, not built artifacts: Pi loads `src/index.ts` at runtime with its own
# bundled TypeScript runtime, so there is nothing to compile. A `runCommand` that copies the
# source and its runtime `node_modules` is the whole build. The values are therefore **directories,
# not binaries**, and a single attrset keeps that explicit.
#
# ## Vendoring rule
#
# Every extension here is pinned to an **immutable source**: a commit tarball with a `sha256`
# (or an npm tarball with `integrity`). Never `main`, never a branch. A pinned commit cannot be
# retargeted, and the hash makes a changed file fail the build instead of silently swapping.
#
# Runtime dependencies go in `fetchNpmDeps`-style FODs beside the source, because Pi does not run
# `npm install` for a path-loaded extension.
{ pkgs, lib, ... }:
let
  # Build one extension directory from a source tree plus its runtime dependency closure.
  #
  # `src` must contain the extension's `package.json` and source. `npmDeps` is the unpacked
  # `node_modules` tree its `dependencies` need (Pi supplies its own SDK packages, so they are NOT
  # vendored here).
  mkExtension =
    {
      name,
      src,
      npmDeps ? null,
      # Extra generated files placed at the extension root, e.g. a catalog snapshot.
      extraFiles ? { },
    }:
    pkgs.runCommand "pi-extension-${name}" { } ''
      mkdir -p $out
      cp -r ${src}/. $out/
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (path: file: "install -m 0644 ${file} $out/${path}") extraFiles
      )}
      ${lib.optionalString (npmDeps != null) ''
        # The extension's own runtime deps. Pi injects its SDK packages, so a missing
        # @earendil-works/* import is expected and correct.
        mkdir -p $out/node_modules
        cp -r ${npmDeps}/. $out/node_modules/
      ''}
      chmod -R u+w $out
    '';
  # model-discovery reads the curated client projection at runtime: the extension
  # itself is TypeScript and cannot import Nix. `mkPiModelsJson` is the SAME
  # function home-manager uses for `models.json`, so there is one source of truth
  # (`data/llm.nix`) and no second capability table. Rendering it as an extension
  # file makes a `data/llm.nix` change rebuild the extension.
  modelDiscoveryCatalog = (pkgs.formats.json { }).generate "pi-model-catalog.json" (
    let
      llm = import ../../lib/llm.nix { inherit lib; };
    in
    # A localHost endpoint (`brys`, `oams`) is included only for the host that
    # asks, so render both and merge: the catalog carries every direct endpoint
    # plus the two shared ones. The provider keys are disjoint.
    llm.mkPiModelsJson { host = "brys"; } // llm.mkPiModelsJson { host = "oams"; }
  );
in
{
  # pi-orchestrator: forces the main agent to delegate to a subagent fleet ("engaged" mode).
  # Vendored at the commit this repo first tested. Bump `rev` and `hash` together.
  pi-orchestrator =
    let
      # Forked to nazarewk-iac to add a config-driven child context policy. childContext
      # defaults to `auto`: a child on a listed provider/model (default ["brys"]) spawns with
      # --no-context-files --no-skills --no-prompt-templates, skips parent-prompt forwarding,
      # and gets a compact rules block; `fullAgents` opts an agent out. Upstream had no context
      # flag, so a child loaded AGENTS.md (~3.8k tokens, about 45% of a 16k window).
      # PI_ORCHESTRATOR_CHILD_MINIMAL still overrides. nazarewk.3 adds session stats to the
      # fleet panel (per-agent runs/tokens for the whole session, not just the live run);
      # nazarewk.4 adds /orchestrator-runs and ctrl+alt+r: pick a live or recent child and open
      # its own pi session in a new zellij pane (fork when live, resume when finished).
      # Bump `rev` and `hash` together.
      rev = "cec714456f9791d6e9f6634b91d25b17b4b2bc38";
      version = "0.11.0+nazarewk.4";
      src = pkgs.fetchzip {
        url = "https://github.com/nazarewk-iac/pi-orchestrator/archive/${rev}.tar.gz";
        hash = "sha256-RnAp0GyxfhXYnq+otzHKLUdkZAZSOST2YnktV8cU3hc=";
        stripRoot = true;
      };

      # The extension's only runtime dependency. Pi supplies the @earendil-works/* SDK packages,
      # so they are deliberately NOT vendored. `jsonc-parser` has no transitive deps of its own.
      # An unpacked `node_modules` tree: `<out>/jsonc-parser/{package.json,lib}`. The extension
      # imports bare `jsonc-parser`, so it must sit at the top level of node_modules, not flattened.
      jsonc-parser = pkgs.runCommand "jsonc-parser-3.3.1-unpacked" { } ''
        mkdir -p $out/jsonc-parser
        tar xzf ${
          pkgs.fetchurl {
            url = "https://registry.npmjs.org/jsonc-parser/-/jsonc-parser-3.3.1.tgz";
            hash = "sha256-SgMVuGcedGO65698FCzfGemqe6Oes23C3zg7hkjjy8k=";
          }
        } -C $out/jsonc-parser --strip-components=1
      '';
    in
    mkExtension {
      name = "pi-orchestrator-${version}";
      inherit src;
      npmDeps = jsonc-parser;
    };

  # This repository's own small extensions. They live here, not under `data/`, because they are
  # general: no repo-specific path, secret or option. A consumer outside this repository takes
  # them the same way as the vendored one.
  # The context gate is interim: it registers `measure`, which sizes a file or a byte count and
  # checks it against a model alias' served context. A prompt rule cannot stop "send a 468 KB
  # transcript to a 32k model", so this is the code that can. Interim because it belongs in the
  # pi-orchestrator fork (see docs/tasks/2026-11/pi-harness-consolidation/); the fork keeps
  # `upstream` mergeable, so a ported tool is a rebase, not a second extension.
  orchestrator-gate = ./orchestrator-gate;

  # Live fleet state for the orchestrator: which aliases are loaded, their served context, and the
  # host headroom, in one tool. It degrades to the static view on a network fault.
  fleet-status = ./fleet-status;

  # The engine profile, injected into the system prompt once per CHANGE. A running session caches
  # the model entry it discovered at startup, and a profile switch happens under the same alias, so
  # without this the agent keeps assuming the old profile. One line per switch, none on a normal
  # turn, and no line at all when brys is unreachable.
  engine-state = ./engine-state;

  # The engine priority class, stamped as `x-kdn-priority` on every model request. The gateway
  # turns it into a slot lease; `primary` is the human's own turn, a delegate child is `normal`.
  priority-headers = ./priority-headers;
  # Model discovery: dynamic providers (refreshModels) that list the LIVE litellm
  # gateway, local llama-swap and Requesty router catalogs, so `pi --list-models`
  # shows discovered models (e.g. Requesty ids) layered under the static
  # data/llm.nix catalog. The bundled `catalog.json` carries the curated fields a
  # live endpoint does not publish (input modalities, client token budgets).
  model-discovery = mkExtension {
    name = "model-discovery";
    src = ./model-discovery;
    extraFiles."catalog.json" = modelDiscoveryCatalog;
  };

  # pi-hashline-edit: replaces the built-in read/edit with hashline versions. read prefixes each
  # line with "N:" and a [path#TAG] header; edit takes a line-anchored patch and REJECTS it when
  # the tag no longer matches the file. That solves two real problems here: a small model editing
  # stale lines (it must re-read), and two agents writing one file. It echoes no old text, so it
  # is cheaper than a search/replace edit. Vendored; its only peers are host-injected.
  pi-hashline-edit =
    let
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@ravshansbox/pi-hashline-edit/-/pi-hashline-edit-3.0.4.tgz";
        hash = "sha256-0jGiJvrmHxkgEPXh02uMkQn2d0c2pZaFuACv4YuqwN8=";
      };
      unpacked = pkgs.runCommand "pi-hashline-edit-3.0.4" { } ''
        mkdir -p $out
        tar xzf ${src} -C $out --strip-components=1
        chmod -R u+w $out
      '';
    in
    mkExtension {
      name = "pi-hashline-edit-3.0.4";
      src = unpacked;
    };

  # session-digest: read Pi sessions in three widening steps (list -> digest with `#n` refs ->
  # exact detail for the steps you pick), with fuzzy search over session id/repo/name. Read-only;
  # default scope is this repository, with an explicit scope="all" opt-in. It reuses Fuse.js rather
  # than hand-rolling a scorer.
  session-digest =
    let
      # Closest npm match for a dependency-free fuzzy search: Fuse.js ships ESM and has no
      # transitive deps of its own. Unpacked as a top-level node_modules entry, like jsonc-parser.
      fusejs = pkgs.runCommand "fuse.js-7.5.0-unpacked" { } ''
        mkdir -p $out/fuse.js
        tar xzf ${
          pkgs.fetchurl {
            url = "https://registry.npmjs.org/fuse.js/-/fuse.js-7.5.0.tgz";
            hash = "sha256-B25zdVEM0vQLhhCM19h1NM87MmgugN8jzSum8lc38Wg=";
          }
        } -C $out/fuse.js --strip-components=1
      '';
    in
    mkExtension {
      name = "session-digest";
      src = ./session-digest;
      npmDeps = fusejs;
    };

  timestamps = ./timestamps;
  idle-marker = ./idle-marker;

  # pi-btw: throwaway side conversations in an overlay (`/btw`, `/side`, and the
  # `/btw:*` subcommands), so a tangent does not consume the main session's
  # context. Vendored from the published npm tarball; it declares no runtime
  # dependencies (only Pi's own pi-ai/pi-coding-agent/pi-tui peers), so there is
  # no node_modules tree to carry. The package manifest points at
  # `extensions/btw.ts`, which Pi resolves when the directory is loaded.
  pi-btw =
    let
      version = "0.8.1";
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/pi-btw/-/pi-btw-${version}.tgz";
        hash = "sha256-MNPnzf7VasfyxlqV41jl7swmkQ4dKHphz8XOS4PfZpw=";
      };
      # The npm tarball nests everything under `package/`; strip that one root so
      # `package.json`, `extensions/` and `skills/` sit at the output root.
      unpacked = pkgs.runCommand "pi-btw-${version}" { } ''
        mkdir -p $out
        tar xzf ${src} -C $out --strip-components=1
        chmod -R u+w $out
      '';
    in
    mkExtension {
      name = "pi-btw-${version}";
      src = unpacked;
    };

  # pi-ask-user: the interactive `ask_user` tool. It lets an agent stop and ask the operator a
  # focused question with option lists, instead of guessing or silently stalling. Vendored from a
  # pinned commit; the Pi host injects the @sinclair/typebox and @earendil-works peers, so there is
  # no node_modules tree to carry.
  pi-ask-user =
    let
      rev = "cec297cc9bf319b1bf65c13de56bce6cf80835b5";
      version = "0.17.2";
      src = pkgs.fetchzip {
        url = "https://github.com/edlsh/pi-ask-user/archive/${rev}.tar.gz";
        hash = "sha256-MXFEgfLzpcg80Wu275iy0K5Tbbv460cz+mHBsleisyo=";
        stripRoot = true;
      };
    in
    mkExtension {
      name = "pi-ask-user-${version}";
      inherit src;
    };

  # pi-atelier: a responsive status rail and live activity sidebar (model, context, git status,
  # usage, tool/agent activity, per-subagent cost curves, prefill progress). It is the status
  # surface for the Pi harness in place of the OpenCode built-ins. Vendored from a pinned commit;
  # zero runtime dependencies (only the Pi host peers), so no `npmDeps` tree is needed.
  pi-atelier =
    let
      # A fork of michaelmjhhhh/pi-atelier on nazarewk-iac that (a) prefers jj over git for
      # the workspace pulse and shows the jj change id/bookmarks, (b) adds a STATS panel
      # with per-sub-agent avg/latest tok/s, and (c) shows trusted contributed panels
      # (pi-orchestrator fleet) by default. Bump `rev` and `hash` together when the branch moves.
      rev = "4b914e45686cb7c8a949cd9f685512c069145a91";
      version = "0.18.0+jjstats";
      src = pkgs.fetchzip {
        url = "https://github.com/nazarewk-iac/pi-atelier/archive/${rev}.tar.gz";
        hash = "sha256-bMr2HoCJshgMUR431y063V6cJeZ5ofEau1urvfZOnHI=";
        stripRoot = true;
      };
    in
    mkExtension {
      name = "pi-atelier-${version}";
      inherit src;
    };
}
