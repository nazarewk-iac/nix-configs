{ pkgs, flakeInputs, ... }:
let
  nixosModules = [
    ./desktop/base
    ./desktop/gnome/base
    ./desktop/remote-server
    ./desktop/sway/base
    ./desktop/sway/remote
    ./desktop/sway/through-gdm
    ./desktop/sway/through-systemd
    ./desktop/xfce/base
    ./development/cloud
    ./development/data
    ./development/elixir
    ./development/golang
    ./development/k8s
    ./development/linux-utils
    ./development/nix
    ./development/nodejs
    ./development/podman
    ./development/python
    ./development/ruby
    ./development/rust
    ./development/terraform
    ./filesystems/base
    ./filesystems/zfs-root
    ./hardware/discovery
    ./hardware/intel-graphics-fix
    ./hardware/modem
    ./hardware/pipewire
    ./hardware/yubikey
    ./hardware/usbip
    ./headless
    ./headless/base
    ./containers/docker
    ./containers/k3s/single-node
    ./networking/wireguard
    ./packaging/asdf
    ./programs/aws-vault
    ./programs/gnupg
    ./programs/keepass
    ./programs/nix-direnv
    ./programs/nix-index
    ./programs/obs-studio
    ./virtualization/nixops/libvirtd
  ];
  hmModules = [
    ./development/git/hm.nix
    ./development/fresha/hm.nix
    ./development/terraform/hm.nix
  ];
in
{
  imports = [
    flakeInputs.home-manager.nixosModules.home-manager
  ] ++ nixosModules;

  config = {
    # renamed from nix.binaryCachePublicKeys
    nix.settings.trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8="
    ];
    # renamed from nix.binaryCaches
    nix.settings.substituters = [
      "https://cache.nixos.org"
      "https://nixpkgs-wayland.cachix.org"
      "https://nix-community.cachix.org"
      "https://nixpkgs-update.cachix.org"
    ];
    nix.settings.auto-optimise-store = true;
    nix.package = pkgs.nixFlakes;
    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';
    nixpkgs.config.allowUnfree = true;

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.sharedModules = hmModules ++ [
      (
        let
          cfg = ''
            { allowUnfree = true; }
          '';
        in
        {
          nixpkgs.config.allowUnfree = true;
          xdg.configFile."nixpkgs/config.nix".text = cfg;
          home.file.".nixpkgs/config.nix".text = cfg;
        }
      )
    ];
  };
}
