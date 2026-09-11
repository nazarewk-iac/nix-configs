# The Docker daemon, as a den aspect. It ports
# `modules/universal/virtualisation/containers/docker/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs the Docker daemon, and it installs the client and the compose plugin.
#
# ## One class only
#
# The old module runs on NixOS only, so this aspect serves the `nixos` class only.
#
# ## Pick one engine
#
# Do not include this aspect together with `virt-containers-podman`. That aspect sets
# `virtualisation.docker.enable` to false with `lib.mkDefault`, and this aspect sets it to true with
# a plain definition, so the plain definition wins and both engines run. `virt-containers` defaults
# neither engine on, so the consumer picks one.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** The target writes `environment.systemPackages`.
#    Design B.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `lib` and `pkgs` only.
{ ... }:
{
  kdn.virt-containers-docker.nixos =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      virtualisation.docker.enable = true;

      environment.systemPackages = filterPackages (
        with pkgs;
        [
          docker-client
          docker-compose
        ]
      );
    };
}
