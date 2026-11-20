# The stable launchd and operator entry point for a macOS host whose Nix store lives on an
# external USB volume.
#
# macOS TCC denies USB-volume access to every non-Apple binary in a launchd daemon context unless
# that exact path holds a Full Disk Access grant. A /nix/store path churns with every nixpkgs
# bump, so the grant cannot live there. This Go binary is copied (not symlinked, TCC resolves
# symlinks) to the fixed path `/usr/local/bin/kdn-nix-darwin-helper` by the activation of
# `hosts/anji/default.nix`, is granted once, and spawns the real daemons or operator commands as
# children.
#
# The old name was `kdn-nix-bootstrap`. The new name says what it is: the one granted helper for
# every Darwin operation, not only the store mount. The rename changes the TCC path and therefore
# needs one fresh Full Disk Access grant; see docs/darwin-quirks.md.
#
# Stdlib-only Go, so `vendorHash = null` and the build works on any host.
{
  lib,
  buildGoModule,
}:
buildGoModule (finalAttrs: {
  pname = "kdn-nix-darwin-helper";
  version = "0.2.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./main.go
      ./main_test.go
    ];
  };
  vendorHash = null;
  subPackages = [ "." ];

  doCheck = true;

  meta = {
    description = "Fixed-path Darwin helper that holds the Full Disk Access grant for the external Nix store and operator commands";
    mainProgram = "kdn-nix-darwin-helper";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
})
