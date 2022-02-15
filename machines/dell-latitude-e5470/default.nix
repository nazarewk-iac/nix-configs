# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
#
# see https://gist.github.com/dysinger/2a768db5b6e3b729ec898d7d4208add3

{ config, pkgs, lib, ... }:
{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # NETWORKING
  networking.hostId = "f77614af"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "nazarewk";

  # NIX / NIXOS
  # renamed from nix.autoOptimiseStore
  system.stateVersion = "21.05";
  location.provider = "geoclue2";

  # BOOT
  boot.kernelParams = [ "consoleblank=90" ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;
  boot.cleanTmpDir = true;

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 1048576; # default:  8192
    "fs.inotify.max_user_instances" = 1024; # default:   128
    "fs.inotify.max_queued_events" = 32768; # default: 16384
  };

  nazarewk.hardware.intel-graphics-fix.enable = true;
}
