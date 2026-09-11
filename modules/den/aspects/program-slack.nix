# `kdn.programs.slack`, as a den aspect. It ports `modules/universal/programs/slack/default.nix`.
#
# The pipewire rule stops slack from taking an exclusive hold on the microphone.
{ kdn, ... }:
{
  kdn.program-slack.includes = [ kdn.apps ];

  kdn.program-slack.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        kdn.apps."slack" = {
          enable = true;
          dirs.config = [ "Slack" ];
        };

        xdg.configFile."pipewire/pipewire.conf.d/51-slack.conf".text = builtins.toJSON {
          "node.rules" = [
            {
              matches = [
                { "application.process.binary" = config.kdn.apps."slack".package.final.meta.mainProgram; }
              ];
              actions.update-props."node.dont-reconnect" = false;
            }
          ];
        };
      };
    };
}
