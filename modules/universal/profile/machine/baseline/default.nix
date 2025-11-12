{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.profile.machine.baseline;
in {
  options.kdn.profile.machine.baseline = {
    enable = lib.mkEnableOption "baseline machine profile for server/non-interactive use";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.enable = true;
        kdn.locale.enable = true;
        kdn.profile.user.kdn.enable = true;
      }
      {
        kdn.env.packages = with pkgs; [
          git
          bash
          curl

          nix-derivation # pretty-derivation
          nix-output-monitor
          nix-du
          nix-tree
          pkgs.kdn.kdn-nix
        ];
      }
    ]
  );
}
