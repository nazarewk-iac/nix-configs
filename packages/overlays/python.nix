# based on https://github.com/flyingcircusio/fc-nixos/blob/a1c1063c4f2205fb6385fadc53083425451af5db/pkgs/overlay-python.nix
# see https://discourse.nixos.org/t/how-to-override-python-package-anki/8213/4

# usage:
#   python3 = pkgs.python3.override { packageOverrides = pkgs.kdn.overlays.python pkgs; };
{ ... }:
pkgs: final: prev:
{
  # https://github.com/NixOS/nixpkgs/issues/197408
  dbus-next = prev.dbus-next.overridePythonAttrs (old: {
    checkPhase = builtins.replaceStrings [ "not test_peer_interface" ] [ "not test_peer_interface and not test_tcp_connection_with_forwarding" ] old.checkPhase;
  });

  pypass = prev.pypass.overrideAttrs (o:
    let
      pbr_version = "0.2.2dev";
      version = "f86cf0ba0e5cb6a1236ff16d8f238b92bc49c517";
      sha256 = "sha256-PEPgWdsBjyHpgqPx2MNtYnn0wxI0KtlE+uCD7xO0pvE=";
    in
    {
      inherit version;

      src = pkgs.fetchFromGitHub {
        owner = "nazarewk";
        # see https://github.com/aviau/python-pass/pull/34
        repo = "python-pass";
        rev = version;
        inherit sha256;
      };
      doInstallCheck = false;
      patches = [
        (with pkgs; substituteAll {
          src = ./pypass-mark-executables.patch;
          version = pbr_version;
          git_exec = "${git}/bin/git";
          grep_exec = "${gnugrep}/bin/grep";
          gpg_exec = "${gnupg}/bin/gpg2";
          tree_exec = "${tree}/bin/tree";
          xclip_exec = "${xclip}/bin/xclip";
        })
      ];
    });
}
