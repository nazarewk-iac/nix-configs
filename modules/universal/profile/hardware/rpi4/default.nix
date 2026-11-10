{

  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
let
  inherit (kdnConfig) self inputs;

  cfg = config.kdn.profile.hardware.rpi4;

  mkIfRPi4 = cond: conf: lib.attrsets.optionalAttrs (rpi4.any) (lib.mkIf cond conf);

  rpi4.any = kdnConfig.features.rpi4;
  rpi4.normal = rpi4.any && !kdnConfig.features.installer;
  rpi4.installer = rpi4.any && kdnConfig.features.installer;

  # An `imports` list has no context guard, and the auto-loader loads this file into the
  # home-manager evaluation too. Every module below is a NixOS module:
  # `inputs.nixos-hardware.nixosModules.raspberry-pi-4` reaches
  # `raspberry-pi/common/firmware.nix`, which sets `boot.loader.*`. home-manager declares no
  # `boot` option, so the evaluation of this host failed with
  # `The option `home-manager.users.<user>.boot' does not exist`.
  #
  # The `config` block below already carries `kdnConfig.util.ifTypes [ "nixos" ]`. Only the
  # `imports` list lacked the same limit.
  rpi4.nixos = rpi4.any && kdnConfig.moduleType == "nixos";
in
{
  imports = self.lib.lists.optionals rpi4.nixos (
    [
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ]
    ++ [
      inputs.argon40-nix.nixosModules.default
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
    ]
    ++ self.lib.lists.optional rpi4.installer "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
  );
  options.kdn.profile.hardware.rpi4 = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      readOnly = true;
      default = rpi4.any;
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

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf rpi4.any (
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
          # The RPi vendor kernel (nixos-hardware's `raspberry-pi/common/kernel.nix`, 6.18) builds
          # its bundled `tools/bpf` helpers, and since Linux 6.16 the arm64 UAPI declares the
          # 128-bit registers as `__u128` — a typedef the kernel's private
          # `tools/include/linux/types.h` lacks. Against a glibc whose `asm/*.h` carry that
          # declaration the tools build dies with:
          #
          #   tools/bpf/resolve_btfids: pager.c → asm/sigcontext.h:81
          #   error: unknown type name '__u128'; did you mean '__u32'?
          #
          # nixpkgs fixes this for its own kernels (`tools_128bit_types`, nixpkgs #581990), but not
          # for the nixos-hardware package, which pins its own `kernelPatches` list. Prepend the
          # same upstream commit to that derivation's patch list. Remove once nixos-hardware
          # carries it. `overrideAttrs` on `patches`, not `.override { kernelPatches = …; }`: the
          # package the module returns is an `overrideAttrs` result, whose `.override` is inert
          # (measured: `kernelPatches = [ ]` through it leaves the derivation unchanged).
          #
          # The patch is vendored, not `fetchpatch`ed: the fetch happens on the remote builder, and
          # the guest's download of that GitHub URL did not match the hash the client computed
          # (`expected path: …-tools-add-128-bit-…`, `got path: …`), so the build failed on a
          # different set of bytes than the one that was hashed.
          boot.kernelPackages = lib.mkForce (
            pkgs.linuxPackagesFor (
              (pkgs.callPackage "${inputs.nixos-hardware}/raspberry-pi/common/kernel.nix" {
                rpiVersion = 4;
              }).overrideAttrs
                (old: {
                  patches = [ ./tools-128bit-types.patch ] ++ (old.patches or [ ]);
                })
            )
          );
        }
        {
          # there is no module "tpm-tis" for rpi4 kernel
          systemd.tpm2.enable = lib.mkForce false;
          security.tpm2.enable = lib.mkForce false;
          boot.initrd.systemd.tpm2.enable = lib.mkForce false;
        }
        {
          kdn.env.packages = with pkgs; [
            libraspberrypi
            raspberrypi-eeprom
          ];
        }
        {
          # work around invalid modules caused by `hardware.enableAllHardware
          boot.initrd.allowMissingModules = lib.mkDefault true;
        }
        (mkIfRPi4 cfg.i2c.enable {
          hardware.i2c.enable = lib.mkDefault true;
          hardware.raspberry-pi."4".i2c1.enable = lib.mkDefault true;
          kdn.env.packages = with pkgs; [
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
                  src = kdnConfig.nix-configs.inputs.rpi-sbcshop-hat-ups // {
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
              kdn.profile.hardware.rpi4.i2c.enable = lib.mkDefault true;
              kdn.env.packages = [
                watcherScript
              ];
            }
          )
        )
        (mkIfRPi4 cfg.hat.lte.enable {
          kdn.hw.modem.enable = lib.mkDefault true;

          boot.initrd.availableKernelModules = [
            "rndis_host"
            "option"
          ];
        })
        (mkIfRPi4 cfg.hat.fan.enable {
          # FAN HAT seems to be the same as in Argon One case?
          programs.argon.one.enable = lib.mkDefault true;
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
    )
  );
}
