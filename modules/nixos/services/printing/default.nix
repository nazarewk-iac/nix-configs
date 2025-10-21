{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.kdn.services.printing;
in
{
  options.kdn.services.printing = {
    enable = lib.mkEnableOption "CUPSd printing daemon";

    extraAdminGroups = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ "lpadmin" ];
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable CUPS to print documents.
    services.printing.enable = true;
    services.printing.drivers = with pkgs; [
      hplip
      #gutenprint
      #gutenprintBin
      brlaser
      brgenml1lpr
      brgenml1cupswrapper
    ];
    security.polkit.extraConfig =
      let
        isAllowedGroup = lib.pipe cfg.extraAdminGroups [
          (builtins.map (group: ''subject.isInGroup("${group}")''))
          (builtins.concatStringsSep " || ")
          (v: "( ${v} )")
        ];
      in
      ''
        // passwordless printer admins
        polkit.addRule(function(action, subject) {
          if (action.id == "org.opensuse.cupspkhelper.mechanism.all-edit" && ${isAllowedGroup}){
            return polkit.Result.YES;
          }
        });
      '';
    services.printing.extraFilesConf = ''
      SystemGroup root wheel ${builtins.concatStringsSep " " cfg.extraAdminGroups}
    '';
    users.groups.lpadmin = { };
  };
}
