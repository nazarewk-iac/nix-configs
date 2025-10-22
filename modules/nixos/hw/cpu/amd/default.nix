{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.cpu.amd;
in {
  options.kdn.hw.cpu.amd = {
    enable = lib.mkEnableOption "AMD CPU setup";
  };

  config = lib.mkIf cfg.enable {
    hardware.cpu.amd.ryzen-smu.enable = true;
    hardware.cpu.amd.sev.enable = true;
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    programs.ryzen-monitor-ng.enable = true;
    # Error accessing SMU: SMU Driver Version Incompatible With Library Version
    environment.systemPackages = with pkgs; [
      ryzenadj
      amdctl
    ];
  };
}
