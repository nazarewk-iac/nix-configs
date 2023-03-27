{ pkgs
, inputs
, ...
}:
inputs.nixos-generators.nixosGenerate {
  inherit pkgs;
  format = "install-iso";
  modules = [{
    # TODO: make custom modules available?
    #kdn.profile.machine.baseline.enable = true;

    nix.package = pkgs.nixVersions.stable;
    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';
    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.allowAliases = true;

    services.openssh.enable = true;
    services.openssh.openFirewall = true;
    services.openssh.settings.PasswordAuthentication = false;

    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFngB2F2qfcXVbXkssSWozufmyc0n6akKYA8zgjNFdZ"
    ];

    environment.systemPackages = with pkgs; [
      git
      jq
    ];
  }];
}
