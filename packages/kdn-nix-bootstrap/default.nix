# The stable launchd entry point for a macOS host whose Nix store lives on an external USB volume.
#
# macOS TCC denies USB-volume access to every non-Apple binary in a launchd daemon context unless
# that exact path holds a Full Disk Access grant. A /nix/store path churns with every nixpkgs
# bump, so the grant cannot live there. This Go binary is copied (not symlinked, TCC resolves
# symlinks) to the fixed path `/usr/local/bin/kdn-nix-bootstrap` by the activation of
# `kdn.nix-store-bootstrap`, is granted once, and spawns the real nix daemons as children. See
# main.go for the subcommands and docs/tasks/2026-10/nix-store-external-drive/migration/ for the
# design.
#
# Stdlib-only Go, so `vendorHash = null` and the build works on any host.
{
  lib,
  buildGoModule,
}:
buildGoModule (finalAttrs: {
  pname = "kdn-nix-bootstrap";
  version = "0.1.0";

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
    description = "Fixed-path launchd bootstrap that holds the Full Disk Access grant for the external Nix store";
    mainProgram = "kdn-nix-bootstrap";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
})
