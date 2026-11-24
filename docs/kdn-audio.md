---
type: Reference
description: "The kdn-audio CLI and TUI: joining PipeWire outputs, device ids, stored profiles and the automatic daemon."
timestamp: 2026-11-24T19:10:00+01:00
---

# kdn-audio

`kdn-audio` joins several audio outputs into one virtual output, so the same audio plays on all of
them. It lists the joined outputs, removes them again, and applies a stored profile whenever a
given mix of devices is connected. It has a TUI wizard and a set of CLI commands.

The package lives in [packages/kdn-audio](../packages/kdn-audio/), the Nix module in
[modules/universal/programs/kdn-audio](../modules/universal/programs/kdn-audio/default.nix).

## Nothing goes through PulseAudio

The tool drives the PipeWire graph with PipeWire's own tools:

| Need | Tool |
| --- | --- |
| list outputs and streams | `pw-dump` |
| read and write the default output | `pw-metadata` on the `default` metadata |
| create a joined output | `libpipewire-module-combine-stream`, hosted by a transient systemd user unit |
| move a playing stream | `pw-link` (destroy the old links, link the new ports) |
| connect Bluetooth devices | `bluetoothctl` |

A joined output is therefore a native node. It appears in `qpwgraph` and `helvum`, and it keeps
working when the PulseAudio compatibility server is not running.

### Why the join needs a host process

`pw-cli load-module` loads a module into the pw-cli client context, not into the daemon. The sink
belongs to that process, so the process must stay alive. `kdn-audio create` starts
`systemd-run --user --unit=kdn-audio-<name>` with `kdn-audio host`, and the host runs a long-lived
`pw-cli` with one load command. `kdn-audio remove` stops the unit, and the module, the sink and its
streams go with it. There is no state file: the unit name follows from the sink name.

### Measured details that the code depends on

- `stream.rules` needs `actions = { create-stream = { } }`. The array form
  `actions = [ { create-stream = { } } ]` parses, matches nothing, and leaves a sink with no
  streams. Measured on PipeWire 1.6.11.
- `pw-dump` reports `object.register=false` for **every** client stream, a player included, so it
  cannot mark the module loopbacks. The loopbacks carry `node.virtual=true` and a `combine-*` node
  group instead.
- Metadata reads print `value:'{...}' type:'Spa:String:JSON'`, so the value is parsed with a
  regular expression first.
- A sink that disappears takes the default with it. WirePlumber re-picks a default a moment later,
  so `kdn-audio` writes its choice and then confirms it for up to half a second.

## Device ids

Every command accepts a device id, a device name, a node name, a Bluetooth address, or any
unambiguous part of one. Profiles store the id, which survives a restart because PipeWire hands out
a new node id on every start:

| Kind | Id | Example |
| --- | --- | --- |
| Bluetooth | `bt:<address>` | `bt:60:AB:D2:77:07:56` |
| ALSA | `alsa:<card>/<profile>` | `alsa:pci-0000_07_00.6/analog-stereo` |
| joined output | `join:<node name>` | `join:combined_both_ears` |
| anything else | `node:<node name>` | `node:zz_desk1` |

```sh
kdn-audio devices                 # id, name, type, state
kdn-audio devices --ids           # one id per line, for scripts
kdn-audio show bt:60:AB:D2:77:07:56
kdn-audio create --name "Both Ears" bt:60:AB:D2:77:07:56 bt:38:D5:18:B6:64:93
```

## Commands

```
kdn-audio                           TUI wizard when stdout is a terminal, help otherwise
kdn-audio tui                       TUI wizard
kdn-audio intro                     The plain-language guide (also shown from `--help`)
kdn-audio devices [--ids] [--json]
kdn-audio show OUTPUT
kdn-audio create --name N [--default] [--move-streams] [--connect] OUTPUT...
kdn-audio remove NAME... | --all
kdn-audio unlink-all
kdn-audio status [--json]
kdn-audio connect [DEVICE...]
kdn-audio profiles list|show|save|apply|remove|active|check|dir
kdn-audio daemon [--interval 2s] [--once]
kdn-audio version
```

### A join does not touch the routing

Joining changes nothing that plays and nothing that is the default. The audio that plays now stays
where it plays, and new audio keeps going to the previous default. Two flags opt in:

- `--default` makes the joined output the default output.
- `--move-streams` moves the streams that play now.

The TUI shows both choices on one line, off by default, with the keys `s` and `m`. The full TUI
key list is: `space` select, `a` all or none, `enter` name and join, `tab` switch pane, `d` unlink
the highlighted join, `D` unlink all, `s` set the default, `m` move the playing streams, `c`
connect Bluetooth devices, `r` reload, `q` quit, `esc` clear the selection.

One exception is deliberate: when `create` replaces a join with the same name, and the old join was
the default, the new join keeps that place. Losing the default on a rename would silently reroute
everything away from the join.

## Profiles

A profile is one YAML file in `~/.config/kdn-audio/profiles/` (override with `KDN_AUDIO_PROFILES`).
It names the joined output, the device mix that turns it on, and the routing flags:

```yaml
# ~/.config/kdn-audio/profiles/both-ears.yaml
name: Both Ears
description: Earmuffs and JBL Endurance Peak 4 together
priority: 10
outputs:
  - bt:60:AB:D2:77:07:56
  - bt:38:D5:18:B6:64:93
absent: []
default: false
move-streams: false
```

A profile matches when every id in `outputs` resolves to a connected output and no id in `absent`
does. The highest `priority` wins; the name breaks a tie. `kdn-audio profiles list` shows which
profile matches now.

`kdn-audio profiles save NAME --output DEVICE...` writes a profile and stores each output as the
id it resolves to now, so a name never has to be typed twice. `kdn-audio profiles remove NAME`
deletes one, and `--all` deletes every profile.

`kdn-audio daemon` applies the matching profile and removes the profile joins that no longer apply.
Profile joins carry `kdn.audio.profile=<name>`, so the daemon never touches a join made by hand.
`kdn-audio daemon --once` runs one pass. Run it as a systemd user service; the Nix module does
that. Stop the service (`systemctl --user stop kdn-audio-profiles`) to take manual control: a
running daemon puts the best matching profile back on its next pass.

Because a join matches its members by node name, a device that disconnects and reconnects rejoins
the output on its own. The daemon only acts when the device mix changes the matching profile.

### Generating profiles from Nix

```nix
kdn.programs.kdn-audio = {
  enable = true;
  profiles.both-ears = {
    description = "Earmuffs and JBL Endurance Peak 4 together";
    priority = 10;
    outputs = [
      "bt:60:AB:D2:77:07:56"
      "bt:38:D5:18:B6:64:93"
    ];
    default = false;
    moveStreams = false;
  };
};
```

The module writes `~/.config/kdn-audio/profiles/both-ears.yaml` and enables the
`kdn-audio-profiles` user service. A profile written by hand beside the Nix ones is not removed.

## Limits

- A profile cannot name a joined output as a member, and `create` refuses one. PipeWire allows the
  nesting, but a cycle would be a feedback loop.
- The daemon polls. Two seconds is the default and the cost is one `pw-dump` call per pass.
- `--move-streams` links whole channels: a stream output port is matched to the sink input port
  with the same channel suffix. A stream with an unusual channel map keeps the channels it has.
- The default output is written to the runtime metadata, not to a saved WirePlumber setting.

## JSON

`devices`, `status`, `create`, `remove`, `unlink-all`, `connect`, `profiles list`, `profiles show`,
`profiles apply`, `profiles active` and `daemon` accept `--json`. The envelope is
`{schema_version, command, generated_at, data}`.
