{ pkgs, ... }: {
  home-manager.sharedModules = [
    {
      programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
    }
  ];
  environment.systemPackages = with pkgs; [
    # dev software
    sshuttle
    nodejs

    # AWS
    awscli2
    eksctl

    # terraform

    # kubernetes
    kubectl # dep for: chart-testing
    k9s
    kubectx

    # Helm
    kubernetes-helm # dep for: chart-testing
    chart-testing
    helmsman

    yamale # dep for: chart-testing
    yamllint # dep for: chart-testing
  ];
}