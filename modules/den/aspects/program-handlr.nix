# `kdn.programs.handlr`, as a den aspect. It ports `modules/universal/programs/handlr/default.nix`.
#
# Note: `xdg-open` forwards to the available resource openers, but many applications skip `xdg-open`
# and use the desktop integration directly, such as `gio open`, `exo open` or `kde-open`.
# See https://wiki.archlinux.org/title/Xdg-utils#xdg-open
# See https://wiki.archlinux.org/title/Default_applications
# See https://github.com/chmln/handlr/issues/62
#
# ## Two changes the aspect rules force
#
# `xdg-utils.enable` is a reachable `enable` option, so it becomes `xdg-utils.use`.
#
# The old module writes the `handlr.toml` file and a sway keybinding from a `nixos` target, through
# `home-manager.sharedModules`. den holds no such bridge. The `handlr.toml` write moves into the
# `homeManager` target. The keybinding write is dropped: it reads `config.kdn.desktop.sway.keys`, and
# the sway aspect belongs to another batch. Mark for owner review.
{ ... }:
let
  declaration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.handlr;
    in
    {
      options.kdn.programs.handlr.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.handlr-regex;
        description = "The handlr build the aspect installs.";
      };

      options.kdn.programs.handlr.xdg-utils.use = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Take over the `xdg-open` part of `pkgs.xdg-utils`.

          The old module names this option `xdg-utils.enable`. An aspect holds no reachable `enable`,
          so the name changed and the behaviour did not.
        '';
      };

      options.kdn.programs.handlr.xdg-utils.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.writeShellApplication {
          name = "xdg-open";
          runtimeInputs = [ cfg.package ];
          text = ''handlr open "$@"'';
        };
        description = "The `xdg-open` replacement the aspect installs at a high priority.";
      };
    };

  filterPackages = import ../common/filter-packages.nix;

  packagesOf =
    lib: cfg:
    (filterPackages { inherit lib; }) (
      [ cfg.package ] ++ lib.optional cfg.xdg-utils.use (lib.meta.hiPrio cfg.xdg-utils.package)
    );

  hostTarget =
    { config, lib, ... }:
    {
      imports = [ declaration ];

      config.environment.systemPackages = packagesOf lib config.kdn.programs.handlr;
    };
in
{
  kdn.program-handlr.nixos = hostTarget;
  kdn.program-handlr.darwin = hostTarget;

  kdn.program-handlr.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        { home.packages = packagesOf lib config.kdn.programs.handlr; }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          xdg.configFile."handlr/handlr.toml".source = (pkgs.formats.toml { }).generate "handlr.toml" {
            enable_selector = true;
            selector = "${lib.getExe pkgs.wofi} --dmenu --insensitive --normal-window --prompt='Open With: '";
          };
        })
      ];
    };
}
