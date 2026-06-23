# mkBasicMemoryWrapper — builds a named wrapper binary with baked-in dirs and shell completions.
#
# `name` is the instance identifier (e.g. "public", "sensitive").
# Binary name is derived as "basic-memory-<name>"; aliases add shortcuts (e.g. "bmp").
# All paths are derived from `name` by default under the shared knowledge root.
#
# Env var layering (last wins):
#   defaults (path vars)
#   // safeEnv  (values are shell-escaped at build time — safe for any string)
#   // rawEnv   (values written verbatim — use for shell expressions like $HOME/... or "")
{
  lib,
  pkgs,
  basic-memory,
  name,
  aliases ? [ ],
  home ? "$HOME/.local/share/kdn-nix-configs/knowledge/${name}",
  configDir ? "$HOME/.local/share/kdn-nix-configs/knowledge/.config/basic-memory-${name}",
  fastembed-cache ? "${configDir}/fastembed",
  # Default env vars (raw) — overridable baseline, applied before safeEnv and rawEnv
  defaultEnv ? {
    BASIC_MEMORY_HOME = "${home}/default";
    BASIC_MEMORY_PROJECT_ROOT = "${home}";
    BASIC_MEMORY_CONFIG_DIR = "${configDir}";
    FASTEMBED_CACHE_PATH = "${fastembed-cache}";
    BASIC_MEMORY_DATABASE_BACKEND = "sqlite";
    BASIC_MEMORY_DATABASE_URL = "";
    BASIC_MEMORY_LOGFIRE_ENABLED = "false";
    BASIC_MEMORY_LOGFIRE_SEND_TO_LOGFIRE = "false";
    BASIC_MEMORY_CLOUD_PROMO_OPT_OUT = "true";
    BASIC_MEMORY_AUTO_UPDATE = "false";
  },
  # Shell-safe env vars: values are escaped — suitable for literal strings / booleans
  safeEnv ? { },
  # Raw env vars: values written verbatim — use for shell expressions or intentional empty
  rawEnv ? { },
}:
let
  binName = "basic-memory-${name}";
  allNames = [ binName ] ++ aliases;

  mkCompletion =
    n: shell:
    pkgs.runCommand "${n}-completion-${shell}" { } ''
      ${basic-memory}/bin/python3 -c "
      from typer.main import get_command
      import basic_memory.cli.main as m
      import click.shell_completion as sc
      cmd = get_command(m.app)
      cls = sc.get_completion_class('${shell}')
      comp = cls(
        cli=cmd, ctx_args={},
        prog_name='${n}',
        complete_var='_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] n)}_COMPLETE'
      )
      print(comp.source())
      " > $out
    '';

  completionDrv = pkgs.runCommand "${binName}-completions" { } (
    lib.concatMapStrings (
      n:
      let
        bash = mkCompletion n "bash";
        zsh = mkCompletion n "zsh";
        fish = mkCompletion n "fish";
      in
      ''
        install -Dm644 ${bash} $out/share/bash-completion/completions/${n}
        install -Dm644 ${zsh}  $out/share/zsh/site-functions/_${n}
        install -Dm644 ${fish} $out/share/fish/vendor_completions.d/${n}.fish
      ''
    ) allNames
  );

  # defaultEnv // safeEnv // rawEnv, rendered as export statements
  envLines = lib.pipe
    (defaultEnv // (lib.mapAttrs (_: lib.escapeShellArg) safeEnv) // rawEnv)
    [
      (lib.mapAttrsToList (k: v: "export ${k}=${v}"))
      (lib.concatStringsSep "\n")
    ];
in
pkgs.symlinkJoin {
  name = binName;
  paths = [ completionDrv ];
  postBuild = lib.concatMapStrings (n: ''
    mkdir -p $out/bin
    cat > $out/bin/${n} << 'WRAPPER'
    #!/bin/sh
    ${envLines}
    exec ${basic-memory}/bin/basic-memory "$@"
    WRAPPER
    chmod +x $out/bin/${n}
  '') allNames;
  meta.mainProgram = binName;
}
