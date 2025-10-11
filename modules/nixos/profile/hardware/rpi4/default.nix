{
  config,
  pkgs,
  lib,
  kdn,
  ...
}: let
  inherit (kdn) self inputs;

  cfg = config.kdn.profile.hardware.rpi4;

  mkIfRPi4 = cond: conf: lib.attrsets.optionalAttrs (rpi4.any) (lib.mkIf cond conf);

  rpi4.any = kdn.features.rpi4;
  rpi4.normal = rpi4.any && !kdn.features.installer;
  rpi4.installer = rpi4.any && kdn.features.installer;
in {
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

  config = lib.mkIf rpi4.any (lib.mkMerge [
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
    (
      mkIfRPi4 cfg.hat.ups.enable
      /*
      - https://shop.sb-components.co.uk/products/ups-hat-for-raspberry-pi
      - https://learn.sb-components.co.uk/UPS-Hat-for-Raspberry-Pi
      - https://github.com/sbcshop/UPS-Hat-RPi
      */
      (let
        watcherScript = let
          python = pkgs.python3;
          src = kdn.nix-configs.inputs.rpi-sbcshop-hat-ups // {pythonModule = python;};
          name = "INA219_UPS.py";
        in
          lib.kdn.mkPythonScript pkgs {
            inherit src name python;
            scriptFile = src + /INA219_UPS.py;
            packageOverrides = final: prev: {
              smbus = let
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

                  /*
                  error: python3.13-smbus-1.1.post2 does not configure a `format`. To build with setuptools as before, set `pyproject = true` and `build-system = [ setuptools ]`.`
                  */
                  pyproject = true;
                  build-system = with final; [setuptools];

                  /*
                  ┃ error: builder for '/nix/store/rv2jmzl410ifn8a67v6g6hcmw02j1kp0-python3.13-INA219_UPS.py-0.0.1.drv' failed with exit code 1;
                  ┃        last 25 log lines:
                  ┃        >        ^^^^^^^^^^^^^^^^^^^^^^^^
                  ┃        >   File "/nix/store/a65r9k46dxhyx2gn60bpx7j62anjdjr7-python3-3.13.7/lib/python3.13/functools.py", line 1026, in __get__
                  ┃        >     val = self.func(instance)
                  ┃        >   File "/nix/store/c5631sg80pwcki8fj4wn8zzvd9vwyfyl-python3.13-hatchling-1.27.0/lib/python3.13/site-packages/hatchling/builders/config.py", line 713, in only_include
                  ┃        >     only_include = only_include_config.get('only-include', self.default_only_include()) or self.packages
                  ┃        >                                                            ~~~~~~~~~~~~~~~~~~~~~~~~~^^
                  ┃        >   File "/nix/store/c5631sg80pwcki8fj4wn8zzvd9vwyfyl-python3.13-hatchling-1.27.0/lib/python3.13/site-packages/hatchling/builders/wheel.py", line 262, in default_only_include
                  ┃        >     return self.default_file_selection_options.only_include
                  ┃        >            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                  ┃        >   File "/nix/store/a65r9k46dxhyx2gn60bpx7j62anjdjr7-python3-3.13.7/lib/python3.13/functools.py", line 1026, in __get__
                  ┃        >     val = self.func(instance)
                  ┃        >   File "/nix/store/c5631sg80pwcki8fj4wn8zzvd9vwyfyl-python3.13-hatchling-1.27.0/lib/python3.13/site-packages/hatchling/builders/wheel.py", line 250, in default_file_selection_options
                  ┃        >     raise ValueError(message)
                  ┃        > ValueError: Unable to determine which files to ship inside the wheel using the following heuristics: https://hatch.pypa.io/latest/plugins/builder/wheel/#default-file-selection
                  ┃        >
                  ┃        > The most likely cause of this is that there is no directory that matches the name of your project (INA219_UPS.py or ina219_ups_py).
                  ┃        >
                  ┃        > At least one file selection option must be defined in the `tool.hatch.build.targets.wheel` table, see: https://hatch.pypa.io/latest/config/build/
                  ┃        >
                  ┃        > As an example, if you intend to ship a directory named `foo` that resides within a `src` directory located at the root of your project, you can define the following:
                  ┃        >
                  ┃        > [tool.hatch.build.targets.wheel]
                  ┃        > packages = ["src/foo"]
                  ┃        >
                  ┃        > ERROR Backend subprocess exited when trying to invoke build_wheel
                  ┃        For full logs, run 'nix log /nix/store/rv2jmzl410ifn8a67v6g6hcmw02j1kp0-python3.13-INA219_UPS.py-0.0.1.drv'.
                  */
                };
            };
            requirementsFile = pkgs.writeText "rpi-usb-hat-requirements.txt" ''
              pillow
              pyserial
              smbus
            '';
          };
      in {
        kdn.profile.hardware.rpi4.i2c.enable = true;
        environment.systemPackages = [
          watcherScript
        ];
      })
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
  ]);
}
