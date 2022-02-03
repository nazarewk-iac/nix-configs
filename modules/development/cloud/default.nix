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
  ];
}