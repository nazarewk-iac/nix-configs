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

  # Two aspects now write into one allowlist, so a gh-only assertion reads this narrowed list. Every
  # rule the `gh` aspect emits starts with `gh `.
  ghRules = builtins.filter (lib.hasPrefix "gh ") ghAllow;
  ghPackageCount =
    shell: builtins.length (builtins.filter (p: lib.hasPrefix "gh-" (p.name or "")) shell.packages);
  sorted = builtins.sort (a: b: a < b);

  # Every allow rule this tree emits starts with a tool name and one space. So one predicate names
  # the aspect that owns a rule.
  ownedBy = tools: r: lib.any (tool: lib.hasPrefix "${tool} " r) tools;

  # The two routes do not carry one identical allowlist any more. `host-darwin` includes `gh` and
  # `zellij`; a standalone shell includes `nix` too, and that aspect writes its own rules. So the
  # route-equality assertion compares the shared subset.
  sharedAllow = builtins.filter (ownedBy [
    "gh"
    "zellij"
  ]);

  # `devenv-cli` puts exactly one `pkgs.devenv` into every package list it touches. A count catches
  # a miss and an accidental duplicate with one assertion.
  devenvCount = ps: builtins.length (builtins.filter (p: (p.pname or "") == "devenv") ps);

  # A package list holds a package with this exact `name`. `name` carries the version suffix for a
  # versioned package, so every caller below names a package that sets none.
  hasPackageNamed = name: ps: lib.any (p: (p.name or "") == name) ps;

  # The two ends of the `signing` aspect's one promise: git and jj must read one identical
  # `allowed_signers` file. Each reader takes a home-manager `config`.
  gitAllowedSigners = cfg: cfg.programs.git.settings.gpg.ssh.allowedSignersFile;
  jjAllowedSigners = cfg: cfg.programs.jujutsu.settings.signing.backends.ssh.allowed-signers;

  # The ssh drop-in the `ssh-access` aspect installs. The `40-` prefix lets a consumer order its own
  # drop-ins around it.
  dropInPath = ".ssh/config.d/40-kdn-ssh-access.config";

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
      name = "every allow rule names a tool that an included aspect owns";
      expected = [ ];
      actual = builtins.filter (
        r:
        !(ownedBy [
          "devenv"
          "gh"
          # The `jj` aspect owns every `git ` rule too. Those five are the read-only git exceptions
          # that its own guard script names, so they move to a `git` aspect when one exists.
          "git"
          "jj"
          "nix"
          "zellij"
        ] r)
      ) ghAllow;
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
      ) ghRules;
    }
    {
      name = "both routes give one allowlist for the aspects they share";
      expected = sharedAllow ghAllow;
      actual = sharedAllow hostShellDarwin.claude.code.permissions.rules.Bash.allow;
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

  # The `ssh-agent` aspect is the first **`homeManager`-only** port. So these assertions test the
  # user scope on its own, on both routes and on both platforms.
  #
  # The platform split is the point of the last two. The aspect adds the `ssh-agent-claim` login
  # agent on darwin only, because it exists to remove the macOS built-in agent. A Linux user gets
  # the systemd user service from home-manager and no claim agent.
  sshAgentAssertions = [
    # ---- the standalone route, with no den entity
    {
      name = "each standalone home configuration runs the agent";
      expected = {
        home-darwin = true;
        home-linux = true;
      };
      actual = {
        home-darwin = homeDarwin.config.services.ssh-agent.enable;
        home-linux = homeLinux.config.services.ssh-agent.enable;
      };
    }
    # The nixpkgs `openssh` build links libfido2, and the macOS built-in agent supports no
    # `sk-ssh-ed25519` key. So the package choice is the reason this aspect exists.
    {
      name = "the agent package is the nixpkgs openssh build";
      expected = {
        home-darwin = "openssh";
        home-linux = "openssh";
      };
      actual = {
        home-darwin = homeDarwin.config.services.ssh-agent.package.pname;
        home-linux = homeLinux.config.services.ssh-agent.package.pname;
      };
    }

    # ---- the host route, through the `dev` user
    {
      name = "both hosts forward the agent to the user";
      expected = {
        host-darwin = true;
        host-nixos = true;
      };
      actual = {
        host-darwin = darwinCfg.home-manager.users.dev.services.ssh-agent.enable;
        host-nixos = nixosCfg.home-manager.users.dev.services.ssh-agent.enable;
      };
    }

    # ---- the platform split
    {
      name = "the claim agent exists on darwin and on darwin only";
      expected = {
        home-darwin = true;
        home-linux = false;
        host-darwin = true;
        host-nixos = false;
      };
      actual = {
        home-darwin = homeDarwin.config.launchd.agents ? ssh-agent-claim;
        home-linux = homeLinux.config.launchd.agents ? ssh-agent-claim;
        host-darwin = darwinCfg.home-manager.users.dev.launchd.agents ? ssh-agent-claim;
        host-nixos = nixosCfg.home-manager.users.dev.launchd.agents ? ssh-agent-claim;
      };
    }
    {
      name = "the Linux user gets the systemd user service instead";
      expected = true;
      actual = homeLinux.config.systemd.user.services ? ssh-agent;
    }

    # ---- the library route. One module, and it needs no `specialArgs`.
    {
      name = "denLib.imports resolves one homeManager module";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "homeManager";
          aspects = [ "ssh-agent" ];
        }
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
          select = d: [ d.ful.${denLib.namespaceName}.gh ];
        }
      );
    }

    # ---- the namespaces. See ../../modules/den/namespaces.nix.
    {
      name = "the library route carries the namespace, and it holds every registry aspect";
      expected = builtins.attrNames denLib.aspectModules;
      actual = builtins.filter (n: builtins.elem n (builtins.attrNames denLib.aspectModules)) (
        builtins.attrNames den.ful.${denLib.namespaceName}
      );
    }
    {
      name = "the namespace holds no aspect outside the registry";
      expected = [ ];
      actual = lib.subtractLists (
        (builtins.attrNames denLib.aspectModules)
        ++ [
          "_"
          "classes"
          "schema"
          "stages"
        ]
      ) (builtins.attrNames den.ful.${denLib.namespaceName});
    }
    {
      name = "the library route creates no `personal` namespace";
      expected = false;
      actual = den.ful ? personal;
    }
    {
      name = "the flake route exports the namespace as one output";
      expected = true;
      actual = flake.denful ? ${denLib.namespaceName};
    }
    {
      name = "the exported namespace holds every registry aspect";
      expected = builtins.attrNames denLib.aspectModules;
      actual = builtins.filter (n: builtins.elem n (builtins.attrNames denLib.aspectModules)) (
        builtins.attrNames flake.denful.${denLib.namespaceName}
      );
    }
    {
      name = "the flake route never exports the `personal` namespace";
      expected = false;
      actual = flake.denful ? personal;
    }
    {
      name = "the registry holds every ported aspect";
      expected = [
        "ca"
        "devenv-cli"
        "gh"
        "homebrew"
        "jj"
        "jj-fork"
        "llm"
        "llm-client"
        "llm-proxy"
        "mcp"
        "mcp-basic-memory"
        "mcp-pretty-print"
        "mcp-snoop"
        "nix"
        "opencode"
        "rosetta-builder"
        "signing"
        "ssh-access"
        "ssh-agent"
        "zellij"
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
  # The darwin-only greps. home-manager links the generation's `LaunchAgents` directory into the
  # activation package (`<home-manager>/modules/launchd/default.nix:207`) and it names each plist
  # `org.nix-community.home.<agent>.plist` (`:13,78`).
  hmLaunchdGreps = ''
    echo "  the home-manager ssh-agent plist" >&2
    test -f "$target/LaunchAgents/org.nix-community.home.ssh-agent.plist"

    echo "  the ssh-agent-claim login agent plist" >&2
    test -f "$target/LaunchAgents/org.nix-community.home.ssh-agent-claim.plist"

    echo "  the claim agent runs at load" >&2
    grep -Fq 'RunAtLoad' "$target/LaunchAgents/org.nix-community.home.ssh-agent-claim.plist"
  '';

  hmHookGreps = ''
    for pair in 'bash .bashrc' 'zsh .zshrc' 'fish .config/fish/config.fish'; do
      # shellcheck disable=SC2086
      set -- $pair
      echo "  the $1 hook in $2" >&2
      grep -Fq "devenv hook $1" "$target/home-files/$2"
    done
  '';

  # ------------------------------------------------------------------ ca

  # The `nixos`-only aspect. `host-nixos` carries three instances, one per branch of the aspect —
  # see ./host-nixos/default.nix. Every value below is a plain option read, so this stays tier 1: it
  # runs on a darwin machine with no linux builder.
  caCerts = map toString nixosCfg.security.pki.certificateFiles;

  caAssertions = [
    {
      name = "the aspect declares kdn.ca, and the entity supplies the data";
      expected = true;
      actual = nixosCfg.kdn.ca.den-mvp-test.enable;
    }
    {
      name = "the public certificate mounts world-readable";
      expected = "0444";
      actual = nixosCfg.environment.etc."kdn/ca/den-mvp-test.pub".mode;
    }
    {
      name = "the mounted source is the certificate the entity passed";
      expected = toString nixosCfg.kdn.ca.den-mvp-test.certFile;
      actual = toString nixosCfg.environment.etc."kdn/ca/den-mvp-test.pub".source;
    }
    {
      name = "an enabled certificate reaches the system CA bundle";
      expected = true;
      actual = builtins.elem (toString nixosCfg.kdn.ca.den-mvp-test.certFile) caCerts;
    }
    {
      name = "a CA with no encrypted key mounts no key blob";
      expected = false;
      actual = nixosCfg.environment.etc ? "kdn/ca/den-mvp-test.key.sops";
    }
    {
      name = "a CA with an encrypted key mounts it root-only";
      expected = "0400";
      actual = nixosCfg.environment.etc."kdn/ca/den-mvp-keyed.key.sops".mode;
    }
    {
      name = "a disabled CA mounts nothing";
      expected = false;
      actual = nixosCfg.environment.etc ? "kdn/ca/den-mvp-off.pub";
    }
    {
      name = "a disabled CA reaches no system CA bundle";
      expected = false;
      actual = builtins.elem (toString nixosCfg.kdn.ca.den-mvp-off.certFile) caCerts;
    }
    {
      name = "the library route resolves the aspect for the nixos class";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "nixos";
          aspects = [ "ca" ];
        }
      );
    }
    {
      name = "denModules.ca holds a non-empty imports list";
      expected = true;
      actual = (builtins.length flake.denModules.ca.imports) > 0;
    }
  ];

  # ------------------------------------------------------------------ homebrew

  # The Homebrew aspect. It is the first port with **no** slot ancestor, and it is the opt-in answer to
  # a force: `modules/universal/default.nix` configures Homebrew on every darwin host with no switch.
  #
  # Every list assertion is an exact equality on purpose. `./host-darwin/default.nix` supplies one
  # placeholder per list, so equality proves the aspect names no tap, no cask and no formula of its
  # own.
  #
  # nix-darwin coerces a plain string into a tap, cask or brew submodule, so each read below maps the
  # `name` attribute back out.
  brewNames = builtins.map (entry: entry.name);

  homebrewAssertions = [
    {
      name = "the aspect turns nix-darwin's own homebrew module on";
      expected = true;
      actual = darwinCfg.homebrew.enable;
    }
    {
      name = "each list holds the entity's own placeholder and no default of the aspect's";
      expected = {
        taps = [ "example-org/example-tap" ];
        casks = [ "example-cask" ];
        brews = [ "example-brew" ];
      };
      actual = {
        taps = brewNames darwinCfg.homebrew.taps;
        casks = brewNames darwinCfg.homebrew.casks;
        brews = brewNames darwinCfg.homebrew.brews;
      };
    }
    # The aspect declares each list with an empty default, so an adopter who supplies nothing gets
    # nothing. This reads the aspect's own option set, not the entity's values.
    {
      name = "a consumer that supplies no value gets three empty lists";
      expected = {
        taps = [ ];
        casks = [ ];
        brews = [ ];
      };
      actual =
        let
          bare = inputs.nix-darwin.lib.darwinSystem {
            system = null;
            modules = [
              flake.denModules.homebrew
              {
                nixpkgs.hostPlatform = "aarch64-darwin";
                system.primaryUser = "den";
                system.stateVersion = 7;
              }
            ];
          };
        in
        {
          taps = bare.config.kdn.homebrew.taps;
          casks = bare.config.kdn.homebrew.casks;
          brews = bare.config.kdn.homebrew.brews;
        };
    }
    # The three `onActivation` values mirror what `modules/universal/default.nix` sets today.
    {
      name = "the three onActivation values mirror the tree";
      expected = {
        upgrade = true;
        autoUpdate = false;
        cleanup = "zap";
      };
      actual = {
        inherit (darwinCfg.homebrew.onActivation) upgrade autoUpdate cleanup;
      };
    }
    # The aspect stays compatible with a hand-managed Homebrew, so it brings no nix-homebrew module.
    {
      name = "the aspect declares no nix-homebrew option";
      expected = false;
      actual = darwinCfg ? nix-homebrew;
    }
    {
      name = "the library route resolves the aspect for the darwin class";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "darwin";
          aspects = [ "homebrew" ];
        }
      );
    }
    {
      name = "denModules.homebrew holds a non-empty imports list";
      expected = true;
      actual = (builtins.length flake.denModules.homebrew.imports) > 0;
    }
  ];

  # ------------------------------------------------------------------ zellij

  # The first aspect with a Claude Code hook, and the first that installs a repository file.
  #
  # `devenv-darwin` leaves `kdn.isSourceRepo` false, so it installs the skill file. `devenv-linux`
  # sets it true, so it installs none. Both branches of the `files` guard then get a test — see
  # ./devenv/default.nix.
  zellijHooks = devenvDarwin.claude.code.hooks;
  zellijAllow = builtins.filter (lib.hasPrefix "zellij") ghAllow;
  skillPath = ".claude/skills/zellij/SKILL.md";

  # `lib.getName` reads `pname` when a derivation carries one, and it parses `name` otherwise. So one
  # helper counts a nixpkgs package and a `writeShellApplication` alike.
  countNamed = shell: n: builtins.length (builtins.filter (p: lib.getName p == n) shell.packages);

  zellijAssertions = [
    {
      name = "the shell holds exactly one zellij";
      expected = 1;
      actual = countNamed devenvDarwin "zellij";
    }
    {
      name = "the shell holds the kdn-slug helper, with no overlay";
      expected = 1;
      actual = countNamed devenvDarwin "kdn-slug";
    }
    {
      name = "the shell holds the zellij-llm helper, with no overlay";
      expected = 1;
      actual = countNamed devenvDarwin "zellij-llm";
    }
    {
      name = "the linux shell holds the same three packages";
      expected = [
        1
        1
        1
      ];
      actual = map (countNamed devenvLinux) [
        "zellij"
        "kdn-slug"
        "zellij-llm"
      ];
    }
    {
      name = "the PreToolUse hook matches a Bash call";
      expected = {
        hookType = "PreToolUse";
        matcher = "Bash";
      };
      actual = {
        inherit (zellijHooks.zellij-wait-for-devenv) hookType matcher;
      };
    }
    {
      name = "the PostToolUse hook matches a file write";
      expected = {
        hookType = "PostToolUse";
        matcher = "^(Edit|MultiEdit|Write)$";
      };
      actual = {
        inherit (zellijHooks.zellij-wait-for-devenv-start) hookType matcher;
      };
    }
    {
      name = "each hook runs a store path";
      expected = [
        true
        true
      ];
      actual = map (h: lib.hasPrefix builtins.storeDir h) [
        zellijHooks.zellij-wait-for-devenv.command
        zellijHooks.zellij-wait-for-devenv-start.command
      ];
    }
    {
      name = "the allowlist holds the one static read of the agent's own pane";
      expected = true;
      actual = lib.elem ''zellij action dump-screen -p "$ZELLIJ_PANE_ID" | tail -n 1'' zellijAllow;
    }
    {
      name = "the allowlist holds no wildcard pane read";
      expected = [ ];
      actual = builtins.filter (r: lib.hasInfix "dump-screen" r && lib.hasInfix "*" r) zellijAllow;
    }
    {
      name = "the allowlist holds no mutating action and no other content read";
      expected = [ ];
      actual = builtins.filter (
        r:
        lib.any (a: lib.hasInfix a r) [
          "new-pane"
          "new-tab"
          "go-to-tab"
          "focus-pane-id"
          "close-"
          "kill-session"
          "delete-session"
          "write"
          "paste"
          "send-keys"
          "subscribe"
          "edit-scrollback"
        ]
      ) zellijAllow;
    }
    {
      name = "an adopter shell installs the skill file";
      expected = true;
      actual = devenvDarwin.files ? ${skillPath};
    }
    {
      name = "the skill source names one file inside the tree the evaluation already reads";
      expected = true;
      actual = lib.hasSuffix "/.agents/skills/zellij/SKILL.md" (
        toString devenvDarwin.files.${skillPath}.source
      );
    }
    {
      name = "the source repository installs no skill file";
      expected = false;
      actual = devenvLinux.files ? ${skillPath};
    }
    {
      name = "the library route resolves the aspect for the devenv class";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "devenv";
          aspects = [ "zellij" ];
        }
      );
    }
    {
      name = "denModules.zellij holds a non-empty imports list";
      expected = true;
      actual = (builtins.length flake.denModules.zellij.imports) > 0;
    }
  ];

  # ------------------------------------------------------------------ opencode

  # The aspect declares eight options and holds no data. `./devenv/default.nix` supplies every value
  # as a neutral placeholder, so these assertions also prove the aspect names no provider, no model
  # and no checkout path by itself.
  #
  # `devenv-darwin` keeps the real `pkgs.opencode` and names a model. `devenv-linux` overrides the
  # package and leaves `defaultModel` null, so both negative cases get a test.
  ocSettings = devenvDarwin.opencode.settings;
  ocPermission = ocSettings.permission;
  ocWrapper = lib.head (builtins.filter (p: lib.getName p == "opencode") devenvDarwin.packages);

  opencodeAssertions = [
    {
      name = "devenv's own opencode integration is on";
      expected = true;
      actual = devenvDarwin.opencode.enable;
    }
    {
      name = "the shell holds exactly one binary named opencode";
      expected = 1;
      actual = countNamed devenvDarwin "opencode";
    }
    {
      name = "that binary is the wrapper, not the real opencode";
      expected = false;
      actual = ocWrapper.outPath == devenvDarwin.kdn.opencode.package.outPath;
    }
    {
      name = "the default package is the real opencode";
      expected = "opencode";
      actual = lib.getName devenvDarwin.kdn.opencode.package;
    }
    {
      name = "a package override reaches the wrapper";
      expected = "opencode-under-test";
      actual = lib.getName devenvLinux.kdn.opencode.package;
    }
    {
      name = "every allowed path reaches the read permission block";
      expected = {
        "/nix/store/**" = "allow";
        "~/src/**" = "allow";
      };
      actual = ocPermission.read;
    }
    {
      name = "the four read-only tools share one allow map";
      expected = [
        ocPermission.read
        ocPermission.read
        ocPermission.read
      ];
      actual = [
        ocPermission.glob
        ocPermission.grep
        ocPermission.list
      ];
    }
    {
      name = "a reach outside the project asks first";
      expected = "ask";
      actual = ocPermission.external_directory."*";
    }
    {
      name = "a write asks first";
      expected = "ask";
      actual = ocPermission.edit;
    }
    {
      name = "an unlisted shell command asks first";
      expected = "ask";
      actual = ocPermission.bash."*";
    }
    {
      name = "the consumer supplies the only provider name";
      expected = [ "example-provider" ];
      actual = builtins.attrNames ocSettings.provider;
    }
    {
      name = "a named default model reaches opencode.jsonc";
      expected = "example-provider/example-model";
      actual = ocSettings.model;
    }
    {
      name = "a null default model writes no model key";
      expected = false;
      actual = devenvLinux.opencode.settings ? model;
    }
    {
      name = "the library route resolves the aspect for the devenv class";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "devenv";
          aspects = [ "opencode" ];
        }
      );
    }
    {
      name = "denModules.opencode holds a non-empty imports list";
      expected = true;
      actual = (builtins.length flake.denModules.opencode.imports) > 0;
    }
  ];

  # The `mcp` family, four aspects in one diamond. `mcp-snoop` includes `mcp`, and
  # `mcp-basic-memory` includes `mcp-pretty-print`, which includes `mcp` too. So these assertions
  # test two things at once: each aspect's own promise, and that den collapses the diamond.
  #
  # `mcp-servers-nix` is a `devenv.yaml` input, so no den evaluation reaches the real one. The
  # entity passes ../mcp-servers-nix-stub instead, and the stub turns the aspect's own `programs`
  # declarations into servers. So the translation code gets a real test on both branches.
  mcpBackendNames = shell: sorted (builtins.attrNames shell.kdn.mcp.backends);
  mcpPnames = shell: builtins.filter (n: n == "mcp-gateway") (map (p: p.pname or "") shell.packages);

  mcpAssertions = [
    # ---- the parent aspect: the translation from `programs` to gateway backends
    {
      name = "every declared program and every extra backend reaches the gateway";
      expected = [
        "devenv"
        "fetch"
        "filesystem"
        "jj"
        "memory-archive"
        "memory-general"
        "nixos"
        "sequential-thinking"
        "stub-http"
        "time"
      ];
      actual = mcpBackendNames devenvDarwin;
    }
    {
      name = "devenv-linux translates the same backend set";
      expected = mcpBackendNames devenvDarwin;
      actual = mcpBackendNames devenvLinux;
    }
    {
      name = "a stdio server folds its args into one command string";
      expected = "/den-mvp/bin/filesystem /nix/store";
      actual = devenvDarwin.kdn.mcp.backends.filesystem.command;
    }
    {
      name = "an http server takes the url key and never a command";
      expected = [
        "description"
        "headers"
        "http_url"
      ];
      actual = sorted (builtins.attrNames devenvDarwin.kdn.mcp.backends.stub-http);
    }
    {
      name = "the gateway registers with Claude Code as a stdio server";
      expected = "stdio";
      actual = devenvDarwin.claude.code.mcpServers.mcp-gateway.type;
    }
    {
      name = "no warning fires while the entity supplies a servers source";
      expected = [ ];
      actual = devenvDarwin.warnings;
    }

    # ---- the diamond. Four aspects name `mcp` in their own `includes` — `mcp-snoop`,
    # `mcp-pretty-print`, `nix` and `jj` — and the shell must hold one gateway.
    {
      name = "the diamond collapses to exactly one gateway package";
      expected = 1;
      actual = builtins.length (mcpPnames devenvDarwin);
    }

    # ---- `mcp-snoop`: it wraps the gateway command, exactly once
    {
      name = "the snoop aspect adds exactly one command overlay";
      expected = 1;
      actual = builtins.length devenvDarwin.kdn.mcp.commandOverlays;
    }
    {
      name = "the registered command is the snoop wrapper, not the gateway itself";
      expected = true;
      actual = lib.hasSuffix "-mcp-gateway-snoop-wrapper" devenvDarwin.claude.code.mcpServers.mcp-gateway.command;
    }

    # ---- `mcp-pretty-print`: the permission hook
    {
      name = "the pretty-print hook registers on the gateway invoke tool";
      expected = {
        hookType = "PermissionRequest";
        matcher = "mcp__mcp-gateway__gateway_invoke";
      };
      actual = {
        inherit (devenvDarwin.claude.code.hooks.mcp-gateway-pretty-print) hookType matcher;
      };
    }

    # ---- `mcp-basic-memory`: one wrapper per base, and the formatter that renders it
    {
      name = "the basic-memory formatter reaches the pretty-print plugin set";
      expected = [ "basic-memory" ];
      actual = sorted (builtins.attrNames devenvDarwin.kdn.mcp.pretty-print.formatters);
    }
    {
      name = "each base backend calls its own wrapper binary in mcp mode";
      expected = true;
      actual = lib.hasSuffix "/bin/basic-memory-general mcp" devenvDarwin.kdn.mcp.backends.memory-general.command;
    }
    {
      name = "each base backend carries the description the entity gave it";
      expected = "den MVP general knowledge base";
      actual = devenvDarwin.kdn.mcp.backends.memory-general.description;
    }
    {
      name = "the agent rule installs when the consumer is not the source repository";
      expected = true;
      actual = devenvDarwin.files ? ".claude/rules/basic-memory.md";
    }
    {
      name = "the agent rule stays out of the source repository, which commits it";
      expected = false;
      actual = devenvLinux.files ? ".claude/rules/basic-memory.md";
    }
  ];

  # ------------------------------------------------------------------ nix

  # The `nix` aspect is the first port whose coupling runs **downward**: it writes two of the `mcp`
  # aspect's own options through `includes`. It is also the first aspect that registers a git-hooks
  # pre-commit hook, so it is the first that needs a real flake input inside the devenv class — see
  # `den.devenv.inputs` in ../../modules/den/classes/devenv.nix.
  #
  # Three groups of assertion cover the three defects the port fixes:
  #
  #  1. The `devenv` MCP backend runs a wrapper, so `DEVENV_ROOT` expands at run time. The slot froze
  #     a read-only store copy of the whole repository into `env.DEVENV_ROOT`.
  #  2. `kdn.nix.extraBashAllow` carries the consumer's own flake app. The slot hardcoded one app of
  #     this repository.
  #  3. Each installed file comes from a relative path literal, so the derivation reads one file.
  nixHook = devenvDarwin.claude.code.hooks.git-hooks-run;
  nixStoreSymlinkHook = devenvDarwin.git-hooks.hooks.check-nix-store-symlinks;

  # The `nix` aspect installs two skills and one rule. Every path below is relative to the consumer's
  # own working tree.
  nixFilePaths = [
    ".claude/skills/flake-update/SKILL.md"
    ".claude/skills/flake-patches/SKILL.md"
    ".claude/rules/okf-format.md"
  ];

  nixAssertions = [
    # ---- the shell packages
    {
      name = "both language servers and the formatter reach the shell packages";
      expected = [
        1
        1
        1
      ];
      actual = map (countNamed devenvDarwin) [
        "nil"
        "nixd"
        "nixfmt"
      ];
    }
    {
      name = "the linux shell holds the same three packages";
      expected = [
        1
        1
        1
      ];
      actual = map (countNamed devenvLinux) [
        "nil"
        "nixd"
        "nixfmt"
      ];
    }

    # ---- the two MCP backends, written through `includes`
    {
      name = "the nixos option-search program is on";
      expected = true;
      actual = devenvDarwin.kdn.mcp.programs.nixos.enable;
    }
    {
      name = "the devenv backend command is a wrapper script, not a bare command";
      expected = true;
      actual = lib.hasSuffix "-devenv-mcp-wrapper" devenvDarwin.kdn.mcp.backends.devenv.command;
    }
    {
      name = "the devenv backend freezes no repository store path in its environment";
      expected = false;
      actual = devenvDarwin.kdn.mcp.backends.devenv ? env;
    }
    {
      name = "the devenv backend keeps the description the slot gave it";
      expected = "devenv — search nixpkgs packages and devenv options";
      actual = devenvDarwin.kdn.mcp.backends.devenv.description;
    }

    # ---- the Claude Code allowlist
    {
      name = "the allowlist holds a read-only nix entry";
      expected = true;
      actual = lib.elem "nix eval *" ghAllow;
    }
    {
      name = "the entity's own extraBashAllow value reaches the allowlist";
      expected = true;
      actual = lib.elem "nix run .#example-formatter -- *" ghAllow;
    }
    # The aspect names no flake app of its own, so the entity's one placeholder is the whole set. A
    # bare `nix run *` wildcard executes an arbitrary flake app, so it must never appear here.
    {
      name = "every nix run rule comes from the entity, and none is a bare wildcard";
      expected = [ "nix run .#example-formatter -- *" ];
      actual = builtins.filter (lib.hasPrefix "nix run") ghAllow;
    }

    # ---- the two git-hooks halves
    {
      name = "the git-hooks-run hook runs the whole suite";
      expected = true;
      actual = lib.hasInfix "--all-files" nixHook.command;
    }
    {
      name = "the git-hooks-run hook keeps devenv's own file-edit matcher";
      expected = "^(Edit|MultiEdit|Write)$";
      actual = nixHook.matcher;
    }
    {
      name = "the store-symlink hook is registered on both stages";
      expected = {
        enable = true;
        always_run = true;
        pass_filenames = false;
        stages = [
          "pre-commit"
          "pre-push"
        ];
      };
      actual = {
        inherit (nixStoreSymlinkHook)
          enable
          always_run
          pass_filenames
          stages
          ;
      };
    }
    # The stub submodule that devenv falls back to declares `enable` alone, and its `package` option
    # does not exist. So a real package name here proves the class carries the real flake input.
    {
      name = "the real git-hooks input reaches the class, so the hook runner is prek";
      expected = {
        enable = true;
        package = "prek";
      };
      actual = {
        inherit (devenvDarwin.git-hooks) enable;
        package = lib.getName devenvDarwin.git-hooks.package;
      };
    }

    # ---- the three installed files, and both branches of `kdn.isSourceRepo`
    {
      name = "an adopter shell installs both skills and the rule";
      expected = [
        true
        true
        true
      ];
      actual = map (path: devenvDarwin.files ? ${path}) nixFilePaths;
    }
    {
      name = "the source repository installs none of the three, because it commits them";
      expected = [
        false
        false
        false
      ];
      actual = map (path: devenvLinux.files ? ${path}) nixFilePaths;
    }
    {
      name = "each source names one file inside the tree the evaluation already reads";
      expected = [
        true
        true
        true
      ];
      actual =
        lib.zipListsWith (path: suffix: lib.hasSuffix suffix (toString devenvDarwin.files.${path}.source))
          nixFilePaths
          [
            "/.agents/skills/flake-update/SKILL.md"
            "/.agents/skills/flake-patches/SKILL.md"
            "/.agents/rules/okf-format.md"
          ];
    }

    # ---- the two adopter routes
    {
      name = "the library route resolves the aspect for the devenv class";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "devenv";
          aspects = [ "nix" ];
        }
      );
    }
    {
      name = "denModules.nix holds a non-empty imports list";
      expected = true;
      actual = (builtins.length flake.denModules.nix.imports) > 0;
    }
  ];

  # ------------------------------------------------------------------ jj and jj-fork

  # The `jj` family, a coupled pair in one diamond. `jj-fork` includes `jj`, and `jj` includes `mcp`.
  # ./devenv/default.nix lists the leaf only, so these assertions prove the parent arrives with it.
  #
  # The family is the first port that de-personalizes a **default**. Three values carried one
  # person's own data: the public remote name, and the pattern list that blocks a push. Each one is
  # now an option with a neutral default, and the entity supplies a placeholder. So an exact-equality
  # assertion on each list also proves the aspect adds nothing of its own.
  #
  # `devenv-darwin` leaves `kdn.isSourceRepo` false and sets both remote URLs. `devenv-linux` sets
  # the flag true and names no URL. So both branches of `files`, of the agent guard and of the
  # `enterShell` block get a test.
  jjConfig = devenvDarwin.kdn.jj.config;
  jjRevsets = jjConfig.revset-aliases;
  jjHook = devenvDarwin.claude.code.hooks.jj-guard;
  jjRules = builtins.filter (lib.hasPrefix "jj ") ghAllow;

  # The `fork-help` alias is `[ "util" "exec" "--" "bash" "-c" <script> ]`, so the script is the last
  # element.
  forkHelpScript = lib.last jjConfig.aliases.fork-help;

  jjFilePaths = [
    ".claude/rules/jujutsu-vcs.md"
    ".claude/skills/jujutsu-vcs/SKILL.md"
    ".claude/rules/flake-update.fork.md"
    ".claude/skills/flake-update-fork/SKILL.md"
  ];

  jjAssertions = [
    # ---- the shell packages. The parent adds jujutsu; the fork half adds the two commands.
    {
      name = "the shell holds exactly one jujutsu, one audit command and one update check";
      expected = [
        1
        1
        1
      ];
      actual = map (countNamed devenvDarwin) [
        "jujutsu"
        "jj-fork-audit"
        "jj-flake-update-complete"
      ];
    }
    {
      name = "the linux shell holds the same three";
      expected = [
        1
        1
        1
      ];
      actual = map (countNamed devenvLinux) [
        "jujutsu"
        "jj-fork-audit"
        "jj-flake-update-complete"
      ];
    }

    # ---- the two MCP writes, through `includes`
    {
      name = "the jj backend runs the jj-mcp binary, with no overlay";
      expected = true;
      actual = lib.hasSuffix "/bin/jj-mcp" devenvDarwin.kdn.mcp.backends.jj.command;
    }
    {
      name = "the jj backend keeps the description the slot gave it";
      expected = "jj — Jujutsu version control tools";
      actual = devenvDarwin.kdn.mcp.backends.jj.description;
    }
    # The gateway's own git backend duplicates the jj backend for a colocated repository, and it names
    # git operations that this repository forbids. So the aspect turns it off, and no backend appears.
    {
      name = "the gateway git backend is off, and it reaches no backend";
      expected = {
        enable = false;
        present = false;
      };
      actual = {
        inherit (devenvDarwin.kdn.mcp.programs.git) enable;
        present = devenvDarwin.kdn.mcp.backends ? git;
      };
    }

    # ---- the raw-git guard hook. It warns and never blocks.
    {
      name = "the guard hook matches every Bash call before it runs";
      expected = {
        hookType = "PreToolUse";
        matcher = "Bash";
      };
      actual = { inherit (jjHook) hookType matcher; };
    }
    {
      name = "the guard hook runs a store path from the consumer's own root";
      expected = true;
      actual =
        lib.hasInfix ''cd "$DEVENV_ROOT"'' jjHook.command && lib.hasInfix builtins.storeDir jjHook.command;
    }

    # ---- the Claude Code allowlist. The negative assertions are the point.
    {
      name = "the allowlist holds the read-only jj log rule";
      expected = true;
      actual = lib.elem "jj log *" ghAllow;
    }
    {
      name = "the allowlist holds no bare jj wildcard";
      expected = [ ];
      actual = builtins.filter (r: r == "jj *" || r == "jj*") ghAllow;
    }
    # A narrow `jj file show *` rule must never widen to `jj file *`, because `jj file chmod`,
    # `jj file track` and `jj file untrack` all mutate.
    {
      name = "the allowlist holds no wide jj file or jj config rule";
      expected = [ ];
      actual = builtins.filter (r: r == "jj file *" || r == "jj config *") ghAllow;
    }
    {
      name = "the allowlist holds no mutating jj subcommand";
      expected = [ ];
      actual = builtins.filter (
        r:
        lib.any (sub: lib.hasPrefix "jj ${sub}" r) [
          "abandon"
          "bookmark delete"
          "bookmark set"
          "commit"
          "describe"
          "edit"
          "git push"
          "new"
          "op restore"
          "rebase"
          "split"
          "squash"
          "undo"
        ]
      ) jjRules;
    }

    # ---- the fork remotes
    {
      name = "the fork remote takes every push, and both remotes take a fetch";
      expected = {
        push = "private";
        fetch = [
          "private"
          "public"
        ];
      };
      actual = { inherit (jjConfig.git) push fetch; };
    }

    # ---- the revset aliases. Each expected value names the entity's own placeholders only.
    {
      name = "trunk() names the fork remote's own main bookmark";
      expected = "main@private";
      actual = jjRevsets."trunk()";
    }
    {
      name = "both incoming tips name the right remote";
      expected = {
        upstream-incoming-tip = "main@public";
        fork-incoming-tip = "main@private";
      };
      actual = {
        inherit (jjRevsets) upstream-incoming-tip fork-incoming-tip;
      };
    }
    # The sensitive-content predicate. Each denied file pattern becomes a path glob and a changed-line
    # glob; each denied message pattern becomes a description glob. So this equality proves the whole
    # mapping, and it proves the aspect names no pattern of its own.
    {
      name = "fork-direct maps every entity pattern and adds none";
      expected = lib.concatStringsSep " | " [
        "files(prefix-glob-i:**/*den-mvp-denied-path**)"
        "diff_lines(glob-i:*den-mvp-denied-path*)"
        "description(glob-i:*den-mvp-denied-message*)"
      ];
      actual = jjRevsets.fork-direct;
    }
    # An ancestor-set difference, never `::(A ~ B)`. The comment in the aspect states why.
    {
      name = "the fork alias keeps the ancestor-set difference";
      expected = lib.concatStringsSep " | " [
        "fork-direct"
        "(::remote_bookmarks(remote=\"private\")) ~ (::upstream@private)"
        "(remote_bookmarks(remote=\"private\") ~ upstream@private)::"
      ];
      actual = jjRevsets.fork;
    }
    # `upstream-safe` must subtract `fork-direct`, the content predicate — never `fork`, which tags
    # every descendant of the fork main and would drop a safe local change too.
    {
      name = "upstream-safe subtracts the content predicate, not the topology alias";
      expected = "to-rebase & ~fork-direct";
      actual = jjRevsets.upstream-safe;
    }
    {
      name = "the revset alias set holds every name the fork workflow reads";
      expected = [
        "fork"
        "fork-chain"
        "fork-direct"
        "fork-incoming"
        "fork-incoming-tip"
        "fork-leaked"
        "fork-tip"
        "merge-frozen"
        "pushed"
        "pushed-fork"
        "pushed-upstream"
        "to-rebase"
        "tree-merge"
        "trunk()"
        "upstream-chain"
        "upstream-incoming"
        "upstream-incoming-tip"
        "upstream-local"
        "upstream-safe"
        "upstream-tip"
      ];
      actual = sorted (builtins.attrNames jjRevsets);
    }

    # ---- the five jj aliases
    {
      name = "the config holds the five fork aliases";
      expected = [
        "fork-audit"
        "fork-help"
        "sync-remotes"
        "sync-upstream"
        "update-check"
      ];
      actual = sorted (builtins.attrNames jjConfig.aliases);
    }
    # The fork document is one file in the store, not a copy of the whole tree. A `/docs/` segment in
    # the script would mean the slot's `"${inputs.nix-configs}/…"` route came across.
    {
      name = "fork-help reads one file, and no whole-tree copy";
      expected = {
        oneFile = true;
        treeCopy = false;
      };
      actual = {
        oneFile = lib.hasInfix "-jujutsu-vcs.fork.md" forkHelpScript;
        treeCopy = lib.hasInfix "/docs/jujutsu-vcs.fork.md" forkHelpScript;
      };
    }
    # `sync-upstream` is the one route that reaches the public remote with a real `git push`, so it is
    # the one route the pre-push hook can see. `jj git push` fires no hook at all.
    {
      name = "sync-upstream pushes the public remote through real git";
      expected = true;
      actual = lib.hasInfix "git -C \"$(jj root)\" push public upstream:main" (
        lib.last jjConfig.aliases.sync-upstream
      );
    }

    # ---- the two git hooks
    {
      name = "the pre-push guard runs on every push, with no file list";
      expected = {
        enable = true;
        always_run = true;
        pass_filenames = false;
        stages = [ "pre-push" ];
      };
      actual = {
        inherit (devenvDarwin.git-hooks.hooks.jj-pre-push)
          enable
          always_run
          pass_filenames
          stages
          ;
      };
    }
    {
      name = "the contamination check runs on every commit, with no file list";
      expected = {
        enable = true;
        always_run = true;
        pass_filenames = false;
        stages = [ "pre-commit" ];
      };
      actual = {
        inherit (devenvDarwin.git-hooks.hooks.jj-check-fork-contamination)
          enable
          always_run
          pass_filenames
          stages
          ;
      };
    }

    # ---- the pattern lists. Each one holds the entity's placeholder and nothing else.
    {
      name = "every pattern list holds the entity's own value and no default of the aspect's";
      expected = {
        alwaysBlocked = [ "den-mvp-blocked-message" ];
        deniedFiles = [ "den-mvp-denied-path" ];
        deniedMessages = [ "den-mvp-denied-message" ];
      };
      actual = {
        alwaysBlocked = devenvDarwin.kdn.jj.alwaysBlockedMessagePatterns;
        deniedFiles = devenvDarwin.kdn.jj.fork.deniedFilePatterns;
        deniedMessages = devenvDarwin.kdn.jj.fork.deniedMessagePatterns;
      };
    }

    # ---- the four installed files, the agent, and both branches of `kdn.isSourceRepo`
    {
      name = "an adopter shell installs both rules and both skills";
      expected = [
        true
        true
        true
        true
      ];
      actual = map (path: devenvDarwin.files ? ${path}) jjFilePaths;
    }
    {
      name = "the source repository installs none of the four, because it commits them";
      expected = [
        false
        false
        false
        false
      ];
      actual = map (path: devenvLinux.files ? ${path}) jjFilePaths;
    }
    {
      name = "each source names one file inside the tree the evaluation already reads";
      expected = [
        true
        true
        true
        true
      ];
      actual =
        lib.zipListsWith (path: suffix: lib.hasSuffix suffix (toString devenvDarwin.files.${path}.source))
          jjFilePaths
          [
            "/.agents/rules/jujutsu-vcs.md"
            "/.agents/skills/jujutsu-vcs/SKILL.md"
            "/.agents/rules/flake-update.fork.md"
            "/.agents/skills/flake-update-fork/SKILL.md"
          ];
    }
    {
      name = "the jj-expert agent installs for an adopter and stays out of the source repository";
      expected = {
        adopter = true;
        sourceRepo = false;
      };
      actual = {
        adopter = devenvDarwin.claude.code.agents ? jj-expert;
        sourceRepo = devenvLinux.claude.code.agents ? jj-expert;
      };
    }
    # devenv removed `claude.code.agents.<name>.proactive` on 2026-08-16, and a definition of it is
    # now a hard assertion failure. The prescribed migration is a phrase in the description. The slot
    # still sets the option, and it never notices, because this repository gates the agent off.
    {
      name = "the agent asks for automatic delegation through its description";
      expected = true;
      actual = lib.hasInfix "Use proactively" devenvDarwin.claude.code.agents.jj-expert.description;
    }
    # This is the cheap gate for the whole class. A failed devenv assertion throws only when
    # something reads `config.shell` or `config.test`, so tier 3 catches it and tier 1 does not. This
    # line reads the list itself, so one evaluation names every failure.
    {
      name = "neither shell holds a failed devenv assertion";
      expected = {
        devenv-darwin = [ ];
        devenv-linux = [ ];
      };
      actual = {
        devenv-darwin = map (a: a.message) (builtins.filter (a: !a.assertion) devenvDarwin.assertions);
        devenv-linux = map (a: a.message) (builtins.filter (a: !a.assertion) devenvLinux.assertions);
      };
    }

    # ---- the two adopter routes, once per aspect
    {
      name = "the library route resolves each aspect for the devenv class";
      expected = {
        jj = 1;
        jj-fork = 1;
      };
      actual = {
        jj = builtins.length (
          denLib.imports {
            class = "devenv";
            aspects = [ "jj" ];
          }
        );
        jj-fork = builtins.length (
          denLib.imports {
            class = "devenv";
            aspects = [ "jj-fork" ];
          }
        );
      };
    }
    {
      name = "both exported modules hold a non-empty imports list";
      expected = {
        jj = true;
        jj-fork = true;
      };
      actual = {
        jj = (builtins.length flake.denModules.jj.imports) > 0;
        jj-fork = (builtins.length flake.denModules.jj-fork.imports) > 0;
      };
    }
  ];

  # ----------------------------------------------------------------------- llm

  # The `llm` family is the first one that spans two classes. `llm` emits `nixos`, `llm-client` emits
  # `devenv`, and `llm-proxy` emits both.
  #
  # No parallel entity includes an aspect of this family yet, so every assertion below reads a route
  # and not a built configuration. `../den-mvp/host-nixos` and `../den-mvp/devenv` gain the
  # inclusions in a later commit, and the deeper assertions come with them.
  llmAssertions = [
    {
      name = "the library route resolves each aspect for its own class";
      expected = {
        llm = 1;
        llm-client = 1;
        llm-proxy-nixos = 1;
        llm-proxy-devenv = 1;
      };
      actual = {
        llm = builtins.length (
          denLib.imports {
            class = "nixos";
            aspects = [ "llm" ];
          }
        );
        llm-client = builtins.length (
          denLib.imports {
            class = "devenv";
            aspects = [ "llm-client" ];
          }
        );
        # One aspect, two classes. Each route resolves on its own, so the shared option module
        # reaches both class trees.
        llm-proxy-nixos = builtins.length (
          denLib.imports {
            class = "nixos";
            aspects = [ "llm-proxy" ];
          }
        );
        llm-proxy-devenv = builtins.length (
          denLib.imports {
            class = "devenv";
            aspects = [ "llm-proxy" ];
          }
        );
      };
    }
    # `llm-client` names `opencode` in its own `includes`, so one aspect name still gives one module.
    # den collapses the pair.
    {
      name = "the whole family resolves in one devenv list, with the opencode diamond collapsed";
      expected = 2;
      actual = builtins.length (
        denLib.imports {
          class = "devenv";
          aspects = [
            "llm-client"
            "llm-proxy"
          ];
        }
      );
    }
    {
      name = "both exported modules hold a non-empty imports list";
      expected = {
        llm = true;
        llm-client = true;
      };
      actual = {
        llm = (builtins.length flake.denModules.llm.imports) > 0;
        llm-client = (builtins.length flake.denModules.llm-client.imports) > 0;
      };
    }
    # `llm-proxy` has no `denModules` entry, because the zero-argument export form names exactly one
    # class. `devenv-cli` and `ssh-access` are absent for the same reason. This line states the fact,
    # so a later change to the export surface cannot pass in silence.
    {
      name = "a multi-class aspect gets no zero-argument export";
      expected = {
        llm-proxy = false;
        devenv-cli = false;
        ssh-access = false;
      };
      actual = {
        llm-proxy = flake.denModules ? llm-proxy;
        devenv-cli = flake.denModules ? devenv-cli;
        ssh-access = flake.denModules ? ssh-access;
      };
    }
  ];

  # The `signing` aspect is a `homeManager`-only port, like `ssh-agent`. So these assertions read the
  # user scope alone, on both routes and on both platforms.
  #
  # The aspect holds no key. Every principal and every public key comes from the test subject, so an
  # assertion here compares wiring and never key material. See ./home/default.nix and
  # ./users/default.nix.
  signingAssertions = [
    # ---- the script reaches every user, on both routes
    {
      name = "each standalone home configuration installs kdn-signing";
      expected = {
        home-darwin = true;
        home-linux = true;
      };
      actual = {
        home-darwin = hasPackageNamed "kdn-signing" homeDarwin.config.home.packages;
        home-linux = hasPackageNamed "kdn-signing" homeLinux.config.home.packages;
      };
    }
    {
      name = "both hosts forward kdn-signing to the user";
      expected = {
        host-darwin = true;
        host-nixos = true;
      };
      actual = {
        host-darwin = hasPackageNamed "kdn-signing" darwinCfg.home-manager.users.dev.home.packages;
        host-nixos = hasPackageNamed "kdn-signing" nixosCfg.home-manager.users.dev.home.packages;
      };
    }

    # ---- one file, two tools. This is the whole point of the aspect: without the wiring each tool
    # signs but verifies nothing, and `jj log -T 'signature.status()'` reports `SIGNED bad`.
    {
      name = "git and jj read one identical allowed_signers file";
      expected = {
        home-darwin = true;
        home-linux = true;
        host-darwin = true;
        host-nixos = true;
      };
      actual = lib.mapAttrs (_: cfg: gitAllowedSigners cfg == jjAllowedSigners cfg) {
        home-darwin = homeDarwin.config;
        home-linux = homeLinux.config;
        host-darwin = darwinCfg.home-manager.users.dev;
        host-nixos = nixosCfg.home-manager.users.dev;
      };
    }
    {
      name = "the wired file is a store path";
      expected = true;
      actual = lib.hasPrefix builtins.storeDir (gitAllowedSigners homeLinux.config);
    }
    # The standalone subject names two signers and the host user names one. So two different entry
    # lists must give two different files, and the generator cannot be a constant.
    {
      name = "a different entry list gives a different file";
      expected = true;
      actual = gitAllowedSigners homeLinux.config != gitAllowedSigners darwinCfg.home-manager.users.dev;
    }

    # ---- rule 2: inclusion is the switch. The slot's `kdn.signing.enable` is gone.
    {
      name = "the aspect declares no `enable` option";
      expected = false;
      actual = homeLinux.options.kdn.signing ? enable;
    }
    # ---- the neutral defaults. An adopter who supplies nothing gets no file and no personal name.
    {
      name = "allowedSigners defaults to the empty list";
      expected = [ ];
      actual = homeLinux.options.kdn.signing.allowedSigners.default;
    }
    # The slot defaults this to a name that carries one person's own namespace. The port names no
    # person. See gap 6 of ../../docs/tasks/2026-09/generalization/definition.md.
    {
      name = "the plain key-file default names no person";
      expected = "~/.ssh/id_ed25519_plain_signing";
      actual = homeLinux.options.kdn.signing.plain.keyFile.default;
    }

    # ---- the export surface. One class, so the zero-argument form exists.
    {
      name = "denLib.imports resolves one homeManager module";
      expected = 1;
      actual = builtins.length (
        denLib.imports {
          class = "homeManager";
          aspects = [ "signing" ];
        }
      );
    }
    {
      name = "the flake exports a zero-argument module with a non-empty imports list";
      expected = true;
      actual = (builtins.length flake.denModules.signing.imports) > 0;
    }
  ];

  # The `ssh-access` aspect emits two classes, `homeManager` and `devenv`. So these assertions read
  # both halves, and they read the empty-graph branch too.
  #
  # The aspect holds no graph. Every host name, address, port and key path comes from
  # ./ssh-access-graph.nix, and every value there is fictional. No assertion opens a connection: the
  # comparisons are evaluations, and even the shell's own `enterTest` calls `emit-ssh-config` alone.
  sshAccessAssertions = [
    # ---- the de-personalized default. The shared schema file
    # ../../packages/kdn-ssh-access/module.nix defaults `defaults.user` to one person's login name,
    # and the aspect overrides it to null at priority 1400. `devenv-linux` names no graph, so it is
    # the one subject that reads the neutralized value.
    {
      name = "the user default is null when the consumer names no graph";
      expected = null;
      actual = devenvLinux.kdn.ssh-access.defaults.user;
    }
    {
      name = "a consumer's own graph wins over the neutral default";
      expected = {
        devenv-darwin = "den-mvp";
        home-linux = "den-mvp";
        host-darwin = "den-mvp";
      };
      actual = {
        devenv-darwin = devenvDarwin.kdn.ssh-access.defaults.user;
        home-linux = homeLinux.config.kdn.ssh-access.defaults.user;
        host-darwin = darwinCfg.home-manager.users.dev.kdn.ssh-access.defaults.user;
      };
    }
    {
      name = "the graph reaches every consumer that names one";
      expected = {
        devenv-darwin = [
          "alpha"
          "beta"
        ];
        home-darwin = [
          "alpha"
          "beta"
        ];
        home-linux = [
          "alpha"
          "beta"
        ];
        host-darwin = [
          "alpha"
          "beta"
        ];
      };
      actual = lib.mapAttrs (_: cfg: sorted (builtins.attrNames cfg.kdn.ssh-access.hosts)) {
        devenv-darwin = devenvDarwin;
        home-darwin = homeDarwin.config;
        home-linux = homeLinux.config;
        host-darwin = darwinCfg.home-manager.users.dev;
      };
    }
    {
      name = "the empty-graph consumer holds no host and no uplink";
      expected = {
        hosts = [ ];
        uplinks = [ ];
      };
      actual = {
        hosts = builtins.attrNames devenvLinux.kdn.ssh-access.hosts;
        uplinks = builtins.attrNames devenvLinux.kdn.ssh-access.uplinks;
      };
    }

    # ---- the `homeManager` half: the ssh drop-in, plus the binary on the user's PATH
    {
      name = "each home route installs the drop-in at the ordered path";
      expected = {
        home-darwin = true;
        home-linux = true;
        host-darwin = true;
        host-nixos = true;
      };
      actual = lib.mapAttrs (_: cfg: cfg.home.file ? ${dropInPath}) {
        home-darwin = homeDarwin.config;
        home-linux = homeLinux.config;
        host-darwin = darwinCfg.home-manager.users.dev;
        host-nixos = nixosCfg.home-manager.users.dev;
      };
    }
    # The binary is the single source of the drop-in: `kdn-ssh-access emit-ssh-config` prints it, and
    # `passthru.sshConfig` captures the output. So the file and the route logic cannot disagree.
    {
      name = "the drop-in comes from the binary's own emit-ssh-config";
      expected = true;
      actual =
        "${homeLinux.config.home.file.${dropInPath}.source}"
        == "${homeLinux.config.kdn.ssh-access.package.sshConfig}";
    }
    # A graph must change the emitted file. An equal path would mean the graph reaches nothing.
    {
      name = "a graph changes the emitted drop-in";
      expected = true;
      actual =
        "${homeLinux.config.kdn.ssh-access.package.sshConfig}"
        != "${devenvLinux.kdn.ssh-access.package.sshConfig}";
    }
    {
      name = "each home route installs the binary";
      expected = {
        home-darwin = true;
        home-linux = true;
        host-darwin = true;
        host-nixos = true;
      };
      actual = lib.mapAttrs (_: cfg: hasPackageNamed "kdn-ssh-access-configured" cfg.home.packages) {
        home-darwin = homeDarwin.config;
        home-linux = homeLinux.config;
        host-darwin = darwinCfg.home-manager.users.dev;
        host-nixos = nixosCfg.home-manager.users.dev;
      };
    }

    # ---- the `devenv` half: the binary and the short shim, and no file at all
    {
      name = "every devenv shell holds the binary and the short shim";
      expected = {
        devenv-darwin = true;
        devenv-linux = true;
        host-darwin = true;
      };
      actual =
        lib.mapAttrs
          (
            _: shell:
            hasPackageNamed "kdn-ssh-access-configured" shell.packages
            && hasPackageNamed "ssh-access" shell.packages
          )
          {
            devenv-darwin = devenvDarwin;
            devenv-linux = devenvLinux;
            host-darwin = hostShellDarwin;
          };
    }

    # ---- rule 2: inclusion is the switch. The slot's `kdn.ssh-access.enable` is gone.
    {
      name = "the aspect declares no `enable` option";
      expected = false;
      actual = homeLinux.config.kdn.ssh-access ? enable;
    }

    # ---- the library route, one call per class. Neither call needs `specialArgs`.
    {
      name = "denLib.imports resolves one module per class";
      expected = {
        homeManager = 1;
        devenv = 1;
      };
      actual =
        lib.mapAttrs
          (
            class: _:
            builtins.length (
              denLib.imports {
                inherit class;
                aspects = [ "ssh-access" ];
              }
            )
          )
          {
            homeManager = null;
            devenv = null;
          };
    }
  ];

  # ------------------------------------------------------------------ the check set

  # Tier 1 runs anywhere: the comparison is an evaluation and the derivation is local.
  portable = {
    den-eval-rosetta-builder = mkEvalCheck "rosetta-builder" rosettaBuilderAssertions;
    den-eval-gh = mkEvalCheck "gh" ghAssertions;
    den-eval-guards = mkEvalCheck "guards" guardAssertions;
    den-eval-routes = mkEvalCheck "routes" routeAssertions;
    den-eval-devenv-cli = mkEvalCheck "devenv-cli" devenvCliAssertions;
    den-eval-ssh-agent = mkEvalCheck "ssh-agent" sshAgentAssertions;
    den-eval-ca = mkEvalCheck "ca" caAssertions;
    den-eval-homebrew = mkEvalCheck "homebrew" homebrewAssertions;
    den-eval-zellij = mkEvalCheck "zellij" zellijAssertions;
    den-eval-opencode = mkEvalCheck "opencode" opencodeAssertions;
    den-eval-mcp = mkEvalCheck "mcp" mcpAssertions;
    den-eval-nix = mkEvalCheck "nix" nixAssertions;
    den-eval-jj = mkEvalCheck "jj" jjAssertions;
    den-eval-llm = mkEvalCheck "llm" llmAssertions;
    den-eval-signing = mkEvalCheck "signing" signingAssertions;
    den-eval-ssh-access = mkEvalCheck "ssh-access" sshAccessAssertions;
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
      den-artifact-hm-host-darwin = mkArtifactCheck "hm-host-darwin" hmHostDarwin (
        hmHookGreps + hmLaunchdGreps
      );
      den-artifact-home-darwin = mkArtifactCheck "home-darwin" homeDarwin.activationPackage (
        hmHookGreps + hmLaunchdGreps
      );

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

        echo "  each enabled CA mounts its public certificate" >&2
        test -f "$target/etc/kdn/ca/den-mvp-test.pub"
        test -f "$target/etc/kdn/ca/den-mvp-keyed.pub"

        echo "  the encrypted key blob mounts for the keyed CA only" >&2
        test -f "$target/etc/kdn/ca/den-mvp-keyed.key.sops"
        test ! -e "$target/etc/kdn/ca/den-mvp-test.key.sops"

        echo "  a disabled CA mounts nothing" >&2
        test ! -e "$target/etc/kdn/ca/den-mvp-off.pub"

        echo "  the system CA bundle is not empty" >&2
        test -s "$target/etc/ssl/certs/ca-certificates.crt"
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
