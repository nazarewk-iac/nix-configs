# The conditional-imports conformance test.
#
# `modules/meta/` exists for one measured reason: static per-host data must decide **which
# third-party modules a host imports**. See
# `docs/tasks/2026-09/generalization/005-conditional-imports-requirement/definition.md` for the
# requirement and `research.md` for the measurements. This file turns the requirement into a test
# that a candidate framework passes or fails.
#
# Two groups run inside the sandbox, and one probe pair runs outside it.
#
# | Part | It proves | How to run it |
# |---|---|---|
# | `conditional-imports-mechanism` | the `specialArgs` route works, and the excluded module stays unevaluated | `nix flake check` |
# | `conditional-imports-repository` | this repository still imports a third-party module from per-host data alone | `nix flake check` |
# | `.recursion` | the `config` route and the `_module.args` route both recurse | `nix run '.#checks.<system>.conditional-imports-mechanism.recursion'` |
#
# The negative half needs its own runner. Measured on 2026-09-11: `builtins.tryEval` does **not**
# catch `error: infinite recursion encountered`. It catches `throw` alone — `builtins.tryEval (let
# x = x; in x)` aborts the whole evaluation. So no in-Nix assertion can state "this route must
# fail", and the two probe files run through `nix-instantiate` instead. A build sandbox has no
# daemon, so the runner is an app and not a check.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Same shape as ./standalone.nix and ./den-mvp/tests.nix tier 1. Every assertion is
  # `{ name; expected; actual; }`, the comparison happens at evaluation time, and the derivation
  # only reports it.
  mkCheck =
    name: assertions:
    let
      failures = lib.filter (a: a.actual != a.expected) assertions;
      total = toString (builtins.length assertions);
      line = a: "  ${a.name}: want ${builtins.toJSON a.expected}, got ${builtins.toJSON a.actual}";
    in
    pkgs.runCommand "conditional-imports-${name}"
      {
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      (
        if failures == [ ] then
          ''
            echo "conditional-imports ${name}: ${total} of ${total} assertions pass" >&2
            touch $out
          ''
        else
          ''
            {
              echo "conditional-imports ${name}: ${toString (builtins.length failures)} of ${total} assertions FAIL"
            ${lib.concatMapStringsSep "\n" (a: "  echo ${lib.escapeShellArg (line a)}") failures}
            } >&2
            exit 1
          ''
      );

  # ------------------------------------------------------------------ the mechanism group

  # The stand-in for `inputs.nixos-hardware.nixosModules.raspberry-pi-4`. It sets one marker option,
  # so the marker proves the import.
  thirdParty = {
    marker = "present";
  };

  # The same module with a poison value. An `imports` list that excludes it must never force it.
  poisonedThirdParty = {
    marker = throw "the excluded third-party module was evaluated";
  };

  baseModule = {
    options.flag = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    options.marker = lib.mkOption {
      type = lib.types.str;
      default = "absent";
    };
  };

  # Route 3 — `specialArgs` drives `imports`. A `specialArgs` value resolves before the module set,
  # so it reaches `imports`. This is the route `modules/meta/` builds, and the one a candidate
  # framework must supply. Routes 1 and 2 live in ./conditional-imports/, because they recurse.
  viaSpecialArgs =
    flag: mod:
    (lib.evalModules {
      specialArgs.hostData = { inherit flag; };
      modules = [
        baseModule
        (
          { hostData, ... }:
          {
            imports = lib.optionals hostData.flag [ mod ];
          }
        )
      ];
    }).config.marker;

  mechanismAssertions = [
    {
      name = "the `specialArgs` route imports the third-party module";
      expected = {
        success = true;
        value = "present";
      };
      actual = builtins.tryEval (viaSpecialArgs true thirdParty);
    }
    {
      name = "the excluded third-party module stays unevaluated";
      expected = {
        success = true;
        value = "absent";
      };
      actual = builtins.tryEval (viaSpecialArgs false poisonedThirdParty);
    }
  ];

  # The negative half. `nix-instantiate` must fail on each file, and the message must name the
  # recursion. A passing run prints one line per probe.
  recursionProbes = [
    ./conditional-imports/probe-config.nix
    ./conditional-imports/probe-module-args.nix
  ];

  recursionRunner = pkgs.writeShellApplication {
    name = "conditional-imports-recursion";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      status=0
      for probe in ${lib.escapeShellArgs (map toString recursionProbes)}; do
        err="$(mktemp)"
        if nix-instantiate --eval --strict \
             --expr "import $probe { lib = import ${inputs.nixpkgs}/lib; }" \
             >/dev/null 2>"$err"; then
          echo "FAIL $probe: the evaluation succeeded, so the route does NOT recurse" >&2
          status=1
        elif grep -q 'infinite recursion' "$err"; then
          echo "pass $probe: infinite recursion, as the requirement states"
        else
          echo "FAIL $probe: it failed for another reason" >&2
          cat "$err" >&2
          status=1
        fi
      done
      exit "$status"
    '';
  };

  # ------------------------------------------------------------------ the repository group

  # Three marker options, one per third-party module that `modules/universal/profile/hardware/rpi4/`
  # imports. Each option exists only when its module is in the list, so the presence of the option
  # proves the import. This is an option-value probe, not a `drvPath` compare: `kdnConfig.self`
  # reaches evaluated config, so every edit moves every host `drvPath`.
  #
  # | option | third-party module |
  # |---|---|
  # | `sdImage` | `${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix` |
  # | `programs.argon` | `inputs.argon40-nix.nixosModules.default` |
  # | `hardware.raspberry-pi` | `inputs.nixos-hardware.nixosModules.raspberry-pi-4` |
  #
  # `.options` forces the module list and every option declaration. It does not force `config`, so
  # this probe needs no builder for the host's own platform.
  markersOf =
    host:
    let
      opts = inputs.self.nixosConfigurations.${host}.options;
    in
    {
      sdImage = opts ? sdImage;
      argon = opts.programs ? argon;
      raspberry-pi = opts.hardware ? raspberry-pi;
    };

  featureOf =
    host: flag:
    (builtins.fromJSON (builtins.readFile (inputs.self + "/hosts/${host}/meta.json"))).features.${flag}
      or false;

  repositoryAssertions = [
    {
      name = "a host with `features.rpi4` imports all three third-party modules";
      expected = {
        sdImage = true;
        argon = true;
        raspberry-pi = true;
      };
      actual = markersOf "briv";
    }
    {
      name = "a host without `features.rpi4` imports none of them";
      expected = {
        sdImage = false;
        argon = false;
        raspberry-pi = false;
      };
      actual = markersOf "oams";
    }
    {
      name = "the flag is data — it comes from `hosts/<host>/meta.json`";
      expected = {
        briv = true;
        oams = false;
      };
      actual = {
        briv = featureOf "briv" "rpi4";
        oams = featureOf "oams" "rpi4";
      };
    }
  ];
in
{
  checks = {
    conditional-imports-mechanism = (mkCheck "mechanism" mechanismAssertions).overrideAttrs (prev: {
      passthru = (prev.passthru or { }) // {
        recursion = recursionRunner;
      };
    });
    conditional-imports-repository = mkCheck "repository" repositoryAssertions;
  };
}
