{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.disk-encryption.tools;
in
{
  options.kdn.hardware.disk-encryption.tools = {
    enable = lib.mkEnableOption "disk encryption tooling setup";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      fido2luks
      (runCommand "systemd-cryptsetup-bin" { } ''
        mkdir -p $out/bin
        ln -sf ${pkgs.systemd}/lib/systemd/systemd-cryptsetup $out/bin/
      '')
    ];
  };
}