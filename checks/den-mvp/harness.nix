# The shared harness of the den MVP test suite. It holds the tier 1 check builder and one bare
# consumer harness per den class. `./tests.nix` reads it, and so does every area file under
# `./assertions/`.
#
# A bare harness is the adopter shape: a plain nixpkgs, nix-darwin, home-manager or devenv
# evaluation, with no `modules/universal`, no `mkSlots` and no `kdnConfig`. So a value a bare
# harness produces proves an aspect works outside this repository.
#
# This file holds no assertion. It moved out of `./tests.nix` so a new area file joins the suite
# with no edit to a shared file.
{
  pkgs,
  lib,
  inputs,
}:
let
  flake = inputs.self;
  denLib = flake.denLib;

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

  # The adopter shape: a bare nix-darwin system with no `modules/universal`, no `mkSlots` and no
  # `kdnConfig`. Both routes get one identical extra module list, so an unequal `drvPath` proves the
  # library route and the `flakeModule` route drifted apart. The README states this equality as a
  # measurement; this makes it a test.
  bareDarwinSystem =
    modules:
    inputs.nix-darwin.lib.darwinSystem {
      # nix-darwin's own default for `system` reads `builtins.currentSystem`, which is impure.
      system = null;
      modules = modules ++ [
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.primaryUser = "den";
          system.stateVersion = 7;
        }
      ];
    };

  bareDarwin = modules: (bareDarwinSystem modules).config.system.build.toplevel.drvPath;

  # The `nixos` class, in the same adopter shape. This is the one subject that forces the `nixos`
  # target of `llm` and of `llm-proxy` to evaluate: no den entity includes either aspect, and
  # `den.lib.aspects.resolve` returns an `imports` list without ever reading a target module.
  #
  # The extra lines are the same ones ./host-nixos/default.nix needs, and they name no hardware.
  # Measured on 2026-09-11: `denModules.llm` evaluates here with no consumer data at all.
  bareNixos =
    modules:
    inputs.nixpkgs.lib.nixosSystem {
      modules = modules ++ [
        (
          { config, ... }:
          {
            nixpkgs.hostPlatform = "x86_64-linux";
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            boot.loader.grub.enable = false;
            system.stateVersion = config.system.nixos.release;
          }
        )
      ];
    };

  # The `devenv` class, in the same adopter shape. `den.devenv.mkShell` returns `.config` alone
  # (../../modules/den/classes/devenv.nix:75), so no existing subject can read an option default.
  # This helper returns the whole evaluation, so an assertion reads `.options.<path>.default`.
  #
  # It repeats the four mandatory devenv lines from that class and adds nothing else. So it also
  # proves the drop-in route: a plain `lib.evalModules`, no den entity, no `kdnConfig` and no
  # overlay. `specialArgs.inputs` carries `git-hooks` alone, because devenv reads that one input
  # directly and the `nix` aspect registers a pre-commit hook.
  bareShell =
    {
      aspects ? [ ],
      modules ? [ ],
      system ? "aarch64-darwin",
    }:
    lib.evalModules {
      class = "devenv";
      specialArgs.inputs = {
        inherit (inputs.devenv.inputs) git-hooks;
      };
      modules = [
        (inputs.devenv.outPath + "/src/modules/top-level.nix")
        {
          _module.args.pkgs = import inputs.nixpkgs { inherit system; };
          devenv.root = "/den-mvp-bare";
          devenv.tmpdir = "/tmp";
          name = "den-mvp-bare";
        }
        (
          { config, ... }:
          {
            devenv.cli.version = lib.mkDefault config.devenv.latestVersion;
          }
        )
      ]
      ++ denLib.imports {
        class = "devenv";
        inherit aspects;
      }
      ++ modules;
    };

  # A standalone home-manager harness, in the same bare-consumer shape as `bareNixos`,
  # `bareDarwin` and `bareShell`. It repeats the three lines ./home/default.nix needs, and it
  # names no real user.
  # `bareHomeConfiguration` returns the whole evaluation, so an assertion reads a config value.
  # `bareHome` returns the `drvPath` alone, which `forceOf.homeManager` needs. The split mirrors the
  # `bareDarwinSystem` and `bareDarwin` pair above.
  bareHomeConfiguration =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };
      modules = modules ++ [
        {
          home.username = "dev";
          home.homeDirectory = "/Users/dev";
          home.stateVersion = "26.11";
        }
      ];
    };

  bareHome = modules: (bareHomeConfiguration modules).activationPackage.drvPath;

  # One force per class. Each one returns a `drvPath`, so the evaluation runs the whole target
  # module body.
  forceOf = {
    nixos = modules: (bareNixos modules).config.system.build.toplevel.drvPath;
    darwin = bareDarwin;
    homeManager = bareHome;
    devenv = modules: (bareShell { inherit modules; }).config.shell.drvPath;
  };
in
{
  inherit
    flake
    denLib
    mkEvalCheck
    bareDarwinSystem
    bareDarwin
    bareNixos
    bareShell
    bareHomeConfiguration
    bareHome
    forceOf
    ;
}
