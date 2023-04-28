{ lib, pkgs, config, inputs, ... }:
let
cfg = config.kdn.programs.nix-index;
in
{
options.kdn.programs.nix-index = {
enable = lib.mkEnableOption "nix-index setup";
};

config = lib.mkIf cfg.enable {
environment.interactiveShellInit = ''
      source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
    '';

# use nix-index without `nix-channel`
# see https://github.com/bennofs/nix-index/issues/167
nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
environment.systemPackages = with pkgs; [ nix-index ];
};
}
