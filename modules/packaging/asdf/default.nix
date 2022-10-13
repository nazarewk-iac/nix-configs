{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.packaging.asdf;
in
{
  options.kdn.packaging.asdf = {
    enable = mkEnableOption "ASDF version manager";
  };

  config = mkIf cfg.enable {
    environment.interactiveShellInit = ''
      [[ -z "$HOME" ]] || export PATH="$HOME/.asdf/shims:$PATH"
      source ${pkgs.asdf-vm}/share/asdf-vm/lib/asdf.sh
    '';

    environment.systemPackages = with pkgs; [
      asdf-vm
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
            $DRY_RUN_CMD asdf reshim
          '';
        };
      })
    ];
  };
}
