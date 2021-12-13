{ pkgs, ... }: {
  environment.interactiveShellInit = ''
    [[ -z "$HOME" ]] || export PATH="$HOME/.asdf/shims:$PATH"
    source ${pkgs.asdf-vm}/share/asdf-vm/lib/asdf.sh
  '';

  environment.systemPackages = with pkgs; [
    asdf-vm
    unzip
    coreutils
  ];
}