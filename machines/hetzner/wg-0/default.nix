{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    ../default.nix
  ];

  networking.hostId = "550ded62"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "wg-0";
}