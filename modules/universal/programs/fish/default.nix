{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.fish;
in
{
  options.kdn.programs.fish = {
    enable = lib.mkEnableOption "fish interactive shell";
    defaultShell = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    defaultShellUsers = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [
          { kdn.programs.fish = kdnConfig.util.modules.forwardAttrsAsDefaults cfg; }
        ];
      })
      {
        kdn.env.packages = with pkgs; [
          grc
          fzf
          babelfish
        ];
      }
      (kdnConfig.util.ifHM {
        xdg.configFile."fish/config.fish".force = true;
        programs.fish = {
          enable = true;
          interactiveShellInit = ''
            set fish_greeting # Disable greeting
            # see https://github.com/franciscolourenco/done
            set -U __done_sway_ignore_visible 1
            fish_vi_key_bindings --no-erase
          '';
          plugins = with pkgs.fishPlugins; [
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
            #{ name = "hydro"; src = hydro.src; }
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
      })
      (kdnConfig.util.ifTypes [ "nixos" "darwin" ] {
        environment.shells = [ config.programs.fish.package ];
        programs.fish = {
          enable = true;
          useBabelfish = false;
        };
        users.users = lib.pipe cfg.defaultShellUsers [
          (map (username: {
            name = username;
            value.shell = pkgs.fish;
          }))
          builtins.listToAttrs
        ];
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        # note: about `fish` printing `linux` twice https://github.com/danth/stylix/issues/526
        users.defaultUserShell = lib.mkIf cfg.defaultShell pkgs.fish;
      })
      (kdnConfig.util.ifTypes [ "darwin" ] {
        kdn.programs.fish.defaultShellUsers = lib.optionals cfg.defaultShell [ "root" ];
      })
    ]
  );
}
