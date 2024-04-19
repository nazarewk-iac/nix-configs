{ pkgs, lib, ... }:
rec {
  # changed to manual list due to infinite recursion errors
  data-converters = pkgs.callPackage ./data-converters { };
  fortitoken-decrypt = pkgs.callPackage ./fortitoken-decrypt { };
  git-credential-keyring = pkgs.callPackage ./git-credential-keyring { };
  git-utils = pkgs.callPackage ./git-utils { };
  gtimelog = pkgs.callPackage ./gtimelog { };
  kdn-nix = pkgs.callPackage ./kdn-nix { };
  klg = pkgs.callPackage ./klg { };
  klog-time-tracker = pkgs.callPackage ./klog-time-tracker { };
  openapi-python-client-cli = pkgs.callPackage ./openapi-python-client-cli { };
  pass-secret-service = pkgs.callPackage ./pass-secret-service { };
  pinentry = pkgs.callPackage ./pinentry { };
  ss-util = pkgs.callPackage ./ss-util { };
  tc-redirect-tap = pkgs.callPackage ./tc-redirect-tap { };
  whicher = pkgs.callPackage ./whicher { };
  yubikey-configure = pkgs.callPackage ./yubikey-configure { };
}
