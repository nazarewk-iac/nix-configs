{
  lib,
  pkgs,
  ...
}: {
  src ? ./cloud-init,
  hostname,
  basename ? "${hostname}.cidata",
}:
pkgs.stdenv.mkDerivation {
  name = basename;
  inherit src hostname;

  nativeBuildInputs = with pkgs; [
    cdrkit # genisoimage
  ];

  patchPhase = ''
    substituteInPlace meta-data \
        --replace-fail "HOSTNAME" "$hostname"
  '';

  buildPhase = ''
    mkdir -p "$out/images"
    cp -r . "$out/cloud-init"
    genisoimage -output "$out/images/${basename}.iso" -V cidata -r -J ./{user,meta}-data
  '';
}
