# Tier-1 assertions for the 11 desktop leaf aspects of batch 12.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here builds a system and nothing activates.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `nixosPlain` | `nixos` | the three host aspects together, no consumer opinion |
# | `nixosRemoteOnly` | `nixos` | the remote server aspect alone |
# | `nixosTeamviewer` | `nixos` | the same aspect with the TeamViewer opinion on |
# | `darwinPlain` | `darwin` | the one aspect that emits a `darwin` target |
# | `homePlain` | `homeManager` | all 10 user aspects, on **x86_64-linux** |
# | `homeOpinion` | `homeManager` | four of them, with real consumer opinions |
# | `homeDarwin` | `homeManager` | the same 10, on `aarch64-darwin` |
#
# ## Why this area builds its own Home Manager consumer
#
# `harness.bareHomeConfiguration` uses `aarch64-darwin`, and every program of the sway family is
# Wayland-only. So each `homeManager` target of this batch wraps its config in a Linux guard, and a
# Darwin consumer gets an empty config. `linuxHomeConfiguration` below repeats the same bare shape
# on `x86_64-linux`, so the target bodies really evaluate. `homeDarwin` proves the guard: the
# terminal stays on, and every Wayland program stays off.
#
# ## Why no `drvPath` force
#
# `../tests.nix` already forces every aspect-class pair, so a repeat here would only pay the cost
# twice. The Darwin force of a `homeManager` pair proves nothing about a guarded body, so this file
# reads real values instead, and it reads the `assertions` list of each Linux subject. A failed
# module assertion then prints its own message, which a `drvPath` force does not.
#
# ## What the keybinding assertions can and cannot do
#
# No subject turns sway on: `wayland.windowManager.sway.enable` stays `false`, so Home Manager
# writes no sway configuration file. The assertions read the option values instead. Home Manager
# gives `config.keybindings` a set of `mkOptionDefault` entries, so the map holds more keys than
# this batch declares. So the assertion states that every declared key is present, not that the map
# holds nothing else.
{
  lib,
  inputs,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);
  has = name: packages: lib.elem name (map lib.getName packages);

  # The failed assertions of a subject, by message. An empty list is the pass.
  failedAssertions = subject: map (a: a.message) (lib.filter (a: !a.assertion) subject.assertions);

  desktopNames = [
    "desktop-base"
    "desktop-kde"
    "desktop-remote-server"
    "desktop-sway-kanshi"
    "desktop-sway-media-keys"
    "desktop-sway-nwg-panel"
    "desktop-sway-nwg-shell"
    "desktop-sway-swaylock"
    "desktop-sway-swaync"
    "desktop-sway-swayr"
    "desktop-sway-waybar"
  ];

  # ------------------------------------------------------------------ the host subjects
  hostNames = [
    "desktop-base"
    "desktop-kde"
    "desktop-remote-server"
  ];

  nixosPlain =
    (bareNixos (
      denLib.imports {
        class = "nixos";
        aspects = hostNames;
      }
    )).config;

  remoteModules = denLib.imports {
    class = "nixos";
    aspects = [ "desktop-remote-server" ];
  };

  nixosRemoteOnly = (bareNixos remoteModules).config;

  # It reads the flag alone. A `true` value writes `services.teamviewer.enable`, and that option
  # pulls an unfree vendor fetch only when a consumer builds the system. This subject never does.
  nixosTeamviewer =
    (bareNixos (remoteModules ++ [ { kdn.desktop-remote-server.teamviewer = true; } ])).config;

  darwinPlain =
    (bareDarwinSystem (
      denLib.imports {
        class = "darwin";
        aspects = [ "desktop-base" ];
      }
    )).config;

  # ------------------------------------------------------------------ the user subjects
  linuxHomeConfiguration =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      modules = modules ++ [
        {
          home.username = "den";
          home.homeDirectory = "/home/den";
          home.stateVersion = "26.11";
        }
      ];
    };

  userNames = lib.subtractLists [ "desktop-remote-server" ] (
    lib.remove "desktop-base" desktopNames ++ [ "desktop-base" ]
  );

  userModules = denLib.imports {
    class = "homeManager";
    aspects = userNames;
  };

  homePlain = (linuxHomeConfiguration userModules).config;
  homeDarwin = (bareHomeConfiguration userModules).config;

  # The consumer opinions. Every monitor name below is a placeholder: it names no real display.
  opinion =
    { config, ... }:
    let
      helpers = config.kdn.desktop-sway-kanshi.helpers;
      devices = config.kdn.desktop-sway-kanshi.devices;
    in
    {
      # A 4K panel at scale 2, and a rotated 1080p panel next to it.
      kdn.desktop-sway-kanshi.devices.main.criteria = "Some Vendor Model-A 000000";
      kdn.desktop-sway-kanshi.devices.main.mode = "3840x2160@60Hz";
      kdn.desktop-sway-kanshi.devices.main.scale = 2.0;
      kdn.desktop-sway-kanshi.devices.side.criteria = "Some Vendor Model-B 111111";
      kdn.desktop-sway-kanshi.devices.side.mode = "1920x1080@60Hz";
      kdn.desktop-sway-kanshi.devices.side.transform = "90";

      kdn.desktop-sway-kanshi.profiles.dual.outputs = [
        (helpers.mkOutput devices.main 0 0 { })
        (helpers.mkOutput devices.side devices.main.w 0 { })
      ];
      kdn.desktop-sway-kanshi.profiles.dual.exec = helpers.mkWorkspaces {
        "1" = devices.main;
        "2" = devices.side;
      };

      kdn.desktop-sway-nwg-shell.components.dock.enable = false;
      kdn.desktop-sway-nwg-panel.config.panel-top.enable = false;

      # The four files the force flags cover. Home Manager needs a body for every file it manages,
      # so a consumer that forces a file also defines it.
      kdn.desktop-base.forceThemeFiles = true;
      xdg.configFile."gtk-3.0/gtk.css".text = "";
      xdg.configFile."gtk-3.0/settings.ini".text = "";
      xdg.configFile."gtk-4.0/gtk.css".text = "";
      xdg.configFile."gtk-4.0/settings.ini".text = "";
    };

  homeOpinion =
    (linuxHomeConfiguration (
      denLib.imports {
        class = "homeManager";
        aspects = [
          "desktop-base"
          "desktop-sway-kanshi"
          "desktop-sway-nwg-panel"
          "desktop-sway-nwg-shell"
        ];
      }
      ++ [ opinion ]
    )).config;

  keybindings = homePlain.wayland.windowManager.sway.config.keybindings;

  # The 24 keys this batch declares. 13 come from the media keys, 8 from the window switcher, and
  # one each from the lock, the notification centre and the display editor.
  declaredKeys = [
    "--inhibited Super+Print"
    "--locked XF86AudioNext"
    "--locked XF86AudioPause"
    "--locked XF86AudioPlay"
    "--locked XF86AudioPrev"
    "Mod1+Shift+Tab"
    "Mod1+Tab"
    "Mod1+XF86AudioMute"
    "Print"
    "Super+C"
    "Super+Delete"
    "Super+L"
    "Super+N"
    "Super+P"
    "Super+Shift+C"
    "Super+Shift+Space"
    "Super+Space"
    "Super+Tab"
    "XF86AudioLowerVolume"
    "XF86AudioMicMute"
    "XF86AudioMute"
    "XF86AudioRaiseVolume"
    "XF86MonBrightnessDown"
    "XF86MonBrightnessUp"
  ];

  kanshiSettings = homeOpinion.services.kanshi.settings;
  kanshiOutputs = map (entry: entry.output) (lib.filter (entry: entry ? output) kanshiSettings);
  kanshiProfiles = map (entry: entry.profile) (lib.filter (entry: entry ? profile) kanshiSettings);
in
{
  assertions = [
    # ---------------------------------------------------------------- the class map
    {
      name = "each desktop leaf emits the classes its old module had";
      expected = {
        desktop-base = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        desktop-kde = [
          "homeManager"
          "nixos"
        ];
        desktop-remote-server = [ "nixos" ];
        desktop-sway-kanshi = [ "homeManager" ];
        desktop-sway-media-keys = [ "homeManager" ];
        desktop-sway-nwg-panel = [ "homeManager" ];
        desktop-sway-nwg-shell = [ "homeManager" ];
        desktop-sway-swaylock = [ "homeManager" ];
        desktop-sway-swaync = [ "homeManager" ];
        desktop-sway-swayr = [ "homeManager" ];
        desktop-sway-waybar = [ "homeManager" ];
      };
      actual = lib.mapAttrs (_: sorted) (lib.getAttrs desktopNames denLib.pairs);
    }

    # ---------------------------------------------------------------- no failed module assertion
    {
      name = "the three host aspects hold no failed assertion together";
      expected = [ ];
      actual = failedAssertions nixosPlain;
    }
    {
      name = "the 10 user aspects hold no failed assertion on Linux";
      expected = [ ];
      actual = failedAssertions homePlain;
    }
    {
      name = "the consumer opinions hold no failed assertion";
      expected = [ ];
      actual = failedAssertions homeOpinion;
    }

    # ---------------------------------------------------------------- kdn.graphical
    {
      name = "a graphical host raises the shared flag, and the remote server does not declare it";
      expected = {
        nixos = true;
        darwinDeclared = true;
        darwinValue = false;
        remoteKeys = [ "desktop-remote-server" ];
      };
      actual = {
        nixos = nixosPlain.kdn.graphical;
        darwinDeclared = darwinPlain.kdn ? graphical;
        darwinValue = darwinPlain.kdn.graphical;
        remoteKeys = sorted (builtins.attrNames nixosRemoteOnly.kdn);
      };
    }

    # ---------------------------------------------------------------- desktop-base, nixos
    {
      name = "SDDM runs on Wayland, with the chili theme and one user id below nobody";
      expected = {
        enable = true;
        wayland = true;
        theme = "chili";
        maximumUid = 65533;
        themePackage = true;
      };
      actual = {
        enable = nixosPlain.services.displayManager.sddm.enable;
        wayland = nixosPlain.services.displayManager.sddm.wayland.enable;
        theme = nixosPlain.services.displayManager.sddm.theme;
        maximumUid = nixosPlain.services.displayManager.sddm.settings.Users.MaximumUid;
        themePackage = has "sddm-chili-theme" nixosPlain.environment.systemPackages;
      };
    }
    {
      name = "the freedesktop services follow the old module";
      expected = {
        uinput = true;
        ydotool = true;
        wshowkeys = true;
        accounts = true;
        dleyna = true;
        gvfs = true;
        powerProfiles = true;
        udisks2 = true;
        upower = true;
        powerManagement = true;
        xserver = true;
        dbusEnvironment = true;
        icons = true;
        mime = true;
        dconf = true;
        glibNetworking = true;
      };
      actual = {
        uinput = nixosPlain.hardware.uinput.enable;
        ydotool = nixosPlain.programs.ydotool.enable;
        wshowkeys = nixosPlain.programs.wshowkeys.enable;
        accounts = nixosPlain.services.accounts-daemon.enable;
        dleyna = nixosPlain.services.dleyna.enable;
        gvfs = nixosPlain.services.gvfs.enable;
        powerProfiles = nixosPlain.services.power-profiles-daemon.enable;
        udisks2 = nixosPlain.services.udisks2.enable;
        # The old module ties the battery daemon to the power management flag, and nixpkgs defaults
        # that flag to `true` (`<nixpkgs>/nixos/modules/config/power-management.nix:18`).
        upower = nixosPlain.services.upower.enable;
        powerManagement = nixosPlain.powerManagement.enable;
        xserver = nixosPlain.services.xserver.enable;
        dbusEnvironment = nixosPlain.services.xserver.updateDbusEnvironment;
        icons = nixosPlain.xdg.icons.enable;
        mime = nixosPlain.xdg.mime.enable;
        dconf = nixosPlain.programs.dconf.enable;
        glibNetworking = nixosPlain.services.gnome.glib-networking.enable;
      };
    }
    {
      name = "the portal runs, it opens a URL, and it names a backend";
      expected = {
        enable = true;
        xdgOpen = true;
        gtkBackend = true;
        defaultNames = [ "xdg-desktop-portal-gtk" ];
      };
      actual = {
        enable = nixosPlain.xdg.portal.enable;
        xdgOpen = nixosPlain.xdg.portal.xdgOpenUsePortal;
        gtkBackend = has "xdg-desktop-portal-gtk" nixosPlain.xdg.portal.extraPortals;
        defaultNames = map lib.getName nixosPlain.kdn.desktop-base.portals;
      };
    }
    {
      name = "the font list installs, and the font directory and the icon cache run";
      expected = {
        dejavu = true;
        cantarell = true;
        blob = true;
        fontDir = true;
        iconCache = true;
      };
      actual = {
        dejavu = has "dejavu-fonts" nixosPlain.fonts.packages;
        cantarell = has "cantarell-fonts" nixosPlain.fonts.packages;
        blob = has "noto-fonts-emoji-blob-bin" nixosPlain.fonts.packages;
        fontDir = nixosPlain.fonts.fontDir.enable;
        iconCache = nixosPlain.gtk.iconCache.enable;
      };
    }
    {
      name = "the desktop tool set, the file manager and the calculator install";
      expected = {
        clipboard = true;
        grim = true;
        okular = true;
        nemo = true;
        calculator = true;
        library = true;
      };
      actual = {
        clipboard = has "wl-clipboard" nixosPlain.environment.systemPackages;
        grim = has "grim" nixosPlain.environment.systemPackages;
        okular = has "okular" nixosPlain.environment.systemPackages;
        nemo = has "nemo-with-extensions" nixosPlain.environment.systemPackages;
        calculator = has "qalculate-qt" nixosPlain.environment.systemPackages;
        library = has "libqalculate" nixosPlain.environment.systemPackages;
      };
    }
    {
      name = "the file manager reaches the session bus";
      # The subject loads three host aspects and nixpkgs adds its own bus packages. So the probe
      # asks for one member instead of an exact list.
      expected = true;
      actual = has "nemo-with-extensions" nixosPlain.services.dbus.packages;
    }

    # ---------------------------------------------------------------- desktop-base, darwin
    {
      name = "the darwin class installs the same eight fonts and both calculators";
      expected = {
        fonts = [
          "cantarell-fonts"
          "dejavu-fonts"
          "font-awesome"
          "noto-fonts"
          "noto-fonts-color-emoji"
          "noto-fonts-emoji-blob-bin"
          "noto-fonts-monochrome-emoji"
          "ubuntu-classic"
        ];
        calculator = true;
        library = true;
      };
      actual = {
        fonts = sorted (map lib.getName darwinPlain.fonts.packages);
        calculator = has "qalculate-qt" darwinPlain.environment.systemPackages;
        library = has "libqalculate" darwinPlain.environment.systemPackages;
      };
    }

    # ---------------------------------------------------------------- desktop-kde
    {
      name = "Plasma 6 runs, it is the default session, and Qt reads the Breeze style";
      expected = {
        plasma6 = true;
        defaultSession = "plasma";
        platformTheme = "kde";
        style = "breeze";
        qt = true;
        keyring = false;
        askPassword = true;
        controls = "org.kde.desktop";
        breezeStyle = true;
        desktopStyle = true;
      };
      actual = {
        plasma6 = nixosPlain.services.desktopManager.plasma6.enable;
        defaultSession = nixosPlain.services.displayManager.defaultSession;
        platformTheme = nixosPlain.qt.platformTheme;
        style = nixosPlain.qt.style;
        qt = nixosPlain.qt.enable;
        keyring = nixosPlain.services.gnome.gnome-keyring.enable;
        askPassword = lib.hasInfix "ksshaskpass" nixosPlain.programs.ssh.askPassword;
        controls = nixosPlain.environment.sessionVariables.QT_QUICK_CONTROLS_STYLE;
        breezeStyle = has "qqc2-breeze-style" nixosPlain.environment.systemPackages;
        desktopStyle = has "qqc2-desktop-style" nixosPlain.environment.systemPackages;
      };
    }
    {
      name = "the user class points Qt at Plasma and turns the GNOME keyring off";
      expected = {
        keyring = false;
        qt = true;
        themePackages = [
          "plasma-integration"
          "systemsettings"
        ];
        stylePackage = "breeze";
        styleName = "breeze";
        sessionVariable = "kde";
      };
      actual = {
        keyring = homePlain.services.gnome-keyring.enable;
        qt = homePlain.qt.enable;
        themePackages = sorted (map lib.getName homePlain.qt.platformTheme.package);
        stylePackage = lib.getName homePlain.qt.style.package;
        styleName = homePlain.qt.style.name;
        sessionVariable = homePlain.systemd.user.sessionVariables.QT_QPA_PLATFORMTHEME;
      };
    }

    # ---------------------------------------------------------------- desktop-remote-server
    {
      name = "the TeamViewer daemon stays off until a consumer asks for it";
      expected = {
        default = false;
        plainService = false;
        opinion = true;
        opinionService = true;
      };
      actual = {
        default = nixosRemoteOnly.kdn.desktop-remote-server.teamviewer;
        plainService = nixosRemoteOnly.services.teamviewer.enable;
        opinion = nixosTeamviewer.kdn.desktop-remote-server.teamviewer;
        opinionService = nixosTeamviewer.services.teamviewer.enable;
      };
    }

    # ---------------------------------------------------------------- the shared sway values
    {
      name = "the shared key map and the session target hold the old defaults";
      expected = {
        keyCount = 13;
        modifier = "Mod3";
        super = "Super";
        superMod = "Mod4";
        lalt = "Mod1";
        shift = "Shift";
        envsTarget = "kdn-sway-envs.target";
      };
      actual = {
        keyCount = builtins.length (builtins.attrNames homePlain.kdn.desktop-sway.keys);
        modifier = homePlain.kdn.desktop-sway.keys.modifier;
        super = homePlain.kdn.desktop-sway.keys.super;
        superMod = homePlain.kdn.desktop-sway.keys.superMod;
        lalt = homePlain.kdn.desktop-sway.keys.lalt;
        shift = homePlain.kdn.desktop-sway.keys.shift;
        envsTarget = homePlain.kdn.desktop-sway.envsTarget;
      };
    }
    {
      name = "every keybinding this batch declares reaches the sway option";
      expected = [ ];
      # `subtractLists` returns the declared keys the map misses. Home Manager adds its own default
      # keys, so the check runs one way only. See the header.
      actual = sorted (lib.subtractLists (builtins.attrNames keybindings) declaredKeys);
    }
    {
      name = "five keybindings name the right program";
      expected = {
        lock = true;
        switcher = true;
        displays = true;
        notifications = true;
        volume = true;
      };
      actual = {
        lock = lib.hasInfix "swaylock" keybindings."Super+L";
        switcher = lib.hasInfix "switch-window" keybindings."Super+Space";
        displays = lib.hasInfix "nwg-displays" keybindings."Super+P";
        notifications = lib.hasInfix "swaync-client" keybindings."Super+N";
        volume = lib.hasInfix "volumectl" keybindings."XF86AudioRaiseVolume";
      };
    }
    {
      name = "the sway include lines and the switcher daemon reach the extra configuration";
      expected = {
        daemon = true;
        outputs = true;
        workspaces = true;
      };
      actual = {
        daemon = lib.hasInfix "swayrd" homePlain.wayland.windowManager.sway.extraConfig;
        outputs = lib.hasInfix "include ~/.config/sway/outputs" homePlain.wayland.windowManager.sway.extraConfig;
        workspaces = lib.hasInfix "include ~/.config/sway/workspaces" homePlain.wayland.windowManager.sway.extraConfig;
      };
    }

    # ---------------------------------------------------------------- desktop-base, homeManager
    {
      name = "the terminal, the launcher and the paste helper reach the user";
      expected = {
        wezterm = true;
        weztermReturn = true;
        foot = true;
        footServer = false;
        dpi = "no";
        scrollback = 100000;
        wofi = true;
        paste = true;
      };
      actual = {
        wezterm = homePlain.programs.wezterm.enable;
        weztermReturn = lib.hasInfix "return config" homePlain.programs.wezterm.extraConfig;
        foot = homePlain.programs.foot.enable;
        footServer = homePlain.programs.foot.server.enable;
        dpi = homePlain.programs.foot.settings.main.dpi-aware;
        scrollback = homePlain.programs.foot.settings.scrollback.lines;
        wofi = homePlain.xdg.configFile ? "wofi/config";
        paste = has "ydotool-paste" homePlain.home.packages;
      };
    }
    {
      name = "the theme force flags follow one opinion, and they stay off by default";
      expected = {
        plainFlag = false;
        plainGtk2 = false;
        plainCss = false;
        opinionFlag = true;
        opinionGtk2 = true;
        opinionForced = [
          true
          true
          true
          true
        ];
        opinionSource = true;
      };
      actual = {
        plainFlag = homePlain.kdn.desktop-base.forceThemeFiles;
        plainGtk2 = homePlain.gtk.gtk2.force;
        # The aspect writes no `gtk-3.0/gtk.css` entry until the opinion turns on. So the probe asks
        # for the presence of the entry. A read of `.force` aborts on a missing attribute.
        plainCss = homePlain.xdg.configFile ? "gtk-3.0/gtk.css";
        opinionFlag = homeOpinion.kdn.desktop-base.forceThemeFiles;
        opinionGtk2 = homeOpinion.gtk.gtk2.force;
        opinionForced = [
          homeOpinion.xdg.configFile."gtk-3.0/gtk.css".force
          homeOpinion.xdg.configFile."gtk-3.0/settings.ini".force
          homeOpinion.xdg.configFile."gtk-4.0/gtk.css".force
          homeOpinion.xdg.configFile."gtk-4.0/settings.ini".force
        ];
        opinionSource = lib.hasPrefix "/nix/store" (
          toString homeOpinion.xdg.configFile."gtk-3.0/gtk.css".source
        );
      };
    }

    # ---------------------------------------------------------------- desktop-sway-waybar
    {
      name = "waybar runs as a user service and reads one generated file";
      expected = {
        enable = true;
        systemd = true;
        configName = true;
        reload = true;
        tray = true;
        requires = true;
        after = true;
        startPost = true;
        indicator = true;
      };
      actual = {
        enable = homePlain.programs.waybar.enable;
        systemd = homePlain.programs.waybar.systemd.enable;
        configName = lib.hasSuffix "waybar-config.json" (
          toString homePlain.xdg.configFile."waybar/config".source
        );
        reload = lib.hasInfix "-USR2 waybar" homePlain.xdg.configFile."waybar/config".onChange;
        # Home Manager writes its own unit keys, so each read asks for one member.
        tray = lib.elem "tray.target" homePlain.systemd.user.services.waybar.Unit.BindsTo;
        requires = lib.elem "kdn-sway-envs.target" homePlain.systemd.user.services.waybar.Unit.Requires;
        after = lib.elem "kdn-sway-envs.target" homePlain.systemd.user.services.waybar.Unit.After;
        startPost = lib.any (
          entry: lib.hasInfix "sleep 3" entry
        ) homePlain.systemd.user.services.waybar.Service.ExecStartPost;
        indicator = has "libappindicator-gtk3" homePlain.home.packages;
      };
    }

    # ---------------------------------------------------------------- desktop-sway-kanshi
    {
      name = "kanshi runs, and it holds no monitor until a consumer names one";
      expected = {
        enable = true;
        devices = { };
        profiles = { };
        settings = [ ];
        helpers = [
          "mkOutput"
          "mkWorkspaces"
        ];
      };
      actual = {
        enable = homePlain.services.kanshi.enable;
        devices = homePlain.kdn.desktop-sway-kanshi.devices;
        profiles = homePlain.kdn.desktop-sway-kanshi.profiles;
        settings = homePlain.services.kanshi.settings;
        helpers = sorted (builtins.attrNames homePlain.kdn.desktop-sway-kanshi.helpers);
      };
    }
    {
      name = "the device read recalculates the size from the scale and the rotation";
      expected = {
        mainDeclaredWidth = 3840;
        mainDeclaredHeight = 2160;
        mainRefresh = 60;
        mainWidth = 1920.0;
        mainHeight = 1080.0;
        sideWidth = 1080;
        sideHeight = 1920;
      };
      actual = {
        mainDeclaredWidth = homeOpinion.kdn.desktop-sway-kanshi.devices.main.declaredWidth;
        mainDeclaredHeight = homeOpinion.kdn.desktop-sway-kanshi.devices.main.declaredHeight;
        mainRefresh = homeOpinion.kdn.desktop-sway-kanshi.devices.main.refresh;
        mainWidth = homeOpinion.kdn.desktop-sway-kanshi.devices.main.w;
        mainHeight = homeOpinion.kdn.desktop-sway-kanshi.devices.main.h;
        sideWidth = homeOpinion.kdn.desktop-sway-kanshi.devices.side.w;
        sideHeight = homeOpinion.kdn.desktop-sway-kanshi.devices.side.h;
      };
    }
    {
      name = "the write gives kanshi two outputs and one profile, and no calculated key";
      expected = {
        outputCount = 2;
        profileCount = 1;
        modes = [
          "1920x1080@60Hz"
          "3840x2160@60Hz"
        ];
        positions = [
          "0,0"
          "1920,0"
        ];
        profileName = "dual";
        profileOutputs = 2;
        execScript = true;
      };
      # kanshi's own `output` type of Home Manager rejects an unknown key, so a calculated key that
      # leaked would stop the evaluation here.
      actual = {
        outputCount = builtins.length kanshiOutputs;
        profileCount = builtins.length kanshiProfiles;
        modes = sorted (map (output: output.mode) kanshiOutputs);
        positions = sorted (map (output: output.position) (builtins.head kanshiProfiles).outputs);
        profileName = (builtins.head kanshiProfiles).name;
        profileOutputs = builtins.length (builtins.head kanshiProfiles).outputs;
        execScript = lib.any (
          entry: lib.hasInfix "kanshi-profile-dual-exec" entry
        ) (builtins.head kanshiProfiles).exec;
      };
    }

    # ---------------------------------------------------------------- desktop-sway-nwg-shell
    {
      name = "the eight nwg components arrive on, and each one names its own package";
      expected = {
        names = [
          "bar"
          "displays"
          "dock"
          "drawer"
          "hello"
          "look"
          "menu"
          "wrapper"
        ];
        packages = [
          "nwg-bar"
          "nwg-displays"
          "nwg-dock"
          "nwg-drawer"
          "nwg-hello"
          "nwg-look"
          "nwg-menu"
          "nwg-wrapper"
        ];
        allOn = true;
        installed = true;
        notifications = true;
      };
      actual = {
        names = sorted (builtins.attrNames homePlain.kdn.desktop-sway-nwg-shell.components);
        packages = sorted (
          map (component: lib.getName component.package) (
            builtins.attrValues homePlain.kdn.desktop-sway-nwg-shell.components
          )
        );
        allOn = lib.all (component: component.enable) (
          builtins.attrValues homePlain.kdn.desktop-sway-nwg-shell.components
        );
        installed = has "nwg-drawer" homePlain.home.packages;
        notifications = homePlain.services.swaync.enable;
      };
    }
    {
      name = "a consumer drops one component and keeps the other seven";
      expected = {
        dock = false;
        dockPackage = false;
        drawerPackage = true;
        pinCache = true;
      };
      actual = {
        dock = homeOpinion.kdn.desktop-sway-nwg-shell.components.dock.enable;
        dockPackage = has "nwg-dock" homeOpinion.home.packages;
        drawerPackage = has "nwg-drawer" homeOpinion.home.packages;
        # The pin cache belongs to the drawer, not to the dock, so it stays.
        pinCache = lib.elem ".cache/nwg-pin-cache" homeOpinion.kdn.disks.persist."usr/config".files;
      };
    }
    {
      name = "the shell aspect publishes the drawer options, the launch script and four state files";
      expected = {
        opts = [
          "-wm"
          "\"$XDG_CURRENT_DESKTOP\""
        ];
        exec = true;
        files = [
          ".cache/nwg-pin-cache"
          ".config/nwg-displays/config"
          ".config/sway/outputs"
          ".config/sway/workspaces"
        ];
      };
      actual = {
        opts = homePlain.kdn.desktop-sway-nwg-shell.drawer.opts;
        exec = lib.hasInfix "nwg-drawer-launch" homePlain.kdn.desktop-sway-nwg-shell.drawer.exec;
        files = sorted homePlain.kdn.disks.persist."usr/config".files;
      };
    }

    # ---------------------------------------------------------------- desktop-sway-nwg-panel
    {
      name = "the panel reads its payload, it shows on every output, and it runs as a unit";
      expected = {
        names = [
          "panel-top"
          "panel-bottom"
        ];
        outputs = [
          "All"
          "All"
        ];
        style = "";
        package = "nwg-panel";
        executor = true;
        unitStart = true;
        unitPre = true;
        wanted = [ "graphical-session.target" ];
      };
      actual = {
        # The `apply` sorts by `order`, so the list order follows the payload file.
        names = map (panel: panel.name) homePlain.kdn.desktop-sway-nwg-panel.config;
        outputs = map (panel: panel.output) homePlain.kdn.desktop-sway-nwg-panel.config;
        style = homePlain.kdn.desktop-sway-nwg-panel.style;
        package = lib.getName homePlain.kdn.desktop-sway-nwg-panel.package;
        executor = has "gopsuinfo" homePlain.home.packages;
        # The unit type wraps an exec directive in a list. `toString` joins it, so the probe reads
        # both a plain string and a one-element list.
        unitStart = lib.hasInfix "nwg-panel" (
          toString homePlain.systemd.user.services.nwg-panel.Service.ExecStart
        );
        unitPre = lib.hasInfix "nwg-panel-set-configs" (
          toString homePlain.systemd.user.services.nwg-panel.Service.ExecStartPre
        );
        wanted = homePlain.systemd.user.services.nwg-panel.Install.WantedBy;
      };
    }
    {
      name = "a consumer drops one panel, and the other one keeps its place";
      expected = [ "panel-bottom" ];
      actual = map (panel: panel.name) homeOpinion.kdn.desktop-sway-nwg-panel.config;
    }

    # ---------------------------------------------------------------- desktop-sway-swaylock
    {
      name = "the lock runs on an idle timer, and the screen sleeps first";
      expected = {
        swaylock = true;
        failedAttempts = true;
        idle = true;
        beforeSleep = true;
        timeouts = [
          240
          300
        ];
        after = true;
        requires = true;
      };
      actual = {
        swaylock = homePlain.programs.swaylock.enable;
        failedAttempts = homePlain.programs.swaylock.settings.show-failed-attempts;
        idle = homePlain.services.swayidle.enable;
        beforeSleep = lib.hasInfix "swaylock" homePlain.services.swayidle.events."before-sleep";
        timeouts = sorted (map (entry: entry.timeout) homePlain.services.swayidle.timeouts);
        after = lib.elem "kdn-sway-envs.target" homePlain.systemd.user.services.swayidle.Unit.After;
        requires = lib.elem "kdn-sway-envs.target" homePlain.systemd.user.services.swayidle.Unit.Requires;
      };
    }

    # ---------------------------------------------------------------- desktop-sway-media-keys
    {
      name = "the volume overlay runs with no setting of its own";
      expected = {
        enable = true;
        settings = { };
      };
      actual = {
        enable = homePlain.services.avizo.enable;
        settings = homePlain.services.avizo.settings;
      };
    }

    # ---------------------------------------------------------------- desktop-sway-swayr
    {
      name = "the window switcher installs, and it reads the payload file";
      expected = {
        package = true;
        configFile = true;
        journal = true;
      };
      actual = {
        package = has "swayr" homePlain.home.packages;
        configFile = lib.hasSuffix "swayr-config.toml" (
          toString homePlain.xdg.configFile."swayr/config.toml".source
        );
        # Every call goes through the journal, under the user's own identifier.
        journal = lib.hasInfix "systemd-cat --identifier=den-swayr" keybindings."Super+Space";
      };
    }

    # ---------------------------------------------------------------- desktop-sway-swaync
    {
      name = "the notification centre runs, and its D-Bus service file lands in the data directory";
      expected = {
        enable = true;
        service = true;
      };
      actual = {
        enable = homePlain.services.swaync.enable;
        service = lib.hasSuffix "org.erikreider.swaync.service" (
          toString homePlain.xdg.dataFile."dbus-1/services/org.erikreider.swaync.service".source
        );
      };
    }

    # ---------------------------------------------------------------- the Darwin guard
    {
      name = "a Darwin consumer keeps the terminal and drops every Wayland program";
      expected = {
        wezterm = true;
        foot = false;
        kanshi = false;
        waybar = false;
        swaync = false;
        swaylock = false;
        swayidle = false;
        avizo = false;
        wofi = false;
        nwg = false;
        swayr = false;
        qt = false;
      };
      actual = {
        wezterm = homeDarwin.programs.wezterm.enable;
        foot = homeDarwin.programs.foot.enable;
        kanshi = homeDarwin.services.kanshi.enable;
        waybar = homeDarwin.programs.waybar.enable;
        swaync = homeDarwin.services.swaync.enable;
        swaylock = homeDarwin.programs.swaylock.enable;
        swayidle = homeDarwin.services.swayidle.enable;
        avizo = homeDarwin.services.avizo.enable;
        wofi = homeDarwin.xdg.configFile ? "wofi/config";
        nwg = has "nwg-drawer" homeDarwin.home.packages;
        swayr = has "swayr" homeDarwin.home.packages;
        qt = homeDarwin.qt.enable;
      };
    }
  ];

  # One row per aspect this batch ports. `../tests.nix` merges every area's rows into the table that
  # `den-eval-coverage` reads.
  instantiatedBy = {
    desktop-base = "den-eval-desktop-leaves nixosPlain, darwinPlain and homePlain";
    desktop-kde = "den-eval-desktop-leaves nixosPlain and homePlain";
    desktop-remote-server = "den-eval-desktop-leaves nixosRemoteOnly and nixosTeamviewer";
    desktop-sway-kanshi = "den-eval-desktop-leaves homePlain and homeOpinion";
    desktop-sway-media-keys = "den-eval-desktop-leaves homePlain";
    desktop-sway-nwg-panel = "den-eval-desktop-leaves homePlain and homeOpinion";
    desktop-sway-nwg-shell = "den-eval-desktop-leaves homePlain and homeOpinion";
    desktop-sway-swaylock = "den-eval-desktop-leaves homePlain";
    desktop-sway-swaync = "den-eval-desktop-leaves homePlain";
    desktop-sway-swayr = "den-eval-desktop-leaves homePlain";
    desktop-sway-waybar = "den-eval-desktop-leaves homePlain";
  };
}
