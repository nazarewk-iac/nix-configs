# Automated tests for the den MVP. Three tiers, and no tier activates anything.
#
# The `den-mvp` aggregate builds. It asserts nothing. These checks assert.
#
# | Tier | What it does | Cost | Needs |
# |---|---|---|---|
# | 1 — evaluation | reads an evaluated option and compares it to an expected value | one evaluation | nothing |
# | 2 — artifact | builds `system.build.toplevel` and greps the result | one system build | a builder for that platform |
# | 3 — smoke run | puts the shell's packages on PATH and runs devenv's `enterTest` | one shell build | a builder for that platform |
#
# Tier 2 is nix-darwin's own test pattern — see `<nix-darwin>/release.nix:15-57` and
# `<nix-darwin>/tests/launchd-daemons.nix`, which grep `${config.out}/activate`.
#
# **No tier runs during activation.** Tier 2 reads a built store path and never executes it. Tier 3
# runs `config.test`, which devenv keeps separate from `enterShell`. Nothing here needs sudo.
#
# A VM test (`pkgs.testers.runNixOSTest`) stays out for now. `host-nixos` carries no aspect yet, so
# a booted guest would assert nothing that tier 1 does not already cover. No darwin VM framework
# exists at all. See ./README.md.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  flake = inputs.self;
  denLib = flake.denLib;
  thisSystem = pkgs.stdenv.hostPlatform.system;

  # ------------------------------------------------------------------ tier helpers

  # Tier 1. Every assertion is `{ name; expected; actual; }`. A mismatch prints one line per
  # failure and fails the build. The comparison happens at evaluation time; the derivation only
  # reports it, so it stays a local `runCommand` on any platform.
  mkEvalCheck =
    name: assertions:
    let
      failures = lib.filter (a: a.actual != a.expected) assertions;
      total = toString (builtins.length assertions);
      line = a: "  ${a.name}: want ${builtins.toJSON a.expected}, got ${builtins.toJSON a.actual}";
    in
    pkgs.runCommand "den-eval-${name}"
      {
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      (
        if failures == [ ] then
          ''
            echo "den eval ${name}: ${total} of ${total} assertions pass" >&2
            touch $out
          ''
        else
          ''
            {
              echo "den eval ${name}: ${toString (builtins.length failures)} of ${total} assertions FAIL"
            ${lib.concatMapStringsSep "\n" (a: "  echo ${lib.escapeShellArg (line a)}") failures}
            } >&2
            exit 1
          ''
      );

  # Tier 2. `target` is a derivation, so the interpolation both names the store path and adds the
  # build dependency. The script reads `$target`.
  mkArtifactCheck =
    name: target: script:
    pkgs.runCommand "den-artifact-${name}"
      {
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      ''
        target='${target}'
        echo "den artifact ${name}: ${"$"}{target}" >&2
        ${script}
        echo "den artifact ${name}: ok" >&2
        touch $out
      '';

  # Tier 3. A real execution, not an evaluation. It puts the shell's own `packages` on PATH and
  # runs devenv's `config.test`. The sandbox has no network and no real home, so every assertion in
  # an `enterTest` must work offline.
  mkSmokeCheck =
    name: shellCfg:
    pkgs.runCommand "den-smoke-${name}"
      {
        nativeBuildInputs = shellCfg.packages;
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        echo "den smoke ${name}: run enterTest" >&2
        ${shellCfg.test}
        echo "den smoke ${name}: ok" >&2
        touch $out
      '';

  # ------------------------------------------------------------------ the entities

  darwinCfg = flake.denConfigurations.host-darwin.config;
  devenvDarwin = flake.denDevenvShells.devenv-darwin;
  devenvLinux = flake.denDevenvShells.devenv-linux;
  hostShellDarwin = flake.denDevenvShells.host-darwin;

  ghAllow = devenvDarwin.claude.code.permissions.rules.Bash.allow;
  ghPackageCount =
    shell: builtins.length (builtins.filter (p: lib.hasPrefix "gh-" (p.name or "")) shell.packages);
  sorted = builtins.sort (a: b: a < b);

  # ------------------------------------------------------------------ tier 1 assertions

  # The `rosetta-builder` aspect promises four option values plus one launchd daemon. This is the
  # first automated form of the comparison that ran by hand on 2026-09-10.
  rosettaBuilderAssertions = [
    {
      name = "nix-rosetta-builder.enable";
      expected = true;
      actual = darwinCfg.nix-rosetta-builder.enable;
    }
    {
      name = "nix-rosetta-builder.onDemand";
      expected = true;
      actual = darwinCfg.nix-rosetta-builder.onDemand;
    }
    {
      name = "nix.settings.builders-use-substitutes";
      expected = true;
      actual = darwinCfg.nix.settings.builders-use-substitutes;
    }
    {
      name = "nix.buildMachines covers both Linux systems";
      expected = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      actual = sorted (lib.unique (lib.concatMap (m: m.systems) darwinCfg.nix.buildMachines));
    }
    {
      name = "launchd.daemons declares rosetta-builderd";
      expected = true;
      actual = darwinCfg.launchd.daemons ? rosetta-builderd;
    }
  ];

  # The `gh` aspect promises the package, the Claude Code opt-in and a read-only allowlist. The
  # negative assertions are the point: a mutating rule must never enter that list.
  ghAssertions = [
    {
      name = "devenv-darwin holds exactly one gh package";
      expected = 1;
      actual = ghPackageCount devenvDarwin;
    }
    {
      name = "devenv-linux holds exactly one gh package";
      expected = 1;
      actual = ghPackageCount devenvLinux;
    }
    {
      name = "claude.code.enable";
      expected = true;
      actual = devenvDarwin.claude.code.enable;
    }
    {
      name = "the allowlist holds `gh pr diff *`";
      expected = true;
      actual = lib.elem "gh pr diff *" ghAllow;
    }
    {
      name = "every allow rule names gh";
      expected = [ ];
      actual = builtins.filter (r: !(lib.hasPrefix "gh " r)) ghAllow;
    }
    {
      name = "the allowlist holds no generic `gh api` passthrough";
      expected = [ ];
      actual = builtins.filter (r: lib.hasPrefix "gh api" r) ghAllow;
    }
    {
      name = "the allowlist holds no auth mutation";
      expected = [ ];
      actual = builtins.filter (
        r:
        lib.any (sub: lib.hasPrefix "gh auth ${sub}" r) [
          "login"
          "logout"
          "refresh"
          "setup-git"
          "token"
        ]
      ) ghAllow;
    }
    {
      name = "the allowlist holds no write subcommand";
      expected = [ ];
      actual = builtins.filter (
        r:
        lib.any (sub: lib.hasInfix " ${sub} " r) [
          "create"
          "edit"
          "close"
          "merge"
          "comment"
          "delete"
        ]
      ) ghAllow;
    }
    {
      name = "the host route and the standalone route give one allowlist";
      expected = ghAllow;
      actual = hostShellDarwin.claude.code.permissions.rules.Bash.allow;
    }
  ];

  # `denLib` ships two guards. This asserts both fire, and that the good path still works.
  den = denLib.eval { };

  # A whole-aspect function. den binds an entity argument inside its own evaluation only, so this
  # shape resolves to `{ imports = [ ]; }` across the library boundary. Measured on 2026-09-10.
  wholeAspectFunction =
    { host, ... }:
    {
      name = "den-test/whole-aspect";
      devenv = { };
    };

  succeeds = value: (builtins.tryEval value).success;

  guardAssertions = [
    {
      name = "a known aspect name resolves to one module";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "devenv";
          aspects = [ "gh" ];
        }
      );
    }
    {
      name = "an unknown aspect name throws when the caller builds the list";
      expected = false;
      actual = succeeds (
        builtins.length (
          denLib.imports {
            class = "devenv";
            aspects = [ "no-such-aspect" ];
          }
        )
      );
    }
    {
      name = "a whole-aspect function throws instead of resolving to a no-op";
      expected = false;
      actual = succeeds (denLib.resolve den "devenv" wholeAspectFunction);
    }
    {
      name = "`select` reaches an aspect with no registry entry";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "devenv";
          select = d: [ d.aspects.gh ];
        }
      );
    }
    {
      name = "the registry holds both ported aspects";
      expected = [
        "gh"
        "rosetta-builder"
      ];
      actual = sorted (builtins.attrNames denLib.aspectModules);
    }
  ];

  # The adopter shape: a bare nix-darwin system with no `modules/universal`, no `mkSlots` and no
  # `kdnConfig`. Both routes get one identical extra module list, so an unequal `drvPath` proves the
  # library route and the `flakeModule` route drifted apart. The README states this equality as a
  # measurement; this makes it a test.
  bareDarwin =
    modules:
    (inputs.nix-darwin.lib.darwinSystem {
      # nix-darwin's own default for `system` reads `builtins.currentSystem`, which is impure.
      system = null;
      modules = modules ++ [
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.primaryUser = "den";
          system.stateVersion = 7;
        }
      ];
    }).config.system.build.toplevel.drvPath;

  routeAssertions =
    if !(inputs ? nix-darwin) then
      [
        {
          name = "inputs.nix-darwin is reachable from checks/";
          expected = true;
          actual = false;
        }
      ]
    else
      [
        {
          name = "denLib.imports and denModules give one drvPath for rosetta-builder";
          expected = bareDarwin [ flake.denModules.rosetta-builder ];
          actual = bareDarwin (
            denLib.imports {
              class = "darwin";
              aspects = [ "rosetta-builder" ];
            }
          );
        }
        {
          name = "denModules.gh holds a non-empty imports list";
          expected = true;
          actual = (builtins.length flake.denModules.gh.imports) > 0;
        }
      ];

  # ------------------------------------------------------------------ the check set

  # Tier 1 runs anywhere: the comparison is an evaluation and the derivation is local.
  portable = {
    den-eval-rosetta-builder = mkEvalCheck "rosetta-builder" rosettaBuilderAssertions;
    den-eval-gh = mkEvalCheck "gh" ghAssertions;
    den-eval-guards = mkEvalCheck "guards" guardAssertions;
    den-eval-routes = mkEvalCheck "routes" routeAssertions;
  };

  # Tier 2 and tier 3 build a real artifact, so each one needs a builder for its own platform. The
  # caller keeps only this machine's entry, exactly like the `den-mvp` aggregate.
  perSystem = {
    aarch64-darwin = {
      den-artifact-host-darwin = mkArtifactCheck "host-darwin" darwinCfg.system.build.toplevel ''
        echo "  the nix.conf holds the substituters opinion" >&2
        grep -Fqx 'builders-use-substitutes = true' "$target/etc/nix/nix.conf"

        echo "  the launchd plist exists" >&2
        test -f "$target/Library/LaunchDaemons/org.nixos.rosetta-builderd.plist"

        echo "  the activation script names the daemon" >&2
        grep -Fq 'org.nixos.rosetta-builderd' "$target/activate"
      '';

      den-smoke-devenv-darwin = mkSmokeCheck "devenv-darwin" devenvDarwin;
      den-smoke-host-darwin = mkSmokeCheck "host-darwin" hostShellDarwin;
    };

    # `host-nixos` carries no aspect yet, so it has no artifact worth a grep. Its shell does hold
    # `gh`, through `den.policies.host-to-devenv`.
    x86_64-linux = {
      den-smoke-devenv-linux = mkSmokeCheck "devenv-linux" devenvLinux;
      den-smoke-host-nixos = mkSmokeCheck "host-nixos" flake.denDevenvShells.host-nixos;
    };
  };

  checks = portable // (perSystem.${thisSystem} or { });

  # The semi-automated runner. It builds every check above plus the `den-mvp` aggregate, one at a
  # time, and it prints a PASS/FAIL summary. Use it when you want the whole picture in one command
  # and a readable result. It needs no sudo and it activates nothing.
  #
  #   nix run '.#checks.aarch64-darwin.den-mvp.smoke'
  #   nix run '.#checks.aarch64-darwin.den-mvp.smoke' -- 'git+file:///path/to/repo'
  smoke = pkgs.writeShellApplication {
    name = "den-mvp-smoke";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      flake=''${1:-.}
      system='${thisSystem}'
      names=(${lib.escapeShellArgs (builtins.attrNames checks)} den-mvp)

      printf 'den MVP smoke: %s checks plus the build gate, flake=%s system=%s\n\n' \
        "${toString (builtins.length (builtins.attrNames checks))}" "$flake" "$system"

      passed=() failed=()
      for name in "''${names[@]}"; do
        printf '── %s\n' "$name" >&2
        if nix build --no-link --print-build-logs "$flake#checks.$system.$name"; then
          passed+=("$name")
        else
          failed+=("$name")
        fi
      done

      printf '\n── summary\n'
      for name in "''${passed[@]}"; do printf 'PASS  %s\n' "$name"; done
      for name in "''${failed[@]}"; do printf 'FAIL  %s\n' "$name"; done
      printf '\n%s passed, %s failed\n' "''${#passed[@]}" "''${#failed[@]}"

      test "''${#failed[@]}" -eq 0
    '';
  };
in
{
  inherit checks smoke;
}
