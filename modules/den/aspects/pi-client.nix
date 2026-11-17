# The `pi-client` aspect: Pi's `~/.pi/agent` configuration, derived from `data/llm.nix`.
#
# ## Why home-manager owns the files
#
# The devshell wrapper used to install `models.json` by COPYING it once, so the file on disk drifted
# after every fleet change. Home-manager's `programs.pi-coding-agent` writes `models.json` and
# `settings.json` as store symlinks, and this aspect's `home.file` does the same for the sub-agent
# definitions under `~/.pi/agent/agents/`: the file IS the derivation, so it cannot go stale. Nothing
# under `~/.pi` is ever copied there by hand.
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
    let
      # Sub-agent definitions are installed by home-manager, never copied out of the repo by hand.
      # pi's discoverAgents reads `$PI_CODING_AGENT_DIR/agents/*.md` (~/.pi/agent/agents/); each
      # *.md under data/pi/agents/ becomes one store symlink beside models.json/settings.json, so
      # a file cannot drift (a manual `cp` goes stale on the next repo change — the bug this
      # replaces). Add an agent by adding a file to data/pi/agents/.
      agentsDir = ../../../data/pi/agents;
      agentFiles = lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".md" name)
        (builtins.readDir agentsDir);
    in
    {
      # `kdn.hostName` is a host option; a Home Manager evaluation declares it through the shared
      # common module, and the consumer states the machine name next to its own user config.
      imports = [ ../common/host-name.nix ];

      programs.pi-coding-agent = {
        enable = true;
        package = null;

        # Only the endpoints valid for THIS host: the shared gateway and router
        # everywhere, plus a serving host's own direct path when running on it.
        models.providers =
          (import ../../../lib/llm.nix { inherit lib; }).mkPiModelsJson
            { host = config.kdn.hostName; };

        # pi resolves the default by an EXACT provider+id lookup (findInitialModel), so the pair
        # must name a model the runtime actually holds. `litellm-dynamic` is the provider the
        # model-discovery extension registers for the gateway, whose live entries include the
        # Requesty SaaS ids; the id is the gateway deployment for Requesty's
        # `deepseek-v4.1-flash-1017` (the deepinfra route; the runware sibling is served too), so
        # a bare `pi` starts on it with thinking at the model default. DS4.1 Flash is the primary:
        # the qwen SaaS pair that held the default first could not compact past ~240k context and
        # tripped Alibaba's content filter on command output (observed 2026-11-14), so it no longer
        # fits a long-running main session — both qwen models stay as the auxiliary depth for the
        # planner/reviewer sub-agents instead. The pair resolves only while the gateway serves
        # that deployment: with the extension absent (bare pi, no wrapper), the gateway down at
        # startup, or before the deployment is live, pi degrades to the first available model — a
        # previous mis-pairing did exactly that and silently ran `gemma-4-12b` (measured
        # 2026-11-13).
        settings = {
          defaultProvider = "litellm-dynamic";
          defaultModel = "requesty/deepinfra/deepseek-v4.1-flash-1017";
          # A store symlink is read-only; keep the settings file free of churn it would try to
          # persist (changelog version, telemetry ids).
          enableInstallTelemetry = false;
          enableAnalytics = false;
          collapseChangelog = true;
        };
      };

      # One symlink per agent definition (planner, reviewer, consultant, ...). This is the only
      # channel that touches ~/.pi/agent/agents/ — nothing is ever copied there by hand.
      home.file = lib.mapAttrs' (name: _: lib.nameValuePair ".pi/agent/agents/${name}" {
        source = agentsDir + "/${name}";
      }) agentFiles;
    };
}
