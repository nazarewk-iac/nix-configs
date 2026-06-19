{ pkgs, ... }:
{
  packages = with pkgs; [
    nil
    nixd
    nixfmt
  ];

  scripts.hello.exec = ''
    echo "hello from nix-configs devenv"
  '';
}
