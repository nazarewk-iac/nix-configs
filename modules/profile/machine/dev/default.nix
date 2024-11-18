{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.profile.machine.dev;
in {
  options.kdn.profile.machine.dev = {
    enable = lib.mkEnableOption "enable dev machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.desktop.enable = true;

    environment.systemPackages = with pkgs; [
      jose # JSON Web Token tool, https://github.com/latchset/jose
    ];

    home-manager.sharedModules = [{kdn.development.jetbrains.enable = true;}];
    kdn.development.ansible.enable = true;
    kdn.development.cloud.aws.enable = true;
    kdn.development.cloud.azure.enable = false;
    kdn.development.cloud.enable = true;
    kdn.development.data.enable = true;
    kdn.development.db.enable = true;
    kdn.development.documents.enable = true;
    kdn.development.elixir.enable = true;
    kdn.development.golang.enable = true;
    kdn.development.java.enable = true;
    kdn.development.k8s.enable = true;
    kdn.development.nickel.enable = true;
    kdn.development.nix.enable = true;
    kdn.development.python.enable = true;
    kdn.development.rpi.enable = true;
    kdn.development.rust.enable = true;
    kdn.development.terraform.enable = true;
    kdn.development.web.enable = true;
    kdn.programs.aws-vault.enable = true;
    services.plantuml-server.enable = false; # TODO: fix this?
  };
}
