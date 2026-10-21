# Based on nixpkgs `pkgs/by-name/ra/rambox/package.nix`. nixpkgs lags the
# upstream Linux AppImage, so this copy tracks the newest Linux release. Bump
# `version` and `hash` when a newer Linux AppImage appears. Upstream ships the
# Linux AppImage after the macOS/Windows builds, so the newest release can have
# no Linux asset at all (for example 3.1.0).
#
# Electron opens external links through `shell.openExternal`, which execs the
# sandbox `xdg-open`. `wrapType2` builds an FHS sandbox, and that sandbox ships
# the stock `xdg-utils` `xdg-open`. The stock script does not know `sway`, so it
# picks its generic fallback list, where `google-chrome` wins. The override below
# installs the handlr `xdg-open` at a high priority, so the sandbox resolves the
# user's default handlers the same way the host does.
#
# The login callback has a second, larger problem. Rambox registers a deep-link
# handler for its `rambox://auth-callback` scheme, and it builds the handler's
# `Exec` line from `process.execPath` unless `$APPIMAGE` is set. The sandbox
# hides `$APPIMAGE`, so the handler names a path inside the sandbox, and the
# system cannot relaunch Rambox when the browser returns the callback. The
# wrapper below sets `$APPIMAGE` to its own host path, so Rambox registers a
# handler that works. See `writeUserDesktopEntry` and `linuxDesktopExec` in the
# bundled `app.asar`.
#
# That runtime registration is unreliable anyway. `installIcon` copies the
# read-only store icon with `fs.copyFileSync`, which copies the source mode, so
# the result in `~/.local/share/icons/rambox.png` is read-only. The next launch
# cannot overwrite it, `copyFileSync` throws `EACCES`, and the `try`/`catch`
# around `writeUserDesktopEntry` aborts before it writes the desktop file. So
# Rambox writes its deep-link handler once, at best. The `desktopItem` below
# therefore carries the scheme itself, and the user's `mimeapps.list` names
# `rambox.desktop` as the handler. The host then never depends on Rambox's own
# write, and `Exec=rambox %u` follows the package through updates.
#
# A consumer can add packages to the sandbox FHS environment. `extraPkgs` is a
# plain package argument, so `override` reaches it:
#
#     pkgs.kdn.rambox.override { extraPkgs = pkgs: with pkgs; [ sshfs ]; }
#
# It feeds `wrapType2`'s own `extraPkgs`, so the added package lands in the
# sandbox `/usr/bin` and can shadow an FHS tool. A changed set rebuilds the FHS
# rootfs; the AppImage extraction is reused. Every call keeps the default
# packages below.
{
  appimageTools,
  lib,
  fetchurl,
  makeDesktopItem,
  pkgs,
  extraPkgs ? (_: [ ]),
}:
let
  # The same `xdg-open` the `program-handlr` aspect installs on the host.
  xdg-open =
    pkgs:
    pkgs.writeShellApplication {
      name = "xdg-open";
      runtimeInputs = [ pkgs.handlr-regex ];
      text = ''handlr open "$@"'';
    };

  # Packages every rambox sandbox carries.
  defaultPkgs =
    pkgs: with pkgs; [
      procps
      handlr-regex
      wofi
      (lib.meta.hiPrio (xdg-open pkgs))
    ];

  pname = "rambox";
  version = "3.1.1";

  src = fetchurl {
    url = "https://github.com/ramboxapp/download/releases/download/v${version}/Rambox-${version}-linux-x64.AppImage";
    hash = "sha256-u/g1WDA/Tgfprykh2dcHYB2cvABp6UBJVJKS19rAyF8=";
  };

  desktopItem = makeDesktopItem {
    desktopName = "Rambox";
    name = "rambox";
    exec = "rambox %u";
    icon = "rambox";
    categories = [ "Network" ];
    mimeTypes = [ "x-scheme-handler/rambox" ];
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit
    pname
    version
    src
    desktopItem
    appimageContents
    ;

  extraInstallCommands = ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps
    install -Dm644 ${appimageContents}/usr/share/icons/hicolor/256x256/apps/rambox*.png $out/share/icons/hicolor/256x256/apps/rambox.png
    install -Dm644 ${desktopItem}/share/applications/* $out/share/applications

    # `$out/bin/rambox` is a symlink to the sandbox wrapper. Replace it with a
    # shim that exports the host path as `$APPIMAGE` and execs the real wrapper:
    # Rambox reads `$APPIMAGE` to build its deep-link handler, and the sandbox
    # hides the wrapper's own path.
    mv $out/bin/rambox $out/bin/.rambox-sandbox
    cat > $out/bin/rambox <<EOF
    #!${pkgs.runtimeShell}
    export APPIMAGE="$out/bin/rambox"
    exec "$out/bin/.rambox-sandbox" "\$@"
    EOF
    chmod +x $out/bin/rambox
  '';

  extraPkgs = pkgs: defaultPkgs pkgs ++ extraPkgs pkgs;

  meta = {
    description = "Workspace Simplifier - a cross-platform application organizing web services into Workspaces similar to browser profiles";
    homepage = "https://rambox.app";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ nazarewk ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
