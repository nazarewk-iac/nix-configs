{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.desktop.sway.remote;
in
{
  options.kdn.desktop.sway.remote = {
    enable = lib.mkEnableOption "remote access setup for Sway";
  };

  config = lib.mkIf cfg.enable {
    kdn.desktop.sway.enable = true;

    # Multi-output directions:
    # - https://www.reddit.com/r/swaywm/comments/k1zl41/thank_you_devs_free_ipad_repurposed_as_a_second/
    # - https://github.com/swaywm/sway/issues/5553
    # - https://wiki.archlinux.org/title/Sway#Create_headless_outputs
    environment.systemPackages = with pkgs; [
      wayvnc
      waypipe

      pkgs.kdn.sway-vnc

      remmina # cannot type $ (dollar sign)
      tigervnc # vncviewer 10.100.0.2::5900
      # realvnc-vnc-viewer  # doesn't pass/locks up on left alt key combinations
      # turbovnc  # Algorithm negotiation fails
    ];
  };
}
