# `kdn.programs.torrent`, as a den aspect. It ports `modules/universal/programs/torrent/default.nix`.
{ kdn, ... }:
{
  kdn.program-torrent.includes = [ kdn.apps ];

  kdn.program-torrent.homeManager = {
    kdn.apps.deluge = {
      enable = true;
      dirs.config = [ "deluge" ];
    };
  };
}
