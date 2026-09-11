# The secrets policy switch and the two secrets systemd targets, as a den aspect. It ports
# `modules/universal/security/secrets/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It answers one question for the whole machine: **may this host hold a secret?** 12 sites of the
# old tree read the answer, over 6 areas — `managed`, `hw/yubikey`, `networking/netbird`,
# `programs/atuin`, `profile` and `services`. Each one turns a feature off when the answer is no.
# That makes it the widest single policy leaf of the machine layer, so it ports early.
#
# On a NixOS host it also declares the two systemd targets that order every secret consumer:
# `kdn-secrets.target` fires once the secrets exist, and `kdn-secrets-reload.target` fires on every
# later reload.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch, so `allowed` no longer multiplies two flags. It now
#    tracks `allow` alone. Both names stay, because 12 call sites read `allowed`.
# 2. **The `sops` read gets an `or` fallback.** The old assertion reads `config.sops.secrets`, and
#    `kdnConfig.util.hasSops` guarded it because a class without `sops-nix` has no such option. This
#    target imports no flake input, so it reads `config.sops.secrets or { }` instead. A missing
#    option then yields the empty set, and the assertion holds with the same meaning.
#
# ## What the port does not cover yet
#
# `kdn.security.secrets.sops.*` and `kdn.security.secrets.age.*` stay in the old tree for now. Both
# parse a file at evaluation time, so both need a design of their own. This aspect declares the
# policy leaf and nothing else, so a later aspect adds those trees next to it.
#
# ## One declaration, three classes
#
# The two options live in one module below, and each target imports it. Only one class loads per
# evaluation, so the module system sees exactly one declaration each time. The darwin target and the
# Home Manager target carry the declaration alone, because both systemd targets are NixOS-only —
# exactly the split the old `ifTypes [ "nixos" ]` guard made.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config` and `lib` only.
{ ... }:
let
  # The two options. Every target imports this one module.
  declaration =
    { config, lib, ... }:
    let
      cfg = config.kdn.security.secrets;
    in
    {
      options.kdn.security.secrets.allow = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Permit a secret on this host.

          Set it to `false` on a machine that must hold no secret at all — a public build machine, a
          test virtual machine, or an installer image. Every consumer then turns its own
          secret-dependent half off, and a NixOS host asserts that no `sops` secret and no `sops`
          template remains.
        '';
      };

      options.kdn.security.secrets.allowed = lib.mkOption {
        readOnly = true;
        type = lib.types.bool;
        default = cfg.allow;
        defaultText = lib.literalExpression "config.kdn.security.secrets.allow";
        description = ''
          The answer every consumer reads. It is read-only.

          The old tree multiplies `allow` by an `enable` flag. An aspect has no `enable` — inclusion
          is the switch — so the value now tracks `allow` alone. The name stays, because 12 call
          sites read it.
        '';
      };
    };

  nixosTarget =
    { config, ... }:
    let
      cfg = config.kdn.security.secrets;
    in
    {
      imports = [ declaration ];

      assertions = [
        {
          # `or { }` replaces the old class guard. A class without `sops-nix` declares no `sops`
          # option, so the read yields the empty set and the assertion holds.
          assertion =
            cfg.allow || ((config.sops.secrets or { }) == { } && (config.sops.templates or { }) == { });
          message = "`sops.secrets` and `sops.templates` must be empty when `kdn.security.secrets.allow` is `false`";
        }
      ];

      systemd.targets.kdn-secrets = {
        description = "kdn's secrets loaded for the first time";
        upholds = [ "kdn-secrets-reload.target" ];
      };

      systemd.targets.kdn-secrets-reload = {
        description = "kdn's secrets reload target";
        after = [ "kdn-secrets.target" ];
        requires = [ "kdn-secrets.target" ];
        wantedBy = [ "kdn-secrets.target" ];
        partOf = [ "kdn-secrets.target" ];
      };
    };
in
{
  kdn.secrets.nixos = nixosTarget;
  kdn.secrets.darwin = declaration;
  kdn.secrets.homeManager = declaration;
}
