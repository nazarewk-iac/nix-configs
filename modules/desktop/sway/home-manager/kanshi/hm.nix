{ osConfig, config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;
  # TODO: assign workspaces with `profile.exec` https://git.sr.ht/~emersion/kanshi/tree/master/item/doc/kanshi.5.scd
  # TODO: generate a list of per-profile outputs?
  isRotated = d: lib.lists.intersectLists [ "90" "270" "flipped-90" "flipped-270" ] [ d.transform ] != [ ];

  mkOutput = dev: x: y: cfg: {
    inherit (dev) criteria;
    position = "${builtins.toString (builtins.floor x)},${builtins.toJSON (builtins.floor y)}";
  } // cfg;

  swaymsg = lib.getExe' config.wayland.windowManager.sway.package "swaymsg";

  mkWorkspaces = lib.attrsets.mapAttrsToList (ws: dev:
    "${swaymsg} workspace ${ws}, move workspace to output '${builtins.toJSON dev.criteria}'"
  );

  recalc = d:
    let
      inherit (d) scale;
      rotated = isRotated d;
      width = if rotated then d.declaredHeight else d.declaredWidth;
      height = if rotated then d.declaredWidth else d.declaredHeight;
      w = width / scale;
      h = height / scale;
    in
    d // {
      inherit scale w h;
      width = w;
      height = h;
    };
  devices = builtins.mapAttrs
    (_: entry:
      let
        cfg = {
          status = null;
          transform = null;
          adaptiveSync = null;
          scale = 1.0;
          position = "0,0";
        } // entry;

        parsed = lib.pipe cfg.mode [
          (builtins.split "x|@|Hz")
          (builtins.filter builtins.isString)
          (lib.lists.subtractLists [ "" ])
          (builtins.map builtins.fromJSON)
          (lib.lists.zipListsWith lib.attrsets.nameValuePair [ "declaredWidth" "declaredHeight" "refresh" ])
          builtins.listToAttrs
        ];
      in
      recalc (cfg // parsed))
    {
      oams = {
        criteria = "Chimei Innolux Corporation 0x1540 Unknown";
        mode = "2560x1440@165Hz";
        scale = 1.25;
      };
      gb-m32uc = {
        criteria = "GIGA-BYTE TECHNOLOGY CO., LTD. M32UC 22090B013112";
        /* M32UC supports:
          - 144/160 Hz over DisplayPort
          - only <=120 Hz over HDMI 2.1 on Linux (licensing issue)
          - 144/120 Hz over HDMI 2.1 on other systems
        */
        mode = "3840x2160@120Hz";
      };
      asus-pg78q-hub = {
        /* ASUS ROG PG278Q, it started reporting own name when connected to laptop/through a HUB
            see https://zenwire.eu/pl/p/HUB-USB-C-10w1-Display-Port-1.4-HDMI-2.1-8K-4K-120Hz-60Hz-Full-HD-144Hz-USB-3.0-SD-Power-Delivery-100W-Macbook-M1-M2-Zenwire/288
         */
        criteria = "Ancor Communications Inc ROG PG278Q #ASNeZkML0ePd";
        mode = "2560x1440@120Hz";
      };
      asus-pg78q-dp = {
        #criteria = "DP-1";
        # this is the name set through EDID file
        criteria = "The Linux Foundation PG278Q_120 Linux #0";
        mode = "2560x1440@120Hz";
      };
      manta-50lun120d = {
        # Manta 50LUN120D https://manta.com.pl/produkt/50lun120d/
        criteria = "XXX AAA Unknown";
        mode = "3840x2160@60Hz";
        # looks like it affects VLC's video output?
        # scale = 2.0;
        scale = 1.0;
      };
    };
  profiles = with devices; {
    desktop-full = {
      outputs = [
        (mkOutput asus-pg78q-dp 0 0 { mode = "3840x2160@165Hz"; })
        (mkOutput gb-m32uc asus-pg78q-dp.w 0 { })
      ];
      exec = mkWorkspaces {
        "1" = gb-m32uc;
        "2" = asus-pg78q-dp;
        "3" = asus-pg78q-dp;
        "4" = gb-m32uc;
      };
    };
    oams = {
      outputs = [
        (mkOutput oams 0 0 { })
      ];
    };
    oams-desktop-full = {
      outputs = [
        (mkOutput asus-pg78q-dp 0 0 { })
        (mkOutput gb-m32uc asus-pg78q-dp.w 0 { })
        (mkOutput oams (asus-pg78q-dp.w + gb-m32uc.w) (gb-m32uc.h - oams.h) { })
      ];
      exec = mkWorkspaces {
        "1" = gb-m32uc;
        "2" = asus-pg78q-dp;
        "3" = gb-m32uc;
        "4" = oams;
      };
    };
    oams-desktop-m32uc = {
      outputs = [
        (mkOutput gb-m32uc 0 0 { })
        (mkOutput oams (gb-m32uc.w) (gb-m32uc.h - oams.h) { })
      ];
      exec = mkWorkspaces {
        "1" = gb-m32uc;
        "2" = oams;
        "3" = oams;
        "4" = gb-m32uc;
      };
    };
    oams-desktop-pg78q = {
      outputs = [
        (mkOutput asus-pg78q-dp 0 0 { })
        (mkOutput oams (asus-pg78q-dp.w) (asus-pg78q-dp.h - oams.h) { })
      ];
    };
    oams-tv = {
      outputs = [
        (mkOutput manta-50lun120d 0 0 { })
        (mkOutput oams (lib.trivial.max ((manta-50lun120d.w - oams.w) / 2) 0) manta-50lun120d.h { })
      ];
    };
    oams-tv-only = {
      outputs = [
        (mkOutput manta-50lun120d 0 0 { })
        (mkOutput oams (lib.trivial.max ((manta-50lun120d.w - oams.w) / 2) 0) manta-50lun120d.h { status = "disable"; })
      ];
    };
    tv = {
      outputs = [
        (mkOutput manta-50lun120d 0 0 { })
      ];
    };
  };
in
{
  options.kdn.desktop.sway.kanshi = {
    enable = lib.mkEnableOption "Kanshi (automatic display configuration)";
  };

  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) (lib.mkMerge [
    {
      services.kanshi.enable = true;
      services.kanshi.settings = (lib.attrsets.mapAttrsToList
        (_: cfg: {
          output = {
            inherit (cfg) criteria status mode position scale transform adaptiveSync;
          };
        })
        devices)
      ++ (lib.attrsets.mapAttrsToList
        (name: cfg: { profile = cfg // { inherit name; }; })
        profiles)
      ;
    }
  ]);
}
