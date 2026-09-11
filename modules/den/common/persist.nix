# The `kdn.disks.persist` declaration, shared by every aspect that writes into it.
#
# `kdn.disks.persist.*` is the most-written option of the machine layer. The old tree counts 40
# readers and writers. In den each writer is a separate aspect, and every one of them needs the
# option to exist.
#
# The module system rejects two inline declarations of one option. It does dedupe an import **by
# path**. So every aspect that writes this option adds one line to its target module:
#
#     imports = [ ../common/persist.nix ];
#
# Two scopes use it, with the same shape:
#
#   * `nixos` — the host writes a system path, for example `/var/log`. `../aspects/disks.nix`
#     turns the value into `preservation.preserveAt`.
#   * `homeManager` — the user writes a path relative to the home directory, for example
#     `.cache/nix`. The host reads it back through `config.home-manager.users.<name>`.
#
# The `users` sub-option belongs to the `nixos` scope. It lets a host name a per-user path without
# a Home Manager module.
{ lib, pkgs, ... }:
let
  # One path entry. A plain string names the path. An attribute set carries the preservation
  # options too — `mode`, `how`, `inInitrd`, `configureParent`, and so on.
  pathType = lib.types.listOf (
    lib.types.either lib.types.str (
      lib.types.submodule { freeformType = (pkgs.formats.json { }).type; }
    )
  );
in
{
  options.kdn.disks.persist = lib.mkOption {
    default = { };
    description = ''
      What this machine keeps between boots, grouped by bucket. A bucket name matches a
      `kdn.disks.base` entry, for example `sys/data`, `usr/config` or `disposable`.

      Every list merges by concatenation, so many aspects write the same bucket and none of them
      replaces another.
    '';
    example = lib.literalExpression ''
      {
        "sys/data".directories = [ "/var/lib/my-service" ];
        "usr/config".files = [ "/etc/my-service.conf" ];
      }
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.directories = lib.mkOption {
          type = pathType;
          default = [ ];
          description = "Directories this bucket keeps.";
        };
        options.files = lib.mkOption {
          type = pathType;
          default = [ ];
          description = "Single files this bucket keeps.";
        };
        options.users = lib.mkOption {
          default = { };
          description = ''
            Per-user paths this bucket keeps, each one relative to the user's home directory. The
            `nixos` scope uses this; a Home Manager scope writes `directories` and `files` instead.
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              freeformType = (pkgs.formats.json { }).type;
              options.directories = lib.mkOption {
                type = pathType;
                default = [ ];
                description = "Directories this user keeps, relative to the home directory.";
              };
              options.files = lib.mkOption {
                type = pathType;
                default = [ ];
                description = "Single files this user keeps, relative to the home directory.";
              };
            }
          );
        };
      }
    );
  };
}
