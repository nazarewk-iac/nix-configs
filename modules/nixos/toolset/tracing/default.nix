{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.toolset.tracing;
in
{
  options.kdn.toolset.tracing = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkIf cfg.enable {
    programs.bcc.enable = true; # opensnoop
    environment.systemPackages = with pkgs; [
      bpftrace
    ];
  };
}
