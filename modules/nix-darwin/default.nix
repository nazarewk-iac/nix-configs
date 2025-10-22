{
  config,
  lib,
  kdn,
  ...
}: let
  inherit (kdn) inputs;
in {
  imports =
    [
      ../shared/darwin-nixos-os
      ../shared/universal
      inputs.home-manager.darwinModules.default
      inputs.nix-homebrew.darwinModules.nix-homebrew
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {kdn.darwin.type = "nix-darwin";}
      {networking.localHostName = config.kdn.hostName;}
      {
        homebrew.enable = true;
        homebrew.onActivation.upgrade = false;

        nix-homebrew.enable = true;
        nix-homebrew.enableRosetta = true;
        nix-homebrew.mutableTaps = false;

        nix-homebrew.taps = let
          prefix = "brew-tap--";
        in
          lib.pipe inputs [
            (lib.attrsets.filterAttrs (name: _: lib.strings.hasPrefix prefix name))
            (lib.attrsets.mapAttrs' (
              name: src: {
                name = lib.pipe name [
                  (lib.strings.removePrefix prefix)
                  (builtins.replaceStrings ["--"] ["/"])
                ];
                value = src;
              }
            ))
          ];
      }
      {
        home-manager.sharedModules = [{imports = [./hm.nix];}];
      }
      {
        networking.computerName = lib.mkDefault config.kdn.hostName;
      }
    ]
  );
}
