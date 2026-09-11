# The PipeWire audio stack, as a den aspect. It ports the `audio` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It states one audio opinion per machine: PipeWire replaces PulseAudio, and it serves ALSA, JACK
# and the PulseAudio protocol. WirePlumber is the session manager. A user keeps the PulseAudio,
# PipeWire and WirePlumber state directories between boots.
#
# ## Class list: `nixos` and `homeManager`
#
# The old module puts every effect behind a `nixos` context guard, and it reaches the user half
# through the Home Manager bridge of that same guard. den partitions an aspect by scope, so the user
# half becomes a real `homeManager` target. A den host therefore includes this aspect twice: once in
# the host aspect and once in the user aspect. There is no `darwin` target, because the old module
# never had one.
#
# ## What the port changes
#
# 1. **The desktop read becomes an option.** The old module keys its graphical extras on a desktop
#    `enable` flag. A den aspect has no `enable`, so a desktop flag can never exist. The aspect
#    declares `kdn.hw.audio.graphical` and the consumer states it.
# 2. **The persistence write becomes a read-only output.** The old module writes the four user paths
#    into the persistence buckets of the `disks` area. This aspect publishes
#    `kdn.hw.audio.persist.{directories,files}` instead, and the consumer wires them. It follows the
#    `apps` aspect of batch 2.
# 3. **Two dead branches become options.** The old module wraps the WirePlumber debug settings in
#    `lib.mkIf false`, and it enables EasyEffects and then forces it off again. Both branches are
#    unreachable. The aspect declares `kdn.hw.audio.wireplumberDebug` and
#    `kdn.hw.audio.easyeffects`, each `false` by default, so the effective behaviour stays the same
#    and the knob becomes reachable.
# 4. **The dconf forward-write goes.** The old module turns a dconf program flag on for EasyEffects.
#    A den consumer includes the dconf aspect itself.
# 5. **The native option replaces the cross-platform package list.** The `nixos` target writes
#    `environment.systemPackages`. The `apply` filter moves to ../common/filter-packages.nix.
# 6. **One PulseAudio line goes, because it cannot evaluate.** The old module writes
#    `services.pulseaudio.extraModules = [ pkgs.pulseaudio-modules-bt ]`. nixpkgs holds no
#    `pulseaudio-modules-bt` attribute, on `x86_64-linux` or on `aarch64-darwin`, measured
#    2026-09-11. The line survives today only because `services.pulseaudio.enable` is `false`, so
#    nothing forces the list. PipeWire serves Bluetooth audio itself, so the line has no purpose
#    either. The port drops it.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The five options. Both targets import this one module, so an adopter states one opinion and both
  # classes read it.
  declaration =
    { lib, ... }:
    {
      options.kdn.hw.audio.graphical = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Install the graphical audio helpers, for example the PulseAudio volume control.

          The old module reads a desktop `enable` flag here. A den aspect has no `enable`, so the
          consumer states this opinion instead.
        '';
      };

      options.kdn.hw.audio.easyeffects = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Run EasyEffects for the user, with one loudness preset.

          The default is `false`, and that keeps the effective behaviour of the old module: it
          enables the service and then forces it off again, because of upstream issue 4472 of
          EasyEffects. Turn it on once that issue closes.
        '';
      };

      options.kdn.hw.audio.wireplumberDebug = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Raise the WirePlumber log level to 3 and turn its log rules on.

          The old module holds the same settings behind `lib.mkIf false`, so they never apply. This
          option makes the branch reachable and keeps `false` as the default.
        '';
      };

      options.kdn.hw.audio.persist.directories = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {
          "usr/config" = [
            ".config/pulse"
            ".config/pipewire"
            ".local/state/wireplumber"
          ];
        };
        description = ''
          The user directories the audio stack keeps between boots, grouped by bucket. It is
          read-only.

          The old module writes these lists straight into the persistence option of the `disks`
          area. That area has its own aspect, so this aspect publishes the lists and the consumer
          wires them:

              kdn.disks.persist."usr/config".directories =
                config.kdn.hw.audio.persist.directories."usr/config";
        '';
      };

      options.kdn.hw.audio.persist.files = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {
          "usr/config" = [ ".config/pavucontrol.ini" ];
        };
        description = ''
          The single user files the audio stack keeps between boots, grouped by the same buckets as
          `kdn.hw.audio.persist.directories`. It is read-only.
        '';
      };
    };

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.audio;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        {
          environment.systemPackages = filterPackages (
            with pkgs;
            [
              # pactl
              pulseaudio
              libopenaptx
              libfreeaptx
            ]
          );

          # PipeWire replaces PulseAudio and serves every protocol.
          security.rtkit.enable = true;
          services.pulseaudio.enable = false;
          services.pipewire.enable = true;

          services.pipewire.alsa.enable = true;
          services.pipewire.alsa.support32Bit = true;
          services.pipewire.jack.enable = true;
          services.pipewire.pulse.enable = true;
          services.pipewire.wireplumber.enable = true;

          services.pipewire.wireplumber.extraConfig.debug = lib.mkIf cfg.wireplumberDebug {
            "context.properties" = {
              "log.level" = 3;
              "log.rules.enabled" = true;
            };
          };

          hardware.bluetooth.package = pkgs.bluez5-experimental;
        }
        (lib.mkIf cfg.graphical {
          environment.systemPackages = filterPackages (
            with pkgs;
            [
              pavucontrol
            ]
          );
        })
      ];
    };

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.audio;
    in
    {
      imports = [ declaration ];

      # See https://forum.endeavouros.com/t/tutorial-volume-normalization-on-pipewire/22315
      config = lib.mkIf cfg.easyeffects {
        services.easyeffects.enable = true;
        services.easyeffects.extraPresets.LoudnessEqualizer =
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
      };
    };
in
{
  kdn.hw-audio.nixos = nixosTarget;
  kdn.hw-audio.homeManager = homeTarget;
}
