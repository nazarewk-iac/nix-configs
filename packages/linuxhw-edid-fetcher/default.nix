{ lib
, coreutils
, fetchFromGitHub
, gawk
, stdenv
, unixtools
, writeShellApplication
, ...
}:

# Usage:
#   let
#     edids = (linuxhw-edid-fetcher.override {
#       displays = {
#         PG278Q_2014 = [ "PG278Q" "2014" ];
#       };
#     });
#   in
#     "${edids}/lib/firmware/edid/PG278Q_2014.bin";
let
  revision = "98bc7d6e2c0eaad61346a8bf877b562fee16efc3";

  src = fetchFromGitHub {
    owner = "linuxhw";
    repo = "EDID";
    rev = revision;
    sha256 = "sha256-+Vz5GU2gGv4QlKO4A6BlKSETxE5GAcehKZL7SEbglGE=";
  };
in
writeShellApplication {
  name = "linuxhw-edid-fetcher";
  runtimeInputs = [ gawk coreutils unixtools.xxd ];
  text = ''
    cd '${src}'
    ${builtins.readFile ./linuxhw-edid-fetcher.sh}
  '';
}
