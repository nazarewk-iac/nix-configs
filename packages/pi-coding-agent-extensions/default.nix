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
    }:
    pkgs.runCommand "pi-extension-${name}" { } ''
      mkdir -p $out
      cp -r ${src}/. $out/
      ${lib.optionalString (npmDeps != null) ''
        # The extension's own runtime deps. Pi injects its SDK packages, so a missing
        # @earendil-works/* import is expected and correct.
        mkdir -p $out/node_modules
        cp -r ${npmDeps}/. $out/node_modules/
      ''}
      chmod -R u+w $out
    '';
in
{
  # pi-orchestrator: forces the main agent to delegate to a subagent fleet ("engaged" mode).
  # Vendored at the commit this repo first tested. Bump `rev` and `hash` together.
  pi-orchestrator =
    let
      rev = "d62e40d48a9c15f4b4f6c5b632ed3f943bdd5ea5";
      version = "0.11.0";
      src = pkgs.fetchzip {
        url = "https://github.com/saifymatteo/pi-orchestrator/archive/${rev}.tar.gz";
        hash = "sha256-wdEeMikoG4S6eXLPEd5RrH2c6PmaKR2j6SjOvpZ6iTo=";
        stripRoot = true;
      };

      # The extension's only runtime dependency. Pi supplies the @earendil-works/* SDK packages,
      # so they are deliberately NOT vendored. `jsonc-parser` has no transitive deps of its own.
      # An unpacked `node_modules` tree: `<out>/jsonc-parser/{package.json,lib}`. The extension
      # imports bare `jsonc-parser`, so it must sit at the top level of node_modules, not flattened.
      jsonc-parser = pkgs.runCommand "jsonc-parser-3.3.1-unpacked" { } ''
        mkdir -p $out/jsonc-parser
        tar xzf ${pkgs.fetchurl {
          url = "https://registry.npmjs.org/jsonc-parser/-/jsonc-parser-3.3.1.tgz";
          hash = "sha256-SgMVuGcedGO65698FCzfGemqe6Oes23C3zg7hkjjy8k=";
        }} -C $out/jsonc-parser --strip-components=1
      '';
    in
    mkExtension {
      name = "pi-orchestrator-${version}";
      inherit src;
      npmDeps = jsonc-parser;
    };

  # The repo's own small extensions, kept beside the vendored ones so a consumer has one source.
  # These are plain files in `data/pi/extensions/`, so the "package" is just that directory.
  kdn-timestamps = ./../../data/pi/extensions/timestamps.ts;
  kdn-idle-marker = ./../../data/pi/extensions/idle-marker.ts;
  kdn-subagent = ./../../data/pi/extensions/subagent;
}
