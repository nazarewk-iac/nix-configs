{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.nix;
in
{
  options.kdn.nix = {
    enable = lib.mkEnableOption "nix development tooling in devenv";
  };

  config = lib.mkIf cfg.enable {
    claude.code.enable = true;

    packages = with pkgs; [
      nil
      nixd
      nixfmt
    ];

    scripts.hello.exec = ''
      echo "hello from nix-configs devenv"
    '';
  };
}
