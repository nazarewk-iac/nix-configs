# `kdn.programs.logseq`, as a den aspect. It ports `modules/universal/programs/logseq/default.nix`.
{ kdn, ... }:
{
  kdn.program-logseq.includes = [ kdn.apps ];

  kdn.program-logseq.homeManager = {
    kdn.apps.logseq = {
      enable = true;
      dirs.config = [
        # `~/.config/Logseq` holds everything: the Electron data, the cache, the logs and some
        # preference files.
        "Logseq"
        # `~/.logseq` holds a second piece of persistent state. Logseq forgets an open graph when
        # this path is absent. The leading `/` makes the path relative to the home directory.
        "/.logseq"
      ];
    };
  };
}
