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
  # The shared harness: the tier 1 check builder plus one bare consumer per den class. ./harness.nix
  # holds every one of them, so an area file under ./assertions/ reads the same names.
  harness = import ./harness.nix { inherit pkgs lib inputs; };

  inherit (harness)
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

  # The per-area assertion files. ./assertions/default.nix scans that directory, so a new area needs
  # one new file and no edit here. That file also states the `git add` trap.
  areas = import ./assertions {
    inherit
      pkgs
      lib
      inputs
      harness
      ;
  };

  thisSystem = pkgs.stdenv.hostPlatform.system;

  # ------------------------------------------------------------------ tier helpers

  # Tier 1 lives in ./harness.nix, next to the bare consumers every assertion needs.

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

        # `hosts-den/orr/` is a real den host, so `den.policies.host-to-devenv` derives a shell for
        # it too. That host includes no aspect with a `devenv` target, so its shell holds no
        # `devenv` package. Measured on 2026-09-11.
        orr = 0;
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
        "apps"
        "ca"
        "desktop-base"
        "desktop-kde"
        "desktop-remote-server"
        "desktop-sway"
        "desktop-sway-kanshi"
        "desktop-sway-media-keys"
        "desktop-sway-nwg-panel"
        "desktop-sway-nwg-shell"
        "desktop-sway-remote"
        "desktop-sway-swaylock"
        "desktop-sway-swaync"
        "desktop-sway-swayr"
        "desktop-sway-waybar"
        "dev-android"
        "dev-ansible"
        "dev-cloud"
        "dev-cloud-aws"
        "dev-cloud-azure"
        "dev-data"
        "dev-db"
        "dev-documents"
        "dev-dotnet"
        "dev-elixir"
        "dev-git"
        "dev-golang"
        "dev-java"
        "dev-jetbrains"
        "dev-k8s"
        "dev-kernel"
        "dev-llm-claude-code"
        "dev-llm-omp"
        "dev-llm-opencode"
        "dev-llm-pi"
        "dev-lua"
        "dev-nickel"
        "dev-nix"
        "dev-nodejs"
        "dev-python"
        "dev-rpi"
        "dev-rust"
        "dev-shell"
        "dev-terraform"
        "dev-web"
        "devenv-cli"
        "disks"
        "disks-persist"
        "emulation-wine"
        "fs-luks-zfs"
        "fs-watch"
        "fs-zfs"
        "gh"
        "hm-bootstrap"
        "homebrew"
        "homebrew-nix-managed"
        "hw-audio"
        "hw-basic"
        "hw-bluetooth"
        "hw-cpu-amd"
        "hw-cpu-intel"
        "hw-darwin-utm-guest"
        "hw-dell-e5470"
        "hw-edid"
        "hw-gpu"
        "hw-gpu-amd"
        "hw-gpu-intel"
        "hw-intel-graphics-fix"
        "hw-modem"
        "hw-nanokvm"
        "hw-qmk"
        "hw-usbip"
        "hw-yubikey"
        "jj"
        "jj-fork"
        "llm"
        "llm-client"
        "llm-proxy"
        "locale"
        "managed"
        "mcp"
        "mcp-basic-memory"
        "mcp-pretty-print"
        "mcp-snoop"
        "monitoring-prometheus-stack"
        "net-dynamic-hosts"
        "net-interfaces"
        "net-netbird"
        "net-openfortivpn"
        "net-openvpn"
        "net-resolved"
        "net-router"
        "net-router-ddns"
        "net-router-dhcp"
        "net-router-dns"
        "net-router-dns-rewrites"
        "net-tailscale"
        "nix"
        "nix-config"
        "nix-remote-builder"
        "opencode"
        "outputs-host"
        "packaging-asdf"
        "profile-baseline"
        "profile-baseline-flake-links"
        "profile-baseline-gc"
        "profile-basic"
        "profile-desktop"
        "profile-dev"
        "profile-gaming"
        "profile-headless"
        "profile-headless-vim"
        "profile-headless-wezterm"
        "profile-headless-zellij"
        "profile-hetzner"
        "profile-workstation"
        "program-atuin"
        "program-beeper"
        "program-blender"
        "program-browsers-launcher"
        "program-chrome"
        "program-chromium"
        "program-dconf"
        "program-direnv"
        "program-editors-photo"
        "program-editors-video"
        "program-ente-photos"
        "program-firefox"
        "program-fish"
        "program-gnupg"
        "program-handlr"
        "program-kdeconnect"
        "program-keepass"
        "program-keepassxc"
        "program-logseq"
        "program-matrix"
        "program-midnight-commander"
        "program-nextcloud-client"
        "program-nix-index"
        "program-obs-studio"
        "program-office"
        "program-orca-slicer"
        "program-photoprism"
        "program-rambox"
        "program-signal"
        "program-slack"
        "program-spotify"
        "program-ssh-client"
        "program-terminal-ide"
        "program-thunderbird"
        "program-tidal"
        "program-torrent"
        "program-weechat"
        "program-wofi"
        "program-ydotool"
        "program-zsh"
        "rosetta-builder"
        "secrets"
        "security-disk-encryption"
        "security-secrets-age"
        "security-secrets-sops"
        "security-secure-boot"
        "service-caddy"
        "service-coredns"
        "service-home-assistant"
        "service-iperf3"
        "service-k8s"
        "service-k8s-controlplane-lb"
        "service-k8s-kubeadm"
        "service-k8s-management"
        "service-k8s-node"
        "service-nextcloud-client"
        "service-postgresql"
        "service-printing"
        "service-samba"
        "service-syncthing"
        "service-zammad"
        "signing"
        "ssh-access"
        "ssh-agent"
        "stylix"
        "stylix-home"
        "toolset-diagrams"
        "toolset-essentials"
        "toolset-fs"
        "toolset-fs-encryption"
        "toolset-logs-processing"
        "toolset-mikrotik"
        "toolset-network"
        "toolset-network-gui"
        "toolset-nix"
        "toolset-tracing"
        "toolset-unix"
        "user"
        "virt-containers"
        "virt-containers-dagger"
        "virt-containers-distrobox"
        "virt-containers-docker"
        "virt-containers-podman"
        "virt-containers-x11docker"
        "virt-libvirtd"
        "virt-microvm-guest"
        "virt-microvm-host"
        "virt-vagrant"
        "zellij"
      ];
      actual = sorted (builtins.attrNames denLib.aspectModules);
    }
  ];

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
    /*
      The two `package` pins guard a nixpkgs break: `mcp-servers-nix` reads the unversioned
      `typescript` attribute, which now resolves to TypeScript 7, and those two builds fail.
      `lib.getExe` also proves `meta.mainProgram` stays set.
    */
    {
      name = "mcp: the filesystem server takes nixpkgs' own package";
      expected = true;
      actual = lib.hasSuffix "/bin/mcp-server-filesystem" (
        lib.getExe devenvDarwin.kdn.mcp.programs.filesystem.package
      );
    }
    {
      name = "mcp: the sequential-thinking server takes nixpkgs' own package";
      expected = true;
      actual = lib.hasSuffix "/bin/mcp-server-sequential-thinking" (
        lib.getExe devenvDarwin.kdn.mcp.programs.sequential-thinking.package
      );
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

    # ---- the target modules. Every assertion above counts modules in a list, and
    # `den.lib.aspects.resolve` never reads a target module body. So until this block landed, the
    # `nixos` target of `llm` (49 options) and of `llm-proxy`, and the `devenv` target of
    # `llm-client`, evaluated in no check at all. These three subjects force all three.
    {
      name = "the nixos target of each aspect evaluates with no consumer data";
      expected = {
        llm = true;
        llm-proxy = true;
      };
      actual = {
        llm = succeeds llmNixos.config.kdn.llm.local.modelsDir;
        llm-proxy = succeeds llmProxyNixos.config.kdn.llm.proxy.instances;
      };
    }
    {
      name = "the devenv target of llm-client evaluates with no consumer data";
      expected = true;
      actual = succeeds llmClientShell.config.kdn.llm.client.upstreams;
    }
    # An aspect is additive and carries no `enable`, so inclusion alone must configure nothing.
    {
      name = "no instance and no upstream exists until the consumer names one";
      expected = {
        routers = { };
        models = { };
        instances = { };
        upstreams = { };
      };
      actual = {
        routers = llmNixos.config.kdn.llm.local.routers;
        models = llmNixos.config.kdn.llm.local.models;
        instances = llmProxyNixos.config.kdn.llm.proxy.instances;
        upstreams = llmClientShell.config.kdn.llm.client.upstreams;
      };
    }

    # ---- the de-personalized defaults. The slot froze one machine's own model directory and one
    # hardcoded thread count. See ../../modules/den/aspects/llm.nix:50-53.
    {
      name = "the models directory is a neutral system path";
      expected = "/var/lib/kdn/llm/models";
      actual = llmNixos.options.kdn.llm.local.modelsDir.default;
    }
    {
      name = "the thread count comes from the consumer, so the flag stays out";
      expected = null;
      actual = llmNixos.options.kdn.llm.local.defaultThreads.default;
    }
    {
      name = "each listen address is a loopback default";
      expected = {
        llm = "127.0.0.1";
        llm-proxy = "127.0.0.1";
      };
      actual = {
        llm = llmNixos.options.kdn.llm.local.server.host.default;
        llm-proxy = (llmProxyNixos.options.kdn.llm.proxy.instances.type.getSubOptions [ ]).host.default;
      };
    }
    {
      name = "a proxy instance opens no firewall port and forwards no client credential";
      expected = {
        openFirewall = false;
        forwardClientAuth = false;
      };
      actual =
        let
          sub = llmProxyNixos.options.kdn.llm.proxy.instances.type.getSubOptions [ ];
        in
        {
          openFirewall = sub.openFirewall.default;
          forwardClientAuth = sub.forwardClientAuth.default;
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

  # ------------------------------------------------------------------ the bare subjects

  # One bare consumer per class, shared by the four sets below and by `llmAssertions`. Each one
  # supplies **no** data, so `.options.<path>.default` is the value an adopter really gets.
  llmNixos = bareNixos [ flake.denModules.llm ];
  llmProxyNixos = bareNixos (
    denLib.imports {
      class = "nixos";
      aspects = [ "llm-proxy" ];
    }
  );
  llmClientShell = bareShell { aspects = [ "llm-client" ]; };

  # Every `devenv` aspect that declares an option, in one subject and with no consumer data.
  defaultsShell = bareShell {
    aspects = [
      "jj-fork"
      "nix"
      "zellij"
      "opencode"
      "mcp-basic-memory"
    ];
  };

  # ------------------------------------------------------------------ option defaults

  # An option default is a promise to an adopter, and a header comment is not a test. Two facts make
  # this set worth its lines:
  #
  #  1. A stale default claim survives review. ../../modules/den/aspects/mcp.nix:30-32 still says the
  #     `mcp/snoop` and `mcp/pretty-print` slots "both default `enable = true`", while both slot
  #     sources use `lib.mkEnableOption`, which is false.
  #  2. `den.devenv.mkShell` returns `.config` alone, so before `bareShell` existed no subject could
  #     read a `devenv`-class default at all.
  aspectDefaultsAssertions = [
    # ---- the opt-in boundary. Five declarations, one meaning: an aspect writes a file into the
    # consumer's own tree only when the consumer asks. A `true` default here would push this
    # repository's own work mandate into an adopter's working tree.
    {
      name = "every agent-rule install stays opt-in";
      expected = {
        zellij = false;
        nix = false;
        jj = false;
        jj-fork = false;
        basic-memory = false;
      };
      actual = {
        zellij = defaultsShell.options.kdn.zellij.installAgentRules.default;
        nix = defaultsShell.options.kdn.nix.installAgentRules.default;
        jj = defaultsShell.options.kdn.jj.installAgentRules.default;
        jj-fork = defaultsShell.options.kdn.jj.fork.installAgentRules.default;
        basic-memory = defaultsShell.options.kdn.mcp.basic-memory.installAgentRules.default;
      };
    }
    # The shared switch from ../../modules/den/common/source-repo.nix. An adopter must get the files,
    # so the default is false and this repository sets the value true itself.
    {
      name = "a consumer is not the source repository by default";
      expected = false;
      actual = defaultsShell.options.kdn.isSourceRepo.default;
    }

    # ---- de-personalization. Each slot default below named one person's own remote, one person's
    # own pattern or one person's own folder. See gap 6 of
    # ../../docs/tasks/2026-09/generalization/definition.md.
    {
      name = "each remote name is generic, and the fork names none at all";
      expected = {
        upstream = "origin";
        fork = "";
      };
      actual = {
        upstream = defaultsShell.options.kdn.jj.upstream.remote.default;
        fork = defaultsShell.options.kdn.jj.fork.remote.default;
      };
    }
    # A denied pattern is private configuration, and `runtimeEnv` puts it into a world-readable store
    # path. So every pattern list starts empty and the consumer names its own.
    {
      name = "every denied pattern list starts empty";
      expected = {
        message = [ ];
        forkFile = [ ];
        forkMessage = [ ];
      };
      actual = {
        message = defaultsShell.options.kdn.jj.alwaysBlockedMessagePatterns.default;
        forkFile = defaultsShell.options.kdn.jj.fork.deniedFilePatterns.default;
        forkMessage = defaultsShell.options.kdn.jj.fork.deniedMessagePatterns.default;
      };
    }
    # Each value below expands at run time inside a generated script. A store path here freezes one
    # checkout, and an absolute home path names one person.
    {
      name = "each data path is a run-time home lookup, not a store path and not a person";
      expected = {
        knowledgeRoot = "$HOME/.local/share/basic-memory";
        authFile = "$HOME/.local/share/opencode/auth.json";
      };
      actual = {
        knowledgeRoot = defaultsShell.options.kdn.mcp.basic-memory.knowledgeRoot.default;
        authFile = defaultsShell.options.kdn.opencode.authFile.default;
      };
    }
    {
      name = "the knowledge base set starts empty";
      expected = { };
      actual = defaultsShell.config.kdn.mcp.basic-memory.bases;
    }
    # The read allowlist starts at the store alone. A checkout path here names one machine.
    {
      name = "the opencode read allowlist starts at the store alone";
      expected = [ "/nix/store/**" ];
      actual = defaultsShell.options.kdn.opencode.allowedPaths.default;
    }
    {
      name = "the gateway listens on loopback";
      expected = {
        host = "127.0.0.1";
        port = 39400;
      };
      actual = {
        host = defaultsShell.options.kdn.mcp.host.default;
        port = defaultsShell.options.kdn.mcp.port.default;
      };
    }
    # The `mcp-servers-nix` source belongs to the consumer, so the aspect names none.
    {
      name = "the aspect names no mcp-servers-nix source";
      expected = null;
      actual = defaultsShell.options.kdn.mcp.serversNix.default;
    }
  ];

  # ------------------------------------------------------------------ definition priority

  # A priority conflict stops the whole evaluation, and it appears only when a consumer defines the
  # same option the aspect defines. No existing assertion does that, so this set does.
  #
  # Six aspects write `claude.code.enable = lib.mkDefault true` (gh, jj, mcp, mcp-pretty-print, nix,
  # zellij). Equal definitions at priority 1000 merge, and a consumer's plain value at priority 100
  # wins. A change to `lib.mkForce` or to a plain assignment breaks that, and assertion 1 catches it.
  priorityAssertions = [
    {
      name = "a consumer's plain value overrides six mkDefault definitions";
      expected = false;
      actual =
        (bareShell {
          aspects = [
            "gh"
            "nix"
            "zellij"
          ];
          modules = [ { claude.code.enable = false; } ];
        }).config.claude.code.enable;
    }

    # ---- the measured hazard, now closed for the four scalar values.
    # ../../modules/den/aspects/homebrew.nix:128-147 assigns `homebrew.enable` and the three
    # `onActivation` values with `lib.mkDefault`, so a consumer's own plain value overrides them.
    # Measured on 2026-09-11: at plain priority 100 the same override threw a conflict, and only
    # `lib.mkForce` won.
    #
    # The three lists stay at plain priority, and that is deliberate. A `listOf` merges two plain
    # definitions by concatenation, so a consumer's own list adds to the aspect's list and throws
    # nothing. A `mkDefault` there would make the consumer's list replace the option value instead.
    {
      name = "the aspect's own cleanup default reaches a bare consumer";
      expected = "none";
      actual = (bareDarwinSystem [ flake.denModules.homebrew ]).config.homebrew.onActivation.cleanup;
    }
    {
      name = "a consumer's plain cleanup value overrides the aspect's mkDefault";
      expected = "zap";
      actual =
        (bareDarwinSystem [
          flake.denModules.homebrew
          { homebrew.onActivation.cleanup = "zap"; }
        ]).config.homebrew.onActivation.cleanup;
    }
    {
      name = "a consumer's plain cask list adds to the aspect's, and throws no conflict";
      expected = [
        "consumer-cask"
        "example-cask"
      ];
      # nix-darwin coerces every `homebrew.casks` entry to a submodule, so the merged value holds
      # attribute sets and `builtins.sort` cannot compare them. Read the `name` of each entry.
      # Measured on 2026-09-11: a sort of the raw list throws `cannot compare a set with a set`.
      actual = sorted (
        map (cask: cask.name or cask) (
          (bareDarwinSystem [
            flake.denModules.homebrew
            {
              kdn.homebrew.casks = [ "example-cask" ];
              homebrew.casks = [ "consumer-cask" ];
            }
          ]).config.homebrew.casks
        )
      );
    }
  ];

  # ------------------------------------------------------------------ frozen store paths

  # The measured defect: the `nix` slot set `env.DEVENV_ROOT = toString inputs.nix-configs` on the
  # `devenv` MCP backend, so an adopter's tool pointed at a store copy of **this** repository. See
  # ../../modules/den/aspects/nix.nix:19-29.
  #
  # One assertion in `nixAssertions` guards that one backend. This set generalizes it: no backend of
  # either shell may carry an `env` block, and the gateway must find its own configuration through a
  # run-time `DEVENV_ROOT` lookup instead of a build-time path.
  backendsWithEnv =
    shell: sorted (builtins.attrNames (lib.filterAttrs (_: b: b ? env) shell.kdn.mcp.backends));

  frozenPathAssertions = [
    {
      name = "no backend of either shell freezes an environment value";
      expected = {
        devenv-darwin = [ ];
        devenv-linux = [ ];
      };
      actual = {
        devenv-darwin = backendsWithEnv devenvDarwin;
        devenv-linux = backendsWithEnv devenvLinux;
      };
    }
    # `enterShell` repoints a stable in-project symlink on every entry, and the gateway wrapper reads
    # that path through `DEVENV_ROOT`. So `.mcp.json` holds no per-build path, and the consumer's own
    # root always wins.
    {
      name = "the gateway configuration link is a run-time DEVENV_ROOT lookup";
      expected = {
        devenv-darwin = true;
        devenv-linux = true;
      };
      actual = {
        devenv-darwin = lib.hasInfix "$DEVENV_ROOT/.devenv/mcp-gateway.yaml" devenvDarwin.enterShell;
        devenv-linux = lib.hasInfix "$DEVENV_ROOT/.devenv/mcp-gateway.yaml" devenvLinux.enterShell;
      };
    }
    # A bare consumer reaches the same shape with no data of its own. So the run-time lookup is a
    # property of the aspect, and not of this tree's own test subjects.
    {
      name = "a bare consumer gets the same run-time lookup";
      expected = true;
      actual =
        lib.hasInfix "$DEVENV_ROOT/.devenv/mcp-gateway.yaml"
          (bareShell {
            aspects = [ "mcp" ];
          }).config.enterShell;
    }
  ];

  # ------------------------------------------------------------------ the instantiation force

  # `den.lib.aspects.resolve` returns an `imports` list and forces no target module body. So an
  # aspect that names a class proves nothing until some subject forces a value out of that class.
  # The `instantiatedBy` table below names one subject per aspect **by hand**, and nothing checks
  # that the named subject really forces the body.
  #
  # This set closes that hole with no list of its own. It reads the registry, asks den which
  # classes each aspect emits, and forces one bare class harness per pair. A `drvPath` is the
  # force: it runs the whole target module body, and it needs no builder — so every pair runs on
  # every machine, unlike a tier 2 artifact check.
  #
  # Measured on 2026-09-11 in a scratch copy of `modules/den/`, with one planted `throw` per class:
  #
  #   | planted in                    | the `../standalone.nix` option walk | this check              |
  #   |-------------------------------|-------------------------------------|-------------------------|
  #   | `llm` nixos body              | 25 of 25 pass                       | llm/nixos FAIL          |
  #   | `homebrew` darwin body        | 25 of 25 pass                       | homebrew/darwin FAIL    |
  #   | `zellij` devenv body          | 25 of 25 pass                       | zellij/devenv FAIL      |
  #   | `ssh-agent` homeManager body  | 25 of 25 pass                       | ssh-agent/homeManager FAIL |
  #
  # Cost, measured the same day: about +48 s on the 78 s this file already needs.
  #
  # A new **aspect** enters coverage on its own — the registry gives the name and den gives the
  # classes. A new **class** does not: `forceOf` holds no harness for it, and the pair then throws
  # with that instruction.

  # den adds these keys to every aspect attribute set. The remaining keys name the classes the
  # aspect emits. `../standalone.nix` holds the same list; keep the two in step.
  aspectStructuralKeys = [
    "_"
    "__functor"
    "__providesForwarded"
    "classes"
    "description"
    "excludes"
    "includes"
    "meta"
    "name"
    "policies"
    "provides"
  ];

  aspectClassesOf =
    name:
    lib.subtractLists aspectStructuralKeys (builtins.attrNames den.ful.${denLib.namespaceName}.${name});

  # Every (aspect, class) pair the registry yields. 26 pairs: the 25 measured on 2026-09-11,
  # plus `homebrew-nix-managed/darwin`.
  forcePairs = lib.concatLists (
    lib.mapAttrsToList (name: _: map (class: "${name}/${class}") (aspectClassesOf name)) (
      denLib.aspectModules
    )
  );

  # The one pair that nixpkgs itself refuses with an empty consumer. `fs-zfs` turns ZFS on, and
  # nixpkgs then asserts `networking.hostId`. A ZFS host carries a unique id, and no aspect may
  # invent one, so the consumer owns that line. Every real host of ./../../hosts/ writes it.
  #
  # Keep this table small. A new entry means an aspect asks the consumer for data, and that needs a
  # decision, not a table row.
  #
  # The second entry carries such a decision. `net-router-ddns` publishes the router's own public
  # address to DNS, so it must read the two files that hold that address. Neither file has a
  # default, because a wrong default publishes a wrong address. The DDNS updater reads each path at
  # run time, so `/dev/null` satisfies the evaluation here.
  # The third entry carries a decision as well. sops-nix needs a declarative user creation route, so
  # `security-secrets-sops` asserts `services.userborn.enable || services.sysusers.enable`. Neither
  # option is on in a bare consumer, so the pair cannot force without this row. The choice of route
  # belongs to the consumer, not to the aspect. ./assertions/security.nix states the same fact.
  #
  # The machine-profile bundles add three more such decisions, and each one reaches several pairs,
  # because `denLib.imports` follows `includes`. The three bindings below name each decision once.
  #
  # `profile-baseline` writes `users.mutableUsers = false`, so nixpkgs asserts that the root account
  # or a wheel user holds a password or an SSH key. A bare consumer declares no user at all. An
  # aspect must never invent a credential, so the consumer owns that line. `/dev/null` is an empty
  # file, and the evaluation only needs the path.
  rootCredential = {
    kdn.profile-baseline.rootHashedPasswordFile = "/dev/null";
  };
  # `profile-basic` turns Flatpak on, and nixpkgs asserts `xdg.portal.enable`. That option then
  # asserts a non-empty `xdg.portal.extraPortals`, so the row must name a backend as well. The portal
  # belongs to `desktop-base`, and `profile-basic` does not include it.
  # `modules/universal/profile/machine/basic` writes the same pair, so this is old-tree parity, not a
  # port defect. A consumer that wants Flatpak on a headless machine names the portal itself.
  flatpakPortal =
    { pkgs, ... }:
    {
      xdg.portal.enable = true;
      xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };
  # `profile-gaming` names Steam, and `profile-workstation` names the JetBrains IDEs. nixpkgs marks
  # each one unfree. An aspect must never widen a consumer's licence policy, so the consumer owns
  # this line too. ./assertions/machine-profiles.nix states the same fact for the gaming aspect.
  unfree = {
    nixpkgs.config.allowUnfree = true;
  };
  forceData = {
    "fs-zfs/nixos" = [ { networking.hostId = "deadbeef"; } ];
    "net-router-ddns/nixos" = [
      {
        kdn.networking.router.addr.public.ipv4.path = "/dev/null";
        kdn.networking.router.addr.public.ipv6.path = "/dev/null";
      }
    ];
    "security-secrets-sops/nixos" = [ { services.userborn.enable = true; } ];
    "profile-baseline/nixos" = [ rootCredential ];
    "profile-basic/nixos" = [
      rootCredential
      flatpakPortal
    ];
    "profile-desktop/nixos" = [ rootCredential ];
    "profile-gaming/nixos" = [ unfree ];
    "profile-hetzner/nixos" = [ rootCredential ];
    "profile-workstation/nixos" = [
      rootCredential
      unfree
    ];
  };

  # No consumer data at all, except the `forceData` entries above. Measured on 2026-09-11: all
  # pairs of that day force with an empty consumer. An aspect that starts to need data fails here,
  # and that is the correct direction — an external adopter meets the same failure.
  forcedPairs = lib.concatLists (
    lib.mapAttrsToList (
      name: _:
      map (
        class:
        let
          force =
            forceOf.${class} or (throw ''
              den: aspect `${name}` emits the class `${class}`, and ./harness.nix holds no bare
              harness for it. Add one to `forceOf`, next to `nixos`, `darwin`, `homeManager` and
              `devenv`.
            '');
          drv = force (
            denLib.imports {
              inherit class;
              aspects = [ name ];
            }
            ++ (forceData."${name}/${class}" or [ ])
          );
        in
        if lib.isString drv then "${name}/${class}" else "${name}/${class}: broken"
      ) (aspectClassesOf name)
    ) denLib.aspectModules
  );

  instantiateAssertions = [
    {
      name = "every aspect and class forces its target module body in a bare consumer";
      expected = forcePairs;
      actual = forcedPairs;
    }
  ];

  # ------------------------------------------------------------------ batch 1: the root options
  #
  # The two aspects of the machine-layer batch 1, in the bare adopter shape. A host probe cannot
  # reach the priority ladder, so these assertions use `bareDarwinSystem`: a plain nix-darwin
  # evaluation, no den entity, no `mkSlots` and no `kdnConfig`.
  #
  # Two of them are the traps the design named. Trap 1: a plain list **replaces** the whole option
  # default, so an adopter can remove an entry. Trap 2: a plain `null` removes the `build-dir` key,
  # which `lib.mkOptionDefault` could not do — an option's own `default` is a priority-1500
  # definition, so it ties.
  nixConfigAssertions =
    let
      both = denLib.imports {
        class = "darwin";
        aspects = [
          "nix-config"
          "nix-remote-builder"
        ];
      };

      # A consumer that writes nothing. It must keep this tree's own value.
      plain = (bareDarwinSystem both).config;

      # A consumer that neutralises the build directory and replaces the insecure list.
      overridden =
        (bareDarwinSystem (
          both
          ++ [
            {
              kdn.nix.buildDir = null;
              kdn.nixpkgs.permittedInsecurePackages = [ "x" ];
            }
          ]
        )).config;

      # A consumer that renames the builder account and moves its uid. Every one of these five
      # leaves was `readOnly` in `modules/universal/nix/remote-builder/default.nix`, so none of
      # these assignments was possible before the port.
      renamed =
        (bareDarwinSystem (
          both
          ++ [
            {
              kdn.nix.remote-builder.name = "adopter-builder";
              kdn.nix.remote-builder.user.id = 31000;
              kdn.nix.remote-builder.user.ssh.IdentityFile = "/var/lib/secrets/builder.key";
            }
          ]
        )).config;
    in
    [
      # ---- `kdn.hostName`, from ../../modules/den/common/host-name.nix
      {
        name = "a bare darwin consumer that sets no networking.hostName gets an empty kdn.hostName";
        expected = "";
        actual = plain.kdn.hostName;
      }

      # ---- the nine `nix-config` options, at their own defaults
      {
        name = "the default writes the three substituters, each with its own key";
        expected = {
          urls = [
            "https://nix-community.cachix.org"
            "https://nixpkgs-update.cachix.org"
            "https://devenv.cachix.org"
          ];
          keyCount = 3;
        };
        actual = {
          urls = map (entry: entry.url) plain.kdn.nix.substituters;
          keyCount = builtins.length (map (entry: entry.publicKey) plain.kdn.nix.substituters);
        };
      }
      {
        name = "the default writes both admin groups and both allowed groups";
        expected = [
          "@wheel"
          "@admin"
          "@users"
          "@staff"
        ];
        actual = plain.nix.settings.allowed-users;
      }
      {
        name = "the default trusts the two admin groups";
        expected = true;
        actual = lib.all (group: builtins.elem group plain.nix.settings.trusted-users) [
          "@wheel"
          "@admin"
        ];
      }
      {
        name = "the default writes the build directory";
        expected = "/nix/var/nix/builds";
        actual = plain.nix.settings.build-dir;
      }
      {
        name = "the default writes both !include lines and nothing else";
        expected = "!include /etc/nix/nix.sensitive.conf\n!include /etc/nix/nix.access-tokens.auto.conf\n";
        actual = plain.nix.extraOptions;
      }
      {
        name = "the default accepts the four insecure packages this tree needs";
        expected = 4;
        actual = builtins.length plain.nixpkgs.config.permittedInsecurePackages;
      }
      {
        name = "the default accepts an unfree licence and keeps the nixpkgs aliases";
        expected = {
          allowUnfree = true;
          allowAliases = true;
        };
        actual = {
          inherit (plain.nixpkgs.config) allowUnfree allowAliases;
        };
      }

      # ---- trap 1 and trap 2, the priority ladder
      {
        name = "trap 1: a plain list replaces the whole insecure-package default";
        expected = [ "x" ];
        actual = overridden.nixpkgs.config.permittedInsecurePackages;
      }
      {
        name = "trap 2: a plain null removes the build-dir key";
        expected = false;
        actual = overridden.nix.settings ? build-dir;
      }

      # ---- the 18 `nix-remote-builder` leaves
      {
        name = "the builder defaults keep this tree's own account, group and uid";
        expected = {
          name = "kdn-nix-remote-build";
          userName = "kdn-nix-remote-build";
          groupName = "kdn-nix-remote-build";
          userId = 25839;
          groupId = 25839;
          use = false;
          localhostUse = false;
        };
        actual = {
          inherit (plain.kdn.nix.remote-builder) name use;
          userName = plain.kdn.nix.remote-builder.user.name;
          groupName = plain.kdn.nix.remote-builder.group.name;
          userId = plain.kdn.nix.remote-builder.user.id;
          groupId = plain.kdn.nix.remote-builder.group.id;
          localhostUse = plain.kdn.nix.remote-builder.localhost.use;
        };
      }
      {
        name = "the five dropped readOnly flags let an adopter rename the builder account";
        expected = {
          name = "adopter-builder";
          userName = "adopter-builder";
          groupName = "adopter-builder";
          localhostSshUser = "adopter-builder";
          groupId = 31000;
          use = true;
        };
        actual = {
          inherit (renamed.kdn.nix.remote-builder) name use;
          userName = renamed.kdn.nix.remote-builder.user.name;
          groupName = renamed.kdn.nix.remote-builder.group.name;
          localhostSshUser = renamed.kdn.nix.remote-builder.localhost.sshUser;
          groupId = renamed.kdn.nix.remote-builder.group.id;
        };
      }
      {
        name = "the aspect emits no config of its own, so `localhost.use` stays off with no host key";
        expected = false;
        actual = renamed.kdn.nix.remote-builder.localhost.use;
      }
    ];

  # ------------------------------------------------------------------ batch 2: apps, locale, secrets
  #
  # The three aspects of the machine-layer batch 2, in the bare adopter shape. `apps` claims the
  # `homeManager` class alone, so the home subject carries it. `locale` and `secrets` claim three
  # classes each, so the nixos subject and the darwin subject carry both.
  #
  # Two of these assertions are the traps the design named. Trap 1: a plain list **replaces** the
  # whole `kdn.locale.extra` default, so an adopter can remove an entry. Trap 2: the Home Manager
  # `force` writes sit under one `lib.mkIf`, never one per leaf. A per-leaf `mkIf` still creates the
  # `xdg.configFile."user-dirs.dirs"` entry, and Home Manager then asserts that the entry names no
  # source. The `userDirsFiles` row is that guard.
  batch2Assertions =
    let
      hostAspects = [
        "locale"
        "secrets"
      ];

      nixosModules = denLib.imports {
        class = "nixos";
        aspects = hostAspects;
      };

      nixosPlain = (bareNixos nixosModules).config;

      darwinPlain =
        (bareDarwinSystem (
          denLib.imports {
            class = "darwin";
            aspects = hostAspects;
          }
        )).config;

      homeModules = denLib.imports {
        class = "homeManager";
        aspects = [ "apps" ] ++ hostAspects;
      };

      # A user that names no application at all.
      homePlain = (bareHomeConfiguration homeModules).config;

      # A user that names two applications. `jq` installs no package, so it proves the switch.
      homeApps =
        (bareHomeConfiguration (
          homeModules
          ++ [
            {
              kdn.apps.hello.enable = true;
              kdn.apps.hello.dirs.config = [ "hello" ];
              kdn.apps.hello.dirs.disposable = [ "/tmp-hello" ];
              kdn.apps.hello.files.state = [ "hello/last-run" ];
              kdn.apps.jq.enable = true;
              kdn.apps.jq.package.install = false;
            }
          ]
        )).config;

      # The adopter override path. The primary locale stays in the replacement list, because the
      # nixpkgs `i18n` module warns when `supportedLocales` drops the default locale.
      overridden =
        (bareNixos (
          nixosModules
          ++ [
            {
              kdn.locale.timezone = "Europe/Warsaw";
              kdn.locale.extra = [
                "pl_PL.UTF-8/UTF-8"
                "en_GB.UTF-8/UTF-8"
              ];
              kdn.security.secrets.allow = false;
            }
          ]
        )).config;

      appNames =
        packages:
        map lib.getName (
          lib.filter (
            p:
            lib.elem (lib.getName p) [
              "hello"
              "jq"
            ]
          ) packages
        );
    in
    [
      # ---- `locale`, nixos class
      {
        name = "a bare nixos consumer gets the whole i18n opinion of the aspect";
        expected = {
          defaultLocale = "en_GB.UTF-8";
          supportedLocales = [
            "C.UTF-8/UTF-8"
            "en_US.UTF-8/UTF-8"
            "en_GB.UTF-8/UTF-8"
          ];
          extraLocaleSettings = {
            LANGUAGE = "en_GB.UTF-8";
            LC_ALL = "en_GB.UTF-8";
            LC_TIME = "en_GB.UTF-8";
          };
          timeZone = "Etc/UTC";
        };
        actual = {
          inherit (nixosPlain.i18n) defaultLocale supportedLocales extraLocaleSettings;
          timeZone = nixosPlain.time.timeZone;
        };
      }

      # ---- `locale`, darwin class
      {
        name = "a bare darwin consumer gets the cask language list and the four login variables";
        expected = {
          caskLanguage = "en-GB,en-US,en";
          timeZone = "Etc/UTC";
          LANG = "en_GB.UTF-8";
          LANGUAGE = "en_GB.UTF-8";
          LC_ALL = "en_GB.UTF-8";
          LC_TIME = "en_GB.UTF-8";
        };
        actual = {
          caskLanguage = darwinPlain.homebrew.caskArgs.language;
          timeZone = darwinPlain.time.timeZone;
          inherit (darwinPlain.environment.variables)
            LANG
            LANGUAGE
            LC_ALL
            LC_TIME
            ;
        };
      }

      # ---- `locale`, homeManager class
      {
        name = "a bare home consumer gets TZ and the four locale variables in its session";
        expected = {
          TZ = "Etc/UTC";
          LANG = "en_GB.UTF-8";
          LANGUAGE = "en_GB.UTF-8";
          LC_ALL = "en_GB.UTF-8";
          LC_TIME = "en_GB.UTF-8";
        };
        actual = {
          inherit (homePlain.home.sessionVariables)
            TZ
            LANG
            LANGUAGE
            LC_ALL
            LC_TIME
            ;
        };
      }
      {
        name = "the three force writes sit under one mkIf, so no empty user-dirs.dirs entry appears";
        expected = [
          "locale.conf"
          "user-dirs.locale"
        ];
        actual = builtins.attrNames homePlain.xdg.configFile;
      }

      # ---- `secrets`, three classes
      {
        name = "secrets are allowed by default on every class, because allowed now tracks allow alone";
        expected = {
          nixos = true;
          darwin = true;
          home = true;
        };
        actual = {
          nixos = nixosPlain.kdn.security.secrets.allowed;
          darwin = darwinPlain.kdn.security.secrets.allowed;
          home = homePlain.kdn.security.secrets.allowed;
        };
      }
      {
        name = "the nixos class declares the two ordering targets, and the first upholds the second";
        expected = {
          description = "kdn's secrets loaded for the first time";
          upholds = [ "kdn-secrets-reload.target" ];
          reloadPartOf = [ "kdn-secrets.target" ];
        };
        actual = {
          inherit (nixosPlain.systemd.targets.kdn-secrets) description upholds;
          reloadPartOf = nixosPlain.systemd.targets.kdn-secrets-reload.partOf;
        };
      }

      # ---- `apps`, homeManager class
      {
        name = "a user that names no application installs no application and keeps no path";
        expected = {
          packages = [ ];
          directories = {
            "disposable" = [ ];
            "usr/cache" = [ ];
            "usr/config" = [ ];
            "usr/data" = [ ];
            "usr/reproducible" = [ ];
            "usr/state" = [ ];
          };
          files = {
            "disposable" = [ ];
            "usr/cache" = [ ];
            "usr/config" = [ ];
            "usr/data" = [ ];
            "usr/reproducible" = [ ];
            "usr/state" = [ ];
          };
        };
        actual = {
          packages = appNames homePlain.home.packages;
          inherit (homePlain.kdn.apps-persist) directories files;
        };
      }
      {
        name = "package.install = false keeps the entry and installs nothing";
        expected = [ "hello" ];
        actual = appNames homeApps.home.packages;
      }
      {
        name = "an enabled application lands in the right persistence bucket, with the prefix applied";
        expected = {
          directories = {
            "disposable" = [ "tmp-hello" ];
            "usr/cache" = [ ];
            "usr/config" = [ ".config/hello" ];
            "usr/data" = [ ];
            "usr/reproducible" = [ ];
            "usr/state" = [ ];
          };
          files = {
            "disposable" = [ ];
            "usr/cache" = [ ];
            "usr/config" = [ ];
            "usr/data" = [ ];
            "usr/reproducible" = [ ];
            "usr/state" = [ ".local/state/hello/last-run" ];
          };
        };
        actual = {
          inherit (homeApps.kdn.apps-persist) directories files;
        };
      }
      {
        name = "package.final defaults to the nixpkgs attribute the entry name gives";
        expected = "hello";
        actual = lib.getName homeApps.kdn.apps.hello.package.final;
      }

      # ---- the adopter override path
      {
        name = "a plain list definition replaces the whole supportedLocales default";
        expected = {
          timeZone = "Europe/Warsaw";
          supportedLocales = [
            "pl_PL.UTF-8/UTF-8"
            "en_GB.UTF-8/UTF-8"
          ];
          secretsAllowed = false;
        };
        actual = {
          timeZone = overridden.time.timeZone;
          supportedLocales = overridden.i18n.supportedLocales;
          secretsAllowed = overridden.kdn.security.secrets.allowed;
        };
      }

      # ---- the forces. Each one runs the whole target module body, assertions included.
      {
        name = "every batch 2 subject builds, so each target module body evaluates";
        expected = {
          nixos = true;
          darwin = true;
          home = true;
          homeApps = true;
          overridden = true;
        };
        actual = {
          nixos = builtins.isString nixosPlain.system.build.toplevel.drvPath;
          darwin = builtins.isString darwinPlain.system.build.toplevel.drvPath;
          home = builtins.isString homePlain.home.activationPackage.drvPath;
          homeApps = builtins.isString homeApps.home.activationPackage.drvPath;
          overridden = builtins.isString overridden.system.build.toplevel.drvPath;
        };
      }
    ];

  # ------------------------------------------------------------------ coverage tripwire

  # The `llm` family reached the registry, passed "the registry holds every ported aspect", and still
  # evaluated in no target module at all. Nothing stopped it. This set is the tripwire: every registry
  # aspect must name the subject whose **target module** it reaches, so a new aspect cannot land with
  # a resolve-only test again.
  #
  # Add a row when you add an aspect, and name a real subject. A resolve count is not a subject.
  #
  # This table stays a readable index of the entities. `den-eval-instantiate` above is the
  # mechanical guard: it forces every (aspect, class) pair straight from the registry, so it needs
  # no row here and it cannot rot.
  # A later batch adds its own rows inside its own ./assertions/<area>.nix file, under
  # `instantiatedBy`. ./assertions/default.nix merges every such set, and the join below adds it to
  # this base table. So a new aspect needs no edit here.
  baseInstantiatedBy = {
    apps = "den-eval-batch2 (bare home, plain and with two applications)";
    ca = "host-nixos";
    devenv-cli = "host-darwin, host-nixos, users/dev, home, devenv";
    disks = "den-eval-disks-fs (bare nixos, plain and with two LUKS volumes)";
    disks-persist = "den-eval-disks-fs (bare home, with the apps aspect and without it)";
    emulation-wine = "den-eval-toolset-small (bare home, x86 and non-x86)";
    fs-luks-zfs = "den-eval-disks-fs (bare nixos, with a host-written layout and without one)";
    fs-watch = "den-eval-disks-fs (bare nixos, with one instance and with none)";
    fs-zfs = "den-eval-disks-fs (bare nixos, one real layout)";
    gh = "host-darwin, host-nixos, devenv";
    homebrew = "host-darwin";
    # No den entity includes this aspect, and no host may: it changes a real Homebrew
    # installation. `den-eval-instantiate` forces its `darwin` body from the registry, in a bare
    # consumer, so the body still gets coverage.
    homebrew-nix-managed = "den-eval-instantiate (bare darwin force only)";
    hw-audio = "den-eval-hw (bare nixos, plain and graphical; bare home)";
    hw-basic = "den-eval-hw (bare nixos)";
    hw-bluetooth = "den-eval-hw (bare nixos)";
    hw-cpu-amd = "den-eval-hw (bare nixos)";
    hw-cpu-intel = "den-eval-hw (bare nixos)";
    hw-darwin-utm-guest = "den-eval-hw (bare nixos)";
    hw-dell-e5470 = "den-eval-hw (bare nixos, plain and alone)";
    hw-edid = "den-eval-hw (bare nixos)";
    hw-gpu = "den-eval-hw (bare nixos, plain, VFIO and the overlay subject)";
    hw-gpu-amd = "den-eval-hw (bare nixos)";
    hw-gpu-intel = "den-eval-hw (bare nixos)";
    hw-intel-graphics-fix = "den-eval-hw (bare nixos, plain and with an override)";
    hw-modem = "den-eval-hw (bare nixos)";
    hw-nanokvm = "den-eval-hw (bare nixos)";
    hw-qmk = "den-eval-hw (bare nixos, plain and graphical; bare darwin)";
    hw-usbip = "den-eval-hw (bare nixos, one interface and every interface)";
    hw-yubikey = "den-eval-hw (bare nixos, with and without a secret; bare darwin; bare home)";
    jj = "devenv, defaultsShell";
    jj-fork = "devenv, defaultsShell";
    llm = "llmNixos";
    llm-client = "llmClientShell";
    llm-proxy = "llmProxyNixos";
    locale = "orr, den-eval-batch2 (bare nixos, bare darwin, bare home)";
    managed = "den-eval-services (bare nixos, bare darwin)";
    mcp = "devenv, bareShell";
    mcp-basic-memory = "devenv, defaultsShell";
    mcp-pretty-print = "devenv";
    mcp-snoop = "devenv";
    monitoring-prometheus-stack = "den-eval-toolset-small (bare nixos, plain and tuned)";
    nix = "devenv, defaultsShell";
    nix-config = "host-darwin, orr";
    nix-remote-builder = "host-darwin, orr";
    opencode = "devenv, defaultsShell";
    outputs-host = "den-eval-toolset-small (bare nixos, plain and tuned)";
    packaging-asdf = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    rosetta-builder = "host-darwin";
    secrets = "orr, den-eval-batch2 (bare nixos, bare darwin, bare home)";
    service-caddy = "den-eval-services (bare nixos)";
    service-coredns = "den-eval-services (bare nixos, plain and with one rewrite)";
    service-home-assistant = "den-eval-services (bare nixos, plain and with zigbee)";
    service-iperf3 = "den-eval-services (bare nixos, with and without a secret)";
    service-nextcloud-client = "den-eval-services (bare nixos, with and without a secret)";
    service-postgresql = "den-eval-services (bare nixos)";
    service-printing = "den-eval-services (bare nixos, plain and with one printer)";
    service-samba = "den-eval-services (bare nixos, plain and with consumer data)";
    service-syncthing = "den-eval-services (bare home, darwin and Linux)";
    service-zammad = "den-eval-services (bare nixos, privileged and unprivileged port)";
    signing = "users/dev, home";
    ssh-access = "users/dev, home, devenv";
    ssh-agent = "users/dev, home";
    toolset-diagrams = "den-eval-toolset-small (bare home)";
    toolset-essentials = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    toolset-fs = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    toolset-fs-encryption = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    toolset-logs-processing = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    toolset-mikrotik = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    toolset-network = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    toolset-network-gui = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    toolset-nix = "den-eval-toolset-small (bare nixos, bare home)";
    toolset-tracing = "den-eval-toolset-small (bare nixos)";
    toolset-unix = "den-eval-toolset-small (bare nixos, bare darwin, bare home)";
    virt-containers = "den-eval-services (bare nixos, bare home, darwin and Linux)";
    virt-containers-dagger = "den-eval-services (bare nixos, bare darwin, bare home)";
    virt-containers-distrobox = "den-eval-services (bare nixos)";
    virt-containers-docker = "den-eval-services (bare nixos, the docker subject)";
    virt-containers-podman = "den-eval-services (bare nixos, bare darwin)";
    virt-containers-x11docker = "den-eval-services (bare nixos)";
    virt-libvirtd = "den-eval-services (bare nixos, bare home)";
    virt-vagrant = "den-eval-services (bare nixos)";
    zellij = "host-darwin, devenv, defaultsShell";
  };

  instantiatedBy = baseInstantiatedBy // areas.instantiatedBy;

  coverageAssertions = [
    {
      name = "every registry aspect names a subject that evaluates its target module";
      expected = sorted (builtins.attrNames denLib.aspectModules);
      actual = sorted (builtins.attrNames instantiatedBy);
    }
  ];

  # ------------------------------------------------------------------ the check set

  # Tier 1 runs anywhere: the comparison is an evaluation and the derivation is local. This set
  # holds the areas that predate ./assertions/; the loader adds one check per area file below.
  portableHere = {
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
    den-eval-nix-config = mkEvalCheck "nix-config" nixConfigAssertions;
    den-eval-jj = mkEvalCheck "jj" jjAssertions;
    den-eval-llm = mkEvalCheck "llm" llmAssertions;
    den-eval-signing = mkEvalCheck "signing" signingAssertions;
    den-eval-ssh-access = mkEvalCheck "ssh-access" sshAccessAssertions;
    den-eval-defaults = mkEvalCheck "defaults" aspectDefaultsAssertions;
    den-eval-priority = mkEvalCheck "priority" priorityAssertions;
    den-eval-frozen-paths = mkEvalCheck "frozen-paths" frozenPathAssertions;
    den-eval-coverage = mkEvalCheck "coverage" coverageAssertions;
    den-eval-instantiate = mkEvalCheck "instantiate" instantiateAssertions;
    den-eval-batch2 = mkEvalCheck "batch2" batch2Assertions;
  };

  # Each area file adds one `den-eval-<area>` check. A duplicate name would replace a check above in
  # silence, so the merge names the collision and fails.
  collisions = lib.intersectLists (builtins.attrNames portableHere) (builtins.attrNames areas.checks);

  portable =
    if collisions == [ ] then
      portableHere // areas.checks
    else
      throw "den: ./tests.nix and ./assertions/ both declare ${builtins.toJSON collisions}";

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
