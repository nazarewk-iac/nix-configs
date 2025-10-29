{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
} @ args: {
  imports =
    [
      ./_stylix.nix
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";

    args = lib.mkOption {
      internal = true;
      readOnly = true;
      default = args;
    };

    hostName = lib.mkOption {
      type = with lib.types; str;
    };
    nixConfig = lib.mkOption {
      readOnly = true;
      default = import ./nix.nix;
    };
    types = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      apply = value: lib.lists.sort (a: b: a < b) (lib.lists.unique value);
    };
  };

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {
        kdn.types = [kdnConfig.moduleType pkgs.stdenv.system] ++ lib.strings.splitString "-" pkgs.stdenv.system;
      }
    ]
  );
}
