# The remote-builder identity, as a den aspect. It ports
# `modules/universal/nix/remote-builder/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It declares the account, the group and the SSH identity that this tree uses for a remote Nix
# build, plus one hacky `localhost` builder entry. It declares options and it emits **no config**,
# exactly like the file it ports.
#
# The reader of these options is `modules/universal/profile/remote-builders/default.nix`, which a
# later batch ports. So this aspect is declaration-only until that batch lands. It ships now because
# it is mechanical, it carries zero behaviour, and it proves the `enable` and the `readOnly` handling
# before a harder batch needs it.
#
# One module function serves both classes. Nothing here is class-specific.
#
# ## The three changes the aspect rules force
#
# 1. **`enable` goes.** Inclusion is the switch, so the old `kdn.nix.remote-builder.enable` has no
#    job. 18 leaves remain out of 19.
# 2. **`localhost.enable` becomes `localhost.use`.** `checks/standalone.nix` walks the option tree
#    and stops at an `attrsOf submodule` only, so that leaf is reachable and the old name fails the
#    gate. The default expression does not change.
# 3. **The five `readOnly` flags go** — `name`, `user.id`, `user.name`, `group.name` and `group.id`.
#    `readOnly` refuses every assignment, so an adopter could not rename the builder account or move
#    it off a used uid. Every default is unchanged, so this repository's own value does not move.
#    Measured on 2026-09-11: a rename reaches `group.name` and `localhost.sshUser`, and a new uid
#    reaches `group.id`.
#
# ## One option trap this file respects
#
# `localhost.systems`, `localhost.supportedFeatures` and `localhost.mandatoryFeatures` are `listOf`.
# Each one keeps this tree's value in its own `default`, and none of them carries a `lib.mkDefault`.
# A plain definition replaces a `mkDefault` default, but two plain definitions concatenate, so a
# `mkDefault` on a list would change what an adopter can do.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 and change 2 above.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # One module function, assigned to both classes below.
  target =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.nix.remote-builder;
    in
    {
      options.kdn.nix.remote-builder.use = lib.mkOption {
        type = lib.types.bool;
        default = cfg.user.ssh.IdentityFile != null;
        defaultText = lib.literalExpression "config.kdn.nix.remote-builder.user.ssh.IdentityFile != null";
        description = ''
          Use this host as a remote builder client. It defaults to true as soon as the account holds
          an SSH identity file.
        '';
      };

      options.kdn.nix.remote-builder.name = lib.mkOption {
        type = lib.types.str;
        default = "kdn-nix-remote-build";
        description = ''
          The base name of the builder account and of the builder group. An adopter renames it here.
        '';
      };

      options.kdn.nix.remote-builder.description = lib.mkOption {
        type = lib.types.str;
        default = "kdn's remote Nix builder";
        description = "The GECOS description of the builder account.";
      };

      options.kdn.nix.remote-builder.localhost.use = lib.mkOption {
        type = lib.types.bool;
        default = cfg.localhost.publicHostKey != "";
        defaultText = lib.literalExpression ''config.kdn.nix.remote-builder.localhost.publicHostKey != ""'';
        description = ''
          Register a `localhost` builder entry, so that this host builds for itself over SSH. It is a
          hack, and it needs the host's own public host key.
        '';
      };

      options.kdn.nix.remote-builder.localhost.sshUser = lib.mkOption {
        type = lib.types.str;
        default = cfg.user.name;
        defaultText = lib.literalExpression "config.kdn.nix.remote-builder.user.name";
        description = "The account the `localhost` builder entry logs in as.";
      };

      # TODO: find out how to generate this key
      options.kdn.nix.remote-builder.localhost.publicHostKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          The host's own public host key, for the `localhost` builder entry. The empty default keeps
          that entry off.
        '';
      };

      options.kdn.nix.remote-builder.localhost.hostName = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "The host name the `localhost` builder entry connects to.";
      };

      options.kdn.nix.remote-builder.localhost.protocol = lib.mkOption {
        type = lib.types.str;
        default = "ssh-ng";
        description = "The store protocol of the `localhost` builder entry.";
      };

      options.kdn.nix.remote-builder.localhost.maxJobs = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "How many builds the `localhost` builder entry runs at once.";
      };

      options.kdn.nix.remote-builder.localhost.speedFactor = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "The relative speed of the `localhost` builder entry.";
      };

      options.kdn.nix.remote-builder.localhost.systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ pkgs.stdenv.hostPlatform.system ];
        defaultText = lib.literalExpression "[ pkgs.stdenv.hostPlatform.system ]";
        description = "The systems the `localhost` builder entry builds for.";
      };

      options.kdn.nix.remote-builder.localhost.supportedFeatures = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        description = "The features the `localhost` builder entry offers.";
      };

      options.kdn.nix.remote-builder.localhost.mandatoryFeatures = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "The features a derivation must ask for to reach the `localhost` entry.";
      };

      options.kdn.nix.remote-builder.user.id = lib.mkOption {
        type = lib.types.int;
        default = 25839;
        description = ''
          The uid of the builder account. An adopter moves it when the number is already in use.
        '';
      };

      options.kdn.nix.remote-builder.user.name = lib.mkOption {
        type = lib.types.str;
        default = cfg.name;
        defaultText = lib.literalExpression "config.kdn.nix.remote-builder.name";
        description = "The name of the builder account.";
      };

      options.kdn.nix.remote-builder.user.ssh.IdentityFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/var/lib/secrets/remote-builder.key";
        description = ''
          Path to the private SSH key this host logs in with. `null` keeps `use` above false.
        '';
      };

      options.kdn.nix.remote-builder.group.name = lib.mkOption {
        type = lib.types.str;
        default = cfg.name;
        defaultText = lib.literalExpression "config.kdn.nix.remote-builder.name";
        description = "The name of the builder group.";
      };

      options.kdn.nix.remote-builder.group.id = lib.mkOption {
        type = lib.types.int;
        default = cfg.user.id;
        defaultText = lib.literalExpression "config.kdn.nix.remote-builder.user.id";
        description = "The gid of the builder group.";
      };
    };
in
{
  kdn.nix-remote-builder.nixos = target;
  kdn.nix-remote-builder.darwin = target;
}
