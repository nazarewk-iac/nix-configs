{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.services.home-assistant;
in
{
  options.kdn.services.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant server";
    zha.enable = lib.mkEnableOption "Zigbee Home Automation module";
    tuya-local.enable = lib.mkEnableOption "Tuya Local module";
    tuya-cloud.enable = lib.mkEnableOption "Tuya Cloud module";

    user = lib.mkOption {
      type = with lib.types; str;
      readOnly = true;
      default = "hass";
    };
    group = lib.mkOption {
      type = with lib.types; str;
      readOnly = true;
      default = "hass";
    };

    # default to ZBT-1
    zha.controller.name = lib.mkOption {
      type = with lib.types; str;
      default = "ZBT1";
    };
    zha.controller.ttyName = lib.mkOption {
      type = with lib.types; str;
      default = "tty${cfg.zha.controller.name}";
    };
    zha.controller.idVendor = lib.mkOption {
      type = with lib.types; str;
      default = "10c4";
    };
    zha.controller.idProduct = lib.mkOption {
      type = with lib.types; str;
      default = "16a8";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.home-assistant.enable = true;
        services.home-assistant.openFirewall = true;
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
      (lib.mkIf cfg.zha.enable {
        services.home-assistant.extraComponents = [
          "zha" # Enable Zigbee Home Automation
        ];
        services.home-assistant.config = {
          zha = {
            database_path = lib.mkDefault "/var/lib/hass/zigbee.db";
          };
        };
      })
      (lib.mkIf cfg.tuya-cloud.enable {
        services.home-assistant.extraComponents = [
          "tuya"
        ];
      })
      (lib.mkIf cfg.tuya-local.enable {
        services.home-assistant.customComponents = with pkgs.home-assistant-custom-components; [
          tuya_local
        ];
      })
    ]
  );
}
