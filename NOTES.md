# Module consolidation — current state

## What's working
- All modules consolidated into `modules/universal/`
- `modules/{nixos,darwin,home-manager,shared}` deleted
- `flake.nix` retargeted
- 108 files had `ifTypes ["nixos"]` unwrapped from options (options now at top level)
- All files parse (`nix-instantiate --parse`)
- `hm.nix` files eliminated

## Known issues preventing build

### Lost manual merges (scripts overwrote them)
The following files had large manually-merged nixos blocks that were lost
when automated scripts re-ran from /tmp originals:

1. **`modules/universal/profile/machine/baseline/default.nix`** — CRITICAL
   - Lost the entire nixos baseline block (~300 lines) from original `nixos/profile/machine/baseline/default.nix`
   - Content: systemd-boot, boot params, networking, openssh, userborn, user management, etc.
   - Restore from: `jj file show -r main modules/nixos/profile/machine/baseline/default.nix`

2. **`modules/universal/profile/user/kdn/default.nix`** — FIXED (nixos block restored this session)

### Option declaration conflicts (different files)  
- `desktop/sway/default.nix` vs `desktop/sway/home-manager/default.nix` — `kdn.desktop.sway.keys` and other sub-options may conflict. Fixed `enable` and `wayland.systemd.target` already.

### Files still wrapped with full `ifTypes ["nixos"]` (options suppressed in HM)
- `networking/router/default.nix` — too complex for automated transform
- `networking/openvpn/default.nix` — uses multiline strings in config
- `hw/gpu/supergfxctl.nix` — helper, not auto-loaded
- `hw/yubikey/yubikeys.nix` — data module, imported explicitly
- `profile/machine/basic/default.nix` — skipped by script

## Rebuild command
```
~/dev/github.com/nazarewk-iac/nix-configs/nixos-rebuild.sh build remote=oams
```
