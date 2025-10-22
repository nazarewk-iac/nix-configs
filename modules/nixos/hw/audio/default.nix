{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.audio;
in {
  options = {
    kdn.hw.audio = {
      enable = lib.mkEnableOption "audio setup with Pipewire";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # SOUND - PipeWire
        # see additional pavucontrol package
        security.rtkit.enable = true;
        services.pulseaudio.enable = false;
        services.pipewire.enable = true;

        services.pipewire.alsa.enable = true;
        services.pipewire.alsa.support32Bit = true;
        services.pipewire.jack.enable = true;
        services.pipewire.pulse.enable = true;
        services.pipewire.wireplumber.enable = true;

        services.pipewire.wireplumber.extraConfig.debug = lib.mkIf false {
          "context.properties" = {
            "log.level" = 3;
            "log.rules.enabled" = true;
          };
        };

        services.pulseaudio.extraModules = [
          pkgs.pulseaudio-modules-bt
        ];

        hardware.bluetooth.package = pkgs.bluez5-experimental;
        environment.systemPackages = with pkgs; [
          pulseaudio # pactl
          libopenaptx
          libfreeaptx
          pulseaudio
        ];
        home-manager.sharedModules = [
          {
            kdn.hw.disks.persist."usr/config".directories = [
              ".config/pulse"
              ".config/pipewire"
              ".local/state/wireplumber"
            ];
            kdn.hw.disks.persist."usr/config".files = [
              ".config/pavucontrol.ini"
            ];
          }
        ];
      }
      (lib.mkIf config.kdn.desktop.enable {
        environment.systemPackages = with pkgs; [
          pavucontrol
          helvum # A GTK patchbay for pipewire
        ];
        home-manager.sharedModules = [
          {
            # https://forum.endeavouros.com/t/tutorial-volume-normalization-on-pipewire/22315
            services.easyeffects.enable = true;
            services.easyeffects.extraPresets = let
              LoudnessEqualizer =
                lib.pipe
                {
                  url = "https://raw.githubusercontent.com/Digitalone1/EasyEffects-Presets/32d0f416e7867ccffdab16c7fe396f2522d04b2e/LoudnessEqualizer.json";
                  sha256 = "sha256-lphnEyuRestYTEtspHhkpdG0n2oKzKfrX5L1X7wZB4k=";
                }
                [
                  pkgs.fetchurl
                  builtins.readFile
                  builtins.fromJSON
                ];
            in {
              inherit LoudnessEqualizer;
            };
          }
        ];
        # required by easyeffects
        kdn.programs.dconf.enable = true;
      })
    ]
  );
}
