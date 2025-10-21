{
  config,
  pkgs,
  lib,
  kdn,
  ...
}:
let
  inherit (kdn) self inputs;

  cfg = config.kdn.profile.hardware.rpi4;

  mkIfRPi4 = cond: conf: lib.attrsets.optionalAttrs (rpi4.any) (lib.mkIf cond conf);

  rpi4.any = kdn.features.rpi4;
  rpi4.normal = rpi4.any && !kdn.features.installer;
  rpi4.installer = rpi4.any && kdn.features.installer;
in
{
  imports = self.lib.lists.optionals rpi4.any (
    [
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ]
    ++ self.lib.lists.optionals rpi4.any [
      inputs.argon40-nix.nixosModules.default
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
    ]
    ++ self.lib.lists.optional rpi4.installer "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
  );
  options.kdn.profile.hardware.rpi4 = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      readOnly = true;
      default = kdn.features.rpi4;
    };
    i2c.enable = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    hat.fan.enable = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    hat.ups.enable = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    hat.lte.enable = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
  };

  config = lib.mkIf rpi4.any (
    lib.mkMerge [
      {
        boot.loader.systemd-boot.enable = lib.mkForce false;
        boot.initrd.availableKernelModules = [
          "usbhid"
          "usb_storage"
          "vc4"
          "pcie_brcmstb" # required for the pcie bus to work
          "reset-raspberrypi" # required for vl805 firmware to load
        ];

        fileSystems = lib.mkIf rpi4.normal {
          "/" = {
            device = "/dev/disk/by-label/NIXOS_SD";
            fsType = "ext4";
          };
        };
      }
      (mkIfRPi4 true {
        image.baseName = lib.mkDefault "nixos-${config.kdn.hostName}";
        #hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;
      })
      {
        # there is no module "tpm-tis" for rpi4 kernel
        systemd.tpm2.enable = lib.mkForce false;
        security.tpm2.enable = lib.mkForce false;
        boot.initrd.systemd.tpm2.enable = lib.mkForce false;
      }
      {
        environment.systemPackages = with pkgs; [
          libraspberrypi
          raspberrypi-eeprom
        ];
      }
      {
        # work around invalid modules caused by `hardware.enableAllHardware
        boot.initrd.allowMissingModules = true;
      }
      (mkIfRPi4 cfg.i2c.enable {
        hardware.i2c.enable = true;
        hardware.raspberry-pi."4".i2c1.enable = true;
        environment.systemPackages = with pkgs; [
          i2c-tools
        ];
      })
      (mkIfRPi4 cfg.hat.ups.enable
        /*
          - https://shop.sb-components.co.uk/products/ups-hat-for-raspberry-pi
          - https://learn.sb-components.co.uk/UPS-Hat-for-Raspberry-Pi
          - https://github.com/sbcshop/UPS-Hat-RPi
        */
        (
          let
            watcherScript =
              let
                python = pkgs.python3;
                src = kdn.nix-configs.inputs.rpi-sbcshop-hat-ups // {
                  pythonModule = python;
                };
                # it cannot be `INA219_UPS.py`, because the builder won't find the python module
                name = "INA219_UPS";
              in
              lib.kdn.mkPythonScript pkgs {
                inherit src name python;
                scriptFile = src + /INA219_UPS.py;
                packageOverrides = final: prev: {
                  smbus =
                    let
                      pname = "smbus";
                      version = "1.1.post2";
                    in
                    final.buildPythonPackage rec {
                      inherit pname version;

                      src = final.fetchPypi {
                        inherit pname version;
                        sha256 = "sha256-+W00XgqhAFOopJF2NPHcN7ofZW+lys52KbcXd+kIVcY=";
                      };

                      doCheck = false;

                      # error: python3.13-smbus-1.1.post2 does not configure a `format`. To build with setuptools as before, set `pyproject = true` and `build-system = [ setuptools ]`.`
                      pyproject = true;
                      build-system = with final; [ setuptools ];
                    };
                };
                requirementsFile = pkgs.writeText "rpi-usb-hat-requirements.txt" ''
                  pillow
                  pyserial
                  smbus
                '';
              };
          in
          {
            kdn.profile.hardware.rpi4.i2c.enable = true;
            environment.systemPackages = [
              watcherScript
            ];
          }
        )
      )
      (mkIfRPi4 cfg.hat.lte.enable {
        kdn.hw.modem.enable = true;

        boot.initrd.availableKernelModules = [
          "rndis_host"
          "option"
        ];
      })
      (mkIfRPi4 cfg.hat.fan.enable {
        # FAN HAT seems to be the same as in Argon One case?
        programs.argon.one.enable = true;
        programs.argon.one.settings = {
          # Is 'celsius' by default, can also be set to 'fahrenheit'
          displayUnits = "celsius";

          # This is the same config as the original Argon40 config.
          # This is also the default config for this flake.
          fanspeed = [
            {
              temperature = 40;
              speed = 10;
            }
            {
              temperature = 55;
              speed = 30;
            }
            {
              temperature = 60;
              speed = 55;
            }
            {
              temperature = 65;
              speed = 100;
            }
          ];
        };
      })
    ]
  );
}
