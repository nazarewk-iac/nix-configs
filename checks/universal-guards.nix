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
# | `universal-eval-containers` | `containersConf.settings` of the containers module | the Home Manager branch reads the parent through `osConfig` |
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
        inherit osConfig;
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
  ];
in
{
  checks = {
    universal-eval-keepassxc = mkCheck "keepassxc" keepassAssertions;
    universal-eval-containers = mkCheck "containers" containersAssertions;
  };
}
