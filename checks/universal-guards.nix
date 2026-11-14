# Two guard defects of `modules/universal/`, as a runnable test.
#
# `docs/tasks/2026-09/latent-guard-defects/definition.md` states both defects.
# `docs/tasks/2026-09/latent-guard-defects/done.md` states the fix. Nix laziness hides each one:
# no host forces the wrong branch today. A den aspect removes that protection, so each check
# forces the exact attribute path.
#
# | Check | It forces | It proves |
# |---|---|---|
# | `universal-eval-keepassxc` | `kdn.env.packages` of the keepassxc module | a platform test guards the Linux-only package, in both contexts |
# | `universal-eval-containers` | `containersConf.settings` and the rendered `storage.conf` and `99-user.conf` of the containers module | the Home Manager branch reads the parent through `osConfig`, the per-user store names no `~`, the drop-in sorts after the NixOS `00-` file, and a root profile renders no container file |
#
# Each check evaluates one module file, not a whole host. `_module.check = false` tolerates every
# definition that names an option of another module, so the evaluation stays small. A stub
# declares each option the module *reads*, because an undeclared read raises an error.
#
# The pkgs set is explicit, and it is never the check's own system. `pkgs.kdn.kdn-keepass` runs
# `sway` and `systemd`, so `packages/default.nix` keeps it out of the Darwin set, and
# `pkgs.cni-plugins` does not evaluate on Darwin at all. A Linux pkgs set therefore drives every
# assertion, and one Darwin pkgs set proves the negative half. Both use `overlays.packages`,
# which adds `pkgs.kdn` and nothing else; `overlays.default` composes six more overlays and a
# foreign system pays for each one.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Same shape as ./standalone.nix and ./conditional-imports.nix. Every assertion is
  # `{ name; expected; actual; }`, the comparison happens at evaluation time, and the derivation
  # only reports it.
  mkCheck =
    name: assertions:
    let
      failures = lib.filter (a: a.actual != a.expected) assertions;
      total = toString (builtins.length assertions);
      line = a: "  ${a.name}: want ${builtins.toJSON a.expected}, got ${builtins.toJSON a.actual}";
    in
    pkgs.runCommand "universal-eval-${name}"
      {
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      (
        if failures == [ ] then
          ''
            echo "universal-eval ${name}: ${total} of ${total} assertions pass" >&2
            touch $out
          ''
        else
          ''
            {
              echo "universal-eval ${name}: ${toString (builtins.length failures)} of ${total} assertions FAIL"
            ${lib.concatMapStringsSep "\n" (a: "  echo ${lib.escapeShellArg (line a)}") failures}
            } >&2
            exit 1
          ''
      );

  pkgsFor = system: inputs.nixpkgs.legacyPackages.${system}.extend inputs.self.overlays.packages;
  linuxPkgs = pkgsFor "x86_64-linux";
  darwinPkgs = pkgsFor "aarch64-darwin";

  # The real `kdnConfig` of each context, over the production route. `mkSubmodule` builds the
  # parent chain, so every `kdnConfig.util.*` guard answers as it does on a host.
  hostMeta = moduleType: inputs.self.kdnMetaModule.config.output.mkSubmodule { inherit moduleType; };
  hmMeta = moduleType: (hostMeta moduleType).output.mkSubmodule { moduleType = "home-manager"; };

  # ------------------------------------------------------------------ defect 1: the keepassxc guard

  # The module reads two options that other files of `modules/universal/` declare. A stub
  # declares each one, so the read resolves and the assertion sees the value.
  keepassStubs = pkgs': {
    options.kdn.env.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
    options.kdn.apps.keepassxc.package.final = lib.mkOption {
      type = lib.types.package;
      default = pkgs'.hello;
    };
  };

  # Every package name of `kdn.env.packages`. `lib.getName` forces each element, so
  # `pkgs.kdn.kdn-keepass` really evaluates. `hello` stands for the app package, and its name
  # proves the list gathered — an empty list can never pass.
  keepassNames =
    pkgs': kdnConfig:
    map (p: lib.getName p)
      (lib.evalModules {
        modules = [
          { _module.check = false; }
          (keepassStubs pkgs')
          ../modules/universal/programs/keepassxc
          { kdn.programs.keepassxc.enable = true; }
        ];
        specialArgs = {
          pkgs = pkgs';
          inherit kdnConfig;
        };
      }).config.kdn.env.packages;

  keepassAssertions = [
    {
      name = "on Linux both the NixOS context and the Home Manager context hold kdn-keepass";
      expected = {
        nixos = [
          "hello"
          "kdn-keepass"
        ];
        home-manager = [
          "hello"
          "kdn-keepass"
        ];
      };
      actual = {
        nixos = keepassNames linuxPkgs (hostMeta "nixos");
        home-manager = keepassNames linuxPkgs (hmMeta "nixos");
      };
    }
    {
      name = "on Darwin neither context names the Linux-only package";
      expected = {
        darwin = [ "hello" ];
        home-manager = [ "hello" ];
      };
      actual = {
        darwin = keepassNames darwinPkgs (hostMeta "darwin");
        home-manager = keepassNames darwinPkgs (hmMeta "darwin");
      };
    }
    {
      name = "a NixOS host has no NixOS parent, so a parent test is the wrong guard";
      expected = {
        nixos = false;
        home-manager = true;
      };
      actual = {
        nixos = (hostMeta "nixos").util.hasParentOfAnyType [ "nixos" ];
        home-manager = (hmMeta "nixos").util.hasParentOfAnyType [ "nixos" ];
      };
    }
  ];

  # ------------------------------------------------------------------ defect 2: the containers branch

  # The Home Manager branch of the module, with the seccomp hook on. The branch also needs a
  # NixOS parent, so `hmMeta "nixos"` supplies the `kdnConfig`.
  containersSettings =
    osConfig:
    (lib.evalModules {
      modules = [
        { _module.check = false; }
        ../modules/universal/virtualisation/containers
        {
          kdn.virtualisation.containers.enable = true;
          kdn.virtualisation.containers.ociSeccompBpfHook.enable = true;
        }
      ];
      specialArgs = {
        pkgs = linuxPkgs;
        kdnConfig = hmMeta "nixos";
        osConfig = osConfig;
      };
    }).config.kdn.virtualisation.containers.containersConf.settings;

  # The parent stand-in. A real NixOS `config` holds the same path, and `hello` stands for the
  # hook package.
  osStub = {
    boot.kernelPackages.oci-seccomp-bpf-hook = linuxPkgs.hello;
  };

  withParent = containersSettings osStub;
  standalone = containersSettings null;
  emptyParent = containersSettings { };

  # The rendered per-user files, from the same module instance as `containersSettings`.
  # A `~` in `graphroot` is the regression this guards: the engine expands `$HOME` and
  # `$XDG_RUNTIME_DIR` in a path and expands no `~`. Home Manager declares `xdg.configFile` and
  # `home.username`, and this check loads one module file, so a stub declares them: the check
  # reads `source` only. The gate on a non-root user reads `home.username`, so the caller states
  # it, as a real Home Manager does (it has no default there).
  rootlessConfig =
    username:
    (lib.evalModules {
      modules = [
        { _module.check = false; }
        ../modules/universal/virtualisation/containers
        {
          options.home.username = lib.mkOption { type = lib.types.str; };
          config.home.username = username;
          options.xdg.configFile = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule { options.source = lib.mkOption { }; });
            default = { };
          };
        }
        { kdn.virtualisation.containers.enable = true; }
      ];
      specialArgs = {
        pkgs = linuxPkgs;
        kdnConfig = hmMeta "nixos";
        osConfig = osStub;
      };
    }).config;

  kdnHome = rootlessConfig "kdn";
  # A root Home Manager profile must render no container file: `sudo podman` reads
  # `/etc/containers/`, and a per-user file there redirects the privileged engine.
  rootHome = rootlessConfig "root";

  /*
    The `rootlessPersistBase` write. The module reads the bucket in its NixOS branch and passes
    it to Home Manager as a literal key, so a dynamic read inside the Home Manager module would
    re-enter that module's own config and raise `infinite recursion encountered`. This check
    evaluates the NixOS branch and forces the write, which proves the fix and the silence of a
    wrong value alike.

    The same evaluation renders the containers' *NixOS* branch, which writes its own persist
    entries for the system store. So `kdn.disks.persist` also holds them, and the check reads
    the Home Manager value back from `home-manager.sharedModules` instead: exactly the value
    Home Manager receives.
  */
  # One host shape: the option values a host would set. `assertions` and
  # `home-manager.sharedModules` belong to the NixOS class, and the module *writes* them rather
  # than declaring them, so a stub declares them and the value comes back through `config`.
  persistWrite =
    hostConfig:
    (lib.evalModules {
      modules = [
        { _module.check = false; }
        ../modules/universal/virtualisation/containers
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options.assertion = lib.mkOption { type = lib.types.bool; };
                options.message = lib.mkOption { type = lib.types.str; };
              }
            );
            default = [ ];
          };
          options.home-manager.sharedModules = lib.mkOption {
            type = lib.types.listOf lib.types.unspecified;
            default = [ ];
          };
          # The host's buckets. The assertion probes this option, so it must exist here.
          options.kdn.disks.base = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
            default = { };
          };
        }
        { kdn.virtualisation.containers.enable = true; }
        hostConfig
      ];
      specialArgs = {
        pkgs = linuxPkgs;
        kdnConfig = hostMeta "nixos";
      };
    }).config;

  # The write as one shape: which buckets of this Home Manager user name the rootless store, and
  # whether every assertion of the host passes. A stray bucket is a visible extra attribute.
  persistBuckets =
    hostConfig:
    let
      result = persistWrite hostConfig;
      persist =
        (lib.evalModules {
          modules = [
            { _module.check = false; }
            {
              options.kdn.disks.persist = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    options.directories = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                    };
                  }
                );
                default = { };
              };
            }
          ]
          ++ result.home-manager.sharedModules;
          specialArgs = {
            pkgs = linuxPkgs;
            kdnConfig = hmMeta "nixos";
            osConfig = { };
          };
        }).config.kdn.disks.persist;
      holders = builtins.filter (n: builtins.elem ".local/share/containers" persist.${n}.directories) (
        builtins.attrNames persist
      );
    in
    {
      buckets = holders;
      directories = lib.concatMap (n: persist.${n}.directories) holders;
      guardPasses = builtins.all (a: a.assertion) result.assertions;
    };

  # The three host shapes that declare `kdn.disks.base`: oams (`null`), brys (`"usr/data"`) and a
  # typo. A consumer with no `kdn.disks.base` at all (a den target, an adopter) cannot reach this
  # branch: it declares no `preservation.enable` either, so the NixOS branch writes persist
  # entries that nothing reads. The `base == null` arm of the assertion covers a shifted naming
  # that still evaluates the branch.
  persistNull = {
    kdn.virtualisation.containers.storage.rootlessPersistBase = null;
    kdn.disks.base."usr/data" = { };
  };
  persistUsrData = {
    kdn.virtualisation.containers.storage.rootlessPersistBase = "usr/data";
    kdn.disks.base."usr/data" = { };
  };
  persistTypo = {
    kdn.virtualisation.containers.storage.rootlessPersistBase = "usr/datax";
    kdn.disks.base."usr/data" = { };
  };

  rootlessStorage = builtins.readFile kdnHome.xdg.configFile."containers/storage.conf".source;
  rootlessStorageDropin =
    builtins.readFile
      kdnHome.xdg.configFile."containers/storage.conf.d/99-user.conf".source;

  containersAssertions = [
    {
      name = "the hook package comes from the parent config, not from the Home Manager config";
      expected = [ "hello" ];
      actual = map (p: lib.getName p) withParent.engine.hooks_dir;
    }
    {
      name = "a standalone Home Manager and a Darwin parent both drop the hook";
      expected = {
        standalone = [ "init_path" ];
        emptyParent = [ "init_path" ];
      };
      actual = {
        standalone = builtins.attrNames standalone.engine;
        emptyParent = builtins.attrNames emptyParent.engine;
      };
    }
    {
      # `builtins.attrNames` alone forces no value, and `builtins.length` forces no element. So
      # each leaf gets its own read here.
      name = "every leaf of the settings value forces";
      expected = {
        sections = [
          "engine"
          "network"
        ];
        engine = [
          "hooks_dir"
          "init_path"
        ];
        cniPluginDirs = [ true ];
        initPath = true;
      };
      actual = {
        sections = builtins.attrNames withParent;
        engine = builtins.attrNames withParent.engine;
        cniPluginDirs = map (dir: lib.hasSuffix "/bin" dir) withParent.network.cni_plugin_dirs;
        initPath = lib.hasSuffix "/bin/catatonit" withParent.engine.init_path;
      };
    }
    {
      # The universal tree renders the file through `rootlessSettings`. A copy of the den check's
      # path assertion: `~` here alone would pass every other check, and fail every rootless
      # command on the host.
      name = "the rendered storage.conf names the expanded per-user store";
      expected = {
        graphroot = true;
        runroot = true;
        driver = true;
        noLiteralTilde = true;
        noSystemStore = true;
      };
      actual = {
        graphroot = lib.hasInfix ''graphroot = "$HOME/.local/share/containers/storage"'' rootlessStorage;
        runroot = lib.hasInfix ''runroot = "$XDG_RUNTIME_DIR/containers"'' rootlessStorage;
        driver = lib.hasInfix ''driver = "overlay"'' rootlessStorage;
        noLiteralTilde = !(lib.hasInfix ''= "~'' rootlessStorage);
        noSystemStore = !(lib.hasInfix "/var/lib/containers" rootlessStorage);
      };
    }
    {
      # c/storage merges every `*.conf` of every `storage.conf.d` on the search path in file-name
      # order, last writer wins per key. `99-user.conf` is what beats the NixOS
      # `/etc/containers/storage.conf.d/00-nixos.conf`, which names the root-only store; without
      # it the engine reads `/var/lib/containers/storage` there.
      name = "the rendered user storage drop-in names the expanded per-user store";
      expected = {
        graphroot = true;
        runroot = true;
        driver = true;
        noSystemStore = true;
      };
      actual = {
        graphroot = lib.hasInfix ''graphroot = "$HOME/.local/share/containers/storage"'' rootlessStorageDropin;
        runroot = lib.hasInfix ''runroot = "$XDG_RUNTIME_DIR/containers"'' rootlessStorageDropin;
        driver = lib.hasInfix ''driver = "overlay"'' rootlessStorageDropin;
        noSystemStore = !(lib.hasInfix "/var/lib/containers" rootlessStorageDropin);
      };
    }
    {
      # A root Home Manager profile renders nothing, so the privileged engine keeps
      # `/var/lib/containers/storage` and `/run/containers/storage`. Every container file is
      # checked, not only the drop-in: `containers.conf` and `storage.conf` redirect it too.
      name = "a root home profile renders no container file";
      expected = [ ];
      actual = builtins.attrNames rootHome.xdg.configFile;
    }
    {
      # `null` is the oams shape: the home dataset is already persistent, so no write and no
      # stray bucket. A recursion in the shared module would fail here rather than answer.
      name = "rootlessPersistBase null writes no persist bucket";
      expected = {
        buckets = [ ];
        directories = [ ];
        guardPasses = true;
      };
      actual = persistBuckets persistNull;
    }
    {
      name = "rootlessPersistBase usr/data writes exactly the home-relative store";
      expected = {
        buckets = [ "usr/data" ];
        directories = [ ".local/share/containers" ];
        guardPasses = true;
      };
      actual = persistBuckets persistUsrData;
    }
    {
      # A typo creates a bucket that no `kdn.disks.base` declares, and `preservation.preserveAt`
      # is built from the base names, so the store silently stops being preserved. The value is
      # still unknown before activation, hence the assertion rather than a type.
      name = "a bucket that kdn.disks.base does not declare fails the assertion";
      expected = true;
      actual = !(persistBuckets persistTypo).guardPasses;
    }
  ];
in
{
  checks = {
    universal-eval-keepassxc = mkCheck "keepassxc" keepassAssertions;
    universal-eval-containers = mkCheck "containers" containersAssertions;
  };
}
