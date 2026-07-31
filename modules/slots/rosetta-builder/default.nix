# Rosetta-backed multi-arch Linux builder darwin slot.
#
# Enables cpick/nix-rosetta-builder on an aarch64-darwin host so it builds both aarch64-linux
# and x86_64-linux locally. x86_64-linux runs under Rosetta 2 (near-native) instead of QEMU-TCG
# emulation. This is the first slot that targets the `darwin` slot target; all earlier slots
# target `devenv` only.
#
# The bootstrap dance (see docs/multi-arch-builder.md Option C): nix-rosetta-builder needs an
# existing Linux builder to build its own Lima guest image the first time. The consumer keeps the
# stock `nix.linux-builder` enabled until the Rosetta VM is up, then may disable it.
{
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.darwin.rosetta-builder;
in
{
  options.kdn.darwin.rosetta-builder = {
    enable = lib.mkEnableOption "Rosetta-backed dual-arch (aarch64-linux + x86_64-linux) Nix builder";
  };

  config = lib.mkIf cfg.enable {
    darwin = {
      imports = [
        inputs.nix-rosetta-builder.darwinModules.default
      ];

      # Module default is already true; explicit for clarity.
      nix-rosetta-builder.enable = true;
      # Power the VM off when idle.
      nix-rosetta-builder.onDemand = lib.mkDefault true;

      # Let the VM pull build inputs from public caches, instead of the host uploading everything
      # over the slow VM link (see docs/multi-arch-builder.md "Sharing the store").
      nix.settings.builders-use-substitutes = lib.mkDefault true;
    };
  };
}
