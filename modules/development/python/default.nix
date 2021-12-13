{ pkgs, ... }: {
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