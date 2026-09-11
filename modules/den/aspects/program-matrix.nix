# `kdn.programs.matrix`, as a den aspect. It ports `modules/universal/programs/element/default.nix`.
#
# The aspect name follows the option path, so it is `program-matrix` and not `program-element`.
#
# ## Four renames the aspect rules force
#
# `element.enable`, `gomuks.enable`, `fluffychat.enable` and `nheko.enable` are reachable `enable`
# options, so each becomes `.use`. The `kdn.apps.<name>.enable` writes stay: an `enable` inside an
# `attrsOf submodule` is out of reach of the walk.
#
# ## One workaround the port drops
#
# The old module writes `gomuks.enable = lib.mkForce false` right after it declares the default
# `true`, because of a 2024 nixpkgs build failure. The aspect gives `gomuks.use` a `false` default
# instead, so a consumer turns it on with a plain assignment. Mark for owner review.
{ kdn, ... }:
{
  kdn.program-matrix.includes = [ kdn.apps ];

  kdn.program-matrix.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.matrix;
    in
    {
      options.kdn.programs.matrix.element.use = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the Element desktop client.";
      };

      options.kdn.programs.matrix.gomuks.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install the gomuks clients.

          The old module declares a `true` default and then forces `false`, because of a nixpkgs build
          failure of 2024. The default here is `false`, so a plain assignment turns it on.
        '';
      };

      options.kdn.programs.matrix.fluffychat.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install FluffyChat. It holds no persistence entry yet.";
      };

      options.kdn.programs.matrix.nheko.use = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install and configure nheko.";
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.element.use {
          kdn.apps.element-desktop = {
            enable = true;
            package.original = pkgs.element-desktop.override {
              commandLineArgs = "--password-store=gnome-libsecret --disable-gpu";
            };
            dirs.config = [ "Element" ];
          };
        })

        (lib.mkIf cfg.gomuks.use {
          # The old CLI client. It stays off by default.
          kdn.apps.gomuks = {
            enable = lib.mkDefault false;
            package.original = pkgs.gomuks;
            dirs.cache = [ "gomuks" ];
            dirs.config = [ "gomuks" ];
            dirs.data = [ "gomuks" ];
            dirs.state = [ "gomuks" ];
          };
          kdn.apps.gomuks-web = {
            enable = lib.mkDefault true;
            package.original = pkgs.gomuks-web;
            dirs.cache = [ "gomuks" ];
            dirs.config = [ "gomuks" ];
            dirs.data = [ "gomuks" ];
            dirs.state = [ "gomuks" ];
          };
        })

        (lib.mkIf cfg.fluffychat.use {
          kdn.apps.fluffychat = {
            enable = true;
            package.original = pkgs.fluffychat;
          };
        })

        (lib.mkIf cfg.nheko.use {
          programs.nheko.enable = true;
          kdn.apps.nheko = {
            enable = true;
            package.original = pkgs.nheko;
            dirs.cache = [ "nheko" ];
            dirs.config = [ "nheko" ];
            dirs.data = [ "nheko" ];
          };
        })
      ];
    };
}
