# The assertion set for layer-C batch 16: the Sway session core and its VNC extras.
# `../tests.nix` imports this file through `./default.nix`, and the loader registers the result as
# `den-eval-sway-core`.
#
# Every assertion is `{ name; expected; actual; }`, the shape `mkEvalCheck` needs. Nothing here
# builds a system, and nothing activates.
#
# ## The subjects
#
# | Subject | Class | What it proves |
# |---|---|---|
# | `nixosCore` | `nixos` | the session half evaluates with **no** consumer data at all |
# | `nixosCoreOptions` | `nixos` | the option tree holds no `kdn.desktop` and no `enable` |
# | `nixosRemote` | `nixos` | the remote aspect adds the VNC tools and pulls the core in |
# | `homeLinux` | `homeManager` | the real user half evaluates on Linux |
# | `homeDarwin` | `homeManager` | the Linux guard drops the whole user half on darwin |
#
# ## Why this file builds one home harness of its own
#
# `../harness.nix` fixes the home harness to `aarch64-darwin`. Every package of the Sway user half is
# Linux-only, so that harness reaches the inert branch alone. `bareLinuxHome` below repeats the same
# three lines on `x86_64-linux`. It builds no derivation; it evaluates one. `./services.nix` holds
# the same helper for the same reason. A shared helper file cannot live in this directory, because
# `./default.nix` scans the directory and reads every `.nix` file as an area.
#
# ## The two facts of the old tree that this file locks down
#
# 1. **No `apply` gate survives.** The old option carries
#    `apply = value: value && config.kdn.desktop.enable`, so a desktop flag could veto Sway. An
#    aspect declares no reachable `enable`, so inclusion is the switch. Two assertions state that
#    `kdn.desktop` does not exist and that `kdn.graphical` reaches `true` instead.
# 2. **There is no `darwin` class.** Sway is a Linux compositor. The old tree lets a darwin host
#    reach four of the nine user files, which gives a part-configured session. `denLib.pairs` reads
#    the class keys off the aspect, so the missing key makes `denModules.desktop-sway-darwin` absent
#    and an adopter gets a loud `attribute … missing`. Two assertions state that.
#
# ## The doubled prefix
#
# The unit names carry the prefix twice, for example `kdn-sway-kdn-sway-session.target`. That is the
# old behaviour, and a live machine holds those names. Three assertions pin the exact strings, so a
# later "clean-up" cannot rename a live unit in silence.
#
# ## The data holds no real value
#
# Every value below is a default of the aspect or a placeholder. No monitor identifier, no host name
# and no personal path appears here.
{
  lib,
  inputs,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);

  # A Linux home, in the same bare-consumer shape as `../harness.nix`'s darwin one.
  bareLinuxHome =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      modules = modules ++ [
        {
          home.username = "dev";
          home.homeDirectory = "/home/dev";
          home.stateVersion = "26.11";
        }
      ];
    };

  modulesFor =
    class: aspects:
    denLib.imports {
      inherit class aspects;
    };

  # The core, with no consumer opinion. `includes` pulls the eight desktop leaves in, so this one
  # list also proves that the bundle resolves.
  nixosCoreSystem = bareNixos (modulesFor "nixos" [ "desktop-sway" ]);
  nixosCore = nixosCoreSystem.config;
  nixosCoreOptions = nixosCoreSystem.options;

  nixosRemote = (bareNixos (modulesFor "nixos" [ "desktop-sway-remote" ])).config;

  homeModules = modulesFor "homeManager" [ "desktop-sway" ];
  homeLinux = (bareLinuxHome homeModules).config;
  homeDarwin = (bareHomeConfiguration homeModules).config;

  has = name: packages: lib.any (drv: (lib.getName drv) == name) packages;

  swayCfg = nixosCore.kdn.desktop-sway;

  assertions = [
    # ------------------------------------------------------------------ the class shape
    {
      name = "the sway core declares the nixos and homeManager classes only";
      expected = [
        "homeManager"
        "nixos"
      ];
      actual = sorted denLib.pairs.desktop-sway;
    }
    {
      name = "the sway remote aspect declares the nixos class only";
      expected = [ "nixos" ];
      actual = sorted denLib.pairs.desktop-sway-remote;
    }
    {
      name = "neither sway aspect declares a darwin class, because sway is Linux-only";
      expected = {
        core = false;
        remote = false;
      };
      actual = {
        core = lib.elem "darwin" denLib.pairs.desktop-sway;
        remote = lib.elem "darwin" denLib.pairs.desktop-sway-remote;
      };
    }

    # ------------------------------------------------------------------ the enable gate is gone
    {
      name = "the nixos class declares no kdn.desktop option tree, so no apply gate can exist";
      expected = false;
      actual = nixosCoreOptions.kdn ? desktop;
    }
    {
      name = "the sway aspect declares no enable option, so inclusion is the switch";
      expected = false;
      actual = nixosCoreOptions.kdn.desktop-sway ? enable;
    }
    {
      name = "kdn.graphical reaches true on the nixos class of both sway aspects";
      expected = {
        core = true;
        remote = true;
      };
      actual = {
        core = nixosCore.kdn.graphical;
        remote = nixosRemote.kdn.graphical;
      };
    }

    # ------------------------------------------------------------------ the doubled prefix
    {
      name = "the session unit names carry the prefix twice, as the old tree does";
      expected = {
        sway = "kdn-sway-kdn-sway-sway.service";
        session = "kdn-sway-kdn-sway-session.target";
        envsService = "kdn-sway-kdn-sway-envs.service";
        envsTarget = "kdn-sway-kdn-sway-envs.target";
        tray = "kdn-sway-kdn-sway-tray.target";
        polkit = "kdn-sway-kdn-sway-polkit-agent.service";
        secrets = "dbus-kdn-sway-secrets-service.service";
      };
      actual = {
        sway = swayCfg.systemd.sway.service;
        session = swayCfg.systemd.session.target;
        envsService = swayCfg.systemd.envs.service;
        envsTarget = swayCfg.systemd.envs.target;
        tray = swayCfg.systemd.tray.target;
        polkit = swayCfg.systemd.polkit-agent.service;
        secrets = swayCfg.systemd.secrets-service.service;
      };
    }
    {
      name = "the shared envsTarget option gets the computed name on both classes";
      expected = {
        nixos = "kdn-sway-kdn-sway-envs.target";
        home = "kdn-sway-kdn-sway-envs.target";
      };
      actual = {
        nixos = swayCfg.envsTarget;
        home = homeLinux.kdn.desktop-sway.envsTarget;
      };
    }
    {
      name = "the nixos class declares the seven session units under their doubled names";
      expected = {
        sway = true;
        envsService = true;
        polkit = true;
        secretsService = true;
        session = true;
        envsTarget = true;
        tray = true;
        secretsTarget = true;
      };
      actual = {
        sway = nixosCore.systemd.user.services ? "kdn-sway-kdn-sway-sway";
        envsService = nixosCore.systemd.user.services ? "kdn-sway-kdn-sway-envs";
        polkit = nixosCore.systemd.user.services ? "kdn-sway-kdn-sway-polkit-agent";
        secretsService = nixosCore.systemd.user.services ? "dbus-kdn-sway-secrets-service";
        session = nixosCore.systemd.user.targets ? "kdn-sway-kdn-sway-session";
        envsTarget = nixosCore.systemd.user.targets ? "kdn-sway-kdn-sway-envs";
        tray = nixosCore.systemd.user.targets ? "kdn-sway-kdn-sway-tray";
        secretsTarget = nixosCore.systemd.user.targets ? "dbus-kdn-sway-secrets-service";
      };
    }

    # ------------------------------------------------------------------ the nixos session
    {
      name = "the nixos class turns sway on and registers the session with the display manager";
      expected = {
        sway = true;
        gtk = true;
        defaultSession = "kdn-sway";
        providedSessions = [ "kdn-sway" ];
      };
      actual = {
        sway = nixosCore.programs.sway.enable;
        gtk = nixosCore.programs.sway.wrapperFeatures.gtk;
        defaultSession = nixosCore.services.displayManager.defaultSession;
        # nixpkgs reads the flat attribute (`services/display-managers/default.nix:213`), and
        # `mkDerivation` puts every `passthru` key there. So the flat read is the honest one.
        providedSessions = swayCfg.bundle.providedSessions;
      };
    }
    {
      name = "the session bundle exports the six session scripts";
      expected = [
        "env-clear"
        "env-load"
        "env-show"
        "env-wait"
        "start"
        "start-headless"
      ];
      actual = sorted (builtins.attrNames swayCfg.bundle.exes);
    }
    {
      name = "the two environment option sets keep the old counts and reach the session";
      expected = {
        defaults = 2;
        environment = 8;
        gdk = true;
      };
      actual = {
        defaults = builtins.length swayCfg.environmentDefaults;
        environment = builtins.length swayCfg.environment;
        gdk = lib.any (lib.hasPrefix "GDK_BACKEND=") swayCfg.environment;
      };
    }
    {
      name = "the init scripts land in one prefixed sway configuration drop-in";
      expected = {
        file = true;
        groups = [ "systemd" ];
      };
      actual = {
        file = nixosCore.environment.etc ? "sway/config.d/00-kdn-sway-init.conf";
        groups = sorted (builtins.attrNames swayCfg.initScripts);
      };
    }
    {
      name = "the XDG portal routes screencast and screenshot to wlr and refuses inhibit";
      expected = {
        enable = true;
        wlr = true;
        default = "gtk";
        screenCast = "wlr";
        screenshot = "wlr";
        inhibit = "none";
      };
      actual = {
        enable = nixosCore.xdg.portal.enable;
        wlr = nixosCore.xdg.portal.wlr.enable;
        default = nixosCore.xdg.portal.config.sway.default;
        screenCast = nixosCore.xdg.portal.config.sway."org.freedesktop.impl.portal.ScreenCast";
        screenshot = nixosCore.xdg.portal.config.sway."org.freedesktop.impl.portal.Screenshot";
        inhibit = nixosCore.xdg.portal.config.sway."org.freedesktop.impl.portal.Inhibit";
      };
    }
    {
      name = "the portal backend list holds the GTK backend and the wlroots backend";
      # nixpkgs writes to this option too, so an exact list cannot hold. `programs.sway.enable`
      # imports `<nixpkgs>/nixos/modules/programs/wayland/wayland-session.nix`, and its lines 23-24
      # add `xdg-desktop-portal-gtk` a second time, because `enableGtkPortal` defaults to `true`.
      # `desktop-base` adds the same package through `kdn.desktop-base.portals`. A repeated store
      # path in `extraPortals` is harmless, and the old tree produces the identical pair of writes.
      # So this assertion measures the two distinct backend names instead of the raw list.
      expected = [
        "xdg-desktop-portal-gtk"
        "xdg-desktop-portal-wlr"
      ];
      actual = sorted (lib.unique (map lib.getName nixosCore.xdg.portal.extraPortals));
    }
    {
      name = "the portal debug switch and the shared sway package stay off by default";
      expected = {
        debug = false;
        package = null;
      };
      actual = {
        debug = swayCfg.portals.debug;
        package = swayCfg.package;
      };
    }

    # ------------------------------------------------------------------ the user half
    {
      name = "the home class turns the sway module on for a Linux user";
      expected = {
        sway = true;
        ownSystemd = false;
        waylandTarget = "kdn-sway-kdn-sway-session.target";
      };
      actual = {
        sway = homeLinux.wayland.windowManager.sway.enable;
        ownSystemd = homeLinux.wayland.windowManager.sway.systemd.enable;
        waylandTarget = homeLinux.wayland.systemd.target;
      };
    }
    {
      name = "the home class stays inert for a darwin user, because every package is Linux-only";
      expected = {
        sway = false;
        applet = false;
        flameshot = false;
      };
      actual = {
        sway = homeDarwin.wayland.windowManager.sway.enable;
        applet = homeDarwin.services.network-manager-applet.enable;
        flameshot = homeDarwin.services.flameshot.enable;
      };
    }
    {
      name = "the home class states the keyboard layout and the workspace layout";
      # The aspect writes `focus.followMouse = false`, the same value the old tree writes. Home
      # Manager's own option carries an `apply` that maps a bool onto the sway words, so the
      # configuration value reads `"no"`. The expectation names the value after that map.
      expected = {
        xkbLayout = "us";
        workspaceLayout = "tabbed";
        followMouse = "no";
        bars = 0;
      };
      actual = {
        xkbLayout = homeLinux.wayland.windowManager.sway.config.input."type:keyboard".xkb_layout;
        workspaceLayout = homeLinux.wayland.windowManager.sway.config.workspaceLayout;
        followMouse = homeLinux.wayland.windowManager.sway.config.focus.followMouse;
        bars = builtins.length homeLinux.wayland.windowManager.sway.config.bars;
      };
    }
    {
      name = "the lid switch names the built-in panel output of the lidOutput option";
      expected = {
        disable = true;
        enable = true;
        include = true;
      };
      actual = {
        disable = lib.hasInfix "lid:on output eDP-1 disable" homeLinux.wayland.windowManager.sway.extraConfig;
        enable = lib.hasInfix "lid:off output eDP-1 enable" homeLinux.wayland.windowManager.sway.extraConfig;
        include = lib.hasInfix "include /etc/sway/config.d/*" homeLinux.wayland.windowManager.sway.extraConfig;
      };
    }
    {
      name = "the launcher keybinding reads the nwg-shell drawer, and the file manager reaches it";
      expected = {
        binding = true;
        launcherLength = 1;
        fmOpt = true;
      };
      actual = {
        binding = homeLinux.wayland.windowManager.sway.config.keybindings ? "Super+D";
        launcherLength = builtins.length homeLinux.kdn.desktop-sway.launcher;
        fmOpt = lib.elem "-fm" homeLinux.kdn.desktop-sway-nwg-shell.drawer.opts;
      };
    }
    {
      name = "kanshi starts from the sway session target, not from graphical-session.target";
      expected = "kdn-sway-kdn-sway-session.target";
      actual = homeLinux.services.kanshi.systemdTarget;
    }
    {
      name = "the includes bundle loads the seven old leaves and leaves nwg-panel out";
      expected = {
        kanshi = true;
        waybar = true;
        swaylock = true;
        swaync = true;
        nwgPanel = false;
      };
      actual = {
        kanshi = homeLinux.services.kanshi.enable;
        waybar = homeLinux.programs.waybar.enable;
        swaylock = homeLinux.programs.swaylock.enable;
        swaync = homeLinux.services.swaync.enable;
        nwgPanel = homeLinux.systemd.user.services ? "nwg-panel";
      };
    }

    # ------------------------------------------------------------------ the remote extras
    {
      name = "the remote aspect installs the five VNC and pipe tools";
      expected = {
        wayvnc = true;
        waypipe = true;
        swayVnc = true;
        remmina = true;
        tigervnc = true;
      };
      actual = {
        wayvnc = has "wayvnc" nixosRemote.environment.systemPackages;
        waypipe = has "waypipe" nixosRemote.environment.systemPackages;
        swayVnc = has "sway-vnc" nixosRemote.environment.systemPackages;
        remmina = has "remmina" nixosRemote.environment.systemPackages;
        tigervnc = has "tigervnc" nixosRemote.environment.systemPackages;
      };
    }
    {
      name = "the core alone installs none of the remote tools, so the include is the only route";
      expected = {
        wayvnc = false;
        swayVnc = false;
      };
      actual = {
        wayvnc = has "wayvnc" nixosCore.environment.systemPackages;
        swayVnc = has "sway-vnc" nixosCore.environment.systemPackages;
      };
    }
    {
      name = "the remote aspect pulls the whole core in, so the session units exist there too";
      expected = {
        sway = true;
        session = true;
      };
      actual = {
        sway = nixosRemote.programs.sway.enable;
        session = nixosRemote.systemd.user.targets ? "kdn-sway-kdn-sway-session";
      };
    }
  ];

  # ------------------------------------------------------------------ the coverage rows
  #
  # `../tests.nix` merges this set into the table that `den-eval-coverage` reads. One row per aspect
  # this batch ports, so the registry and the table stay equal with no edit to a shared file.
  instantiatedBy = {
    desktop-sway = "den-eval-sway-core (bare nixos, bare Linux home, bare darwin home)";
    desktop-sway-remote = "den-eval-sway-core (bare nixos, the VNC package set)";
  };
in
{
  inherit assertions instantiatedBy;
}
