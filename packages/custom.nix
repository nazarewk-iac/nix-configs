{ pkgs, ... }:
let
  netbird = pkgs.callPackage ./netbird {
    inherit (pkgs.darwin.apple_sdk_11_0.frameworks) Cocoa IOKit Kernel UserNotifications WebKit;
  };
in
{
  inherit netbird;
  netbird-ui = netbird.override {
    ui = true;
  };
}
