{
  pkgs,
  lib,
  ...
}:
let
  exports.netbird = pkgs.callPackage ./netbird/package.nix { };
  exports.netbird-dashboard = pkgs.callPackage ./netbird-dashboard/package.nix { };
  exports.netbird-management = pkgs.callPackage ./netbird-management/package.nix {
    inherit (pkgs.kdn) netbird;
  };
  exports.netbird-relay = pkgs.callPackage ./netbird-relay/package.nix {
    inherit (pkgs.kdn) netbird;
  };
  exports.netbird-signal = pkgs.callPackage ./netbird-signal/package.nix {
    inherit (pkgs.kdn) netbird;
  };
  exports.netbird-ui = pkgs.callPackage ./netbird-ui/package.nix { inherit (pkgs.kdn) netbird; };
  exports.netbird-upload = pkgs.callPackage ./netbird-upload/package.nix {
    inherit (pkgs.kdn) netbird;
  };
in
exports
