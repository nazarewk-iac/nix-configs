{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.rust;
in
{
  options.kdn.development.rust = {
    enable = lib.mkEnableOption "Rust development";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{ kdn.development.rust.enable = true; }];
    environment.systemPackages = with pkgs; [
      #cargo
      #rustc
      rustup
      #rust-analyzer # duplicated by rustup
      pkg-config
    ];
  };
}
