{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hardware.cpu.intel;
in {
  options.kdn.hardware.cpu.intel = {
    enable = lib.mkEnableOption "intel CPU setup";
  };

  config = lib.mkIf cfg.enable {
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    boot.kernelModules = ["kvm-intel"];
  };
}
