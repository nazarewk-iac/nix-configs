/*
  Personal network data for `kdn.services.samba`.

  This file is a module, not a data attribute set. It assigns an option that
  `modules/universal/services/samba/default.nix` declares, so that module names no home LAN.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file and `hostsAllow` falls back to loopback only.

  The whole list belongs here, not only the LAN entry. A `listOf` option discards its `default`
  as soon as one definition exists, so a partial list would drop the loopback entries.

  This file needs no context guard. The module forwards `cfg` into Home Manager with
  `lib.mkDefault` at `services/samba/default.nix:44`, which is priority 1000. This assignment
  sits at priority 100 and wins with the same value.
*/
{ ... }:
{
  config.kdn.services.samba.defaults.hostsAllow = [
    "192.168.0.0/16"
    "127.0.0.0/8"
    "localhost"
    "::1"
  ];
}
