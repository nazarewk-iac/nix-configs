{
  config,
  lib,
  pkgs,
  inputs,
  self,
  ...
}: let
  cfg = config.kdn;
in {
  imports =
    [
      ../shared/all
      ../shared/darwin-nixos
      inputs.home-manager.darwinModules.default
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

  config = lib.mkIf config.kdn.enable (lib.mkMerge [
    {networking.localHostName = lib.mkDefault config.networking.hostName;}
  ]);
}
