{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.tidal;
in {
  options.kdn.programs.tidal = {
    enable = lib.mkEnableOption "tidal setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        xdg.configFile."pipewire/pipewire.conf.d/51-tidal-hifi.conf".text = builtins.toJSON {
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
                  "application.process.binary" = config.kdn.programs.apps.tidal.package.final.meta.mainProgram;
                }
              ];
              actions = {
                "update-props" = {
                  "application.icon_name" = "tidal-hifi";
                  "application.name" = "Tidal HiFi";
                  "media.name" = "Tidal HiFi Audio";
                  "node.description" = "Tidal HiFi";
                  "node.name" = "Tidal HiFi";
                };
              };
            }
          ];
        };
        kdn.programs.apps.tidal = {
          enable = true;
          package.original = pkgs.tidal-hifi;
          dirs.cache = [];
          dirs.config = ["tidal-hifi"];
          dirs.data = [];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}
