# Den aspect for the container runner: containerd + nix-snapshotter + declarative `nerdctl` units.
#
# No cluster. A host that routes traffic should not also run a control plane; the runner is one
# containerd daemon and a unit per container. The universal module owns the mechanism, this aspect
# owns the wiring and the host-facing switch.
{ ... }:
{
  imports = [ ../../universal/containerd-nix-snapshotter.nix ];

  # A host opts in with `kdn.containers.enable = true;` and declares its containers as data.
  kdn.containers.enable = true;
}
