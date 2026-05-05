{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: # many configs pulled from https://git.grml.org/?p=grml-etc-core.git;a=blob_plain;f=etc/zsh/zshrc;hb=HEAD
let
  cfg = config.kdn.programs.zsh;
in
{
  options.kdn.programs.zsh = {
    enable = lib.mkEnableOption "ZSH shell config";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          zsh-completions
        ];
      }
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.programs.zsh = cfg; } ];
      })
      (kdnConfig.util.ifHM {
        # https://nix-community.github.io/home-manager/options.html#opt-programs.zsh.enable
        programs.zsh.enable = true;
        programs.zsh = {
          enableCompletion = true;
          dotDir = "${config.xdg.configHome}/zsh";
          syntaxHighlighting.enable = true;
          autosuggestion.enable = true;
          enableVteIntegration = true;
          history.size = 100000;
          initContent = lib.trivial.pipe ./. [
            builtins.readDir
            (lib.filterAttrs (path: type: type != "directory" && (lib.hasPrefix ".zshrc" path)))
            (lib.attrsets.mapAttrsToList (
              path: t: ''
                # START ${path}
                ${builtins.readFile (./. + "/${path}")}
                # END ${path}
              ''
            ))
            (builtins.concatStringsSep "\n\n")
          ];
          # see `man zshoptions`
          setOptions = [
            "HIST_EXPIRE_DUPS_FIRST"
            "HIST_FIND_NO_DUPS"
            "HIST_FCNTL_LOCK"
            "HIST_IGNORE_DUPS"
            # import new commands from the history file also in other zsh-session
            "SHARE_HISTORY"
            # save each command's beginning timestamp and the duration to the history file
            "EXTENDED_HISTORY"
            # append history list to the history file; this is the default but we make sure
            # because it's required for share_history.
            "APPEND_HISTORY"
            # remove command lines from the history list when the first character on the
            # line is a space
            "HIST_IGNORE_SPACE"
            # if a command is issued that can't be executed as a normal command, and the
            # command is the name of a directory, perform the cd command to that directory.
            "AUTO_CD"
            # in order to use #, ~ and ^ for filename generation grep word
            # *~(*.gz|*.bz|*.bz2|*.zip|*.Z) -> searches for word not in compressed files
            # don't forget to quote '^', '~' and '#'!
            "EXTENDED_GLOB"
            # display PID when suspending processes as well
            "LONG_LIST_JOBS"
            # report the status of backgrounds jobs immediately
            "NOTIFY"
            # whenever a command completion is attempted, make sure the entire command path
            # is hashed first.
            "HASH_LIST_ALL"
            # not just at the end
            "COMPLETE_IN_WORD"
            # make cd push the old directory onto the directory stack.
            "AUTO_PUSHD"
            # don't push the same dir twice.
            "PUSHD_IGNORE_DUPS"
            # avoid "beep"ing
            "NO_BEEP"
            # * shouldn't match dotfiles. ever.
            "NO_GLOB_DOTS"
            # use zsh style word splitting
            "NO_SH_WORD_SPLIT"
          ];
        };
      })
      (kdnConfig.util.ifTypes [ "nixos" "darwin" ] {
        programs.zsh.enable = true;
        programs.zsh = {
          enableCompletion = false; # interferes with home-manager
        };
      })
      (kdnConfig.util.ifTypes [ "darwin" ] {
        programs.zsh = {
          enableSyntaxHighlighting = false;
          enableAutosuggestions = false;
        };
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        # https://search.nixos.org/options?channel=unstable&from=0&size=50&sort=alpha_asc&type=packages&query=programs.zsh
        programs.zsh.autosuggestions.enable = false;
        programs.zsh.syntaxHighlighting.enable = false;
        programs.zsh.vteIntegration = false;
      })
    ]
  );
}
