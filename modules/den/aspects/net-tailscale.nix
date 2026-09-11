# The Tailscale client of the old `networking` area, as a den aspect. It ports
# `modules/universal/networking/tailscale/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs the Tailscale client, it opens the firewall for it, and it keeps `/var/lib/tailscale`
# between boots. A consumer that names an auth key file joins the tailnet with no interactive login.
#
# ## Class list: `nixos`
#
# The old module puts every effect behind a `nixos` guard.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The sops read becomes a plain path option — the de-personalized part.** The old module reads
#    one hardcoded secrets path, `default/tailscale/default/auth_keys/<name>`, and it names the key
#    with `kdn.networking.tailscale.auth_key`. That layout belongs to one person's secrets tree, and
#    an adopter has no such tree. This aspect declares `kdn.networking.tailscale.authKeyFile`
#    instead, and the consumer names the path. The assertion that checked the key name against the
#    discovered set goes with the read, because there is no set to check against.
# 3. **The persistence write goes through the shared declaration.** ../common/persist.nix declares
#    `kdn.disks.persist`, and this target imports it by path, exactly as ../aspects/fs.nix does.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module takes `config` and `lib` only.
{ ... }:
{
  kdn.net-tailscale.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.networking.tailscale;
    in
    {
      imports = [ ../common/persist.nix ];

      options.kdn.networking.tailscale.authKeyFile = lib.mkOption {
        type = with lib.types; nullOr path;
        default = null;
        example = "/run/secrets/tailscale-auth-key";
        description = ''
          The file that holds a Tailscale auth key. The client reads it once and joins the tailnet
          with no interactive login.

          `null` means the client joins with no auth key file. This aspect names no secrets layout,
          so a consumer that keeps the key in a secrets manager passes that manager's own path.
        '';
      };

      config = lib.mkMerge [
        {
          services.tailscale.enable = true;
          services.tailscale.openFirewall = true;
          kdn.disks.persist."usr/data".directories = [
            "/var/lib/tailscale"
          ];
        }
        (lib.mkIf (cfg.authKeyFile != null) {
          services.tailscale.authKeyFile = lib.mkDefault cfg.authKeyFile;
        })
      ];
    };
}
