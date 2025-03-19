# copied from https://github.com/tcarrio/nix-config/blob/3647084712109482b453cf628c8b4453584c79dc/pkgs/ente.nix
{
  appimageTools,
  lib,
  fetchurl,
}: let
  pname = "ente-photos-desktop";
  version = "1.7.10";
  shortName = "ente";
  src = fetchurl {
    url = "https://github.com/ente-io/photos-desktop/releases/download/v${version}/${shortName}-${version}-x86_64.AppImage";
    hash = "sha256-L2N3saNeJDdji/IzC2Zi0Iixc/pPNSUpz07egywx+4U=";
  };

  appimageContents = appimageTools.extractType2 {inherit pname version src;};
in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -m 444 -D ${appimageContents}/${shortName}.desktop $out/share/applications/${pname}.desktop
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace 'Exec=AppRun' "Exec=$out/bin/${pname}"
      cp -r ${appimageContents}/usr/share/icons $out/share
    '';

    extraPkgs = pkgs: with pkgs; [fuse];

    meta = with lib; {
      description = "Fully open source, End to End Encrypted alternative to Google Photos and Apple Photos";
      mainProgram = "ente-photos-desktop";
      homepage = "https://github.com/ente-io/photos-desktop";
      license = licenses.mit;
      maintainers = with maintainer; [tcarrio];
      platforms = ["x86_64-linux"];
    };
  }
