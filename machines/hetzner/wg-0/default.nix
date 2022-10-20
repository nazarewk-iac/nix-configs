{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  kdn.profile.machine.hetzner.enable = true;

  system.stateVersion = "22.11";

  networking.hostId = "550ded62"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "wg-0";
}
