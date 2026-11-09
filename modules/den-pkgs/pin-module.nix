# Opt-in: pin this host's nixpkgs to the single, flake-level per-(system,variant) pkgs from
# modules/den-pkgs. Setting `nixpkgs.pkgs` forces `nixpkgs.overlays`/`nixpkgs.config` to be empty
# (they are mutually exclusive), so both are `mkForce`d empty here. The shared base already carries
# every static overlay (default + jsonTemplate + python metadata + ceph), so a pinned host loses
# nothing that those static overlays provided. A host whose needs are NOT covered by the base
# (host-dependent age sops wrapper, hw-gpu multiGPU package, gaming allowUnfreePredicate) must NOT
# pin, or must take its own variant.
{ lib, config, kdnConfig, ... }:
{
  options.kdn.pkgs = {
    pin = lib.mkEnableOption "pin nixpkgs to the flake-level single per-system pkgs (modules/den-pkgs)";
    variant = lib.mkOption {
      type = lib.types.enum [ "default" "cuda" ];
      default = "default";
      description = "Which pre-built pkgs variant to pin.";
    };
  };
  # Only the nixos/darwin classes have `nixpkgs.pkgs`. The universal tree is also imported into
  # home-manager users, where that option does not exist, so guard by class.
  config = kdnConfig.util.ifTypes [ "nixos" "darwin" ] (lib.mkIf config.kdn.pkgs.pin {
    nixpkgs.pkgs = kdnConfig.self.pkgs.${kdnConfig.system}.${config.kdn.pkgs.variant};
    nixpkgs.overlays = lib.mkForce [ ];
    nixpkgs.config = lib.mkForce { };
    # Home-manager users ride on the same pinned pkgs. `nixpkgs.pkgs` is system-only, so the HM
    # eval must consume the system pkgs (which already carry every overlay) instead of building
    # its own from the now-empty `nixpkgs.overlays`.
    home-manager.useGlobalPkgs = lib.mkIf (config ? home-manager) (lib.mkForce true);
    home-manager.useUserPackages = lib.mkIf (config ? home-manager) (lib.mkForce true);
  });
}
