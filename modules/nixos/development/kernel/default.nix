{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.kernel;
in {
  options.kdn.development.kernel = {
    enable = lib.mkEnableOption "kernel development dependencies";
  };

  config = lib.mkIf cfg.enable {
    # see https://www.kernel.org/doc/html/v5.6/process/changes.html
    environment.systemPackages =
      # Current Minimal Requirements
      (with pkgs; [
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
      # Kernel compilation
      ++ (with pkgs; [
        gcc
        gnumake
        binutils
        pkg-config
        flex
        bison
        perl
        bc
        openssl
      ])
      # /home/kdn/dev/git.kernel.org/pub/scm/linux/kernel/git/stable/linux/tools/objtool/include/objtool/elf.h:10:10: fatal error: gelf.h: No such file or directory
      ++ (with pkgs; [
        libelf
        elfutils
      ])
      ++ config.boot.kernelPackages.kernel.nativeBuildInputs
      ++ config.boot.kernelPackages.kernel.depsBuildBuild;
  };
}
