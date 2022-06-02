{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.programs.gnupg;
in
{
  imports = [
    ./forwarding
  ];

  options.nazarewk.programs.gnupg = {
    enable = mkEnableOption "GnuPG forwarding to remote systems";
  };

  config = mkIf cfg.enable {
    services.pcscd.enable = true;
    programs.gnupg.agent.enable = true;
    programs.gnupg.agent.enableExtraSocket = true;
  };
}
