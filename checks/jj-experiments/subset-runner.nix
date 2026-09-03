# Standalone subset runner for the jj-experiments suite.
#
# Run a subset through a hermetic nix build, passing pytest flags as a JSON
# array — no `--impure` flag:
#   nix build --file checks/jj-experiments/subset-runner.nix \
#     --argstr extraArgsJSON '["-k","placement"]' -L
#
# Classic `-f` evaluation runs in impure mode by default, so `getFlake` and
# `currentSystem` resolve with no flag. `--argstr` is a pure argument and only
# works with `-f` (an auto-called function), not with a flake ref. The build
# itself (the runCommand from mk-pytest.nix) is always sandboxed.
#
# `getFlake ("path:" + repo)` reads the WORKING TREE (gitignore-filtered), so it
# picks up untracked and dirty files — this file and mk-pytest.nix are visible
# before they are committed, and working-tree edits are picked up at once.
{
  repo ? toString ../.., # repo root, from checks/jj-experiments/
  extraArgsJSON ? "[]",
}:
let
  flake = builtins.getFlake ("path:" + repo);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  lib = flake.lib;
  toml = import (flake + "/checks/jj-experiments/render-fork-config.nix") {
    inherit pkgs;
    mkSlots = lib.kdn.mkSlots;
    slotsPath = flake + "/modules/slots";
    nixConfigs = flake;
    extraInputs = flake.inputs;
  };
in
import (flake + "/checks/jj-experiments/mk-pytest.nix") {
  inherit pkgs lib toml;
  suite = flake + "/checks/jj-experiments"; # store-path string; `cp -r` copies it
  extraArgs = builtins.fromJSON extraArgsJSON;
}
