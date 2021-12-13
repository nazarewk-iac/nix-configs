{ pkgs, ... }: {
  home-manager.sharedModules = [
    {
      programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
    }
  ];
  environment.systemPackages = with pkgs; [
    # python software
    pipenv
    poetry
    (python39.withPackages (ps:
      with ps; [
        pip
        ipython
        requests
        pip-tools
      ]))
  ];
}