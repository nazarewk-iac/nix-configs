{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.profile.machine.dev;
in
{
  options.kdn.profile.machine.dev = {
    enable = lib.mkEnableOption "enable dev machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.desktop.enable = true;

    environment.systemPackages = with pkgs; [
      #jetbrains.pycharm-professional
      jetbrains.idea-ultimate
      jetbrains-toolbox
      #jetbrains.clion
      #jetbrains.goland
      #jetbrains.ruby-mine
    ];
    home-manager.sharedModules = [{ services.jetbrains-remote.enable = true; }];

    kdn.development.cloud.enable = true;
    kdn.development.cloud.aws.enable = true;
    kdn.development.cloud.azure.enable = true;
    kdn.development.data.enable = true;
    kdn.development.db.mysql.enable = true;
    kdn.development.elixir.enable = true;
    kdn.development.golang.enable = true;
    kdn.development.java.enable = true;
    kdn.development.k8s.enable = true;
    kdn.development.nix.enable = true;
    kdn.development.python.enable = true;
    kdn.development.ruby.enable = true;
    kdn.development.rust.enable = true;
    kdn.development.terraform.enable = true;
    kdn.programs.aws-vault.enable = true;
    services.plantuml-server.enable = true;
  };
}
