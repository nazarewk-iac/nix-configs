{ lib, ... }: {
  forFlake = self:
    let
      packagesForOverlay = { system, overlay ? self.overlays.default }:
        let
          # adapted from https://github.com/nix-community/nixpkgs-wayland/blob/b703de94dd7c3d73a03b5d30b248b8984ad8adb7/flake.nix#L119-L127
          pkgsFor = pkgs: overlays:
            import pkgs {
              inherit system overlays;
              config.allowUnfree = true;
              config.allowAliases = false;
            };
          pkgs_ = lib.genAttrs (builtins.attrNames self.inputs) (inp: pkgsFor self.inputs."${inp}" [ ]);
          opkgs_ = overlays: lib.genAttrs (builtins.attrNames self.inputs) (inp: pkgsFor self.inputs."${inp}" overlays);
        in
        (opkgs_ [ overlay ]).nixpkgs;

      nixos.system =
        { modules ? [ ]
        , system ? "x86_64-linux"
        , ...
        }: lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self system;
            inherit (self) inputs lib;
            waylandPkgs = self.inputs.nixpkgs-wayland.packages.${system};
          };

          modules = [
            self.nixosModules.default
            { nixpkgs.overlays = [ self.overlays.default ]; }
          ] ++ modules;
        };
      nixos.configuration = { name, ... }@args: { ${name} = nixos.system args; };

      # wrap self.nixosConfigurations in executable packages
      # see https://github.com/astro/microvm.nix/blob/24136ffe7bb1e504bce29b25dcd46b272cbafd9b/flake.nix#L57-L69
      microvm.packages = system: (builtins.foldl'
        (result: systemName:
          let
            nixos = self.nixosConfigurations.${systemName};
            name = builtins.replaceStrings [ "${system}-" ] [ "" ] systemName;
            inherit (nixos.config.microvm) hypervisor;
          in
          if nixos.config ? microvm && nixos.pkgs.stdenv.system == system
          then result // {
            "${name}" = nixos.config.microvm.runner.${hypervisor};
          }
          else result)
        { }
        (builtins.attrNames self.nixosConfigurations));

      microvm.host = { system ? "x86_64-linux", ... }@args: nixos.system (args // {
        modules = [
          self.inputs.microvm.nixosModules.host
          { kdn.virtualization.microvm.host.enable = true; }
        ] ++ args.modules;
      });

      guest = { name, hypervisor ? "qemu", system ? "x86_64-linux", ... }@args: nixos.system (args // {
        modules = [
          self.inputs.microvm.nixosModules.microvm
          { kdn.virtualization.microvm.guest.enable = true; }
          {
            microvm.hypervisor = hypervisor;
            microvm.shares = [{
              # use "virtiofs" for MicroVMs that are started by systemd
              proto = "9p";
              tag = "ro-store";
              # a host's /nix/store will be picked up so that the
              # size of the /dev/vda can be reduced.
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }];
          }
        ] ++ args.modules;
      });

      microvm.configuration = { name, ... }@args: { ${name} = guest args; };
    in
    {
      inherit
        nixos
        microvm
        packagesForOverlay
        ;
    };
}
