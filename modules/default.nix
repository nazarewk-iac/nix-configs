{pkgs, flakeInputs, ...}: {
  imports = [
    flakeInputs.home-manager.nixosModules.home-manager

    ./desktop/base
    ./desktop/gnome/base
    ./desktop/sway/base
    ./desktop/sway/through-gdm
    ./desktop/sway/through-systemd
    ./desktop/xfce/base
    ./development/cloud
    ./development/k8s
    ./development/nix
    ./development/podman
    ./development/python
    ./development/ruby
    ./filesystems/base
    ./filesystems/zfs-root
    ./hardware/intel-graphics-fix
    ./hardware/modem
    ./hardware/pipewire
    ./hardware/yubikey
    ./headless/base
    ./k3s/single-node
    ./packaging/asdf
    ./programs/aws-vault
    ./programs/nix-direnv
    ./programs/nix-index
    ./programs/obs-studio
  ];

  config = {
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
    nix.settings.auto-optimise-store = true;
    nix.package = pkgs.nixFlakes;
    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';
    nixpkgs.config.allowUnfree = true;

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;

    home-manager.sharedModules = [
      ./development/git/hm.nix
      ./development/fresha/hm.nix
    ];
  };
}