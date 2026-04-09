{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.rust;
in
{
  options.kdn.development.rust = {
    enable = lib.mkEnableOption "Rust development";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        programs.helix.extraPackages = with pkgs; [
          rust-analyzer
          lldb
        ];
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.development.rust.enable = true; } ];
        environment.systemPackages = with pkgs; [
          #cargo
          #rustc
          rustup
          #rust-analyzer # duplicated by rustup
          pkg-config
        ];
      }
    ))
  ];
}
