# Topology-aware remote SSH access slot (host connectivity graph).
#
# The option schema lives with the package (packages/kdn-ssh-access/module.nix) and is reused here
# via the self-input path (see `configModule` below); this slot only adds `enable` + `package` and
# wires the targets. The configured binary comes from `pkgs.kdn.kdn-ssh-access.withConfig` and
# carries `.sshConfig` / `.accessConfig` derivations.
#
# Emits: `home` (~/.ssh drop-in + binary on PATH) and `devenv` (`ssh-access` shim).
# Slots-standalone: uses only `lib`/`pkgs`/`config`/`inputs`.
{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.ssh-access;
  # Reference the schema with a relative path literal, so the evaluation reads one file and not
  # the whole repository tree. `modules/den/aspects/ssh-access.nix` reads the same file the same
  # way.
  # Note: do NOT use `pkgs.…configModule` here — `pkgs` is config-derived and this is an option
  # *type*, which would be an infinite recursion.
  configModule = ../../../packages/kdn-ssh-access/module.nix;

  sshAccessShim = pkgs.writeShellScriptBin "ssh-access" ''
    exec ${cfg.package}/bin/kdn-ssh-access ssh "$@"
  '';
in
{
  options.kdn.ssh-access = lib.mkOption {
    default = { };
    description = "Topology-aware remote SSH access (host graph). Schema: kdn-ssh-access/module.nix.";
    type = lib.types.submoduleWith {
      modules = [
        configModule
        (
          { config, ... }:
          {
            options.enable = lib.mkEnableOption "topology-aware remote SSH access (kdn-* host graph)";
            options.package = lib.mkOption {
              type = lib.types.package;
              description = "Configured kdn-ssh-access binary (carries `.sshConfig` / `.accessConfig`).";
              defaultText = lib.literalExpression "pkgs.kdn.kdn-ssh-access.withConfig { … }";
              default =
                lib.throwIf (config.errors != [ ])
                  ("kdn.ssh-access: invalid edges:\n  " + lib.concatStringsSep "\n  " config.errors)
                  (
                    pkgs.kdn.kdn-ssh-access.withConfig {
                      inherit (config)
                        defaults
                        identityAgentPatterns
                        uplinks
                        hosts
                        ;
                    }
                  );
            };
          }
        )
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      home.file.".ssh/config.d/40-kdn-ssh-access.config".source = cfg.package.sshConfig;
      home.packages = [ cfg.package ];
    };
    devenv = {
      packages = [
        cfg.package
        sshAccessShim
      ];
    };
  };
}
