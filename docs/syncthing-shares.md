---
type: How-To
description: The declarative Syncthing shares under ~/.local/share/kdn/synced — the topology, the per-host wiring, persistence, the etra first-start step, and the recipe for adding a share.
timestamp: 2026-11-18T18:18:15+01:00
---

# Syncthing shares

A **share** is one Syncthing folder under `~/.local/share/kdn/synced/<share>` on every host that
holds it. Four shares exist:

| Share           | Contents (candidates)                                       | oams | brys | etra |
| --------------- | ----------------------------------------------------------- | ---- | ---- | ---- |
| `secret-stores` | `pass`, `rosec-storage`, the KeePass DB — the pre-Nextcloud state | yes  | yes  | yes  |
| `small`         | dotfiles, SSH keys, `~/.config/sops/age`                    | yes  | yes  | yes  |
| `medium`        | documents, photos, phone exports                            | yes  | yes  | yes  |
| `large`         | bulk data (the current `~/dev` replacement)                 | yes  | yes  | **no** |

`large` is omitted from etra on purpose: the router keeps the small state, not the bulk. The
pre-existing `~/dev` folder is **not** part of this set and is not touched — the declarative
settings are additive.

## Topology

All device IDs and memberships live in one file, [`data/syncthing.nix`](../data/syncthing.nix):

```nix
{
  devices = {
    oams = "3L5US77-…";
    brys = "LFK67FC-…";
    # etra after its first start;
  };
  shares = {
    secret-stores = [ "oams" "brys" "etra" ];
    small = [ "oams" "brys" "etra" ];
    medium = [ "oams" "brys" "etra" ];
    large = [ "oams" "brys" ];
  };
}
```

Get a device ID with `stc id` on the host. A host listed in `shares` but missing from `devices`
is filtered out of the peers until its ID is filled in.

## Declarative settings

The den aspect (`modules/den/aspects/service-syncthing.nix`) exposes two Home Manager options:

- `kdn.services.syncthing.devices` — peer devices, `name = id`;
- `kdn.services.syncthing.shares` — `share = [ peer names ]`.

It renders them into `services.syncthing.settings` with `overrideDevices = false` and
`overrideFolders = false`, so the existing `~/dev` folder and its pairing stay untouched. Each
share becomes a folder at `${config.xdg.dataHome}/kdn/synced/<share>`, type `sendreceive`, label
`kdn/<share>`.

### Per-host wiring (brys)

`hosts-den/brys/default.nix`, in the Home Manager imports:

```nix
({ lib, ... }:
  let
    st = import ../../data/syncthing.nix;
    self = "brys";
    mine = [ "secret-stores" "small" "medium" "large" ];
  in {
    kdn.services.syncthing.devices = builtins.removeAttrs st.devices [ self ];
    kdn.services.syncthing.shares = builtins.listToAttrs (map (share: {
      name = share;
      value = builtins.filter (h: h != self && builtins.hasAttr h st.devices) st.shares.${share};
    }) mine);
  })
```

The universal tree (`oams`, `etra`) needs the same two options added to
`modules/universal/services/syncthing/default.nix`; the NixOS-level values reach Home Manager
through the existing `home-manager.sharedModules` bridge, so the host block is the same shape.

## Persistence

- **brys**: the home is the **disposable** dataset, so a share under `~` is rolled back at boot
  unless it is in a persist bucket. `hosts-den/brys/default.nix` now carries:

  ```nix
  kdn.disks.userDefaults.persist."usr/data".directories = [
    ".local/share/kdn/synced"
    ".local/share/syncthing"
  ];
  kdn.disks.userDefaults.persist."usr/config".directories = [ ".config/syncthing" ];
  ```

  These are **user-level** buckets (`userDefaults.persist`, or `users.<name>.persist` for one
  user), not the system-level `kdn.disks.persist`: the latter names system paths and does not
  merge across definitions. The aspect also publishes the same lists as
  `kdn.services.syncthing.persist.usrData`/`usrConfig` for a consumer that prefers the outputs.
- **oams** (ZFS): the home is on the pool; create the directories (or dedicated datasets if the
  share should have its own quota/snapshot policy). The empty share roots are created by the
  `home.file` `.keep` entries, so Syncthing never starts against a missing path.
- **etra**: a directory on the system disk; the same `.keep` entries create them.

## Rollout order

1. **oams and brys** with the two known device IDs (this is what `data/syncthing.nix` hold now).
2. **etra**: enable the aspect, deploy, then `stc id` on etra and put the ID in
   `data/syncthing.nix`. Deploy all three again. Until then etra holds the folders locally but
   has no peer.
3. Verify with `stc folders`, `stc devices` and `stc folder_errors` on each host.

## First start and device-ID preservation

Two things bite on the first rollout:

1. **The `.stfolder` marker.** Syncthing refuses a pre-created empty folder with
   `folder marker missing (this indicates potential data loss)`. Create the marker once per share:

   ```sh
   for s in secret-stores small medium large; do
     mkdir -p ~/.local/share/kdn/synced/$s/.stfolder
   done
   ```

2. **The persistent config may be stale.** On brys the home is disposable and the persistence
   bind mounts appear after the first activation. If the persistent `usr/config` already holds an
   older `~/.config/syncthing` (a different device ID), copy the live one into the persistent
   source **before** the bind mounts, otherwise the next restart changes brys' device ID and the
   existing `~/dev` pairing breaks:

   ```sh
   systemctl --user stop syncthing
   sudo umount ~/.config/syncthing ~/.local/share/syncthing
   sudo rm -rf /nix/persist/usr/config/home/kdn/.config/syncthing
   sudo cp -a ~/.config/syncthing /nix/persist/usr/config/home/kdn/.config/
   sudo chown -R kdn:users /nix/persist/usr/config/home/kdn/.config/syncthing
   sudo systemctl start home-kdn-.config-syncthing.mount
   systemctl --user start syncthing
   ```

   Verify with `stc id` that the ID is the one in `data/syncthing.nix`.

## Adding a share

1. Add the name and its member hosts to `data/syncthing.nix` `shares`.
2. Add the name to the `mine` list in each member host's Home Manager block.
3. Deploy the member hosts. The folder and its path appear on the next Syncthing start; the
   `.keep` file creates the directory during activation.

## Notes

- `stc` is read-only for folders and devices (`folders`, `devices`, `folder_errors`, `id`,
  `json_dump`); the configuration itself is declarative, not scripted through `stc`.
- Syncthing's staggered versioning is not set yet; add `versioning` to the folder mapping if a
  share needs history. The per-share conflict report (`rosec-conflicts`) already covers the
  secret store.
