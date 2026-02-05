{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.kdn.services.printing;
in {
  options.kdn.services.printing = {
    enable = lib.mkEnableOption "CUPSd printing daemon";

    extraAdminGroups = lib.mkOption {
      type = with lib.types; listOf str;
      default = ["lpadmin"];
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
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
      security.polkit.extraConfig = let
        isAllowedGroup = lib.pipe cfg.extraAdminGroups [
          (map (group: ''subject.isInGroup("${group}")''))
          (builtins.concatStringsSep " || ")
          (v: "( ${v} )")
        ];
      in ''
        // passwordless printer admins
        polkit.addRule(function(action, subject) {
          if (/^org\.opensuse\.cupspkhelper\.mechanism\./.test(action.id) && ${isAllowedGroup}){
            return polkit.Result.YES;
          }
        });
      '';
      services.printing.extraFilesConf = ''
        SystemGroup root wheel ${builtins.concatStringsSep " " cfg.extraAdminGroups}
      '';
      users.groups.lpadmin = {};

      kdn.disks.persist."sys/data".directories = [
        "/var/lib/cups"
      ];
    }
    {
      hardware.printers.ensureDefaultPrinter = lib.mkDefault "HP-M110w-home";
      hardware.printers.ensurePrinters = [
        {
          name = "HP-M110w-home";
          location = "Home";
          deviceUri = "ipp://192.168.41.25";
          model = "drv:///hp/hpcups.drv/hp-laserjet_m109-m112.ppd";
          ppdOptions.PageSize = "A4";
        }
      ];
    }
  ]);
}
