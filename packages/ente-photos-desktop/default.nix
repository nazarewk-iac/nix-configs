# copied from https://github.com/tcarrio/nix-config/blob/3647084712109482b453cf628c8b4453584c79dc/pkgs/ente.nix
{
  appimageTools,
  lib,
  fetchurl,
  pkgs,
}: let
  pname = "ente-photos-desktop";
  version = "1.7.7";
  shortName = "ente";
  applicationName = "Ente";
  name = "${shortName}-${version}";

  # https://github.com/ente-io/photos-desktop/releases/download/v1.6.63/ente-1.6.63-arm64.AppImage
  # https://github.com/ente-io/photos-desktop/releases/download/v1.6.63/ente-1.6.63-x86_64.AppImage
  mirror = "https://github.com/ente-io/photos-desktop/releases/download";
  src = fetchurl {
    url = "${mirror}/v${version}/${name}-x86_64.AppImage";
    hash = "sha256-PGESx31SA7rDC0WmDAyg+2FAlqAZc0/8zXzTwzXKq7Y=";
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
