{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.desktop.kde;
in
{
  options.kdn.desktop.kde = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      apply = value: value && config.kdn.desktop.enable;
    };
    theme = lib.mkOption {
      type = with lib.types; str;
      default = "kde6";
    };
    style = lib.mkOption {
      type = with lib.types; str;
      default = "breeze";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home-manager.sharedModules = [ { kdn.desktop.kde.enable = cfg.enable; } ]; }
      {
        services.desktopManager.plasma6.enable = true;
        services.displayManager.defaultSession = "plasma";
      }
      {
        # conflicts with seahorse https://github.com/NixOS/nixpkgs/blob/898cb2064b6e98b8c5499f37e81adbdf2925f7c5/nixos/modules/programs/seahorse.nix#L34
        programs.ssh.askPassword = "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";
        services.gnome.gnome-keyring.enable = lib.mkForce false;
      }
      {
        qt.enable = true;
        qt.platformTheme = lib.mkForce cfg.theme;
        qt.style = lib.mkForce cfg.style;

        home-manager.sharedModules = [
          {
            # see https://github.com/nix-community/home-manager/issues/5098#issuecomment-2352172073
            qt.enable = true;
            qt.platformTheme.package = with pkgs.kdePackages; [
              plasma-integration
              # I don't remember why I put this is here, maybe it fixes the theme of the system setttings
              systemsettings
            ];
            qt.style.package = pkgs.kdePackages.breeze;
            qt.style.name = lib.mkForce cfg.style;
            systemd.user.sessionVariables.QT_QPA_PLATFORMTHEME = lib.mkForce cfg.theme;
          }
        ];

        # see https://discourse.nixos.org/t/kde-widgets-look-off-on-a-freshly-installed-nixos/13098
        environment.systemPackages = with pkgs.kdePackages; [
          qqc2-breeze-style
          qqc2-desktop-style
        ];
        environment.sessionVariables.QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";
      }
    ]
  );
}
