{ appimageTools, lib, fetchurl, makeDesktopItem }:

let
  pname = "rambox";
  version = "2.0.9";
  name = "${pname}-${version}";

  src = fetchurl {
    url = "https://github.com/ramboxapp/download/releases/download/v${version}/Rambox-${version}-linux-x64.AppImage";
    sha256 = "sha256-o2ydZodmMAYeU0IiczKNlzY2hgTJbzyJWO/cZSTfAuM=";
  };

  desktopItem = (makeDesktopItem {
    desktopName = "Rambox";
    name = pname;
    exec = pname;
    icon = pname;
    categories = [ "Network" ];
  });

  appimageContents = appimageTools.extractType2 {
    inherit name src;
  };
in
appimageTools.wrapType2 {
  inherit name src;

  extraInstallCommands = ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps
    # CE uses rambox-<version>, Pro uses rambox
    mv $out/bin/rambox* $out/bin/${pname}
    install -Dm644 ${appimageContents}/usr/share/icons/hicolor/256x256/apps/rambox*.png $out/share/icons/hicolor/256x256/apps/${pname}.png
    install -Dm644 ${desktopItem}/share/applications/* $out/share/applications
  '';

  meta = with lib; {
    description = "Free and Open Source messaging and emailing app that combines common web applications into one";
    homepage = "https://rambox.pro";
    license = licenses.unfree;
    maintainers = with maintainers; [ nazarewk ];
    platforms = [ "x86_64-linux" ];
  };
}
