{ lib, pkgs, config, system, ... }:
let
  cfg = config.kdn.development.kernel;
in
{
  options.kdn.development.kernel = {
    enable = lib.mkEnableOption "kernel development dependencies";
  };

  config = lib.mkIf cfg.enable {
    # see https://www.kernel.org/doc/html/v5.6/process/changes.html
    environment.systemPackages = (with pkgs; [
      gcc
      gnumake
      binutils
      flex
      bison
      util-linux
      kmod
      e2fsprogs
      jfsutils
      reiserfsprogs
      xfsprogs
      squashfs-tools-ng
      btrfs-progs
      pcmciaUtils
      unixtools.quota
      ppp
      nfs-utils
      procps
      oprofile
      eudev # udev
      grub2
      mcelog
      iptables
      openssl
      bc
      sphinx
    ])
    ++ config.boot.kernelPackages.kernel.nativeBuildInputs
    ++ config.boot.kernelPackages.kernel.depsBuildBuild
    ;
  };
}
