{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  # inputs.nixpkgs-mesa.url = "github:nixos/nixpkgs/f5db95a96aef57c945d4741c2134104da1026b7d";
  inputs.wayland.url = "github:nix-community/nixpkgs-wayland";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.poetry2nix.url = "github:nix-community/poetry2nix";
  inputs.poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.poetry2nix.inputs.flake-utils.follows = "flake-utils";

  inputs.nix-alien.url = "github:thiagokokada/nix-alien";
  inputs.nix-alien.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-alien.inputs.flake-utils.follows = "flake-utils";
  inputs.nix-alien.inputs.poetry2nix.follows = "poetry2nix";

  inputs.nix-ld.url = "github:Mic92/nix-ld";
  inputs.nix-ld.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-ld.inputs.utils.follows = "flake-utils";

  outputs = {
    nixpkgs,
    # nixpkgs-mesa,
    wayland,
    home-manager,
    flake-utils,
    poetry2nix,
    nix-alien,
    nix-ld,
    ...
 } : {
      nixosConfigurations.rpi4 = nixpkgs.lib.nixosSystem {
        # nix build '.#nixosConfigurations.rpi4.config.system.build.sdImage' --system aarch64-linux -L
        # see for a next step: https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$w4Zx8Y0vG0DhlD3zzWReWDaOdRSZvwyrn1tQsLhYDEU?via=nixos.org&via=matrix.org&via=tchncs.de
        system = "aarch64-linux";
        modules = [
          ./rpi4/sd-image.nix
        ];
      };
      nixosConfigurations.nazarewk = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit nixpkgs; };
        modules = [
          {
            # renamed from nix.binaryCachePublicKeys
            nix.settings.trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
            # renamed from nix.binaryCaches
            nix.settings.substituters = [
              "https://cache.nixos.org"
              "https://nixpkgs-wayland.cachix.org"
              "https://nix-community.cachix.org"
            ];
            nixpkgs.overlays = [
              wayland.overlay
              (self: super: {
#                 yubikey-manager = super.yubikey-manager.overrideAttrs (old: {
#                   src = super.fetchFromGitHub {
#                     repo = "yubikey-manager";
#                     # https://github.com/Yubico/yubikey-manager/tree/32914673d1d0004aba820e614ac9a9a640b4d196
#                     rev = "32914673d1d0004aba820e614ac9a9a640b4d196";
#                     owner = "Yubico";
#                     sha256 = "";
#                   };
#                 });
              })
            ];
            nazarewk.programs.aws-vault.enable = true;
            programs.nix-direnv.enable = true;
            nazarewk.sway.gdm.enable = true;
            nazarewk.sway.systemd.enable = false;
            nazarewk.modem.enable = true;
            nazarewk.hw.pipewire.enable = true;
            nazarewk.hw.pipewire.useWireplumber = true;

            home-manager.users.nazarewk = {
              fresha.development.enable = true;
              fresha.development.bastionUsername = "krzysztof.nazarewski";
            };

            environment.variables.AWS_VAULT_BACKEND = "secret-service";
          }
          ./legacy/nixos/configuration.nix
          ./legacy/nixos/podman.nix

          ./modules/aws-vault
          ./modules/desktop/base
          ./modules/desktop/gnome/base
          ./modules/desktop/sway/base
          ./modules/desktop/sway/through-gdm
          ./modules/desktop/sway/through-systemd
          ./modules/desktop/xfce/base
          ./modules/development/cloud
          ./modules/development/k8s
          ./modules/development/python
          ./modules/development/ruby
          ./modules/development/fresha
          ./modules/hardware/modem
          ./modules/hardware/pipewire
          ./modules/hardware/yubikey
          ./modules/nix-direnv
          ./modules/packaging/asdf
          # ./modules/obs-studio
          ./modules/nix-index
          # # TODO: CNI plugin discovery
          # ./modules/k3s/single-node

          {
            # should fix mesa crashes
            # - https://gitlab.freedesktop.org/mesa/mesa/-/issues/5864
            # - https://gitlab.freedesktop.org/mesa/mesa/-/issues/5600
            # - https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$U1Qhgf2AX_tVar9LuBrzOnNFYeoGkIntkv5OLs0D-dM?via=nixos.org&via=matrix.org&via=tchncs.de
            environment.variables = {
              MESA_LOADER_DRIVER_OVERRIDE = "i965";
            };
            nixpkgs.overlays = [
              (self: super: {
                  # mesa = nixpkgs-mesa.legacyPackages.x86_64-linux.mesa;
              })
            ];
          }


          {
            environment.systemPackages = [
              nixpkgs.legacyPackages.x86_64-linux.nix-index
              # nix-alien.packages.x86_64-linux.nix-alien
              # nix-alien.packages.x86_64-linux.nix-index-update
            ];
          }

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };
    };
}
