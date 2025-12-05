{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.system.scripts;
in {
  options.kdn.outputs.host = {
    luks-keyfiles = lib.mkOption {
      readOnly = true;
      default = lib.pipe config.kdn.disks.luks.volumes [
        lib.attrsets.attrsToList
        (builtins.filter (e: e.value.keyFile != null))
        (builtins.map (e: {
          inherit (e) name;
          inherit (e.value) keyFile;
        }))
      ];
    };
  };
}
