{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.golang;
in
{
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      go_1_19
      gccgo
      delve
      goreleaser
      golangci-lint # for netbird
    ];
  };
}
