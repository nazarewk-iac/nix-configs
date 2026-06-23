{
  lib,
  pkgs,
  __inputs__ ? { },
}:
let
  inputs = __inputs__.inputs or { };

  uv2nix = inputs.uv2nix or (throw "basic-memory requires the uv2nix flake input");
  pyproject-nix =
    inputs.pyproject-nix or (throw "basic-memory requires the pyproject-nix flake input");
  pyproject-build-systems =
    inputs.pyproject-build-systems
      or (throw "basic-memory requires the pyproject-build-systems flake input");

  python = pkgs.python313;

  src = pkgs.fetchFromGitHub {
    owner = "basicmachines-co";
    repo = "basic-memory";
    rev = "b5f13d690317abe18987377d3100514d3b44d8a1";
    hash = "sha256-lPZ7Qe9XH/jsElOIB7tcHxGSgUfDS+23rtFBW+rh1jk=";
  };

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };

  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.wheel
      overlay
      (final: prev: {
        # These packages don't declare setuptools as build dep but need it
        pymeta3 = prev.pymeta3.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        pybars3 = prev.pybars3.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
      })
    ]
  );
  env = pythonSet.mkVirtualEnv "basic-memory-env" workspace.deps.default;
in
env.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    mkWrapper =
      args:
      pkgs.callPackage ./wrapper.nix (
        {
          basic-memory = env;
        }
        // args
      );
  };
})
