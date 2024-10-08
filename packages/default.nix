{ pkgs, lib, ... }:
rec {
  # changed to manual list due to infinite recursion errors
  data-converters = pkgs.callPackage ./data-converters { };
  ente-photos-desktop = pkgs.callPackage ./ente-photos-desktop { };
  fortitoken-decrypt = pkgs.callPackage ./fortitoken-decrypt { };
  git-credential-keyring = pkgs.callPackage ./git-credential-keyring { };
  git-utils = pkgs.callPackage ./git-utils { };
  gtimelog = pkgs.callPackage ./gtimelog { };
  kdn-keepass = pkgs.callPackage ./kdn-keepass { };
  kdn-nix = pkgs.callPackage ./kdn-nix { };
  ff-ctl = pkgs.callPackage ./ff-ctl { };
  klg = pkgs.callPackage ./klg { };
  klog-time-tracker = pkgs.callPackage ./klog-time-tracker { };
  pass-secret-service = pkgs.callPackage ./pass-secret-service { };
  pinentry = pkgs.callPackage ./pinentry { };
  ss-util = pkgs.callPackage ./ss-util { };
  tc-redirect-tap = pkgs.callPackage ./tc-redirect-tap { };
  whicher = pkgs.callPackage ./whicher { };
  yubikey-configure = pkgs.callPackage ./yubikey-configure { };
}
