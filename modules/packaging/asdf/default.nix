{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.packaging.asdf;
in
{
  options.kdn.packaging.asdf = {
    enable = lib.mkEnableOption "ASDF version manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.asdf-vm;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.interactiveShellInit = ''
      [[ -z "$HOME" ]] || export PATH="$HOME/.asdf/shims:$PATH"
      source ${cfg.package}/share/asdf-vm/lib/asdf.sh
    '';

    environment.systemPackages = with pkgs; [
      cfg.package
      unzip
      coreutils
    ];

    home-manager.sharedModules = [
      ({ lib, ... }: {
        home.activation = {
          asdfReshim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if [ -d "$HOME/.asdf/shims" ] ; then
              $DRY_RUN_CMD rm -rf "$HOME/.asdf/shims"
            fi
            $DRY_RUN_CMD "${cfg.package}/bin/asdf" reshim
          '';
        };
      })
    ];
  };
}
