{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.golang;
in
{
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      go_1_20
      go_1_19
      #gccgo
      delve
      goreleaser
      golangci-lint # for netbird
    ];
    home-manager.sharedModules = [{ kdn.development.jetbrains.go.enable = true; }];
  };
}
