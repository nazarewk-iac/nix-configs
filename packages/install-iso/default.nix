{ pkgs
, lib
, inputs
, ...
}:
let
  ssh = import ../../modules/profile/user/me/ssh.nix { inherit lib; };
in
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

    users.users.root.openssh.authorizedKeys.keys = ssh.authorizedKeysList;

    environment.systemPackages = with pkgs; [
      git
      jq
      zfs-prune-snapshots
      sanoid
    ];
  }];
}
