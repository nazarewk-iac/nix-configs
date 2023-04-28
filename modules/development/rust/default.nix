{ lib, pkgs, config, ... }:
let
cfg = config.kdn.development.rust;
in
{
options.kdn.development.rust = {
enable = lib.mkEnableOption "Rust development";
};

config = lib.mkIf cfg.enable {
environment.systemPackages = with pkgs; [
#cargo
#rustc
rustup
rust-analyzer
pkg-config
];
};
}
