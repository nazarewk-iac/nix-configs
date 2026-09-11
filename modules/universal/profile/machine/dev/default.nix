{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.profile.machine.dev;
in
{
  options.kdn.profile.machine.dev = {
    enable = lib.mkEnableOption "enable dev machine profile";

    /*
      The three switches below split one bundle into one concern per switch.

      One profile used to turn on 18 language toolchains, a desktop and a container runtime
      together. An adopter who wants the desktop but no container runtime had to write one `false`
      per item. Each group now carries one switch, and every per-item switch below it stays.

      Each default is `true`, the value this repository uses today. A `true` default costs nothing
      when `enable` is `false`, because the whole `config` sits behind `enable`. An adopter writes a
      plain `false`, which wins over the `mkDefault` forward into Home Manager.
    */
    languages.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Turn on the language and cloud toolchains of this profile.";
    };
    containers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Turn on the container runtime of this profile.";
    };
    desktop.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Turn on the desktop machine profile from this profile.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.profile.machine.dev = lib.mkDefault cfg; } ];
      })
      {
        kdn.env.packages = with pkgs; [
        ];

        kdn.toolset.ide.enable = lib.mkDefault true;
        kdn.toolset.mikrotik.enable = lib.mkDefault (
          pkgs.stdenv.hostPlatform.isx86 && config.kdn.desktop.enable
        );
      }
      (lib.mkIf cfg.desktop.enable {
        kdn.profile.machine.desktop.enable = lib.mkDefault true;
      })
      (lib.mkIf cfg.languages.enable {
        kdn.development.ansible.enable = lib.mkDefault true;
        kdn.development.cloud.aws.enable = lib.mkDefault true;
        kdn.development.cloud.azure.enable = lib.mkDefault false;
        kdn.development.cloud.enable = lib.mkDefault true;
        kdn.development.data.enable = lib.mkDefault true;
        kdn.development.db.enable = lib.mkDefault true;
        kdn.development.documents.enable = lib.mkDefault true;
        kdn.development.elixir.enable = lib.mkDefault true;
        kdn.development.golang.enable = lib.mkDefault true;
        kdn.development.java.enable = lib.mkDefault true;
        kdn.development.k8s.enable = lib.mkDefault true;
        kdn.development.nickel.enable = lib.mkDefault true;
        kdn.development.nix.enable = lib.mkDefault true;
        kdn.development.python.enable = lib.mkDefault true;
        kdn.development.rpi.enable = lib.mkDefault true;
        kdn.development.rust.enable = lib.mkDefault true;
        kdn.development.terraform.enable = lib.mkDefault true;
        kdn.development.web.enable = lib.mkDefault true;
      })
      (lib.mkIf cfg.containers.enable {
        kdn.virtualisation.containers.enable = lib.mkDefault true;
        kdn.virtualisation.containers.podman.enable = lib.mkDefault true;
      })
    ]
  );
}
