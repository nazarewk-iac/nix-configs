{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.tracing;
in {
  options.kdn.toolset.tracing = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # bpftrace # TODO: 2025-01-03 fails to build https://github.com/NixOS/nixpkgs/issues/368727
      bcc # opensnoop
    ];
  };
}
