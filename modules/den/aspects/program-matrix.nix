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

      # A recorded deviation from old-tree parity. The old module defaults nheko on, but nheko needs
      # `olm`, and nixpkgs marks `olm` insecure. Home Manager's own `programs.nheko` module writes
      # the package straight into `home.packages`, so the shared package filter never sees it.
      # An aspect has no reachable `enable`, so inclusion is the only switch. A consumer who
      # includes this aspect must get a configuration that evaluates. The old default cannot
      # evaluate without `permittedInsecurePackages`, so parity here means a broken default.
      # A consumer who wants nheko sets this option to `true` and permits `olm` as well.
      options.kdn.programs.matrix.nheko.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install and configure nheko.

          The default is `false`, because nheko needs the insecure `olm` package. Turn it on and
          add `olm` to `nixpkgs.config.permittedInsecurePackages` yourself.
        '';
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
