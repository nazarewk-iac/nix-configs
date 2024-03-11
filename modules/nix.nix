{
  nix.extraOptions = ''
    # run as kdn:
    #   begin; set file nix/nix.sensitive.conf ; pass show "$file" | sudo tee "/etc/$file" >/dev/null && sudo chmod 0640 "/etc/$file" && sudo chown root:wheel "/etc/$file"; end
    !include /etc/nix/nix.sensitive.conf
  '';
  nix.settings = {
    show-trace = true;
    experimental-features = [ "nix-command" "flakes" ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "krul.kdn.im:9D33FhBuxCj/20Ct2ASHx3SqJ5FmfT8+BgoSzTwAZMc="
    ];
    substituters = [
      #"https://nix-community.cachix.org"
      "https://nixpkgs-update.cachix.org"
      "https://devenv.cachix.org"
    ];
    allowed-users = [ "@wheel" ];
    trusted-users = [ "@wheel" ];
  };

  nixpkgs.config = {
    allowAliases = true;
    allowUnfree = true;

    permittedInsecurePackages = [
      "electron-25.9.0" # loqseq dependency
      "qtwebkit-5.212.0-alpha4"

      # see https://github.com/NixOS/nixpkgs/blob/1c4d9e9a752232eb35579ab9d213ab217897cb6f/pkgs/top-level/release.nix#LL22C1-L30C7
      "openssl-1.1.1t"

      # TODO: remove after poetry2nix gets updated, see:
      # see 2.29 pinned at nixos-unstable https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/tools/poetry2nix/poetry2nix/pkgs/poetry/poetry.lock#L1505
      "python3.11-requests-2.29.0"
      "python3.11-cryptography-40.0.2"
    ];
  };

}
