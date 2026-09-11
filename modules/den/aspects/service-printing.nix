# The CUPS print daemon, as a den aspect. It ports
# `modules/universal/services/printing/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs CUPS with three printer drivers, it lets a member of an admin group manage a printer with
# no password, and it declares the printers the consumer lists.
#
# ## The printer data stays with the consumer
#
# The aspect names **no** printer and **no** printer address. `printers` is an empty list and
# `defaultPrinter` is `null` until a consumer fills them. This repository keeps its own printer data
# in a separate data file, outside every module.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The persist write becomes an output option.** See below.
#
# ## The persist directories become a read-only output
#
# The old module writes `kdn.disks.persist."sys/data".directories`. An aspect must not write another
# aspect's option, so this aspect publishes the list and the consumer wires it in one line:
#
#     kdn.disks.persist."sys/data".directories = config.kdn.services.printing.persist.sysData;
#
# ## Two drivers stay out
#
# `brgenml1lpr` and `brgenml1cupswrapper` ship a 32-bit i686 binary only, so nix builds them as an
# i686-linux derivation. A build host with no i686-linux builder cannot build them. `brlaser` drives
# most Brother laser printers and it builds native, so it stays.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.service-printing.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.printing;
    in
    {
      options.kdn.services.printing.extraAdminGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "lpadmin" ];
        description = ''
          The groups whose members manage a printer with no password. The aspect creates the
          `lpadmin` group itself.
        '';
      };

      options.kdn.services.printing.printers = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        description = ''
          The printers this host declares. Each entry matches one `hardware.printers.ensurePrinters`
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

      options.kdn.services.printing.defaultPrinter = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The name of the default printer, or `null` for no default. The name must match one
          `printers` entry.
        '';
      };

      options.kdn.services.printing.persist.sysData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The directories this aspect wants on persistent system storage. The consumer wires the
          list into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          services.printing.enable = true;
          services.printing.drivers = with pkgs; [
            hplip
            brlaser
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

          kdn.services.printing.persist.sysData = [
            "/var/lib/cups"
          ];
        }
        {
          # `lib.mkDefault` keeps priority 1000, so a consumer overrides with a plain assignment.
          hardware.printers.ensureDefaultPrinter = lib.mkIf (cfg.defaultPrinter != null) (
            lib.mkDefault cfg.defaultPrinter
          );
          hardware.printers.ensurePrinters = cfg.printers;
        }
      ];
    };
}
