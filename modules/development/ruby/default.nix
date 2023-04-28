{ lib, pkgs, config, ... }:
let
cfg = config.kdn.development.ruby;
in
{
options.kdn.development.ruby = {
enable = lib.mkEnableOption "Ruby development";
};

config = lib.mkIf cfg.enable {
environment.systemPackages = with pkgs; [
ruby_3_0
];
};
}
