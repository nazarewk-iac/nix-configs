{
  lib,
  pkgs,
  fetchFromGitHub,
  makeWrapper,
  ...
}: let
  gtk3 = pkgs.gtk3;
  python = pkgs.python3;
  pythonPackages = pkgs.python3Packages;
  buildPythonPackage = pythonPackages.buildPythonPackage;
in
  buildPythonPackage rec {
    pname = "gtimelog";
    version = "git-2022-10-07";

    src = fetchFromGitHub {
      owner = pname;
      repo = pname;
      rev = "b99b82238eb626c8efcad6675b625b6c478421a7";
      sha256 = "sha256-zC2IWYhHgwVbmN9X0q+/unu7E0sP2iTUbIIp1kvynoQ=";
    };

    nativeBuildInputs = [makeWrapper];
    buildInputs = with pkgs; [
      glibcLocales
      gobject-introspection
      gtk3
      libsoup
      libsecret
    ];

    propagatedBuildInputs = with pythonPackages; [
      pygobject3
      freezegun
      mock
    ];

    checkPhase = ''
      substituteInPlace runtests --replace "/usr/bin/env python3" "${python.interpreter}"
      ./runtests
    '';

    pythonImportsCheck = ["gtimelog"];

    # found at https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$reRwjXiP3c4q9-z3wnnnBF9Q5KYGi9w3DxeQLhEJhnI?via=nixos.org&via=matrix.org&via=tchncs.de
    makeWrapperArgs = [
      "--set GI_TYPELIB_PATH ${lib.makeSearchPathOutput "lib"
        "lib/girepository-1.0" (with pkgs; [
          gtk3
          libsoup
          libsecret
          pango
          harfbuzz
          gdk-pixbuf
          atk
        ])}"
      "--set GIO_MODULE_DIR ${lib.makeSearchPathOutput "out"
        "lib/gio/modules" (with pkgs; [
          glib-networking
        ])}"
    ];

    preFixup = ''
      wrapProgram $out/bin/gtimelog \
        --prefix GI_TYPELIB_PATH : "$GI_TYPELIB_PATH" \
        --prefix LD_LIBRARY_PATH ":" "${gtk3.out}/lib" \
    '';

    meta = with lib; {
      description = "A time tracking app";
      longDescription = ''
        GTimeLog is a small time tracking application for GNOME.
        It's main goal is to be as unintrusive as possible.
        To run gtimelog successfully on a system that does not have full GNOME 3
        installed, the following NixOS options should be set:
        - programs.dconf.enable = true;
        - services.gnome.gnome-keyring.enable = true;
        In addition, the following packages should be added to the environment:
        - gnome.adwaita-icon-theme
        - gnome.dconf
      '';
      homepage = "https://gtimelog.org/";
      license = licenses.gpl2Plus;
      maintainers = with maintainers; [oxzi nazarewk];
    };
  }
