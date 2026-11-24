# `kdn-audio`: join several audio outputs into one virtual output, and keep a stored profile
# active whenever a given mix of devices is connected.
#
# The profiles are declared here and written to `~/.config/kdn-audio/profiles/`, so a Nix host
# owns them like any other configuration file. The daemon reads that directory at run time, so a
# profile that a user edits by hand still works beside the Nix ones.
{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.kdn-audio;

  profileFile =
    name: profile:
    (pkgs.formats.yaml { }).generate "kdn-audio-profile-${name}.yaml" (
      lib.filterAttrs (_: value: value != null) {
        inherit (profile) name outputs absent priority;
        default = profile.default;
        move-streams = profile.moveStreams;
        description = profile.description;
      }
    );
in
{
  options.kdn.programs.kdn-audio = {
    enable = lib.mkEnableOption "the kdn-audio join CLI and TUI";

    autoActivate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `kdn-audio daemon` as a systemd user service, so the best matching profile is applied
        whenever the device mix changes.
      '';
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Free text for humans.";
            };
            priority = lib.mkOption {
              type = lib.types.int;
              default = 0;
              description = "Higher wins when several profiles match.";
            };
            outputs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = ''
                Device ids that must all be connected. `kdn-audio devices` maps ids to names; a
                Bluetooth output is `bt:<address>`, an ALSA output is `alsa:<card>/<profile>`.
              '';
            };
            absent = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Devices whose presence blocks the profile.";
            };
            default = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Make the joined output the default output when the profile activates.";
            };
            moveStreams = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Move the streams that play now when the profile activates.";
            };
          };
        }
      );
      default = { };
      description = "Profiles written to `~/.config/kdn-audio/profiles/<name>.yaml`.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = [ pkgs.kdn.kdn-audio ];
      }
      # A host sets this option in the NixOS tree, while the files and the service live in the
      # home-manager tree, which has its own copy of the option. Forward the value, exactly as
      # `modules/universal/programs/keepassxc` does.
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [
          { kdn.programs.kdn-audio = lib.mkDefault cfg; }
        ];
      })
      (kdnConfig.util.ifHM {
        xdg.configFile = lib.mapAttrs' (
          name: profile:
          lib.nameValuePair "kdn-audio/profiles/${name}.yaml" {
            source = profileFile name (profile // { inherit name; });
          }
        ) cfg.profiles;

        systemd.user.services.kdn-audio-profiles = lib.mkIf cfg.autoActivate {
          Unit = {
            Description = "kdn-audio profile daemon";
            # The daemon polls, so ordering is only a head start; this keeps the first pass from
            # racing a server that is still starting.
            After = [
              "pipewire.service"
              "wireplumber.service"
            ];
          };
          Install.WantedBy = [ "default.target" ];
          Service = {
            ExecStart = "${pkgs.kdn.kdn-audio}/bin/kdn-audio daemon";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      })
    ]
  );
}
