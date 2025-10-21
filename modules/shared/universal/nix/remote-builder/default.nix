{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.nix.remote-builder;
in
{
  options.kdn.nix.remote-builder = {
    enable = lib.mkEnableOption "remote builder config";

    use = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.user.ssh.IdentityFile != null;
    };

    name = lib.mkOption {
      type = with lib.types; str;
      readOnly = true;
      default = "kdn-nix-remote-build";
    };
    description = lib.mkOption {
      type = with lib.types; str;
      default = "kdn's remote Nix builder";
    };

    user.id = lib.mkOption {
      type = with lib.types; int;
      readOnly = true;
      default = 25839;
    };
    user.name = lib.mkOption {
      type = with lib.types; str;
      readOnly = true;
      default = cfg.name;
    };
    user.ssh.IdentityFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    group.name = lib.mkOption {
      type = with lib.types; str;
      readOnly = true;
      default = cfg.name;
    };
    group.id = lib.mkOption {
      type = with lib.types; int;
      readOnly = true;
      default = cfg.user.id;
    };
  };
}
