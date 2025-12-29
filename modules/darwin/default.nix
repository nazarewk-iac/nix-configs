{
  config,
  lib,
  kdnConfig,
  ...
}: let
  inherit (kdnConfig) inputs;
in {
  imports =
    [
      ../shared/darwin-nixos
      inputs.home-manager.darwinModules.default
      inputs.nix-homebrew.darwinModules.nix-homebrew
      inputs.sops-nix.darwinModules.default
      inputs.angrr.darwinModules.angrr
    ]
    ++ kdnConfig.util.loadModules {
      curFile = ./default.nix;
      src = ./.;
      withDefault = true;
    };

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {kdn.desktop.enable = lib.mkDefault true;}
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
        home-manager.sharedModules = [
          {imports = [../home-manager];}
          ({kdnConfig, ...}: {
            imports = kdnConfig.util.loadModules {
              curFile = ./default.nix;
              src = ./.;
            };
          })
          {
            # TODO: figure tmpfiles alternative for MacOS/systemd-less?
            systemd.user.tmpfiles.rules = lib.mkForce [];
          }
        ];
        # fixes home directory being `null` in home-manager
        users.users.root.home = "/var/root";
      }
      {
        networking.computerName = lib.mkDefault config.kdn.hostName;
      }
      {
        environment.enableAllTerminfo = true;
      }
    ]
  );
}
