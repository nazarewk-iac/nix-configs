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
# A VM test (`pkgs.testers.runNixOSTest`) stays out for now. `host-nixos` **does** carry a real
# `nixos`-class aspect since `devenv-cli` landed, so a booted guest is no longer vacuous. But every
# value it would read is either a static option value or a file in the toplevel, and tier 1 and
# tier 2 already read both. A VM earns its cost only for a runtime behaviour — a service that must
# start, an activation that must converge. No darwin VM framework exists at all. See ./README.md.
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
  nixosCfg = flake.denConfigurations.host-nixos.config;
  devenvDarwin = flake.denDevenvShells.devenv-darwin;
  devenvLinux = flake.denDevenvShells.devenv-linux;
  hostShellDarwin = flake.denDevenvShells.host-darwin;

  # The two standalone home-manager configurations. They belong to no den host, and they are the
  # shape an external adopter uses. See ./home/default.nix.
  homeDarwin = flake.denHomeConfigurations.home-darwin;
  homeLinux = flake.denHomeConfigurations.home-linux;

  # The two home-manager generations that a den **host** forwards. Tier 2 greps all four.
  hmHostDarwin = darwinCfg.home-manager.users.dev.home.activationPackage;
  hmHostNixos = nixosCfg.home-manager.users.dev.home.activationPackage;

  ghAllow = devenvDarwin.claude.code.permissions.rules.Bash.allow;
  ghPackageCount =
    shell: builtins.length (builtins.filter (p: lib.hasPrefix "gh-" (p.name or "")) shell.packages);
  sorted = builtins.sort (a: b: a < b);

  # `devenv-cli` puts exactly one `pkgs.devenv` into every package list it touches. A count catches
  # a miss and an accidental duplicate with one assertion.
  devenvCount = ps: builtins.length (builtins.filter (p: (p.pname or "") == "devenv") ps);

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

  # The `devenv-cli` aspect is the four-target port, and it is the only aspect that reaches every
  # den class this harness covers. So these assertions are the full-matrix test.
  #
  # Two inclusion shapes matter, and they are not the same test:
  #
  #  * A **host** inclusion delivers `nixos`/`darwin` plus `devenv`. It does **not** deliver
  #    `homeManager`, because den partitions by scope. Measured on 2026-09-10: with the aspect at
  #    host scope alone, `home-manager.users.dev.home.packages` held **0** devenv; with it at both
  #    host scope and user scope, **1**. So the `dev` user aspect includes it a second time. See
  #    ./users/default.nix.
  #  * A **standalone** home-manager evaluation carries no den entity at all. See ./home/default.nix.
  devenvCliAssertions = [
    # ---- the `nixos` and `darwin` targets. One shared module, two class trees.
    {
      name = "darwin systemPackages holds one devenv";
      expected = 1;
      actual = devenvCount darwinCfg.environment.systemPackages;
    }
    {
      name = "nixos systemPackages holds one devenv";
      expected = 1;
      actual = devenvCount nixosCfg.environment.systemPackages;
    }
    # `nix.extraOptions` is a free-text block and another module may append to it. So test for the
    # two lines, never for equality.
    {
      name = "darwin nix.extraOptions keeps outputs and derivations";
      expected = true;
      actual =
        lib.hasInfix "keep-outputs = true" darwinCfg.nix.extraOptions
        && lib.hasInfix "keep-derivations = true" darwinCfg.nix.extraOptions;
    }
    {
      name = "nixos nix.extraOptions keeps outputs and derivations";
      expected = true;
      actual =
        lib.hasInfix "keep-outputs = true" nixosCfg.nix.extraOptions
        && lib.hasInfix "keep-derivations = true" nixosCfg.nix.extraOptions;
    }

    # ---- the `devenv` target. The slot has no such target; this half is new.
    {
      name = "every devenv shell holds one devenv package";
      expected = {
        devenv-darwin = 1;
        devenv-linux = 1;
        host-darwin = 1;
        host-nixos = 1;
      };
      actual = lib.mapAttrs (_: shell: devenvCount shell.packages) flake.denDevenvShells;
    }

    # ---- the `homeManager` target, forwarded through a den user
    {
      name = "both hosts forward exactly one home-manager user";
      expected = {
        host-darwin = [ "dev" ];
        host-nixos = [ "dev" ];
      };
      actual = {
        host-darwin = builtins.attrNames darwinCfg.home-manager.users;
        host-nixos = builtins.attrNames nixosCfg.home-manager.users;
      };
    }
    {
      name = "the forwarded user holds one devenv on both hosts";
      expected = {
        host-darwin = 1;
        host-nixos = 1;
      };
      actual = {
        host-darwin = devenvCount darwinCfg.home-manager.users.dev.home.packages;
        host-nixos = devenvCount nixosCfg.home-manager.users.dev.home.packages;
      };
    }
    {
      name = "define-user derives the home directory from the host system";
      expected = {
        host-darwin = "/Users/dev";
        host-nixos = "/home/dev";
      };
      actual = {
        host-darwin = darwinCfg.home-manager.users.dev.home.homeDirectory;
        host-nixos = nixosCfg.home-manager.users.dev.home.homeDirectory;
      };
    }
    {
      name = "define-user declares the OS account on both classes";
      expected = {
        host-darwin = true;
        host-nixos = true;
      };
      actual = {
        host-darwin = darwinCfg.users.users ? dev;
        host-nixos = nixosCfg.users.users ? dev;
      };
    }
    {
      name = "primary-user sets system.primaryUser";
      expected = "dev";
      actual = darwinCfg.system.primaryUser;
    }

    # ---- the standalone home-manager route, with no den entity
    {
      name = "each standalone home configuration holds one devenv";
      expected = {
        home-darwin = 1;
        home-linux = 1;
      };
      actual = {
        home-darwin = devenvCount homeDarwin.config.home.packages;
        home-linux = devenvCount homeLinux.config.home.packages;
      };
    }

    # ---- the library route. One module per class, through `denLib.imports`.
    #
    # `denModules.devenv-cli` deliberately does not exist. That zero-argument form names one common
    # class per aspect, and a four-class aspect has none. `denLib.imports` is the general form, and
    # this asserts it reaches every class.
    {
      name = "denLib.imports resolves one module on each of the four classes";
      expected = {
        darwin = 1;
        devenv = 1;
        homeManager = 1;
        nixos = 1;
      };
      actual =
        lib.genAttrs
          [
            "darwin"
            "devenv"
            "homeManager"
            "nixos"
          ]
          (
            class:
            builtins.length (
              denLib.imports {
                inherit class;
                aspects = [ "devenv-cli" ];
              }
            )
          );
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
      name = "the registry holds every ported aspect";
      expected = [
        "devenv-cli"
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

  # The shell-hook greps, shared by all four home-manager artifact checks. `devenv-cli` writes one
  # hook per shell, and home-manager writes an `initExtra` only for an **enabled** shell — so this
  # also proves the test subject turned all three on.
  #
  # The generated line reads `<store-path>/bin/devenv hook <shell>`, so `devenv hook <shell>` is a
  # literal substring of it.
  hmHookGreps = ''
    for pair in 'bash .bashrc' 'zsh .zshrc' 'fish .config/fish/config.fish'; do
      # shellcheck disable=SC2086
      set -- $pair
      echo "  the $1 hook in $2" >&2
      grep -Fq "devenv hook $1" "$target/home-files/$2"
    done
  '';

  # ------------------------------------------------------------------ the check set

  # Tier 1 runs anywhere: the comparison is an evaluation and the derivation is local.
  portable = {
    den-eval-rosetta-builder = mkEvalCheck "rosetta-builder" rosettaBuilderAssertions;
    den-eval-gh = mkEvalCheck "gh" ghAssertions;
    den-eval-guards = mkEvalCheck "guards" guardAssertions;
    den-eval-routes = mkEvalCheck "routes" routeAssertions;
    den-eval-devenv-cli = mkEvalCheck "devenv-cli" devenvCliAssertions;
  };

  # Tier 2 and tier 3 build a real artifact, so each one needs a builder for its own platform. The
  # caller keeps only this machine's entry, exactly like the `den-mvp` aggregate.
  perSystem = {
    aarch64-darwin = {
      den-artifact-host-darwin = mkArtifactCheck "host-darwin" darwinCfg.system.build.toplevel ''
        echo "  the nix.conf holds the substituters opinion" >&2
        grep -Fqx 'builders-use-substitutes = true' "$target/etc/nix/nix.conf"

        echo "  the nix.conf holds both devenv-cli garbage-collector opinions" >&2
        grep -Fqx 'keep-outputs = true' "$target/etc/nix/nix.conf"
        grep -Fqx 'keep-derivations = true' "$target/etc/nix/nix.conf"

        echo "  devenv is on the system path" >&2
        test -x "$target/sw/bin/devenv"

        echo "  the launchd plist exists" >&2
        test -f "$target/Library/LaunchDaemons/org.nixos.rosetta-builderd.plist"

        echo "  the activation script names the daemon" >&2
        grep -Fq 'org.nixos.rosetta-builderd' "$target/activate"
      '';

      # The `homeManager` half, both routes. The host route proves den forwards the aspect to
      # `home-manager.users.dev`; the standalone route proves the same half is a valid
      # home-manager module with no den entity at all.
      den-artifact-hm-host-darwin = mkArtifactCheck "hm-host-darwin" hmHostDarwin hmHookGreps;
      den-artifact-home-darwin = mkArtifactCheck "home-darwin" homeDarwin.activationPackage hmHookGreps;

      den-smoke-devenv-darwin = mkSmokeCheck "devenv-darwin" devenvDarwin;
      den-smoke-host-darwin = mkSmokeCheck "host-darwin" hostShellDarwin;
    };

    # `host-nixos` carries a real `nixos`-class aspect since `devenv-cli` landed, so it finally has
    # an artifact worth a grep. Its shell also holds `gh`, through `den.policies.host-to-devenv`.
    #
    # One script shape fits both classes. The NixOS toplevel links `$out/etc` to
    # `system.build.etc/etc` and `$out/sw` to `system.path`
    # (`<nixpkgs>/nixos/modules/system/activation/top-level.nix:34,36`); nix-darwin does the same at
    # `<nix-darwin>/modules/system/default.nix:152,153`.
    x86_64-linux = {
      den-artifact-host-nixos = mkArtifactCheck "host-nixos" nixosCfg.system.build.toplevel ''
        echo "  the nix.conf holds both devenv-cli garbage-collector opinions" >&2
        grep -Fqx 'keep-outputs = true' "$target/etc/nix/nix.conf"
        grep -Fqx 'keep-derivations = true' "$target/etc/nix/nix.conf"

        echo "  devenv is on the system path" >&2
        test -x "$target/sw/bin/devenv"
      '';

      den-artifact-hm-host-nixos = mkArtifactCheck "hm-host-nixos" hmHostNixos hmHookGreps;
      den-artifact-home-linux = mkArtifactCheck "home-linux" homeLinux.activationPackage hmHookGreps;

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
