{ config, pkgs, lib, ... }: {
  options.kdn.programs.firefox.overrides.nativeMessagingHosts = lib.mkOption {
    type = with lib.types; listOf package;
    default = [ ];
    description = lib.mdDoc ''
      Additional packages containing native messaging hosts that should be made available to Firefox extensions.
    '';
  };
  config = lib.mkIf config.programs.firefox.enable {
    programs.firefox.package = pkgs.firefox.override (old: {
      inherit (config.kdn.programs.firefox.overrides) nativeMessagingHosts;
    });
  };
}
