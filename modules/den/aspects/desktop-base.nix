# The base graphical desktop, as a den aspect. It ports the `desktop/base` module of the old tree.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It states the opinions that every graphical machine of this repository shares: SDDM is the display
# manager, a font set is installed, the freedesktop services run, and the portal is on. It also
# installs one terminal and one launcher configuration for the user.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module carries three halves. Two of them sit behind a system-kind guard (`nixos`, and
# `nixos` plus `darwin`), and the third reaches the user through the Home Manager bridge. den
# partitions an aspect by scope, so the user half becomes a real `homeManager` target. A den host
# therefore includes this aspect twice: once in the host aspect and once in the user aspect.
#
# ## What the port changes
#
# 1. **The desktop flag becomes `kdn.graphical`.** The old module keys everything on a desktop
#    `enable` flag. A den aspect has no `enable`, so inclusion is the switch, and this aspect sets
#    `kdn.graphical = lib.mkDefault true` for the aspects that read it.
# 2. **The native option replaces the cross-platform package list.** The `nixos` and the `darwin`
#    target write `environment.systemPackages`; the `homeManager` target writes `home.packages`. The
#    old module writes one shared list that lands in all three at once, so the two calculator
#    packages now sit in the system list only. The drop filter moves to ../common/filter-packages.nix.
# 3. **Two forward writes become plain nixpkgs options.** The old module turns on two wrapper
#    options of the old tree for dconf and for ydotool. nixpkgs declares `programs.dconf.enable` and
#    `programs.ydotool.enable` itself, so this aspect writes those directly.
# 4. **The theme-file overrides become an option.** The old module forces four GTK files and the
#    GTK 2 configuration, so that its own theme generator wins. Home Manager needs a `source` or a
#    `text` for every file it manages, so a bare consumer that forces a file it never defines fails
#    to evaluate. `kdn.desktop-base.forceThemeFiles` carries the opinion, and it is `false` by
#    default. A consumer that runs a theme generator sets it to `true`.
# 5. **The Linux-only user half gets a platform guard.** The old module reaches that half through a
#    "Home Manager under a NixOS parent" guard. den has no such guard, so the target reads
#    `pkgs.stdenv.hostPlatform.isLinux` instead. Every package in that half is Wayland-only, and
#    nixpkgs refuses each one at evaluation time on `aarch64-darwin` — measured 2026-09-11 for
#    `wofi`, `ydotool` and `wl-clipboard`.
# 6. **The aspect names its own portal backend.** The old module turns the portal on and names no
#    backend, and nixpkgs asserts that the backend list is not empty. The old sway module fills the
#    list two files away, so a base-only machine depends on the desktop it also installs. An aspect
#    stands alone, so `kdn.desktop-base.portals` holds the list, and it defaults to the GTK backend.
#    That is the same backend the old sway module names.
# 7. **The launcher configuration moves next to this file.** `./desktop-base/wofi-config` is a copy
#    of the old payload file. The name carries no leading dot and no directory, because a file named
#    `config` inside the aspect directory reads better with the tool name in front.
#
# ## One measured dead branch, kept as it is
#
# The old font list appends every `pkgs.nerd-fonts` entry that holds a `caskName` attribute. No
# entry holds one: 0 of 75 on `x86_64-linux` and 0 of 75 on `aarch64-darwin`, measured 2026-09-11.
# So the append contributes nothing today. The port keeps the expression, because a nixpkgs change
# can revive it and a drop would then change behaviour in silence.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The one option. Every target imports this module, so an adopter states one opinion and all three
  # classes read it.
  declaration =
    { lib, ... }:
    {
      options.kdn.desktop-base.forceThemeFiles = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Overwrite the GTK 2, GTK 3 and GTK 4 configuration files with no backup.

          The old module sets the same five flags unconditionally, so that its own theme generator
          wins over a file another module wrote. Home Manager demands a `source` or a `text` for
          every file it manages, so a consumer that forces a file it never defines fails to
          evaluate. Turn this on together with a theme generator that defines all four files.
        '';
      };
    };

  fontPackages =
    { lib, pkgs, ... }:
    with pkgs;
    [
      cantarell-fonts
      font-awesome
      noto-fonts
      noto-fonts-color-emoji
      noto-fonts-monochrome-emoji
      noto-fonts-emoji-blob-bin

      dejavu_fonts
      ubuntu-classic
    ]
    # Measured 2026-09-11: no `pkgs.nerd-fonts` entry holds `caskName`, so this appends nothing
    # today. See the header.
    ++ lib.pipe pkgs.nerd-fonts [
      builtins.attrValues
      (builtins.filter (e: e ? caskName))
    ];

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [
        declaration
        ../common/graphical.nix
      ];

      # `xdg.portal.enable` needs a backend: nixpkgs asserts `extraPortals != [ ]`
      # (`<nixpkgs>/nixos/modules/config/xdg/portal.nix:134-139`). The old tree meets that assertion
      # two files away, in its sway module, so a base-only machine relies on the desktop it also
      # installs. An aspect stands alone, so this one names its own backend. See change 6 in the
      # header.
      options.kdn.desktop-base.portals = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ pkgs.xdg-desktop-portal-gtk ];
        defaultText = lib.literalExpression "[ pkgs.xdg-desktop-portal-gtk ]";
        description = ''
          The XDG desktop portal backends of this machine.

          The GTK backend serves every interface that a plain desktop needs. A desktop aspect can
          add its own backend: the KDE aspect of nixpkgs adds the KDE one on its own, and the sway
          route adds the wlroots one.
        '';
      };

      config = lib.mkMerge [
        {
          kdn.graphical = lib.mkDefault true;

          environment.systemPackages = filterPackages (
            with pkgs;
            [
              qalculate-qt
              libqalculate
            ]
          );

          fonts.packages = filterPackages (fontPackages {
            inherit lib pkgs;
          });
          fonts.fontDir.enable = true;
          gtk.iconCache.enable = true;

          programs.dconf.enable = lib.mkDefault true;
        }
        {
          services.displayManager.sddm.enable = true;
          services.displayManager.sddm.settings.Users.MaximumUid = config.ids.uids.nobody - 1;
          services.displayManager.sddm.wayland.enable = true;
          services.displayManager.sddm.theme = "chili";
          environment.systemPackages = filterPackages (
            with pkgs;
            [
              sddm-chili-theme
            ]
          );
        }
        {
          hardware.uinput.enable = true;
          programs.ydotool.enable = lib.mkDefault true;
          programs.wshowkeys.enable = true;
          services.accounts-daemon.enable = true;
          services.dleyna.enable = true;
          services.gvfs.enable = true;
          services.power-profiles-daemon.enable = true;
          services.udisks2.enable = true;
          services.upower.enable = config.powerManagement.enable;
          services.xserver.enable = true;
          services.xserver.updateDbusEnvironment = true;
          xdg.icons.enable = true;
          xdg.mime.enable = true;

          environment.systemPackages = filterPackages (
            with pkgs;
            [
              xeyes
              xhost
              xlsclients
              libva-utils
              brightnessctl
              gsettings-desktop-schemas
              lxappearance
              xsettingsd
              dex
              evtest
              libinput
              v4l-utils
              wev
              ashpd-demo
              grim
              libnotify
              libsecret
              wayland-utils
              wl-clipboard
              wl-clipboard-x11
              hicolor-icon-theme
              glib
              bustle
              sound-theme-freedesktop
            ]
            ++ (with pkgs.kdePackages; [
              okular
              ark
              gwenview
              pix
            ])
          );

          xdg.portal.enable = true;
          xdg.portal.xdgOpenUsePortal = true;
          xdg.portal.extraPortals = filterPackages config.kdn.desktop-base.portals;
        }
        {
          services.gnome.glib-networking.enable = true;

          environment.systemPackages = filterPackages (
            with pkgs;
            [
              nemo-with-extensions
              nemo-fileroller
              gtk3.out
              xdg-user-dirs
              desktop-file-utils
            ]
          );
          services.dbus.packages = with pkgs; [
            nemo-with-extensions
          ];
        }
      ];
    };

  # nix-darwin declares `fonts.packages` and `environment.systemPackages`, and it declares none of
  # the freedesktop services above. So the darwin half holds the fonts and the two calculators.
  darwinTarget =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [
        declaration
        ../common/graphical.nix
      ];

      config = {
        fonts.packages = filterPackages (fontPackages {
          inherit lib pkgs;
        });

        environment.systemPackages = filterPackages (
          with pkgs;
          [
            qalculate-qt
            libqalculate
          ]
        );
      };
    };

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-base;
    in
    {
      imports = [
        declaration
        ../common/graphical.nix
      ];

      config = lib.mkMerge [
        {
          programs.wezterm.enable = true;
          programs.wezterm.extraConfig = lib.mkMerge [
            (lib.mkOrder 1 ''
              local wezterm = require 'wezterm'
              local config = wezterm.config_builder()
            '')
            ''
              config.front_end = "OpenGL"
              config.hide_tab_bar_if_only_one_tab = true
              config.enable_kitty_keyboard = true
            ''
            (lib.mkOrder 9999 "return config")
          ];
        }
        # Every package below is Wayland-only, and nixpkgs refuses each one on a darwin platform at
        # evaluation time. See change 5 in the header.
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          xdg.configFile."wofi/config".source = ./desktop-base/wofi-config;

          home.packages = [
            (pkgs.writeShellApplication {
              name = "ydotool-paste";
              runtimeInputs = with pkgs; [
                ydotool
                wl-clipboard
              ];
              text = ''
                sleep "''${1:-0.5}"
                wl-paste --no-newline | ydotool type --file=-
              '';
            })
          ];

          programs.foot.enable = true;
          programs.foot.server.enable = false;
          programs.foot.settings.main.dpi-aware = "no";
          programs.foot.settings.scrollback.lines = 100000;
        })
        (lib.mkIf cfg.forceThemeFiles {
          gtk.gtk2.force = true;
          xdg.configFile."gtk-3.0/gtk.css".force = true;
          xdg.configFile."gtk-3.0/settings.ini".force = true;
          xdg.configFile."gtk-4.0/gtk.css".force = true;
          xdg.configFile."gtk-4.0/settings.ini".force = true;
        })
      ];
    };
in
{
  kdn.desktop-base.nixos = nixosTarget;
  kdn.desktop-base.darwin = darwinTarget;
  kdn.desktop-base.homeManager = homeTarget;
}
