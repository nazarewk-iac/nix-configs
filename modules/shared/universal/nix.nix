let
  adminUsers = [
    "@wheel" # linux
    "@admin" # macos
  ];
  allowedUsers = [
    "@users" # nixos
    "@staff" # macos
  ];
in {
  nix.extraOptions = ''
    # run as kdn:
    #   begin; set file nix/nix.sensitive.conf ; pass show "$file" | sudo tee "/etc/$file" >/dev/null && sudo chmod 0640 "/etc/$file" && sudo chown root:wheel "/etc/$file"; end
    !include /etc/nix/nix.sensitive.conf
    !include /etc/nix/nix.access-tokens.auto.conf
  '';

  nix.settings = {
    show-trace = true;
    experimental-features = ["nix-command" "flakes"];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
    substituters = [
      # TODO: cachix.org was down on  2025-03-20 17:20
      #"https://nix-community.cachix.org"
      #"https://nixpkgs-update.cachix.org"
      #"https://devenv.cachix.org"
    ];
    allowed-users = adminUsers ++ allowedUsers;
    trusted-users = adminUsers;
  };

  nixpkgs.config = {
    allowAliases = true;
    allowUnfree = true;

    permittedInsecurePackages = [
      "litestream-0.3.13"
      "electron-28.3.3" # loqseq dependency
      "electron-27.3.11" # loqseq dependency? 2024-07-12
    ];
  };
}
