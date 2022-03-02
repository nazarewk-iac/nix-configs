{ lib, pkgs, config, flakeInputs, ... }:
with lib;
let
  cfg = config.nazarewk.desktop.base;
in {
  options.nazarewk.desktop.base = {
    enable = mkEnableOption "Desktop base setup";
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      flakeInputs.nixpkgs-wayland.overlay

      (self: super: {
        wlroots = super.wlroots.overrideAttrs (old: {
          src = super.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "wlroots";
            repo = "wlroots";
            # report: https://github.com/swaywm/sway/issues/6856
            # overriden version: https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/3469/commits
            rev = "15008750db82115fbdcf77d1fccbde9a91d70a06";
            sha256 = "sha256-T3LhUaczQVp0mj/vKpxRb7PLwZk0iEsejOqSWtQMw8k=";
          };
        });
      })
    ];

    fonts.fonts = with pkgs; [
      cantarell-fonts
      font-awesome
      nerdfonts
      noto-fonts
      noto-fonts-emoji
      noto-fonts-emoji-blob-bin
      noto-fonts-extra
    ];

    environment.systemPackages = with pkgs; [
      qt5.qtwayland
      qt5Full

      xorg.xeyes
      xlibs.xhost

      # audio
      libopenaptx
      libfreeaptx
      pulseaudio
    ];
  };
}
