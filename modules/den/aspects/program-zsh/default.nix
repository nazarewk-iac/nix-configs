# `kdn.programs.zsh`, as a den aspect. It ports `modules/universal/programs/zsh/default.nix`.
#
# Many settings come from
# https://git.grml.org/?p=grml-etc-core.git;a=blob_plain;f=etc/zsh/zshrc;hb=HEAD
#
# ## Why this aspect is a directory
#
# The old module reads its own directory with `builtins.readDir ./.` and it takes every file that
# starts with `.zshrc`. An aspect must hold its own data, so the three files live next to this one.
# They lost the leading dot, because the repository ignores a dot file by default. `initFiles` names
# them, so an adopter replaces the set with one plain assignment.
{ ... }:
let
  defaultInitFiles = [
    ./zshrc
    ./zshrc.grml.colors-less
    ./zshrc.grml.keybindings
  ];

  declaration =
    { lib, ... }:
    {
      options.kdn.programs.zsh.initFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = defaultInitFiles;
        description = ''
          Files the aspect concatenates into `programs.zsh.initContent`. Each file gets a START and an
          END marker comment, so a reader finds the source of a line.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it — a plain
          definition then replaces the default instead of adding to it.
        '';
      };
    };

  filterPackages = import ../../common/filter-packages.nix;

  hostTarget =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];

      config.environment.systemPackages = (filterPackages { inherit lib; }) [ pkgs.zsh-completions ];
      config.programs.zsh.enable = true;
      # `enableCompletion` interferes with the Home Manager side.
      config.programs.zsh.enableCompletion = false;
    };
in
{
  kdn.program-zsh.nixos =
    { ... }:
    {
      imports = [ hostTarget ];

      # See https://search.nixos.org/options?query=programs.zsh
      config.programs.zsh.autosuggestions.enable = false;
      config.programs.zsh.syntaxHighlighting.enable = false;
      config.programs.zsh.vteIntegration = false;
    };

  kdn.program-zsh.darwin =
    { ... }:
    {
      imports = [ hostTarget ];

      config.programs.zsh.enableSyntaxHighlighting = false;
      config.programs.zsh.enableAutosuggestions = false;
    };

  kdn.program-zsh.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      config = {
        home.packages = (filterPackages { inherit lib; }) [ pkgs.zsh-completions ];

        # See https://nix-community.github.io/home-manager/options.html#opt-programs.zsh.enable
        programs.zsh.enable = true;
        programs.zsh.enableCompletion = true;
        programs.zsh.dotDir = "${config.xdg.configHome}/zsh";
        programs.zsh.syntaxHighlighting.enable = true;
        programs.zsh.autosuggestion.enable = true;
        programs.zsh.enableVteIntegration = true;
        programs.zsh.history.size = 100000;

        programs.zsh.initContent = lib.pipe config.kdn.programs.zsh.initFiles [
          (map (
            path:
            let
              name = builtins.baseNameOf (toString path);
            in
            ''
              # START ${name}
              ${builtins.readFile path}
              # END ${name}
            ''
          ))
          (builtins.concatStringsSep "\n\n")
        ];

        # See `man zshoptions`
        programs.zsh.setOptions = [
          "HIST_EXPIRE_DUPS_FIRST"
          "HIST_FIND_NO_DUPS"
          "HIST_FCNTL_LOCK"
          "HIST_IGNORE_DUPS"
          # import new commands from the history file also in another zsh session
          "SHARE_HISTORY"
          # save each command's start timestamp and its duration to the history file
          "EXTENDED_HISTORY"
          # append the history list to the history file; this is the default, but `share_history`
          # needs it, so the option stays explicit
          "APPEND_HISTORY"
          # remove a command line from the history list when the first character is a space
          "HIST_IGNORE_SPACE"
          # when a command is not executable and it names a directory, cd to that directory
          "AUTO_CD"
          # use #, ~ and ^ for filename generation; grep word *~(*.gz|*.bz|*.bz2|*.zip|*.Z) then
          # searches for the word outside a compressed file. Quote '^', '~' and '#'!
          "EXTENDED_GLOB"
          # show the PID when a process suspends
          "LONG_LIST_JOBS"
          # report the status of a background job at once
          "NOTIFY"
          # hash the whole command path first, on every completion attempt
          "HASH_LIST_ALL"
          # complete inside a word, not only at the end
          "COMPLETE_IN_WORD"
          # make cd push the old directory onto the directory stack
          "AUTO_PUSHD"
          # do not push the same directory twice
          "PUSHD_IGNORE_DUPS"
          # no beep
          "NO_BEEP"
          # `*` never matches a dot file
          "NO_GLOB_DOTS"
          # use the zsh word split rules
          "NO_SH_WORD_SPLIT"
        ];
      };
    };
}
