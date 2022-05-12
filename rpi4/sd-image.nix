{ modulesPath, ... }: {
  imports = [
    ../modules/installers/zfs/sd-image-aarch64.nix
    ../modules/zfs/default.nix
    ../legacy/nixos/nazarewk.nix
  ];
}
