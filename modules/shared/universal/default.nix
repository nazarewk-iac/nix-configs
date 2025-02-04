{
  config,
  lib,
  pkgs,
  ...
}: {
  imports =
    [
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";
    hostName = lib.mkOption {
      type = with lib.types; str;
    };
    nixConfig = lib.mkOption {
      readOnly = true;
      default = import ./nix.nix;
    };
  };

  config = lib.mkIf config.kdn.enable (lib.mkMerge [
    {
    }
  ]);
}
