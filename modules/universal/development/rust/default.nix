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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          #cargo
          #rustc
          rustup
          #rust-analyzer # duplicated by rustup
          pkg-config
        ];
      }
      (kdnConfig.util.ifHM {
        programs.helix.extraPackages = with pkgs; [
          rust-analyzer
          lldb
        ];
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        home-manager.sharedModules = [ { kdn.development.rust.enable = true; } ];
      })
    ]
  );
}
