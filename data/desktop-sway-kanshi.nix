/*
  Personal display data for `kdn.desktop.sway.kanshi`.

  This file is a module, not a data attribute set. It assigns two options that
  `modules/universal/desktop/sway/home-manager/kanshi/default.nix` declares, so that module
  holds no display serial and no personal arrangement.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file, and both options fall back to the empty set.

  The two guards copy the module. `hasParentOfAnyType [ "nixos" ]` keeps the data out of a host
  context and out of a darwin Home Manager, because `osConfig` and
  `config.wayland.windowManager.sway` exist only in a Home Manager under a NixOS parent.
  `lib.mkIf cfg.enable` keeps both options empty while kanshi is off.
*/
{
  config,
  lib,
  kdnConfig,
  osConfig ? { },
  ...
}:
let
  cfg = config.kdn.desktop.sway.kanshi;
  inherit (cfg.helpers) mkOutput mkWorkspaces;
in
{
  config = lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.desktop.sway.kanshi.devices = {
            oams = {
              criteria = "Chimei Innolux Corporation 0x1540 Unknown";
              mode = "2560x1440@165Hz";
              #scale = 1.25;
              scale = 1.0;
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
                (
                  matches:
                  if matches == [ ] then "The Linux Foundation PG278Q_120 Linux #0" else (builtins.head matches).name
                )
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
                (mkOutput kvm-brys 0 0 { })
              ];
            };
            brys-kvm-asus = {
              outputs = [
                (mkOutput kvm-brys 0 0 { })
                (mkOutput asus-pg78q-dp kvm-brys.w 0 { })
              ];
            };
            brys-kvm-only = {
              outputs = [
                (mkOutput kvm-brys 0 0 { })
                (mkOutput asus-pg78q-dp kvm-brys.w 0 { status = "disable"; })
              ];
            };
            brys-desktop = {
              outputs = [
                (mkOutput asus-pg78q-dp 0 0 { })
                (mkOutput gb-m32uc asus-pg78q-dp.w 0 { mode = "3840x2160@144Hz"; })
              ];
              exec = mkWorkspaces {
                "1" = gb-m32uc;
                "2" = asus-pg78q-dp;
                "3" = asus-pg78q-dp;
                "4" = gb-m32uc;
              };
            };
            brys-desktop-full = {
              outputs = [
                (mkOutput asus-pg78q-dp 0 0 { })
                (mkOutput gb-m32uc asus-pg78q-dp.w 0 { mode = "3840x2160@144Hz"; })
                (mkOutput kvm-brys (asus-pg78q-dp.w + gb-m32uc.w + 500) 0 { })
              ];
              exec = mkWorkspaces {
                "1" = gb-m32uc;
                "2" = asus-pg78q-dp;
                "3" = asus-pg78q-dp;
                "4" = gb-m32uc;
                "9" = kvm-brys;
              };
            };
            oams = {
              outputs = [
                (mkOutput oams 0 0 { })
              ];
            };
            oams-desktop-full = {
              outputs = [
                (mkOutput asus-pg78q-hub 0 0 { })
                (mkOutput gb-m32uc asus-pg78q-hub.w 0 { })
                (mkOutput oams (asus-pg78q-hub.w + gb-m32uc.w) (gb-m32uc.h - oams.h) { })
              ];
              exec = mkWorkspaces {
                "1" = gb-m32uc;
                "2" = asus-pg78q-hub;
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
                (mkOutput asus-pg78q-hub 0 0 { })
                (mkOutput oams (asus-pg78q-hub.w) (asus-pg78q-hub.h - oams.h) { })
              ];
            };
            oams-tv = {
              outputs = [
                (mkOutput living-room-tv 0 0 { })
                (mkOutput oams (lib.trivial.max ((living-room-tv.w - oams.w) / 2) 0) living-room-tv.h {
                  status = "enable";
                })
              ];
            };
            oams-tv-only = {
              outputs = [
                (mkOutput living-room-tv 0 0 { })
                (mkOutput oams (lib.trivial.max ((living-room-tv.w - oams.w) / 2) 0) living-room-tv.h {
                  status = "disable";
                })
              ];
            };
            tv = {
              outputs = [
                (mkOutput living-room-tv 0 0 { })
              ];
            };
          };
        }
      ]
    )
  );
}
