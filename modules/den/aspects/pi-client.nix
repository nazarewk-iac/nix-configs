# The `pi-client` aspect: Pi's `~/.pi/agent` configuration, derived from `data/llm.nix`.
#
# ## Why home-manager owns the files
#
# The devshell wrapper used to install `models.json` by COPYING it once, so the file on disk drifted
# after every fleet change. Home-manager's `programs.pi-coding-agent` writes `models.json` and
# `settings.json` as store symlinks: the file IS the derivation, so it cannot go stale.
#
# `package = null` on purpose. The binary comes from the devshell wrapper (which adds
# `--append-system-prompt` and `--extension`) or from `kdn.apps.pi`; this aspect owns configuration
# only.
#
# ## Endpoints
#
# `models.providers` is `lib/llm.nix`'s `mkPiModelsJson`, so every endpoint in `data/llm.nix`
# appears here with no second list: the local `brys` fleet and the remote `requesty` router.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.pi-client.homeManager =
    { config, lib, ... }:
    {
      programs.pi-coding-agent = {
        enable = true;
        package = null;

        # Only the endpoints valid for THIS host: the shared gateway and router
        # everywhere, plus a serving host's own direct path when running on it.
        models.providers =
          (import ../../../lib/llm.nix { inherit lib; }).mkPiModelsJson
            { host = config.kdn.hostName; };

        # pi has no per-provider default for `brys` or `requesty`, so without this it falls back to
        # the first entry in models.json, which is alphabetical (measured: `gemma-4-12b`).
        settings = {
          defaultProvider = "requesty";
          defaultModel = "deepseek-v4.1-flash-1017";
          # A store symlink is read-only; keep the settings file free of churn it would try to
          # persist (changelog version, telemetry ids).
          enableInstallTelemetry = false;
          enableAnalytics = false;
          collapseChangelog = true;
        };
      };
    };
}
