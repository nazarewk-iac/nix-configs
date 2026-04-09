{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.hw.cpu.intel;
in
{
  options.kdn.hw.cpu.intel = {
    enable = lib.mkEnableOption "intel CPU setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      boot.kernelModules = [ "kvm-intel" ];
    }
  );
}
