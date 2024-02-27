{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.terraform;
in
{
  options.kdn.development.rust = {
    enable = lib.mkEnableOption "Rust development";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs;[
      rust-analyzer
      lldb_15
    ];
  };
}
