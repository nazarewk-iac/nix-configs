# The `profile/default-secrets` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It is the machine-wide baseline for the repository's own sops file: it names the default file,
# declares the three `kdn.security.secrets.sops.files` entries that read it, and renders the two
# templates that every machine needs — the `/etc/hosts.d` fragments and the `nix` access tokens
# with their `netrc` fragment. It also installs the anonymiser toolkit.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The old default follows
#    `kdn.security.secrets.sops.hasDefaultFile`; the aspect is unconditional and every file entry
#    is gated on that same flag.
# 2. **The default file path is the consumer's.** The old module names this repository's
#    `default.unattended.sops.yaml`. An aspect holds no flake, so it reads
#    `config.kdn.security.secrets.sops.defaultFile` and the consumer sets it. A consumer that sets
#    nothing gets no file, and the aspect is then a no-op.
# 3. **`kdn.env.packages` and `kdn.env.variables` become the native options.**
#    `environment.systemPackages` and `environment.variables`, through ../common/filter-packages.nix.
# 4. **`kdn.security.secrets.enable` becomes `kdn.security.secrets.allow`.** The den `secrets` aspect
#    has no `enable`: `allowed` tracks `allow` alone. `lib.mkDefault` keeps a consumer's plain value
#    in charge.
# 5. **The sway keybinding is published, not written.** The old module writes a
#    `home-manager.sharedModules` sway binding. den partitions by scope and forbids one aspect
#    writing a sibling's option, so the aspect publishes
#    `kdn.profile-default-secrets.anonymizeClipboard` as a read-only package and the host wires it
#    into its keybinding map. That is the `net-dynamic-hosts` shape.
# 6. **`pkgs.kdn.kdn-anonymize` becomes a relative `callPackage`.** An aspect must work with no
#    overlay of this repository. `../../../packages/kdn-anonymize`.
#
# ## What it reads from another aspect
#
# `config.kdn.managed.infix.default` is read straight from the old module. `infix` defaults to an
# empty set and the old tree never sets `default`, so the read is only forced when the default sops
# file holds `networking.hosts` entries. The port keeps the same expression and the same behaviour.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `hasDefaultFile` is not an `enable`: it is a
#    read-only fact about the consumer's file.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.profile-default-secrets.includes = [
    kdn.secrets
    kdn.security-secrets-sops
  ];

  kdn.profile-default-secrets.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.security.secrets.sops;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      kdn-anonymize = pkgs.callPackage ../../../packages/kdn-anonymize { };

      kdn-net-anonymize = pkgs.writeShellApplication {
        name = "kdn-net-anonymize";
        text = ''
          ${lib.getExe kdn-anonymize} /run/configs/networking/anonymization
        '';
      };

      anonymizeClipboard = pkgs.writeShellApplication {
        name = "kdn-anonymize-clipboard";
        runtimeInputs = with pkgs; [
          kdn-anonymize
          wl-clipboard
          libnotify
        ];
        text = ''
          # see https://github.com/bugaevc/wl-clipboard/issues/245
          notify-send --expire-time=3000 "kdn-anonymize-clipboard" "$( { wl-paste | kdn-anonymize | wl-copy 2>/dev/null ; } 2>&1 )"
        '';
      };
    in
    {
      options.kdn.profile-default-secrets.anonymizeClipboard = lib.mkOption {
        readOnly = true;
        type = lib.types.package;
        description = ''
          The clipboard anonymiser. A consumer wires it into its own keybinding map; this aspect
          cannot write a sibling's option.
        '';
      };

      config = lib.mkMerge [
        # The policy default. A consumer that names no file gets no entry and the aspect is inert.
        {
          kdn.security.secrets.allow = lib.mkDefault cfg.hasDefaultFile;
        }

        (lib.mkIf cfg.hasDefaultFile {
          kdn.security.secrets.sops.files = {
            "default" = {
              sopsFile = cfg.defaultFile;
            };
            "networking" = {
              keyPrefix = "networking";
              sopsFile = cfg.defaultFile;
              basePath = "/run/configs";
              sops.mode = "0444";
            };
            "anonymization" = {
              keyPrefix = "anonymization";
              sopsFile = cfg.defaultFile;
              basePath = "/run/configs";
              sops.mode = "0444";
            };
          };
        })

        # The templates. Two families share one `sops.templates` set:
        #   * one `/etc/hosts.d` fragment per placeholder host name
        #   * the `nix` access-tokens file and the `netrc` fragment that carries the same token
        (lib.mkIf (config.kdn.security.secrets.allowed && cfg.hasDefaultFile) {
          sops.templates = lib.pipe cfg.placeholders.networking.hosts [
            (lib.attrsets.mapAttrsToList (
              name: text:
              let
                path = "/etc/hosts.d/60-${config.kdn.managed.infix.default}-${name}.hosts";
              in
              {
                "${path}" = {
                  inherit path;
                  mode = "0644";
                  content = text;
                };
              }
            ))
            (
              l:
              l
              ++ [
                {
                  # TODO: render those from "$XDG_CONFIG_DIRS/nix/access-tokens.d/*.tokens" for both users and system-wide?
                  "nix.access-tokens.auto.conf" = {
                    path = "/etc/nix/nix.access-tokens.auto.conf";
                    mode = "0444";
                    content = lib.pipe cfg.placeholders.default.nix.access-tokens [
                      (lib.attrsets.mapAttrsToList (name: value: "${name}=${value}"))
                      (builtins.concatStringsSep " ")
                      (value: ''
                        access-tokens = ${value}
                      '')
                    ];
                  };
                  # One netrc fragment. `/etc/nix/netrc` is assembled from `/etc/nix/netrc.d/*.netrc`
                  # by `kdn-gen-netrc` (see kdn.security-dynamic-netrc). This fragment holds the
                  # GitHub token from the same `nix/access-tokens` secret as the file above, so both
                  # stay in step.
                  "nix-netrc-github" = {
                    path = "/etc/nix/netrc.d/kdn-github.netrc";
                    mode = "0444";
                    content = ''
                      machine github.com login x-access-token password ${
                        cfg.placeholders.default.nix.access-tokens."github.com"
                      }
                    '';
                  };
                }
              ]
            )
            lib.mkMerge
          ];
        })

        # The anonymiser toolkit is always available. The clipboard half is desktop-only, so it is
        # published and not installed.
        {
          environment.systemPackages = filterPackages [
            kdn-anonymize
            kdn-net-anonymize
          ];
          environment.variables.KDN_ANONYMIZE_DEFAULTS = "/run/configs";
          kdn.profile-default-secrets.anonymizeClipboard = anonymizeClipboard;
        }
      ];
    };
}
