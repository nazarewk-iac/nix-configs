{ lib, ... }: {
  for = self:
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

      microvm.packages = { name, hypervisor, system, ... }:
        let
          cfg = self.nixosConfigurations.${name}.config;
        in
        lib.mkIf (system == cfg.system) {
          ${name} = cfg.microvm.runner.${hypervisor};
        };

      microvm.system = { name, hypervisor, system ? "x86_64-linux", ... }@args: nixos.system (args // {
        modules = [
          self.microvm.nixosModules.microvm
          {
            shares = [{
              # use "virtiofs" for MicroVMs that are started by systemd
              proto = "9p";
              tag = "ro-store";
              # a host's /nix/store will be picked up so that the
              # size of the /dev/vda can be reduced.
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }];
            socket = "control.socket";
            microvm.hypervisor = hypervisor;
          }
        ] ++ args.modules;
      });

      microvm.configuration = { name, ... }@args: { ${name} = microvm.system args; };
    in
    {
      inherit
        nixos
        microvm
        packagesForOverlay
        ;
    };
}
