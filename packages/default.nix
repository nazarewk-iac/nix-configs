{ pkgs, lib, ... }: rec {
  # changed to manual list due to infinite recursion errors
  data-converters = pkgs.callPackage ./data-converters { };
  git-credential-keyring = pkgs.callPackage ./git-credential-keyring { };
  git-utils = pkgs.callPackage ./git-utils { };
  gtimelog = pkgs.callPackage ./gtimelog { };
  edid-generator = pkgs.callPackage ./edid-generator { };
  klg = pkgs.callPackage ./klg { };
  klog-time-tracker = pkgs.callPackage ./klog-time-tracker { };
  linuxhw-edid-fetcher = pkgs.callPackage ./linuxhw-edid-fetcher { };
  netbird = pkgs.callPackage ./netbird {
    inherit (pkgs.darwin.apple_sdk_11_0.frameworks) Cocoa IOKit Kernel UserNotifications WebKit;
  };
  netbird-ui = netbird.override { ui = true; };
  openapi-python-client-cli = pkgs.callPackage ./openapi-python-client-cli { };
  pass-secret-service = pkgs.callPackage ./pass-secret-service { };
  ss-util = pkgs.callPackage ./ss-util { };
  yubikey-configure = pkgs.callPackage ./yubikey-configure { };
}
