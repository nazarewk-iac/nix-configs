{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.linux-utils;
in
{
  options.nazarewk.development.linux-utils = {
    enable = mkEnableOption "linux utils";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      socat
      (pkgs.writeShellApplication {
        name = "get-proc-env";
        runtimeInputs = with pkgs; [ jq ];
        text = ''
          jq -R 'split("\u0000") | map(split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries' "/proc/$1/environ"
        '';
      })
    ];
  };
}
