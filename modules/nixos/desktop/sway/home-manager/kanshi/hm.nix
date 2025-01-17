{
  osConfig,
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.desktop.sway.kanshi;
  # TODO: generate a list of per-profile outputs?
  isRotated = d: lib.lists.intersectLists ["90" "270" "flipped-90" "flipped-270"] [d.transform] != [];

  mkOutput = dev: x: y: extra: ({
      inherit (dev) criteria;
      position = "${builtins.toString (builtins.floor x)},${builtins.toJSON (builtins.floor y)}";
    }
    // extra);

  swaymsg = lib.getExe' config.wayland.windowManager.sway.package "swaymsg";

  execLib.getActiveWorkspace = ''${swaymsg} -t get_workspaces --raw | ${lib.getExe pkgs.jq} -r '.[] | select(.focused).name' '';
  execLib.switchToWorkspace = ws: ''
    ${swaymsg} "workspace ${ws}"
    while test "$(${execLib.getActiveWorkspace}) != "${ws}" ; do
      sleep 0.1
    done
  '';

  execLib.mkWorkspaces = ws:
    lib.pipe ws [
      (lib.attrsets.mapAttrsToList execLib.mkAssign)
      (a:
        [''old_workspace="$(${execLib.getActiveWorkspace})"'']
        ++ a
        ++ [''${swaymsg} "workspace $old_workspace"''])
      (execLib.mkExec "setup-workspaces")
    ];

  execLib.mkAssign = ws: dev: ''
    ${execLib.switchToWorkspace ws}
    ${swaymsg} 'move workspace to output ${builtins.toJSON dev.criteria}'
  '';
  execLib.mkExec = name: lines:
    lib.pipe lines [
      lib.lists.toList
      (builtins.concatStringsSep "\n")
      (pkgs.writeScript "kdn-${name}")
      builtins.toString
      lib.lists.toList
    ];

  recalc = d: let
    inherit (d) scale;
    rotated = isRotated d;
    width =
      if rotated
      then d.declaredHeight
      else d.declaredWidth;
    height =
      if rotated
      then d.declaredWidth
      else d.declaredHeight;
    w = width / scale;
    h = height / scale;
  in
    d
    // {
      inherit scale w h;
      width = w;
      height = h;
    };

  cleanOutput = output: {
    criteria = output.criteria;
    mode = output.mode;
    status = output.status or "enable";
    position = output.position or "0,0";
    scale = output.scale or 1.0;
    transform = output.transform or null;
    adaptiveSync = output.adaptiveSync or null;
  };
in {
  options.kdn.desktop.sway.kanshi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      apply = value: value && config.kdn.desktop.enable;
    };

    devices = lib.mkOption {
      type = with lib.types; attrsOf anything;
      apply =
        builtins.mapAttrs
        (_: entry: let
          device =
            {
              status = "enable";
              transform = null;
              adaptiveSync = null;
              scale = 1.0;
              position = "0,0";
            }
            // entry;

          parsed = lib.pipe device.mode [
            (builtins.split "x|@|Hz")
            (builtins.filter builtins.isString)
            (lib.lists.subtractLists [""])
            (builtins.map builtins.fromJSON)
            (lib.lists.zipListsWith lib.attrsets.nameValuePair ["declaredWidth" "declaredHeight" "refresh"])
            builtins.listToAttrs
          ];
        in
          recalc (device // parsed));
    };
    profiles = lib.mkOption {
      type = with lib.types; attrsOf anything;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.kanshi.enable = true;
      services.kanshi.settings =
        (lib.attrsets.mapAttrsToList
          (_: cfg: {output = cleanOutput cfg;})
          cfg.devices)
        ++ (lib.attrsets.mapAttrsToList
          (name: cfg: {
            profile =
              cfg
              // {
                inherit name;
              }
              // (
                if cfg ? exec
                then {
                  exec = lib.pipe cfg.exec [
                    lib.lists.toList
                    (builtins.concatStringsSep "\n")
                    (pkgs.writeScript "kanshi-profile-${name}-exec")
                    builtins.toString
                    lib.lists.toList
                  ];
                }
                else {}
              );
          })
          cfg.profiles);
    }
    {
      kdn.desktop.sway.kanshi.devices = {
        oams = {
          criteria = "Chimei Innolux Corporation 0x1540 Unknown";
          mode = "2560x1440@165Hz";
          scale = 1.25;
        };
        gb-m32uc = {
          criteria = "GIGA-BYTE TECHNOLOGY CO., LTD. M32UC 22090B013112";
          /*
           M32UC supports:
          - 144/160 Hz over DisplayPort
          - only <=120 Hz over HDMI 2.1 on Linux (licensing issue)
          - 144/120 Hz over HDMI 2.1 on other systems
          */
          mode = "3840x2160@120Hz";
          scale = 1.25;
        };
        asus-pg78q-hub = {
          /*
          ASUS ROG PG278Q, it started reporting own name when connected to laptop/through a HUB
           see https://zenwire.eu/pl/p/HUB-USB-C-10w1-Display-Port-1.4-HDMI-2.1-8K-4K-120Hz-60Hz-Full-HD-144Hz-USB-3.0-SD-Power-Delivery-100W-Macbook-M1-M2-Zenwire/288
          */
          criteria = "Ancor Communications Inc ROG PG278Q #ASNeZkML0ePd";
          mode = "2560x1440@120Hz";
        };
        asus-pg78q-dp = {
          #criteria = "DP-4";
          # this is the name set through EDID file
          criteria = lib.pipe osConfig.hardware.display.outputs [
            (lib.attrsets.mapAttrsToList lib.attrsets.nameValuePair)
            (builtins.filter (e: lib.strings.hasInfix "pg278q_120" (lib.strings.toLower e.value.edid)))
            (matches:
              if matches == []
              then "The Linux Foundation PG278Q_120 Linux #0"
              else (builtins.head matches).name)
          ];
          mode = "2560x1440@120Hz";
        };
        living-room-tv = {
          criteria = "LG Electronics LG TV SSCR2 0x01010101";
          # 120Hz doesn't work
          mode = "3840x2160@60Hz";
          # looks like it affects VLC's video output?
          # scale = 2.0;
          scale = 1.0;
        };
        kvm-brys = {
          criteria = "HDMI-A-1";
          #criteria = "VCS Connector 0x004515311"; # this doesn't work
          mode = "1920x1080@60Hz";
        };
      };
    }
    {
      kdn.desktop.sway.kanshi.profiles = with cfg.devices; {
        brys-kvm = {
          outputs = [
            (mkOutput kvm-brys 0 0 {})
          ];
        };
        brys-kvm-asus = {
          outputs = [
            (mkOutput kvm-brys 0 0 {})
            (mkOutput asus-pg78q-dp kvm-brys.w 0 {})
          ];
        };
        brys-kvm-only = {
          outputs = [
            (mkOutput kvm-brys 0 0 {})
            (mkOutput asus-pg78q-dp kvm-brys.w 0 {status = "disable";})
          ];
        };
        brys-desktop = {
          outputs = [
            (mkOutput asus-pg78q-dp 0 0 {})
            (mkOutput gb-m32uc asus-pg78q-dp.w 0 {mode = "3840x2160@144Hz";})
          ];
          exec = execLib.mkWorkspaces {
            "1" = gb-m32uc;
            "2" = asus-pg78q-dp;
            "3" = asus-pg78q-dp;
            "4" = gb-m32uc;
          };
        };
        brys-desktop-full = {
          outputs = [
            (mkOutput asus-pg78q-dp 0 0 {})
            (mkOutput gb-m32uc asus-pg78q-dp.w 0 {mode = "3840x2160@144Hz";})
            (mkOutput kvm-brys (asus-pg78q-dp.w + gb-m32uc.w + 500) 0 {})
          ];
          exec = execLib.mkWorkspaces {
            "1" = gb-m32uc;
            "2" = asus-pg78q-dp;
            "3" = asus-pg78q-dp;
            "4" = gb-m32uc;
            "9" = kvm-brys;
          };
        };
        oams = {
          outputs = [
            (mkOutput oams 0 0 {})
          ];
        };
        oams-desktop-full = {
          outputs = [
            (mkOutput asus-pg78q-hub 0 0 {})
            (mkOutput gb-m32uc asus-pg78q-hub.w 0 {})
            (mkOutput oams (asus-pg78q-hub.w + gb-m32uc.w) (gb-m32uc.h - oams.h) {})
          ];
          exec = execLib.mkWorkspaces {
            "1" = gb-m32uc;
            "2" = asus-pg78q-hub;
            "3" = gb-m32uc;
            "4" = oams;
          };
        };
        oams-desktop-m32uc = {
          outputs = [
            (mkOutput gb-m32uc 0 0 {})
            (mkOutput oams (gb-m32uc.w) (gb-m32uc.h - oams.h) {})
          ];
          exec = execLib.mkWorkspaces {
            "1" = gb-m32uc;
            "2" = oams;
            "3" = oams;
            "4" = gb-m32uc;
          };
        };
        oams-desktop-pg78q = {
          outputs = [
            (mkOutput asus-pg78q-hub 0 0 {})
            (mkOutput oams (asus-pg78q-hub.w) (asus-pg78q-hub.h - oams.h) {})
          ];
        };
        oams-tv = {
          outputs = [
            (mkOutput living-room-tv 0 0 {})
            (mkOutput oams (lib.trivial.max ((living-room-tv.w - oams.w) / 2) 0) living-room-tv.h {status = "enable";})
          ];
        };
        oams-tv-only = {
          outputs = [
            (mkOutput living-room-tv 0 0 {})
            (mkOutput oams (lib.trivial.max ((living-room-tv.w - oams.w) / 2) 0) living-room-tv.h {status = "disable";})
          ];
        };
        tv = {
          outputs = [
            (mkOutput living-room-tv 0 0 {})
          ];
        };
      };
    }
  ]);
}
