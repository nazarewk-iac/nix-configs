# The loader of the per-area assertion files. It scans this directory and turns each sibling
# `<area>.nix` into one `den-eval-<area>` check.
#
# ## The area file contract
#
# An area file is a function. The loader passes `pkgs`, `lib`, `inputs` and `harness`, plus **every
# name `../harness.nix` exports, flat**. So both of these headers work:
#
#   { lib, denLib, harness, ... }:      let inherit (harness) bareNixos; in [ ... ]
#   { lib, denLib, bareNixos, ... }:    [ ... ]
#
# End the argument set with `...`. The loader passes a superset, so a set without `...` fails.
#
# It returns one of two shapes:
#
#   [ { name; expected; actual; } ... ]                            # the assertion list alone
#   { assertions = [ ... ]; instantiatedBy = { ... }; }             # the list plus its coverage rows
#
# The second shape is the one to use. `instantiatedBy` holds one row per aspect the batch ports, and
# `../tests.nix` merges every area's rows into the table that `den-eval-coverage` reads. So a batch
# adds a coverage row inside its own file.
#
# ## Why the scan exists
#
# A new area joins the suite with **one new file** and no edit to a shared file. So ten batches write
# ten files in parallel, and none of them waits for another. `../../bundles.nix` reads the
# `den-eval-` prefix, so a new area also joins `bundle-den` on its own.
#
# ## The `git add` trap
#
# `builtins.readDir` reads the flake source, and the `git+file:` fetcher hides an untracked file. So
# a brand-new area file stays invisible until git tracks it, and the check then goes missing with no
# error at all. Run `git ls-files -- checks/den-mvp/assertions/` and confirm the new file before you
# trust a result.
{
  pkgs,
  lib,
  inputs,
  harness,
}:
let
  isArea = name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix";

  areaFiles = builtins.attrNames (lib.filterAttrs isArea (builtins.readDir ./.));

  # A bare list is the older shape. Normalise it, so both shapes reach the same code below.
  normalise =
    result:
    if builtins.isList result then
      {
        assertions = result;
        instantiatedBy = { };
      }
    else
      {
        inherit (result) assertions;
        instantiatedBy = result.instantiatedBy or { };
      };

  # Every harness export arrives flat, and `harness` arrives whole. So an area file reads either
  # shape. `harness` already holds `denLib` and `flake`, so those two arrive flat too.
  areaArgs = harness // {
    inherit
      pkgs
      lib
      inputs
      harness
      ;
  };

  loadArea = fileName: {
    name = lib.removeSuffix ".nix" fileName;
    value = normalise (import (./. + "/${fileName}") areaArgs);
  };

  areas = builtins.listToAttrs (map loadArea areaFiles);
in
{
  # One tier 1 check per area file.
  checks = lib.mapAttrs' (
    area: loaded: lib.nameValuePair "den-eval-${area}" (harness.mkEvalCheck area loaded.assertions)
  ) areas;

  # Every area's coverage rows, in one set. `../tests.nix` joins this to its own base table, and
  # `den-eval-coverage` compares the result with the registry.
  instantiatedBy = lib.foldl' (acc: loaded: acc // loaded.instantiatedBy) { } (lib.attrValues areas);

  # The area names, for a diagnostic read.
  areaNames = builtins.attrNames areas;
}
