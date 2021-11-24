{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    vim
    wget
    bash
    aws-vault
    awscli2
    sshuttle
    jq
    yubikey-manager
    kubectl
    terraform

    k9s
    nodejs
    helm # unsupported Mac
    helmsman
  ];

  programs.git.enable = true;
  programs.git.signing.key = "916D8B67241892AE";
  programs.git.signing.signByDefault = true;
  programs.git.userName = "Krzysztof Nazarewski";
  programs.git.userEmail = "3494992+nazarewk@users.noreply.github.com";

  programs.ssh.enable = true;
  programs.ssh.extraConfig = ''
    Host *.fresha.io *.shedul.io
        User krzysztof.nazarewski
  '';
  
  programs.zsh.enable = true;
  # programs.zsh.enableSyntaxHighlighting = true;
  programs.zsh.initExtra = ''
    source ${pkgs.grml-zsh-config}/etc/zsh/zshrc
    eval "$(aws-vault --completion-script-zsh)"
  '';
  programs.zsh.sessionVariables = {
    AWS_VAULT_PROMPT = "ykman";
    AWS_ASSUME_ROLE_TTL = "8h";
  };
  programs.zsh.shellAliases = {
    aws-shell = "aws-vault exec -n";
    aws-login = "aws-vault login";
  };
}
