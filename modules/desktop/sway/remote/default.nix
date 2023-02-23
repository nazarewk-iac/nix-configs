{ lib, pkgs, config, waylandPkgs, ... }:
with lib;
let
  cfg = config.kdn.sway.remote;

  sway-headless-vnc = pkgs.writeShellApplication {
    name = "sway-headless-vnc";
    runtimeInputs = with pkgs; [ wayvnc jq sway coreutils findutils ];
    text = builtins.readFile ./sway-headless-vnc.sh;
  };
in
{
  options.kdn.sway.remote = {
    enable = lib.mkEnableOption "remote access setup for Sway";
  };

  config = lib.mkIf cfg.enable {
    kdn.sway.base.enable = true;

    nixpkgs.overlays = [
      (final: prev:
        {
          wayvnc = waylandPkgs.wayvnc;
        })
    ];

    # Multi-output directions:
    # - https://www.reddit.com/r/swaywm/comments/k1zl41/thank_you_devs_free_ipad_repurposed_as_a_second/
    # - https://github.com/swaywm/sway/issues/5553
    # - https://wiki.archlinux.org/title/Sway#Create_headless_outputs
    environment.systemPackages = with pkgs; [
      wayvnc
      waypipe

      sway-headless-vnc

      remmina # cannot type $ (dollar sign)
      tigervnc # vncviewer 10.100.0.2::5900
      # realvnc-vnc-viewer  # doesn't pass/locks up on left alt key combinations
      # turbovnc  # Algorithm negotiation fails
    ];
  };
}
