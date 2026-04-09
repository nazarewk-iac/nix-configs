{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.tracing;
in
{
  options.kdn.toolset.tracing = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      programs.bcc.enable = true; # opensnoop
      environment.systemPackages = with pkgs; [
        bpftrace
      ];
    }
  );
}
