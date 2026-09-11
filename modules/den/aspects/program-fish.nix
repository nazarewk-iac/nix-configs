# `kdn.programs.fish`, as a den aspect. It ports `modules/universal/programs/fish/default.nix`.
#
# Three classes: `nixos`, `darwin` and `homeManager`. Each class is a separate evaluation, so the two
# options need one declaration module that all three import.
#
# Design B applies. The old module writes `kdn.env.packages`; each target below writes the native
# option of its own class.
{ ... }:
let
  # One declaration, three importers. `imports` takes this same function value in each target, so the
  # module system sees one module and never a duplicate declaration.
  declaration =
    { lib, ... }:
    {
      options.kdn.programs.fish.defaultShell = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Make fish the default login shell of every user the class supports.

          On NixOS it sets `users.defaultUserShell`. On nix-darwin it adds `root` to
          `defaultShellUsers`, because nix-darwin holds no equivalent option.
        '';
      };

      options.kdn.programs.fish.defaultShellUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          User names that get fish as their login shell.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it — a plain
          definition then replaces the default instead of adding to it.
        '';
      };
    };

  filterPackages = import ../common/filter-packages.nix;

  # The three interactive helpers the old module puts on the system path.
  hostPackages =
    pkgs: with pkgs; [
      grc
      fzf
      babelfish
    ];

  # Shared between `nixos` and `darwin`. Both classes hold `programs.fish`, `environment.shells` and
  # `users.users.<name>.shell`.
  hostCommon =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.fish;
    in
    {
      imports = [ declaration ];

      config = {
        environment.shells = [ config.programs.fish.package ];
        environment.systemPackages = (filterPackages { inherit lib; }) (hostPackages pkgs);

        programs.fish.enable = true;
        programs.fish.useBabelfish = false;

        users.users = lib.pipe cfg.defaultShellUsers [
          (map (username: {
            name = username;
            value.shell = pkgs.fish;
          }))
          builtins.listToAttrs
        ];
      };
    };
in
{
  kdn.program-fish.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ hostCommon ];

      # About `fish` that prints `linux` twice: https://github.com/danth/stylix/issues/526
      config.users.defaultUserShell = lib.mkIf config.kdn.programs.fish.defaultShell pkgs.fish;
    };

  kdn.program-fish.darwin =
    { config, lib, ... }:
    {
      imports = [ hostCommon ];

      # nix-darwin holds no `users.defaultUserShell`, so the aspect names the one user it can set.
      config.kdn.programs.fish.defaultShellUsers = lib.optionals config.kdn.programs.fish.defaultShell [
        "root"
      ];
    };

  kdn.program-fish.homeManager =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];

      config = {
        home.packages = (filterPackages { inherit lib; }) (hostPackages pkgs);

        xdg.configFile."fish/config.fish".force = true;

        programs.fish.enable = true;
        programs.fish.interactiveShellInit = ''
          set fish_greeting # Disable greeting
          # see https://github.com/franciscolourenco/done
          set -U __done_sway_ignore_visible 1
          fish_vi_key_bindings --no-erase
        '';
        programs.fish.plugins = with pkgs.fishPlugins; [
          {
            name = "grc";
            src = grc.src;
          }
          {
            name = "done";
            src = done.src;
          }
          {
            name = "forgit";
            src = forgit.src;
          }
          {
            name = "fzf";
            src = fzf-fish.src;
          }
          {
            name = "fish-history-merge";
            src = pkgs.fetchFromGitHub {
              owner = "2m";
              repo = "fish-history-merge";
              rev = "7e415b8ab843a64313708273cf659efbf471ad39";
              sha256 = "sha256-oy32I92sYgEbeVX41Oic8653eJY5bCE/b7EjZuETjMI=";
            };
          }
        ];
      };
    };
}
