{ lib, ... }:
let
  mkPythonScript = pkgs: import ./mkPythonScript.nix { inherit lib pkgs; };
in
{
  inherit
    mkPythonScript
    ;
}
