{ config, pkgs, ... }:

{
  xdg.configFile."sway/config".source = ./sway/config;
  xdg.configFile."swayr/config.toml".source = ./swayr/config.toml;
  xdg.configFile."waybar/config".source = ./waybar/config;
  xdg.configFile."waybar/style.css".source = ./waybar/style.css;
  xdg.configFile."direnv/lib/nix-direnv.sh".source = ./direnv/lib/nix-direnv.sh;

  programs.git.enable = true;
  programs.git.signing.key = "916D8B67241892AE";
  programs.git.signing.signByDefault = true;
  programs.git.userName = "Krzysztof Nazarewski";
  programs.git.userEmail = "3494992+nazarewk@users.noreply.github.com";

  programs.ssh.enable = true;
  programs.ssh.extraConfig = ''
    Host *.fresha.io
        User krzysztof.nazarewski
  '';

  programs.zsh.enable = true;
}
