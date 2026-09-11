# The shared `nix` and `nixpkgs` opinion of this tree, as a den aspect.
#
# It ports `modules/universal/_options.nix` and `modules/universal/nix.nix`. Both files stay in
# place and keep working. This file is the parallel den implementation.
#
# ## Why the name is not `nix`
#
# `modules/den/aspects/nix.nix` already ports the `nix` **slot** — the devenv shell that carries the
# two language servers and the formatter. That name is taken, so this aspect is `nix-config`.
#
# ## What it does
#
# It writes one `nix.conf` opinion and one nixpkgs opinion on a NixOS host and on a nix-darwin host:
#
#   - the three binary caches, each with its own public key
#   - the two admin groups and the two allowed groups
#   - the build directory, the trace flag and the two `!include` lines
#   - `allowUnfree`, `allowAliases` and the four insecure packages this tree accepts
#
# One module function serves both classes. Nothing here is class-specific: `nix.settings`,
# `nix.extraOptions` and `nixpkgs.config` all exist on NixOS and on nix-darwin. Measured on
# 2026-09-11 against a real host of each class.
#
# ## What the port drops
#
# `kdn.nixConfig` does not survive. It is an intermediate attribute set that exists only because the
# old loader copies it into three places. A den target writes `nix.settings`, `nix.extraOptions` and
# `nixpkgs.config` directly, so both the indirection and the whole `nix.nix` helper file go away.
#
# `kdn.enable` and `kdn.args` do not survive either. Rule 2 below forbids the first; the second has
# zero readers in the whole repository.
#
# `nix.nix:26` carries a comment with one person's password-manager command. This port drops it. A
# `!include` of a missing file is a no-op in `nix.conf`, so an adopter is safe with the default.
#
# ## Two option traps this file respects
#
# 1. **Every list stays in the option `default`.** `types.listOf` concatenates every definition, so a
#    literal at the assignment site is a definition an adopter can add to but never remove. So
#    `permittedInsecurePackages`, `substituters`, `adminGroups`, `allowedGroups` and
#    `extraConfIncludes` each carry this tree's value as a default, and no `lib.mkDefault` goes on
#    any of them.
# 2. **`buildDir` is `nullOr str`.** `null` is the neutral value and the `config` block branches on
#    it, so a plain consumer assignment works. `lib.mkOptionDefault` would not: an option's own
#    `default =` is a priority-1500 definition, so it ties. Use `lib.mkOverride 1400` to neutralise
#    one from outside.
#
# `experimental-features` and `allowAliases` stay literals. The flake cannot evaluate without the
# first, and nixpkgs already defaults the second to `true`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `kdn.enable` is gone, and
#    `kdn.nix.applySettings` is not an `enable`: it selects whether this host writes the `nix.conf`
#    opinion at all, and the old tree turns it off for a microvm guest.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
let
  # One module function, assigned to both classes below.
  target =
    { config, lib, ... }:
    let
      cfg = config.kdn;
    in
    {
      # One declaration of `kdn.hostName`, imported by path. Seven later areas read it. The module
      # system rejects two inline declarations of one option, and it drops a repeated import by
      # path. See ../common/.
      imports = [ ../common/host-name.nix ];

      options.kdn.nixpkgs.allowUnfree = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Accept the unfree licence of a package.

          A licence is a policy decision, and an adopter may want a pure-free tree. The default is
          `true`, the value this repository uses today.
        '';
      };

      options.kdn.nixpkgs.permittedInsecurePackages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "litestream-0.3.13"
          "electron-28.3.3" # logseq dependency
          "electron-27.3.11" # logseq dependency? 2024-07-12
          "olm-3.2.16" # required for Matrix clients
        ];
        example = [ ];
        description = ''
          Packages this tree accepts although nixpkgs marks them insecure.

          The list stays an option default. It never becomes a literal at the assignment site:
          `types.listOf` concatenates every definition, so a literal is a definition an adopter can
          add to but never remove. A default goes away as soon as the adopter writes their own list.
        '';
      };

      options.kdn.nix.substituters = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options.url = lib.mkOption {
              type = lib.types.str;
              example = "https://cache.example.invalid";
              description = "The substituter URL.";
            };
            options.publicKey = lib.mkOption {
              type = lib.types.str;
              example = "cache.example.invalid-1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
              description = "The public key that signs this substituter's paths.";
            };
          }
        );
        default = [
          {
            url = "https://nix-community.cachix.org";
            publicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
          }
          {
            url = "https://nixpkgs-update.cachix.org";
            publicKey = "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8=";
          }
          {
            url = "https://devenv.cachix.org";
            publicKey = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
          }
        ];
        example = [ ];
        description = ''
          The binary caches this tree trusts, in order of preference.

          A binary cache is a trust decision, and an adopter may object to every entry. Each entry
          holds the URL together with its public key: a substituter fails at run time when the URL
          has no matching key, so the two never separate.
        '';
      };

      options.kdn.nix.adminGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "@wheel" # linux
          "@admin" # macos
        ];
        example = [ "@wheel" ];
        description = ''
          The groups this host trusts to run a Nix build with elevated rights. Each entry goes to
          `nix.settings.trusted-users` and to `nix.settings.allowed-users`.
        '';
      };

      options.kdn.nix.allowedGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "@users" # nixos
          "@staff" # macos
        ];
        example = [ "@users" ];
        description = ''
          The groups this host permits to talk to the Nix daemon. Each entry goes to
          `nix.settings.allowed-users`, next to every admin group.
        '';
      };

      options.kdn.nix.buildDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/nix/var/nix/builds";
        example = null;
        description = ''
          The directory each build runs in. `null` writes no `build-dir` key, so Nix keeps its own
          default.

          The option's own `default` is a priority-1500 definition, so `lib.mkOptionDefault` ties
          with it and the evaluation fails with `defined both null and not null`. Use
          `lib.mkOverride 1400` to neutralise this default from outside.
        '';
      };

      options.kdn.nix.extraConfIncludes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "/etc/nix/nix.sensitive.conf"
          "/etc/nix/nix.access-tokens.auto.conf"
        ];
        example = [ ];
        description = ''
          Files that `nix.conf` pulls in with `!include`. Each one holds a secret, so it never
          enters the store.

          An `!include` of a missing file is a no-op in `nix.conf`, so the default is safe on a host
          that holds neither file.
        '';
      };

      options.kdn.nix.showTrace = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = "Print the whole evaluation trace of a failure.";
      };

      options.kdn.nix.applySettings = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Write this aspect's `nix.conf` and nixpkgs opinion on this host.

          The old tree gates the same block on the `microvm-guest` feature flag: a microvm guest
          inherits the host's `/etc/nix`, so a second opinion there is noise. This is a plain
          option, not a feature flag, so any consumer turns it off with one line.
        '';
      };

      config = lib.mkIf cfg.nix.applySettings {
        # The two `!include` lines. Each file holds a secret, so it never enters the store.
        nix.extraOptions = lib.concatMapStrings (path: "!include ${path}\n") cfg.nix.extraConfIncludes;

        nix.settings = {
          show-trace = cfg.nix.showTrace;

          # A literal on purpose. This flake cannot evaluate without either feature.
          experimental-features = [
            "nix-command"
            "flakes"
          ];

          # `kdn.nix.substituters` keeps each URL next to its public key, so the two lists below
          # stay aligned. A substituter with no matching key fails at run time.
          trusted-public-keys = map (entry: entry.publicKey) cfg.nix.substituters;
          substituters = map (entry: entry.url) cfg.nix.substituters;

          allowed-users = cfg.nix.adminGroups ++ cfg.nix.allowedGroups;
          trusted-users = cfg.nix.adminGroups;
        }
        // lib.optionalAttrs (cfg.nix.buildDir != null) { build-dir = cfg.nix.buildDir; };

        # A literal on purpose. nixpkgs already defaults it to `true`.
        nixpkgs.config.allowAliases = true;
        nixpkgs.config.allowUnfree = cfg.nixpkgs.allowUnfree;
        nixpkgs.config.permittedInsecurePackages = cfg.nixpkgs.permittedInsecurePackages;
      };
    };
in
{
  kdn.nix-config.nixos = target;
  kdn.nix-config.darwin = target;
}
