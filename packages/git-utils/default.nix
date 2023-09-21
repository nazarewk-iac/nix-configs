{ pkgs, resholve, ... }:
# see https://github.com/abathur/resholve
# see https://github.com/NixOS/nixpkgs/blob/d9c6fcb483ae66621c1dd382cdd939493b8712d0/pkgs/development/misc/resholve/README.md
resholve.mkDerivation {
  version = "unset";
  pname = "git-utils";
  src = ./.;
  installPhase = ''
  '';
  solutions = {

    #    # an arbitrary name that you'd use to override this solution
    #    # (some packages need multiple conflicting solutions)
    #    funsies = {
    #      # $out-relative paths
    #      scripts = [ "library.bash" "bin/funsies.bash" ]; # 1
    #      interpreter = "${bash_5}/bin/sh"; # 2
    #      inputs = [ ]; # 3
    #    };
  };
}
