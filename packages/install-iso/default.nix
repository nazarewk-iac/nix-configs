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
    imports = [
      ../../modules/nix.nix
    ];
    config = {
      # TODO: make custom modules available?
      #kdn.profile.machine.baseline.enable = true;

      nix.package = pkgs.nixVersions.stable;

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
      # fix for:
      #   error: The option `isoImage.isoName' has conflicting definition values:
      #     - In `/nix/store/v7l65f0mfszidw5z6napdsiyq0nnnvxn-source/nixos/modules/installer/cd-dvd/installation-cd-base.nix': "nixos-23.11.20230527.e108023-aarch64-linux.iso"
      #     - In `/nix/store/ld9rn0fc23j6cp92v9r31fq2nwc4s96b-source/formats/install-iso.nix': "nixos.iso"
      #     Use `lib.mkForce value` or `lib.mkDefault value` to change the priority on any of these definitions.
      isoImage.isoName = lib.mkForce "nixos.iso";
    };
  }];
}
