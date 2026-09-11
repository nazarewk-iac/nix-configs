# Podman, as a den aspect. It ports
# `modules/universal/virtualisation/containers/podman/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# On NixOS it runs Podman as the OCI backend, with the Docker compatibility layer and the Docker
# socket, and with `netavark` plus `nftables` for the network. On Darwin it takes the `podman` binary
# from Homebrew.
#
# ## Two classes
#
# The `nixos` class runs the daemon. The `darwin` class installs the binary only, because Darwin
# needs a virtual machine for a Linux container and this aspect starts none.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** Each target writes its own native option. Design B.
# 3. **The Homebrew flag defaults to `true`.** The old default follows `kdn.homebrew.enable`, and
#    that option belongs to a part of the old tree that den does not port. Darwin has no other podman
#    route here, so `true` keeps the binary. A consumer that runs its own Homebrew sets `false`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.virt-containers-podman.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      config = lib.mkMerge [
        {
          environment.systemPackages = filterPackages [ pkgs.podman-compose ];

          virtualisation.docker.enable = lib.mkDefault false;
          virtualisation.podman.enable = true;

          virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

          virtualisation.oci-containers.backend = "podman";
          virtualisation.podman.dockerCompat = !config.virtualisation.docker.enable;
          virtualisation.podman.dockerSocket.enable = !config.virtualisation.docker.enable;

          # see https://github.com/NixOS/nixpkgs/issues/226365#issuecomment-1814296639
          networking.firewall.interfaces."podman*".allowedUDPPorts = [ 53 ];

          boot.kernel.sysctl."user.max_user_namespaces" = 15000;
        }
        {
          /*
            fixes `Error: netavark: code: 1, msg: iptables: Chain already exists.` when running more than 1 container
            - https://github.com/containers/netavark/issues/274
            - (fix) https://github.com/containers/netavark/issues/339#issuecomment-2080432677
          */
          virtualisation.containers.containersConf.settings.network.network_backend =
            lib.mkDefault "netavark";
          virtualisation.containers.containersConf.settings.network.firewall_driver =
            lib.mkDefault "nftables";
          # see https://github.com/containers/netavark/issues/274#issuecomment-3219896130
          virtualisation.podman.extraPackages = [ pkgs.nftables ];
        }
      ];
    };

  kdn.virt-containers-podman.darwin =
    { config, lib, ... }:
    let
      cfg = config.kdn.virtualisation.containers.podman;
    in
    {
      options.kdn.virtualisation.containers.podman.darwin.viaHomebrew = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Take the Darwin `podman` binary from Homebrew.

          Darwin has no other podman route in this tree, so `false` leaves the host with no podman
          binary. A consumer that runs its own Homebrew sets `false`.
        '';
      };

      config = lib.mkIf cfg.darwin.viaHomebrew {
        homebrew.brews = [ "podman" ];
      };
    };
}
