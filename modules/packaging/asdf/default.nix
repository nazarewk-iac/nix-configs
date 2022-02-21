{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.packaging.asdf;
in {
  options.nazarewk.packaging.asdf = {
    enable = mkEnableOption "ASDF version manager";
  };

  config = mkIf cfg.enable {
    environment.interactiveShellInit = ''
      [[ -z "$HOME" ]] || export PATH="$HOME/.asdf/shims:$PATH"
      source ${pkgs.asdf-vm}/share/asdf-vm/lib/asdf.sh
    '';

    environment.systemPackages = with pkgs; [
      asdf-vm
      unzip
      coreutils
    ];
  };
}