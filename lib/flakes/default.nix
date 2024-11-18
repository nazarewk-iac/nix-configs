{lib, ...}: {
  forFlake = self: let
    overlayedInputs = {
      system,
      overlay ? self.overlays.default,
    }: let
      # adapted from https://github.com/nix-community/nixpkgs-wayland/blob/b703de94dd7c3d73a03b5d30b248b8984ad8adb7/flake.nix#L119-L127
      pkgsFor = pkgs: overlays:
        import pkgs {
          inherit system overlays;
          config.allowUnfree = true;
          config.allowAliases = true;
        };
      _overlayedInputs = overlays: lib.genAttrs (builtins.attrNames self.inputs) (inp: pkgsFor self.inputs."${inp}" overlays);
    in
      _overlayedInputs [overlay];

    mkNixosSystemArgs = {
      modules ? [],
      system ? "x86_64-linux",
      ...
    }: {
      inherit system;
      specialArgs = {
        inherit self system;
        inherit (self) inputs lib;
      };

      modules = [self.nixosModules.default] ++ modules;
    };

    nixos.system = args: lib.nixosSystem (mkNixosSystemArgs args);
    nixos.configuration = {name, ...} @ args: {${name} = nixos.system args;};
    nixos.install-iso = args: let
      prev = mkNixosSystemArgs args;
    in
      self.inputs.nixos-generators.nixosGenerate (prev
        // {
          inherit (prev.specialArgs) lib;
          inherit (lib) nixosSystem;

          modules =
            prev.modules
            ++ [
              {
                /*
                `isoImage.isoName` gives a stable image filename
                */
                /*
                `lib.mkForce` is a fix for:
                 error: The option `isoImage.isoName' has conflicting definition values:
                   - In `/nix/store/v7l65f0mfszidw5z6napdsiyq0nnnvxn-source/nixos/modules/installer/cd-dvd/installation-cd-base.nix': "nixos-23.11.20230527.e108023-aarch64-linux.iso"
                   - In `/nix/store/ld9rn0fc23j6cp92v9r31fq2nwc4s96b-source/formats/install-iso.nix': "nixos.iso"
                   Use `lib.mkForce value` or `lib.mkDefault value` to change the priority on any of these definitions.
                */
                isoImage.isoName = lib.mkForce "nixos.iso";

                /*
                 `install-iso` uses some weird GRUB booting chimera
                see https://github.com/NixOS/nixpkgs/blob/9fbeebcc35c2fbc9a3fb96797cced9ea93436097/nixos/modules/installer/cd-dvd/iso-image.nix#L780-L787
                */
                boot.initrd.systemd.enable = lib.mkForce false;
                boot.loader.systemd-boot.enable = lib.mkForce false;
              }
            ];

          format = "install-iso";
        });

    # wrap self.nixosConfigurations in executable packages
    # see https://github.com/astro/microvm.nix/blob/24136ffe7bb1e504bce29b25dcd46b272cbafd9b/flake.nix#L57-L69
    microvm.packages = system: (builtins.foldl'
      (result: systemName: let
        nixos = self.nixosConfigurations.${systemName};
        name = builtins.replaceStrings ["${system}-"] [""] systemName;
        inherit (nixos.config.microvm) hypervisor;
      in
        if nixos.config ? microvm && nixos.pkgs.stdenv.system == system
        then
          result
          // {
            "${name}" = nixos.config.microvm.runner.${hypervisor};
          }
        else result)
      {}
      (builtins.attrNames self.nixosConfigurations));

    microvm.host = {system ? "x86_64-linux", ...} @ args:
      nixos.system (args
        // {
          modules = [{kdn.virtualization.microvm.host.enable = true;}] ++ args.modules;
        });

    microvm.guest = {
      name,
      system ? "x86_64-linux",
      ...
    } @ args:
      nixos.system (args
        // {
          modules = [{kdn.virtualization.microvm.guest.enable = true;}] ++ args.modules;
        });

    microvm.configuration = {name, ...} @ args: {${name} = microvm.guest args;};
  in {
    inherit
      nixos
      microvm
      overlayedInputs
      ;
  };
}
