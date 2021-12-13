{ pkgs, ... }: {
  home-manager.sharedModules = [
    {
      programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
    }
  ];
  environment.systemPackages = with pkgs; [
    # dev software
    awscli2
    sshuttle
    kubectl
    # terraform

    k9s
    nodejs
    kubernetes-helm
    helmsman
    kubectx
  ];
}