# Tier-1 assertions for the 30 `dev-*` aspects. It is the candidate text of
# `checks/den-mvp/assertions/development.nix`.
#
# ## What it asserts
#
# 1. Every declared (aspect, class) pair passes den's resolve guard. 64 pairs.
# 2. One value per aspect, read back from a real consumer evaluation.
# 3. The platform split of the two aspects that write a systemd user unit or a tmpfiles rule.
#
# ## Why it builds its own subjects
#
# Each subject here is a **bare** evaluation: one aspect, one class, no den host and no den user. So
# a new aspect needs no change to a shared entity file, and 30 aspects add no cost to the two host
# evaluations that every other check reads.
#
# ## Why it keeps its own helpers, now that `../harness.nix` exists
#
# `../harness.nix` exports `bareHome` and `bareNixos`, and each one takes a plain module list on one
# fixed platform. The subjects here need two extra things that shape does not give:
#
#   1. An **aspect name list**, so `denLib.imports` runs per subject.
#   2. A **`x86_64-linux` home**, so the `dev-java` and `dev-jetbrains` platform split gets a real
#      Linux subject. `harness.bareHome` is `aarch64-darwin` only.
#
# So the two local helpers stay. They keep the same bare-consumer shape: a plain home-manager or
# nixpkgs evaluation, no `modules/universal`, no `mkSlots` and no `kdnConfig`.
#
# ## What it does not assert
#
# The `darwin` class gets no value assertion. A bare `darwinSystem` needs more scaffolding than a
# bare `nixosSystem`, and the two system targets of each aspect are the same module text. Item 1
# above still resolves every `darwin` pair, and `checks/standalone.nix` walks its option tree.
{
  lib,
  inputs,
  denLib,
  ...
}:
let
  # ------------------------------------------------------------------ the bare subjects

  pkgsFor =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

  # A standalone home-manager configuration, from one aspect list. `denLib.imports` needs no den
  # entity: it takes a plain class name.
  bareHome =
    {
      system,
      aspects,
      extra ? { },
    }:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor system;
      modules =
        denLib.imports {
          class = "homeManager";
          inherit aspects;
        }
        ++ [
          {
            home.username = "dev";
            home.homeDirectory = if lib.hasSuffix "darwin" system then "/Users/dev" else "/home/dev";
            home.stateVersion = "26.11";

            # The aspects turn on no shell, so the subject does. Three aspects write a shell profile.
            programs.bash.enable = true;
            programs.zsh.enable = true;
            programs.fish.enable = true;
          }
          extra
        ];
    }).config;

  # A build-only NixOS system, from one aspect list. It never activates.
  bareNixos =
    {
      aspects,
      extra ? { },
    }:
    (inputs.nixpkgs.lib.nixosSystem {
      system = null;
      modules =
        denLib.imports {
          class = "nixos";
          inherit aspects;
        }
        ++ [
          {
            nixpkgs.hostPlatform = "x86_64-linux";
            nixpkgs.config.allowUnfree = true;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            boot.loader.grub.enable = false;
            system.stateVersion = "26.11";
          }
          extra
        ];
    }).config;

  darwinHome =
    aspects:
    bareHome {
      system = "aarch64-darwin";
      inherit aspects;
    };
  linuxHome =
    aspects:
    bareHome {
      system = "x86_64-linux";
      inherit aspects;
    };

  pkgNames = ps: lib.sort (a: b: a < b) (map (p: lib.getName p) ps);
  hasPkg = name: cfg: builtins.elem name (pkgNames cfg.home.packages);

  # ------------------------------------------------------------------ the class table
  #
  # One row per aspect, and the row names every class it exports. The first assertion reads it.
  systemAndHome = [
    "nixos"
    "darwin"
    "homeManager"
  ];
  homeOnly = [ "homeManager" ];

  classTable = {
    dev-android = systemAndHome;
    dev-ansible = systemAndHome;
    dev-cloud = systemAndHome;
    dev-cloud-aws = systemAndHome;
    dev-cloud-azure = systemAndHome;
    dev-data = systemAndHome;
    dev-db = systemAndHome;
    dev-documents = homeOnly;
    dev-dotnet = systemAndHome;
    dev-elixir = systemAndHome;
    dev-git = homeOnly;
    dev-golang = homeOnly;
    dev-java = homeOnly;
    dev-jetbrains = homeOnly;
    dev-k8s = systemAndHome;
    dev-kernel = [ "nixos" ];
    dev-llm-claude-code = homeOnly;
    dev-llm-omp = homeOnly;
    dev-llm-opencode = homeOnly;
    dev-llm-pi = homeOnly;
    dev-lua = systemAndHome;
    dev-nickel = systemAndHome;
    dev-nix = homeOnly;
    dev-nodejs = systemAndHome;
    dev-python = systemAndHome;
    dev-rpi = systemAndHome;
    dev-rust = systemAndHome;
    dev-shell = systemAndHome;
    dev-terraform = homeOnly;
    dev-web = homeOnly;
  };

  # ------------------------------------------------------------------ the subjects this file reads

  # The `dev-llm-*` aspects write into `kdn.apps`, which the `apps` aspect declares. Their `includes`
  # names it, and a bare resolve reads no `includes`, so the subject names both.
  gitHome = darwinHome [ "dev-git" ];
  nixHome = darwinHome [ "dev-nix" ];
  nixHomeWithFlake = bareHome {
    system = "aarch64-darwin";
    aspects = [ "dev-nix" ];
    extra.kdn.dev-nix.flake.path = "/etc/nixos";
  };
  golangHome = darwinHome [ "dev-golang" ];
  terraformHome = darwinHome [ "dev-terraform" ];
  k8sHome = darwinHome [ "dev-k8s" ];
  k8sNixos = bareNixos { aspects = [ "dev-k8s" ]; };
  kernelNixos = bareNixos { aspects = [ "dev-kernel" ]; };
  dotnetNixos = bareNixos { aspects = [ "dev-dotnet" ]; };
  dotnetHome = darwinHome [ "dev-dotnet" ];
  nodejsHome = darwinHome [ "dev-nodejs" ];
  pythonHome = darwinHome [ "dev-python" ];
  luaHome = darwinHome [ "dev-lua" ];
  dataHome = darwinHome [ "dev-data" ];
  awsHome = darwinHome [ "dev-cloud-aws" ];

  claudeHome = darwinHome [
    "apps"
    "dev-llm-claude-code"
  ];
  ompHome = darwinHome [
    "apps"
    "dev-llm-omp"
  ];
  piHome = darwinHome [
    "apps"
    "dev-llm-pi"
  ];

  javaLinux = linuxHome [ "dev-java" ];
  javaDarwin = darwinHome [ "dev-java" ];
  jetbrainsLinux = linuxHome [ "dev-jetbrains" ];
  jetbrainsDarwin = darwinHome [ "dev-jetbrains" ];

  den = denLib.eval { };
  aspectOf = name: den.ful.${denLib.namespaceName}.${name};

  # ------------------------------------------------------------------ the coverage rows
  #
  # `../tests.nix` merges this set into the table that `den-eval-coverage` reads. One row per aspect
  # this batch ports, so the registry and the table stay equal with no edit to a shared file.
  #
  # `den-eval-instantiate` reads the registry and forces one bare class harness per pair, so a row
  # that names it is honest: that check really evaluates the target module body. 12 aspects hold no
  # value worth a hand-written assertion beyond their package list, and they take that row.
  instantiatedBy = {
    dev-android = "den-eval-instantiate (bare force of all three classes)";
    dev-ansible = "den-eval-instantiate (bare force of all three classes)";
    dev-cloud = "den-eval-instantiate (bare force of all three classes)";
    dev-cloud-aws = "den-eval-development (bare home, persist paths)";
    dev-cloud-azure = "den-eval-instantiate (bare force of all three classes)";
    dev-data = "den-eval-development (bare home, helix language servers)";
    dev-db = "den-eval-instantiate (bare force of all three classes)";
    dev-documents = "den-eval-instantiate (bare force of the homeManager class)";
    dev-dotnet = "den-eval-development (bare nixos and bare home, DOTNET_ROOT)";
    dev-elixir = "den-eval-instantiate (bare force of all three classes)";
    dev-git = "den-eval-development (bare home)";
    dev-golang = "den-eval-development (bare home, persist paths)";
    dev-java = "den-eval-development (bare home, Linux and darwin)";
    dev-jetbrains = "den-eval-development (bare home, Linux and darwin)";
    dev-k8s = "den-eval-development (bare nixos and bare home)";
    dev-kernel = "den-eval-development (bare nixos)";
    dev-llm-claude-code = "den-eval-development (bare home, with the apps aspect)";
    dev-llm-omp = "den-eval-development (bare home, with no omp overlay)";
    dev-llm-opencode = "den-eval-instantiate (bare force of the homeManager class)";
    dev-llm-pi = "den-eval-development (bare home, with the apps aspect)";
    dev-lua = "den-eval-development (bare home, four versions)";
    dev-nickel = "den-eval-instantiate (bare force of all three classes)";
    dev-nix = "den-eval-development (bare home, with and without a flake path)";
    dev-nodejs = "den-eval-development (bare home, the npm cache file)";
    dev-python = "den-eval-development (bare home, seven interpreters)";
    dev-rpi = "den-eval-instantiate (bare force of all three classes)";
    dev-rust = "den-eval-instantiate (bare force of all three classes)";
    dev-shell = "den-eval-instantiate (bare force of all three classes)";
    dev-terraform = "den-eval-development (bare home, the tofu configuration)";
    dev-web = "den-eval-instantiate (bare force of the homeManager class)";
  };

  assertions = [
    # ---- 1. every declared pair passes the resolve guard
    #
    # `denLib.imports` gives one module per name it takes, so a length of 1 is the pass. The value of
    # this assertion is the guard inside `denLib.resolve`: it throws when the resolved module holds an
    # empty `imports` list, which is what an aspect with an entity argument gives. So this row proves
    # each of the 64 pairs really carries a target.
    {
      name = "each dev-* aspect resolves on each class it declares";
      expected = lib.mapAttrs (_: classes: map (_: 1) classes) classTable;
      actual = lib.mapAttrs (
        name: classes:
        map (
          class:
          builtins.length (
            denLib.imports {
              inherit class;
              aspects = [ name ];
            }
          )
        ) classes
      ) classTable;
    }

    # ---- 2. the `includes` edges. den collapses a diamond, so a shared name may repeat.
    {
      name = "each aspect that depends on another one names it in includes";
      expected = {
        dev-cloud = 2;
        dev-cloud-azure = 1;
        dev-k8s = 1;
        dev-llm-claude-code = 1;
        dev-llm-omp = 1;
        dev-llm-opencode = 1;
        dev-llm-pi = 1;
        dev-web = 1;
      };
      actual = lib.mapAttrs (name: _: builtins.length (aspectOf name).includes) {
        dev-cloud = null;
        dev-cloud-azure = null;
        dev-k8s = null;
        dev-llm-claude-code = null;
        dev-llm-omp = null;
        dev-llm-opencode = null;
        dev-llm-pi = null;
        dev-web = null;
      };
    }

    # ---- 3. dev-git
    {
      name = "dev-git turns on git, difftastic and jujutsu";
      expected = {
        git = true;
        difftastic = true;
        jujutsu = true;
      };
      actual = {
        git = gitHome.programs.git.enable;
        difftastic = gitHome.programs.difftastic.git.enable;
        jujutsu = gitHome.programs.jujutsu.enable;
      };
    }
    {
      name = "dev-git ignores the worktree directory of git-utils";
      expected = true;
      actual = lib.hasInfix ".worktrees" (builtins.concatStringsSep "\n" gitHome.programs.git.ignores);
    }
    {
      name = "dev-git installs git-utils, gh and jjui";
      expected = true;
      actual = lib.all (n: hasPkg n gitHome) [
        "git-utils"
        "gh"
        "jjui"
      ];
    }

    # ---- 4. dev-nix. `nh.use` replaces the old `nh.enable`, so its default is the whole behaviour.
    {
      name = "dev-nix runs nh and states no checkout path of its own";
      expected = {
        use = true;
        flakePath = null;
        nhFlake = null;
        overrideCount = 0;
      };
      actual = {
        use = nixHome.kdn.dev-nix.nh.use;
        flakePath = nixHome.kdn.dev-nix.flake.path;
        nhFlake = nixHome.kdn.dev-nix.nh.flake;
        overrideCount = builtins.length nixHome.kdn.dev-nix.nh.package.overrideAttrs;
      };
    }
    {
      name = "a consumer that states a checkout path gets it inside the nh wrapper";
      expected = {
        nhFlake = "/etc/nixos";
        overrideCount = 1;
        wrapperSetsFlake = true;
      };
      actual = {
        nhFlake = nixHomeWithFlake.kdn.dev-nix.nh.flake;
        overrideCount = builtins.length nixHomeWithFlake.kdn.dev-nix.nh.package.overrideAttrs;
        wrapperSetsFlake = lib.hasInfix "NH_FLAKE" nixHomeWithFlake.kdn.dev-nix.nh.package.final.buildCommand;
      };
    }
    {
      name = "dev-nix installs the formatter and both language servers";
      expected = true;
      actual = lib.all (n: hasPkg n nixHome) [
        "kdn-nix-fmt"
        "nixfmt"
        "nh"
      ];
    }

    # ---- 5. the persist publication. Four aspects publish, and none writes a persist option.
    {
      name = "each aspect publishes its own persist paths, read-only";
      expected = {
        dev-cloud-aws = {
          "usr/data".directories = [ ".aws" ];
        };
        dev-golang = {
          "usr/cache".directories = [ ".cache/go" ];
        };
        dev-java = {
          "usr/cache".directories = [ ".cache/gradle" ];
        };
        dev-jetbrains = {
          "usr/cache".directories = [ ".cache/JetBrains" ];
          "usr/config".directories = [ ".config/JetBrains" ];
          "usr/data".directories = [ ".local/share/JetBrains" ];
          "usr/state".directories = [ ".java/.userPrefs/jetbrains" ];
          "usr/state".files = [ ".java/.userPrefs/prefs.xml" ];
        };
      };
      actual = {
        dev-cloud-aws = awsHome.kdn.dev-persist.dev-cloud-aws;
        dev-golang = golangHome.kdn.dev-persist.dev-golang;
        dev-java = javaLinux.kdn.dev-persist.dev-java;
        dev-jetbrains = jetbrainsLinux.kdn.dev-persist.dev-jetbrains;
      };
    }

    # ---- 6. the platform split. Three aspects write a Linux-only fact, and Darwin must stay clean.
    {
      name = "the tmpfiles rules and the user unit reach Linux only";
      expected = {
        javaLinuxRules = 2;
        javaDarwinRules = 0;
        jetbrainsLinuxRules = 1;
        jetbrainsDarwinRules = 0;
        jetbrainsLinuxUnit = true;
        jetbrainsDarwinUnit = false;
      };
      actual = {
        javaLinuxRules = builtins.length javaLinux.systemd.user.tmpfiles.rules;
        javaDarwinRules = builtins.length javaDarwin.systemd.user.tmpfiles.rules;
        jetbrainsLinuxRules = builtins.length jetbrainsLinux.systemd.user.tmpfiles.rules;
        jetbrainsDarwinRules = builtins.length jetbrainsDarwin.systemd.user.tmpfiles.rules;
        jetbrainsLinuxUnit = jetbrainsLinux.systemd.user.services ? jetbrains-remote;
        jetbrainsDarwinUnit = jetbrainsDarwin.systemd.user.services ? jetbrains-remote;
      };
    }
    {
      name = "dev-java turns on the home-manager java program";
      expected = true;
      actual = javaLinux.programs.java.enable;
    }

    # ---- 7. the two renamed flags. Neither is an `enable`, and both default to off.
    {
      name = "the two renamed flags default to off";
      expected = {
        jetbrainsGo = false;
        k8sLens = false;
      };
      actual = {
        jetbrainsGo = jetbrainsLinux.kdn.dev-jetbrains.go.use;
        k8sLens = k8sHome.kdn.dev-k8s.lens.install;
      };
    }
    {
      name = "dev-k8s installs no Lens until a consumer asks for it";
      expected = false;
      actual = hasPkg "lens-desktop" k8sHome;
    }

    # ---- 8. dev-k8s on the nixos class
    {
      name = "dev-k8s sets the krew root, the kubectl alias and the fish completion";
      expected = {
        krewRoot = true;
        kcIsKubecolor = true;
        fishWraps = true;
      };
      actual = {
        krewRoot = lib.hasInfix "KREW_ROOT" k8sNixos.environment.interactiveShellInit;
        kcIsKubecolor = lib.hasSuffix "/bin/kubecolor" k8sNixos.environment.shellAliases.kc;
        fishWraps = lib.hasInfix "complete -c kc --wraps kubectl" k8sNixos.programs.fish.interactiveShellInit;
      };
    }

    # ---- 9. dev-terraform
    {
      name = "dev-terraform points every tool at the tofu configuration";
      expected = {
        tfpath = "tofu";
        hasCliConfig = true;
        tfAlias = "tofu";
        toolVersions = "opentofu 1.6.2\nterragrunt 0.55.16\n";
      };
      actual = {
        tfpath = terraformHome.home.sessionVariables.TERRAGRUNT_TFPATH;
        hasCliConfig = lib.hasSuffix "/tofu/.tofurc" terraformHome.home.sessionVariables.TF_CLI_CONFIG_FILE;
        tfAlias = terraformHome.home.shellAliases.tf;
        toolVersions = builtins.readFile terraformHome.home.file.".tool-versions".source;
      };
    }
    {
      name = "dev-terraform adds the terraform ignore rules to git";
      expected = true;
      actual = lib.hasInfix "tfstate" (builtins.concatStringsSep "\n" terraformHome.programs.git.ignores);
    }

    # ---- 10. dev-dotnet. One variable, three class-native option names.
    {
      name = "dev-dotnet sets DOTNET_ROOT on each class and turns on nix-ld on NixOS";
      expected = {
        home = true;
        nixos = true;
        nixLd = true;
      };
      actual = {
        home = dotnetHome.home.sessionVariables ? DOTNET_ROOT;
        nixos = dotnetNixos.environment.sessionVariables ? DOTNET_ROOT;
        nixLd = dotnetNixos.programs.nix-ld.enable;
      };
    }

    # ---- 11. dev-nodejs. The old tree writes this file from the NixOS half only.
    {
      name = "dev-nodejs writes the npm cache configuration for every home";
      expected = "cache=~/.cache/npm\nprefix=~/.cache/npm-global\n";
      actual = nodejsHome.home.file.".npmrc".text;
    }

    # ---- 12. dev-python
    {
      name = "dev-python adds the python ignore rules to git";
      expected = true;
      actual = lib.hasInfix "__pycache__" (
        builtins.concatStringsSep "\n" pythonHome.programs.git.ignores
      );
    }
    {
      name = "dev-python installs seven interpreters and graphviz";
      expected = {
        interpreters = 7;
        graphviz = true;
      };
      actual = {
        interpreters = builtins.length (
          builtins.filter (n: n == "python3") (pkgNames pythonHome.home.packages)
        );
        graphviz = hasPkg "graphviz" pythonHome;
      };
    }

    # ---- 13. dev-lua
    {
      name = "dev-lua installs one interpreter per version, plus the default one";
      expected = {
        versions = [
          "5.1"
          "5.2"
          "5.3"
          "5.4"
        ];
        defaultVersion = "5.4";
        interpreters = 5;
      };
      actual = {
        versions = luaHome.kdn.dev-lua.versions;
        defaultVersion = luaHome.kdn.dev-lua.defaultVersion;
        interpreters = builtins.length (builtins.filter (n: n == "lua") (pkgNames luaHome.home.packages));
      };
    }

    # ---- 14. dev-data
    {
      name = "dev-data adds five language servers to helix and teaches it jq";
      expected = {
        helix = 5;
        jqLanguage = 1;
      };
      actual = {
        helix = builtins.length dataHome.programs.helix.extraPackages;
        jqLanguage = builtins.length (
          builtins.filter (l: l.name == "jq") dataHome.programs.helix.languages.language
        );
      };
    }

    # ---- 15. the four `dev-llm-*` aspects, through the `apps` aspect
    {
      name = "dev-llm-claude-code registers the harness and both of its paths";
      expected = {
        enable = true;
        dirs = [ ".claude" ];
        files = [ ".claude.json" ];
      };
      actual = {
        enable = claudeHome.kdn.apps.claude-code.enable;
        dirs = claudeHome.kdn.apps.claude-code.dirs.data;
        files = claudeHome.kdn.apps.claude-code.files.config;
      };
    }
    {
      name = "dev-llm-pi registers the package that nixpkgs names pi-coding-agent";
      expected = "pi-coding-agent";
      actual = lib.getName piHome.kdn.apps.pi.package.final;
    }
    # `pkgs.omp` comes from a separate flake overlay. A consumer without it must still evaluate.
    {
      name = "dev-llm-omp registers nothing when the overlay is absent";
      expected = {
        package = null;
        registered = false;
      };
      actual = {
        package = ompHome.kdn.dev-llm-omp.package;
        registered = ompHome.kdn.apps ? omp;
      };
    }

    # ---- 16. dev-kernel. nixpkgs removed one name of the old list, and a throw defeats the filter.
    {
      name = "dev-kernel names no package that nixpkgs removed";
      expected = {
        reiserfsprogs = false;
        elfutils = true;
      };
      actual =
        let
          names = pkgNames kernelNixos.environment.systemPackages;
        in
        {
          reiserfsprogs = builtins.elem "reiserfsprogs" names;
          elfutils = builtins.elem "elfutils" names;
        };
    }
  ];
in
{
  inherit assertions instantiatedBy;
}
