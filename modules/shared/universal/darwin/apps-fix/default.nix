/*
based on https://github.com/reckenrode/nixos-configs/blob/ed1afab17fab89c552d943ccdd8cd21f5d5e7873/modules/by-name/co/copy-apps/module.nix

for background see:
  - https://github.com/nix-community/home-manager/issues/1341#issuecomment-1653434732
  - https://github.com/YorikSar/dotfiles/commit/d7eccf447a399c15fe987ab02db13f4ef1e1b557
  - https://github.com/jcszymansk/nixcasks/blob/e1980177fe25e2a2b8108e88cecbfefd92b4a3d2/README.md#limitations
*/
{
  lib,
  pkgs,
  config,
  self,
  ...
}: {
  options.kdn.darwin.apps-fix = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = config.kdn.darwin.enable;
    };

    copyScript = lib.mkOption {
      type = with lib.types; str;
      default =
        lib.optionalString (config.kdn.darwin.type == "nix-darwin") ''
          echo 'Setting up /Applications/Nix Apps...' >&2
        ''
        + ''
          appsSrc="${config.kdn.darwin.dirs.apps.src}"
          if [ -d "$appsSrc" ]; then
            baseDir="${config.kdn.darwin.dirs.apps.base}"
            rsyncFlags=(
              --archive
              --checksum
              --chmod=-w
              --copy-unsafe-links
              --delete
              --no-group
              --no-owner
            )
            $DRY_RUN_CMD mkdir -p "$baseDir"
            $DRY_RUN_CMD ${lib.getExe pkgs.rsync} \
              ''${VERBOSE_ARG:+-v} "''${rsyncFlags[@]}" "$appsSrc/" "$baseDir"
          fi
        '';
    };
  };
}
