# `kdn.programs.tidal`, as a den aspect. It ports `modules/universal/programs/tidal/default.nix`.
{ kdn, ... }:
{
  kdn.program-tidal.includes = [ kdn.apps ];

  kdn.program-tidal.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps."tidal-hifi" = {
          enable = true;
          package.original = pkgs.tidal-hifi;
          dirs.config = [ "tidal-hifi" ];
        };

        xdg.configFile."pipewire/pipewire.conf.d/51-tidal-hifi.conf".text = builtins.toJSON {
          "node.rules" = [
            {
              matches = [
                { "application.process.binary" = config.kdn.apps."tidal-hifi".package.final.meta.mainProgram; }
              ];
              actions.update-props."node.dont-reconnect" = false;
            }
          ];
        };
      };
    };
}
