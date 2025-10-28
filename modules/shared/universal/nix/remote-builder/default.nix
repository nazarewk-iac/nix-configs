{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.nix.remote-builder;
in {
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

    localhost.enable = lib.mkOption {
      description = "a `localhost` hacky builder to allow building locally";
      type = with lib.types; bool;
      default = cfg.localhost.publicHostKey != "";
    };
    localhost.sshUser = lib.mkOption {
      type = with lib.types; str;
      default = cfg.user.name;
    };
    # TODO: find out how and generate this key
    localhost.publicHostKey = lib.mkOption {
      type = with lib.types; str;
      default = "";
    };
    localhost.hostName = lib.mkOption {
      type = with lib.types; str;
      default = "localhost";
    };

    localhost.protocol = lib.mkOption {
      type = with lib.types; str;
      default = "ssh-ng";
    };

    localhost.maxJobs = lib.mkOption {
      type = with lib.types; int;
      default = 2;
    };
    localhost.speedFactor = lib.mkOption {
      type = with lib.types; int;
      default = 1;
    };
    localhost.systems = lib.mkOption {
      type = with lib.types; listOf str;
      default = [pkgs.stdenv.system];
    };
    localhost.supportedFeatures = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
    };
    localhost.mandatoryFeatures = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
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
