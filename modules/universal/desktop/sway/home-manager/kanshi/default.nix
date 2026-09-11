{
  osConfig,
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
let
  /*
    Helpers that a `profiles` definition needs.

    They sit at the top level, so the `helpers` option below can publish them to a data
    module. `swaymsg` reads a Home Manager option that a host context does not declare, so it
    stays a lazy `let` binding. A read of `helpers` returns two closures and forces neither.
  */
  mkOutput =
    dev: x: y: extra:
    (
      {
        inherit (dev) criteria;
        position = "${toString (builtins.floor x)},${builtins.toJSON (builtins.floor y)}";
      }
      // extra
    );

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
in
{
  options.kdn.desktop.sway.kanshi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      apply = value: value && config.kdn.desktop.enable;
    };

    devices = lib.mkOption {
      type = with lib.types; attrsOf anything;
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
    profiles = lib.mkOption {
      type = with lib.types; attrsOf anything;
      description = ''
        kanshi profiles, by name. Each entry takes an `outputs` list and an optional `exec`
        entry. Build an `outputs` element with `helpers.mkOutput`, and an `exec` entry with
        `helpers.mkWorkspaces`.

        `attrsOf` supplies an empty set, so a host with no arrangement data gets kanshi with
        the per-device outputs only.
      '';
    };

    helpers = lib.mkOption {
      type = lib.types.raw;
      internal = true;
      readOnly = true;
      default = {
        inherit mkOutput;
        inherit (execLib) mkWorkspaces;
      };
      description = ''
        Helpers that a `profiles` definition needs. `data/desktop-sway-kanshi.nix` reads them.

        `mkOutput` takes a device, an x position, a y position and an extra attribute set.
        `mkWorkspaces` takes a workspace-name-to-device map and returns an `exec` list.

        `lib.types.raw` keeps both values lazy, so a host context never forces the sway
        package path.
      '';
    };
  };

  config = lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
    let
      cfg = config.kdn.desktop.sway.kanshi;
      # TODO: generate a list of per-profile outputs?
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
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          services.kanshi.enable = true;
          services.kanshi.settings =
            (lib.attrsets.mapAttrsToList (_: cfg: { output = cleanOutput cfg; }) cfg.devices)
            ++ (lib.attrsets.mapAttrsToList (name: cfg: {
              profile =
                cfg
                // {
                  inherit name;
                }
                // (
                  if cfg ? exec then
                    {
                      exec = lib.pipe cfg.exec [
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
        }
      ]
    )
  );
}
