# litestream inspired by https://github.com/NixOS/nixpkgs/blob/2726f127c15a4cc9810843b96cad73c7eb39e443/nixos/modules/services/network-filesystems/litestream/default.nix
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.atuin;
in {
  options.kdn.programs.atuin = {
    enable = lib.mkEnableOption "Atuin shell history management and sync";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.atuin.enable = true;
      programs.atuin.settings = {
        auto_sync = true;
        update_check = false;
        sync_frequency = "60";
        daemon = {
          enabled = true;
          sync_frequency = 300;
        };
      };
      xdg.configFile."atuin/config.toml".force = true;
    }
    (lib.mkIf (config.home.username != "root") {
      systemd.user.services.atuind = {
        Unit = {
          Description = "Atuin shell history synchronization daemon";
          After = [
            "network.target"
          ];
          Wants = [
            "network.target"
          ];
          Requires = [
          ];
        };
        Service.ExecStart = "${lib.getExe config.programs.atuin.package} daemon";
        Service.Slice = "background.slice";
        Service.Environment = [
          "ATUIN_LOG=info"
        ];
        Install.WantedBy = ["default.target"];
      };
    })
  ]);
}
