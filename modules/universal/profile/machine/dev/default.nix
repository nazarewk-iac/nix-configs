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
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.profile.machine.dev = lib.mkDefault cfg; } ];
      })
      {
        kdn.env.packages = with pkgs; [
          jose # JSON Web Token tool, https://github.com/latchset/jose
        ];

        kdn.profile.machine.desktop.enable = lib.mkDefault true;
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
        kdn.development.llm.online.enable = lib.mkDefault true;
        kdn.development.nickel.enable = lib.mkDefault true;
        kdn.development.nix.enable = lib.mkDefault true;
        kdn.development.python.enable = lib.mkDefault true;
        kdn.development.rpi.enable = lib.mkDefault true;
        kdn.development.rust.enable = lib.mkDefault true;
        kdn.development.terraform.enable = lib.mkDefault true;
        kdn.development.web.enable = lib.mkDefault true;
        kdn.toolset.ide.enable = lib.mkDefault true;
        kdn.toolset.mikrotik.enable = lib.mkDefault (
          pkgs.stdenv.hostPlatform.isx86 && config.kdn.desktop.enable
        );
      }
    ]
  );
}
