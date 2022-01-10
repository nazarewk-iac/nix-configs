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
    python37
    python38
    (python39.withPackages (ps:
      with ps; [
        pip
        ipython
        requests
        pipx
        # pip-tools
        pyaml
        boto3
      ]))
    python310
    python311
  ];

  environment.interactiveShellInit = ''
    [[ -z "$HOME" ]] || export PATH="$HOME/.local/bin:$PATH"
  '';
}