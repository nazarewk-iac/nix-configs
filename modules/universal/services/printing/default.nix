{

  lib,
  config,
  pkgs,
  kdnConfig,
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

    printers = lib.mkOption {
      type = with lib.types; listOf (attrsOf anything);
      description = ''
        Printers this host ensures. Each entry matches one `hardware.printers.ensurePrinters`
        entry, so it takes `name`, `deviceUri`, `model`, and the optional `location`,
        `description` and `ppdOptions` keys.

        `listOf` supplies an empty list, so a host with no printer data still gets CUPS.
      '';
      example = lib.literalExpression ''
        [
          {
            name = "office";
            location = "Office";
            deviceUri = "ipp://printer.example.com";
            model = "drv:///sample.drv/generic.ppd";
            ppdOptions.PageSize = "A4";
          }
        ]
      '';
    };

    defaultPrinter = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = ''
        Name of the default printer, or `null` for no default. The name must match one
        `printers` entry.
      '';
    };
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          # Enable CUPS to print documents.
          services.printing.enable = true;
          services.printing.drivers = with pkgs; [
            hplip
            #gutenprint
            #gutenprintBin
            brlaser
            # brgenml1lpr and brgenml1cupswrapper ship only 32-bit i686 binaries, so nix
            # builds them as i686-linux derivations. A build host without an i686-linux
            # builder cannot build them. A darwin host with a rosetta x86_64-linux/aarch64-linux
            # builder is one such host. brlaser drives most Brother laser printers and builds
            # native, so it stays. Add these two back when an i686-linux builder is available.
            #brgenml1lpr
            #brgenml1cupswrapper
          ];
          security.polkit.extraConfig =
            let
              isAllowedGroup = lib.pipe cfg.extraAdminGroups [
                (map (group: ''subject.isInGroup("${group}")''))
                (builtins.concatStringsSep " || ")
                (v: "( ${v} )")
              ];
            in
            ''
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
          users.groups.lpadmin = { };

          kdn.disks.persist."sys/data".directories = [
            "/var/lib/cups"
          ];
        }
        {
          # `lib.mkDefault` keeps today's priority 1000, so a host still overrides with a plain
          # assignment. No module forwards the whole `cfg` of this module into Home Manager, so
          # this `lib.mkDefault` cannot tie with a forwarded definition.
          hardware.printers.ensureDefaultPrinter = lib.mkIf (cfg.defaultPrinter != null) (
            lib.mkDefault cfg.defaultPrinter
          );
          hardware.printers.ensurePrinters = cfg.printers;
        }
      ]
    )
  );
}
