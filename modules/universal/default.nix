{
  config,
  lib,
  pkgs,
  kdnConfig,
  osConfig ? {},
  darwinConfig ? {},
  ...
} @ args: let
  inherit (kdnConfig) self inputs;
  cfg = config.kdn;

  parentConfig = let
    ensure = val:
      if builtins.isAttrs val
      then val
      else {};
  in
    ensure osConfig // ensure darwinConfig;
in {
  imports =
    [
      ./_stylix.nix
      ./_options.nix
    ]
    ++ lib.optional (kdnConfig.moduleType == "home-manager") inputs.sops-nix.homeManagerModules.sops
    ++ lib.optionals (kdnConfig.moduleType == "darwin") [
      inputs.home-manager.darwinModules.default
      inputs.nix-homebrew.darwinModules.nix-homebrew
      inputs.sops-nix.darwinModules.default
      inputs.angrr.darwinModules.angrr
    ]
    ++ lib.optionals (kdnConfig.moduleType == "nixos") [
      ./ascii-workaround.nix
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.lanzaboote.nixosModules.lanzaboote
      inputs.nur.modules.nixos.default
      inputs.preservation.nixosModules.preservation
      inputs.sops-nix.nixosModules.sops
      inputs.angrr.nixosModules.angrr
    ]
    ++ kdnConfig.util.loadModules {
      curFile = ./default.nix;
      src = ./.;
      suffixes = ["/default.nix"];
    };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.extraSpecialArgs = (kdnConfig.output.mkSubmodule {moduleType = "home-manager";}).specialArgs;
      home-manager.sharedModules = [
        ./_options.nix
        ./_hm-bootstrap.nix
        ({kdnConfig, ...}: {
          imports = kdnConfig.util.loadModules {
            curFile = ./default.nix;
            src = ./.;
            suffixes = ["/default.nix" "/hm.nix"];
          };
        })
      ];
    })
    (kdnConfig.util.ifTypes ["nixos" "darwin"] (lib.mkIf cfg.enable (lib.mkMerge [
      {
        networking.hostName = cfg.hostName;
        nix.registry.nixpkgs.flake = inputs.nixpkgs;
        nix.optimise.automatic = true;
        nix.package = let
          latest = pkgs.lixPackageSets.latest.lix;
        in
          # TODO: 2025-12-19: lix 2.94.0 failed tests on darwin
          if pkgs.stdenv.hostPlatform.isDarwin
          then
            latest.overrideAttrs (prev: {
              doCheck = false;
              doInstallCheck = false;
            })
          else latest;
        nixpkgs.overlays = [self.overlays.default];
      }
      (lib.mkIf (!kdnConfig.features.microvm-guest) {
        nix.extraOptions = cfg.nixConfig.nix.extraOptions;
        nix.settings = cfg.nixConfig.nix.settings;
        nixpkgs.config = cfg.nixConfig.nixpkgs.config;
      })
      {
        home-manager.backupFileExtension = "hmbackup";
        home-manager.useGlobalPkgs = false;
        home-manager.useUserPackages = true;

        home-manager.sharedModules = [
          {
            config = {
              kdn.hostName = cfg.hostName;
            };
          }
        ];
      }
    ])))
    (kdnConfig.util.ifTypes ["nixos"] (lib.mkIf cfg.enable {
      # lib.mkDefault is 1000, lib.mkOptionDefault is 1500
      disko.enableConfig = lib.mkDefault false;
    }))
    (kdnConfig.util.ifTypes ["darwin"] (lib.mkIf cfg.enable (lib.mkMerge [
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
    ])))
  ];
}
