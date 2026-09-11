# kanshi, the sway output manager, as a den aspect. It ports `desktop/sway/home-manager/kanshi`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on the kanshi user service, it writes one kanshi output block per declared monitor, and it
# writes one kanshi profile block per declared arrangement. A profile can also run a script when
# kanshi applies it, and the script moves each sway workspace to the correct monitor.
#
# ## Class list: `homeManager`
#
# kanshi runs as a user service, and `services.kanshi` is a Home Manager option. So this aspect holds
# one target, and it declares its options inside that target.
#
# ## Where the monitor data lives
#
# This aspect holds **no** monitor identifier. `devices` and `profiles` are empty by default, so a
# consumer with no arrangement data gets the kanshi service alone. The consumer states its own
# monitors in its own data module, and it builds each entry with the two helpers this aspect
# publishes. The old tree keeps its data in `data/universal-deps/desktop-sway-kanshi.nix`; a den
# consumer keeps its own under `data/slots/`.
#
# ## What the port changes
#
# 1. **Inclusion replaces the `enable` flag.** The old option holds an `apply` that ANDs the desktop
#    flag into the kanshi flag. A den aspect has no `enable`, so the aspect list carries the choice.
# 2. **Two dead `let` bindings go.** The old `config` block defines `isRotated` and `recalc` a second
#    time and reads neither: `cleanOutput` is the only binding it uses. The `devices` `apply` above
#    holds the live copy of both. Measured 2026-09-11 by a read of all 220 lines.
# 3. **A platform guard replaces the parent-kind guard.** The old module emits its config only under
#    a NixOS parent. den has no such guard, so the target reads `pkgs.stdenv.hostPlatform.isLinux`.
#    kanshi is a Wayland program, and nixpkgs refuses it on `aarch64-darwin`. Measured 2026-09-11.
# 4. **The options move next to the target.** The aspect emits one class, so no second module needs
#    the declarations and a shared declaration file would only add a file.
#
# ## The helpers option keeps its shape
#
# `helpers` stays an `internal`, `readOnly` option of type `raw`. A consumer needs the two closures
# to write a `profiles` entry, and one of them reads the consumer's own sway package. So a plain
# helper file cannot serve them: it would need the consumer's evaluated config as an argument. `raw`
# keeps both values lazy, so a read forces neither and no consumer pays for the sway package path.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # `mkOutput` needs no module argument, so it sits here. It takes a device, an x position, a y
  # position and an extra attribute set, and it returns one kanshi output entry.
  mkOutput =
    dev: x: y: extra:
    (
      {
        inherit (dev) criteria;
        position = "${toString (builtins.floor x)},${builtins.toJSON (builtins.floor y)}";
      }
      // extra
    );

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-sway-kanshi;

      # `swaymsg` reads the consumer's own sway package, so it stays a lazy `let` binding. A read of
      # `helpers` returns two closures and forces neither.
      swaymsg = lib.getExe' config.wayland.windowManager.sway.package "swaymsg";

      execLib.getActiveWorkspace = "${swaymsg} -t get_workspaces --raw | ${lib.getExe pkgs.jq} -r '.[] | select(.focused).name'";
      execLib.switchToWorkspace = ws: ''
        ${swaymsg} "workspace ${ws}"
        while test "$(${execLib.getActiveWorkspace})" != "${ws}" ; do
          sleep 0.1
        done
      '';

      execLib.mkWorkspaces =
        ws:
        lib.pipe ws [
          (lib.attrsets.mapAttrsToList execLib.mkAssign)
          (
            a:
            [ ''old_workspace="$(${execLib.getActiveWorkspace})"'' ]
            ++ a
            ++ [ ''${swaymsg} "workspace $old_workspace"'' ]
          )
          (execLib.mkExec "setup-workspaces")
        ];

      execLib.mkAssign = ws: dev: ''
        ${execLib.switchToWorkspace ws}
        ${swaymsg} 'move workspace to output ${builtins.toJSON dev.criteria}'
      '';
      execLib.mkExec =
        name: lines:
        lib.pipe lines [
          lib.lists.toList
          (builtins.concatStringsSep "\n")
          (pkgs.writeScript "kdn-${name}")
          toString
          lib.lists.toList
        ];

      # kanshi accepts these seven keys in an output block. The `devices` `apply` adds calculated
      # keys such as `w` and `h`, and a consumer reads those to place a monitor. So the write drops
      # every key kanshi does not know.
      cleanOutput = output: {
        criteria = output.criteria;
        mode = output.mode;
        status = output.status or "enable";
        position = output.position or "0,0";
        scale = output.scale or 1.0;
        transform = output.transform or null;
        adaptiveSync = output.adaptiveSync or null;
      };
    in
    {
      options.kdn.desktop-sway-kanshi.devices = lib.mkOption {
        type = with lib.types; attrsOf anything;
        default = { };
        example = lib.literalExpression ''
          {
            main.criteria = "Some Vendor Some Model ABC123";
            main.mode = "3840x2160@60Hz";
          }
        '';
        description = ''
          The monitors, by short name. Each entry takes a kanshi `criteria` and a `mode`, and it can
          also take `status`, `transform`, `adaptiveSync`, `scale` and `position`.

          The `apply` below parses `mode` and adds the calculated keys `declaredWidth`,
          `declaredHeight`, `refresh`, `w`, `h`, `width` and `height`. `w` and `h` hold the size the
          compositor reports, so they follow the scale and the rotation. A `profiles` entry reads
          them to place the next monitor.
        '';
        apply = builtins.mapAttrs (
          _: entry:
          let
            device = {
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
              (lib.lists.subtractLists [ "" ])
              (map builtins.fromJSON)
              (lib.lists.zipListsWith lib.attrsets.nameValuePair [
                "declaredWidth"
                "declaredHeight"
                "refresh"
              ])
              builtins.listToAttrs
            ];

            isRotated =
              d: lib.lists.intersectLists [ "90" "270" "flipped-90" "flipped-270" ] [ d.transform ] != [ ];

            recalc =
              d:
              let
                inherit (d) scale;
                rotated = isRotated d;
                width = if rotated then d.declaredHeight else d.declaredWidth;
                height = if rotated then d.declaredWidth else d.declaredHeight;
                w = width / scale;
                h = height / scale;
              in
              d
              // {
                inherit scale w h;
                width = w;
                height = h;
              };
          in
          recalc (device // parsed)
        );
      };

      options.kdn.desktop-sway-kanshi.profiles = lib.mkOption {
        type = with lib.types; attrsOf anything;
        default = { };
        example = lib.literalExpression ''
          {
            solo.outputs = [ (helpers.mkOutput devices.main 0 0 { }) ];
          }
        '';
        description = ''
          kanshi profiles, by name. Each entry takes an `outputs` list and an optional `exec` entry.
          Build an `outputs` element with `helpers.mkOutput`, and an `exec` entry with
          `helpers.mkWorkspaces`.

          The default is an empty set, so a consumer with no arrangement data gets kanshi with the
          per-device outputs only.
        '';
      };

      options.kdn.desktop-sway-kanshi.helpers = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        readOnly = true;
        default = {
          inherit mkOutput;
          inherit (execLib) mkWorkspaces;
        };
        description = ''
          The helpers that a `profiles` definition needs. A consumer's own data module reads them.

          `mkOutput` takes a device, an x position, a y position and an extra attribute set.
          `mkWorkspaces` takes a workspace-name-to-device map and returns an `exec` list.

          `lib.types.raw` keeps both values lazy, so a read forces neither closure.
        '';
      };

      # kanshi is a Wayland program. See change 3 in the header.
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        services.kanshi.enable = true;
        services.kanshi.settings =
          (lib.attrsets.mapAttrsToList (_: device: { output = cleanOutput device; }) cfg.devices)
          ++ (lib.attrsets.mapAttrsToList (name: profile: {
            profile =
              profile
              // {
                inherit name;
              }
              // (
                if profile ? exec then
                  {
                    exec = lib.pipe profile.exec [
                      lib.lists.toList
                      (builtins.concatStringsSep "\n")
                      (pkgs.writeScript "kanshi-profile-${name}-exec")
                      toString
                      lib.lists.toList
                    ];
                  }
                else
                  { }
              );
          }) cfg.profiles);
      };
    };
in
{
  kdn.desktop-sway-kanshi.homeManager = homeTarget;
}
