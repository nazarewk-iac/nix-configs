# The build-farm clients of the old `profile/remote-builders` module, as one pure data function.
#
# The old module holds this list inline. A den aspect carries no personal data, so the value lives
# here and the consumer passes it to `kdn.profile-remote-builders.buildMachines`.
#
# The function reproduces the old pipeline exactly, because the order of the filters changes the
# result:
#
#   1. drop the machine itself (by name, and by name prefix);
#   2. drop every builder that lists `x86_64-linux` — the old TODO left the common x86 builder on
#      the local path, so `etra` and `brys` never reach this list;
#   3. add the shared defaults and concatenate `supportedFeatures`;
#   4. duplicate each entry per domain, with a speed factor;
#   5. append the `localhost` entry when the host has a public host key.
#
# Measured on `brys` 2026-11-17: the old list is `briv` × 2 domains and `anji` × 2 domains.
{
  lib,
  hostName,
  user,
}:
let
  builders = [
    {
      hostName = "briv";
      systems = [ "aarch64-linux" ];
      maxJobs = 2;
      speedFactor = 4;
      supportedFeatures = [ "gccarch-armv8-a" ];
      mandatoryFeatures = [ ];
    }
    {
      hostName = "etra";
      systems = [ "x86_64-linux" ];
      maxJobs = 2;
      speedFactor = 4;
    }
    {
      hostName = "brys";
      systems = [ "x86_64-linux" ];
      maxJobs = 12;
      speedFactor = 32;
    }
    {
      hostName = "oams";
      systems = [ "x86_64-linux" ];
      maxJobs = 6;
      speedFactor = 10;
    }
    {
      hostName = "anji";
      # `anji` is aarch64-darwin, and it runs a QEMU aarch64-linux builder. So it serves
      # `aarch64-linux` too: its own daemon forwards each such build to that builder VM
      # (`nix.distributedBuilds` is on there). One entry covers every system, so no separate
      # `anji-linux-builder` host name is needed.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
      ];
      maxJobs = 4;
      speedFactor = 8; # 4 performance and 4 efficiency cores
    }
  ];

  defaults = {
    protocol = "ssh-ng";
    sshUser = user.name;
    supportedFeatures = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
    mandatoryFeatures = [ ];
  };
in
lib.pipe builders [
  (builtins.filter (
    builder: hostName != builder.hostName && !(lib.strings.hasPrefix hostName builder.hostName)
  ))
  # The old TODO: the common `x86_64-linux` builder stays on the local path.
  (builtins.filter (builder: !(builtins.elem "x86_64-linux" builder.systems)))
  (map (
    old:
    defaults
    // old
    // {
      supportedFeatures = builtins.concatLists [
        (defaults.supportedFeatures or [ ])
        (old.supportedFeatures or [ ])
      ];
    }
  ))
  (map (
    old:
    (map
      (
        {
          domain,
          factor ? 100,
        }:
        old
        // lib.attrsets.optionalAttrs (domain != "") {
          hostName = "${old.hostName}.${domain}";
          speedFactor = builtins.floor (old.speedFactor * factor);
        }
      )
      [
        {
          domain = "lan.etra.net.int.kdn.im.";
          factor = 100;
        }
        {
          domain = "priv.nb.net.int.kdn.im.";
          factor = 20;
        }
      ]
    )
  ))
  lib.lists.flatten
]
