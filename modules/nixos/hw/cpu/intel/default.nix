{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.hw.cpu.intel;
in
{
  options.kdn.hw.cpu.intel = {
    enable = lib.mkEnableOption "intel CPU setup";
  };

  config = lib.mkIf cfg.enable {
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    boot.kernelModules = [ "kvm-intel" ];
  };
}
