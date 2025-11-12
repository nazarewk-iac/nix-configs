{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.slack;
in {
  options.kdn.programs.slack = {
    enable = lib.mkEnableOption "slack setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        xdg.configFile."pipewire/pipewire.conf.d/51-slack.conf".text = builtins.toJSON {
          /*
          there is no rule matching on client objects
          in pulseaudio, you can use pulse.rules with update-props, that should update the client properties

          see https://matrix.to/#/!kySKEYzDwVhedDCSoX:matrix.org/$68PPYfLJ9ZYxcCUR43Kn6I8uD0XFHvyV6r6eJYdN7-k?via=matrix.org&via=kde.org&via=fedora.im
          */
          # PulseAudio Volume Control still sees it as Chromium due to PipeWire Client configuration
          # but PipeWire Client configuration cannot be edited at all
          "node.rules" = [
            {
              matches = [
                {
                  "application.process.binary" = config.kdn.apps.slack.package.final.meta.mainProgram;
                }
              ];
              actions = {
                "update-props" = {
                  "application.icon_name" = "slack";
                  "application.name" = "Slack";
                  "media.name" = "Slack Audio";
                  "node.description" = "Slack";
                  "node.name" = "Slack";
                };
              };
            }
          ];
        };
        kdn.apps.slack = {
          enable = true;
          dirs.cache = [];
          dirs.config = ["Slack"];
          dirs.data = [];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}
