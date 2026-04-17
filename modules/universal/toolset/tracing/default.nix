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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifTypes [ "nixos" ] {
        kdn.env.packages = with pkgs; [
          bpftrace
        ];

        programs.bcc.enable = true; # opensnoop
      })
    ]
  );
}
