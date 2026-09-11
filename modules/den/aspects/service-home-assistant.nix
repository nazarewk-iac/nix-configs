# Home Assistant, as a den aspect. It ports
# `modules/universal/services/home-assistant/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs Home Assistant on a NixOS host with the default component set, the three onboarding
# components, and the frontend port open. Three optional integrations sit behind a switch each:
# Zigbee Home Automation, Tuya Cloud and Tuya Local.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The three nested `enable` flags become `use` flags.** Rule 2 forbids a reachable `enable`
#    option, and these three sit in a plain option tree, so the walk reaches them. The names are
#    `zha.use`, `tuyaCloud.use` and `tuyaLocal.use`. The two Tuya names also lose the dash, because
#    a dash needs a quoted attribute name.
# 3. Nothing else. Every emitted value matches the old module.
#
# ## The port opens the frontend port itself
#
# `services.home-assistant.openFirewall` no longer exists. nixpkgs removed it, because the frontend
# port is not in the YAML config any more, so the module cannot read the port at evaluation time.
# 8123 is the Home Assistant default, and this aspect sets no other port.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 2 above.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.service-home-assistant.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.home-assistant;
    in
    {
      options.kdn.services.home-assistant.user = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "hass";
        description = "The system user the nixpkgs module runs the service as.";
      };

      options.kdn.services.home-assistant.group = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "hass";
        description = "The system group the nixpkgs module runs the service as.";
      };

      options.kdn.services.home-assistant.zha.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Add the Zigbee Home Automation component and point it at a local database.

          The name is `use`, not `enable`: an aspect declares no reachable `enable` option.
        '';
      };

      options.kdn.services.home-assistant.tuyaCloud.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Add the Tuya Cloud component.";
      };

      options.kdn.services.home-assistant.tuyaLocal.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Add the Tuya Local custom component.";
      };

      options.kdn.services.home-assistant.zha.controller.name = lib.mkOption {
        type = lib.types.str;
        default = "ZBT1";
        example = "SkyConnect";
        description = "A short name for the Zigbee controller. The default names the ZBT-1.";
      };

      options.kdn.services.home-assistant.zha.controller.ttyName = lib.mkOption {
        type = lib.types.str;
        default = "tty${cfg.zha.controller.name}";
        defaultText = lib.literalExpression "\"tty\${config.kdn.services.home-assistant.zha.controller.name}\"";
        description = "The stable device name a udev rule gives the Zigbee controller.";
      };

      options.kdn.services.home-assistant.zha.controller.idVendor = lib.mkOption {
        type = lib.types.str;
        default = "10c4";
        description = "The USB vendor id of the Zigbee controller.";
      };

      options.kdn.services.home-assistant.zha.controller.idProduct = lib.mkOption {
        type = lib.types.str;
        default = "16a8";
        description = "The USB product id of the Zigbee controller.";
      };

      config = lib.mkMerge [
        {
          services.home-assistant.enable = true;
          networking.firewall.allowedTCPPorts = [ 8123 ];
          services.home-assistant.config = {
            # Includes dependencies for a basic setup
            # https://www.home-assistant.io/integrations/default_config/
            default_config = { };
          };
          services.home-assistant.extraPackages =
            python3Packages: with python3Packages; [
            ];
        }
        {
          # onboarding requirements
          services.home-assistant.extraComponents = [
            "esphome"
            "met"
            "radio_browser"
          ];
        }
        (lib.mkIf cfg.zha.use {
          services.home-assistant.extraComponents = [
            "zha"
          ];
          services.home-assistant.config.zha.database_path = lib.mkDefault "/var/lib/hass/zigbee.db";
        })
        (lib.mkIf cfg.tuyaCloud.use {
          services.home-assistant.extraComponents = [
            "tuya"
          ];
        })
        (lib.mkIf cfg.tuyaLocal.use {
          services.home-assistant.customComponents = with pkgs.home-assistant-custom-components; [
            tuya_local
          ];
        })
      ];
    };
}
