{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.linux-utils;
in
{
  options.kdn.development.linux-utils = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      socat
      arp-scan
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
