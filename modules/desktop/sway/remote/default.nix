{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.sway.remote;
in {
  options.nazarewk.sway.remote = {
    enable = mkEnableOption "remote access setup for Sway";
  };

  config = mkIf cfg.enable {
    nazarewk.sway.base.enable = true;

    # Multi-output directions:
    # - https://www.reddit.com/r/swaywm/comments/k1zl41/thank_you_devs_free_ipad_repurposed_as_a_second/
    # - https://github.com/swaywm/sway/issues/5553
    # - https://wiki.archlinux.org/title/Sway#Create_headless_outputs
    environment.systemPackages = with pkgs; [
      wayvnc
      waypipe

      remmina
      # didn't build on 2022-04-25
      #tigervnc
    ];
  };
}
