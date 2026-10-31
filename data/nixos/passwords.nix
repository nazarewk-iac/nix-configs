# The owner's password hashes, as a data module for the den tree.
#
# `data/README.md` rule 3 puts this file under `nixos/`: it names no `kdnConfig`, and every
# consumer is a NixOS host. It is a module, not a payload: a consumer imports it by path behind
# `builtins.pathExists`, so deleting the file leaves the tree evaluating.
#
# ## Why hashes here and not in an aspect
#
# A password hash is the owner's personal value. The `data/` rule keeps it out of
# `modules/universal/`, `modules/slots/` and `modules/den/`. The old universal tree inlines these
# hashes in its own module files; this file is the den-side home for the same values. The
# universal tree is left alone on purpose, so the move to den is the only change.
#
# ## `hashedPasswordFile`, never an inline hash
#
# Each value is written to a file and the file path is what the option receives. nixpkgs types
# `users.users.<name>.hashedPasswordFile` and `kdn.profile-baseline.rootHashedPasswordFile` as a
# path string and reads it only at activation, so no evaluation needs the value. A sops user may
# override the host line with a secret path; this file is the default source for the same values.
#
# It sets the two options the den tree already declares, so no new option is needed:
#   kdn.users.<name>.hashedPasswordFile             (modules/den/common/user-schema.nix)
#   kdn.profile-baseline.rootHashedPasswordFile     (modules/den/aspects/profile-baseline.nix)
#
# The hashes are the yescrypt/crypt values the old tree ships, unchanged:
#   root  modules/universal/profile/machine/baseline/default.nix
#   kdn   modules/universal/profile/user/kdn/default.nix
#   bn    modules/universal/profile/user/bn/default.nix
#   sn    modules/universal/profile/user/sn/default.nix
{ pkgs, ... }:
let
  # One file per account, holding the one-line hash. Both options type as `nullOr str`, so the
  # value is the store path as a **string** (`"${…}"`), not a path object.
  hashFile =
    name: hash: "${pkgs.writeText "password-hash-${name}" (hash + "\n")}";
in
{
  kdn.profile-baseline.rootHashedPasswordFile = hashFile "root"
    "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";

  kdn.users = {
    kdn.hashedPasswordFile = hashFile "kdn"
      "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
    bn.hashedPasswordFile = hashFile "bn"
      "$6$rounds=4096$KyC.856JV99or3zx$X2wYf1M6rO3xqDkOlMwFaAJvgiIUewc/LtWEPNCgZUBQceFlNsgEw1IgZmjduFE41IFdJWKqKuroUAznvE0Sx0";
    sn.hashedPasswordFile = hashFile "sn"
      "$y$j9T$WGU0Qrlm0.jq7Y4QfyVYC0$HiYyLZMDX8M/A7WNshB5PjtZEGufQ.Qa93FY4WIlcw8";
  };
}
