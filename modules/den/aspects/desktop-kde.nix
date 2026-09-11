# The KDE Plasma 6 desktop, as a den aspect. It ports the `desktop/kde` module of the old tree.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on Plasma 6, it makes Plasma the default session, and it points every Qt program at the
# Breeze style. It also turns off the GNOME keyring, because Plasma brings its own wallet.
#
# ## Class list: `nixos` and `homeManager`
#
# The old module carries a NixOS half and a Home Manager half, and the NixOS half pushes the second
# one down through the bridge. den partitions by scope, so both halves become real targets. A den
# host includes this aspect twice: once in the host aspect and once in the user aspect.
#
# Plasma is Linux-only, so this aspect declares no `darwin` target.
#
# ## What the port changes
#
# 1. **The inclusion replaces the two `enable` flags.** The old option holds an `apply` that ANDs the
#    desktop flag into the KDE flag, so a host that turns KDE on with the desktop off gets nothing.
#    A den aspect has no `enable`, so the host aspect list carries the same decision.
# 2. **The native options replace the cross-platform ones.** The `nixos` target writes
#    `environment.systemPackages` and `environment.sessionVariables` directly.
# 3. **The user half gets a platform guard.** Every value in it is Linux-only:
#    `pkgs.kdePackages.breeze` refuses to evaluate on `aarch64-darwin`, and Home Manager asserts
#    that `systemd.user.*` needs Linux. Measured 2026-09-11.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The two options. Both targets import this module, so an adopter states one opinion and the
  # NixOS half and the user half read the same value.
  declaration =
    { lib, ... }:
    {
      options.kdn.desktop-kde.theme = lib.mkOption {
        type = lib.types.str;
        default = "kde";
        example = "kde";
        description = ''
          The Qt platform theme name.

          `qt.platformTheme` of nixpkgs is an enum, and it holds no `"kde6"`. The accepted names are
          `gnome`, `gtk2`, `kde`, `lxqt` and `qt5ct`. The `kde` entry already carries the Qt 6
          packages, so `"kde"` is the Plasma 6 value. `"kde6"` stopped the evaluation of every KDE
          host. Measured 2026-09-10.
        '';
      };

      options.kdn.desktop-kde.style = lib.mkOption {
        type = lib.types.str;
        default = "breeze";
        example = "breeze";
        description = ''
          The Qt widget style name. Plasma ships `breeze`.
        '';
      };
    };

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-kde;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [
        declaration
        ../common/graphical.nix
      ];

      config = lib.mkMerge [
        {
          kdn.graphical = lib.mkDefault true;

          services.desktopManager.plasma6.enable = true;
          services.displayManager.defaultSession = "plasma";
        }
        {
          # `programs.ssh.askPassword` conflicts with seahorse. See
          # https://github.com/NixOS/nixpkgs/blob/898cb2064b6e98b8c5499f37e81adbdf2925f7c5/nixos/modules/programs/seahorse.nix#L34
          programs.ssh.askPassword = "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";
          services.gnome.gnome-keyring.enable = lib.mkForce false;
        }
        {
          qt.enable = true;
          qt.platformTheme = lib.mkForce cfg.theme;
          qt.style = lib.mkForce cfg.style;

          # The KDE widgets look wrong without these two. See
          # https://discourse.nixos.org/t/kde-widgets-look-off-on-a-freshly-installed-nixos/13098
          environment.systemPackages = filterPackages (
            with pkgs.kdePackages;
            [
              qqc2-breeze-style
              qqc2-desktop-style
            ]
          );
          environment.sessionVariables.QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";
        }
      ];
    };

  # Every value below is Linux-only, so the whole target sits behind one platform guard. See change
  # 3 in the header.
  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-kde;
    in
    {
      imports = [
        declaration
        ../common/graphical.nix
      ];

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        services.gnome-keyring.enable = lib.mkForce false;

        # See https://github.com/nix-community/home-manager/issues/5098#issuecomment-2352172073
        qt.enable = true;
        qt.platformTheme.package = with pkgs.kdePackages; [
          plasma-integration
          # The reason for this second entry is lost. It probably fixes the theme of the system
          # settings program.
          systemsettings
        ];
        qt.style.package = pkgs.kdePackages.breeze;
        qt.style.name = lib.mkForce cfg.style;
        systemd.user.sessionVariables.QT_QPA_PLATFORMTHEME = lib.mkForce cfg.theme;
      };
    };
in
{
  kdn.desktop-kde.nixos = nixosTarget;
  kdn.desktop-kde.homeManager = homeTarget;
}
