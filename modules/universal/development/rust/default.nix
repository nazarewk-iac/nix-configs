{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.development.rust = {
            enable = lib.mkEnableOption "Rust development";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.development.rust;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            programs.helix.extraPackages = with pkgs; [
              rust-analyzer
              lldb
            ];
          }));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.development.rust;
        in {

          config = lib.mkIf cfg.enable {
            home-manager.sharedModules = [{kdn.development.rust.enable = true;}];
            environment.systemPackages = with pkgs; [
              #cargo
              #rustc
              rustup
              #rust-analyzer # duplicated by rustup
              pkg-config
            ];
          };
        }
      )
    )
  ];
}
