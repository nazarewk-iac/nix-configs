# oams-specific devenv profile.
#
# A profile scoped to the oams host, imported by the primary `devenv.nix` via
# `profiles.hostname."oams".module`. It is a plain devenv module: it imports the den
# aspects it needs and sets their options. The parent shell already imports `opencode`,
# so den collapses the diamond and one wrapper reaches this shell.
#
# It enables opencode (via the parent shell) and feeds the required info to
# `kdn.llm.client`, which writes the opencode provider. The `opencode` wrapper injects the
# brys API key. The self-signed cert is trusted system-wide on oams via the `kdn.ca.kdn`
# slot (security.pki). This file is intentionally minimal.
#
# Only the host whose hostname is `oams` auto-activates this profile.
{
  inputs,
  lib,
  ...
}:
let
  # One opencode subagent per served model id (`lfm2.5-24b-a2b`,
  # `mellum-2.1-12b-a2.5b-thinking`, ...), derived from `data/llm.nix` so the client
  # follows the server when the catalogue changes. A caller names the model it wants;
  # the purpose-alias scheme was dropped on 2026-11-23. See
  # ../../lib/llm-agents.nix and the `kdn-llms` skill for the current model table.
  aliasAgents = import ../../lib/llm-agents.nix { inherit lib; };
in
{
  imports = inputs.nix-configs.denLib.imports {
    class = "devenv";
    # `ssh-ca` pulls in `ca-manager`, so this shell holds the `kdn-certs` CLI and the CA DAG.
    # That is the client half of the SSH CA: `kdn-certs ssh login <host>` writes the user
    # certificate this host presents.
    aspects = [
      "llm-client"
      "ssh-ca"
    ];
  };

  # The generic opencode aspect turns opencode on, supplies the default permission
  # skeleton, and provides the `opencode` wrapper. `kdn.llm.client` adds the per-upstream
  # provider, and wires the API key itself from `apiKeyFile`.
  #
  # These two settings keep the behaviour the old slot defaults gave on this host: the
  # Requesty cloud provider (auth from auth.json, hardcodes no model) and its credential,
  # plus the local fleet reached through `kdn.llm.client.upstreams.litellm` below.
  kdn.opencode.settings.provider.requesty = { };
  # One subagent per served model id (`lfm2.5-24b-a2b`, `mellum-2.1-12b-a2.5b-thinking`, ...):
  # the caller names the model it wants; the purpose-alias layer was dropped on 2026-11-23. The old `qwen-<level>` family (one agent
  # per thinking level on the local frontier Qwen) retired with the model on
  # 2026-11-13: depth is now a server-side alias, not a client-side level
  # matrix.
  kdn.opencode.settings.agent = aliasAgents;
  kdn.opencode.allowedPaths = [
    "/nix/store/**"
    "~/dev/**"
  ];
  kdn.opencode.authKeys.REQUESTY_API_KEY = "requesty";

  # The LiteLLM gateway on etra: one entrypoint in front of the whole fleet, with
  # load-balancing and failover across brys and oams. Same discovery model as `brys`;
  # the key is the gateway master key (a sops secret the client reads at runtime).
  kdn.llm.client.upstreams.litellm = {
    enable = true;
    # The gateway is exposed on its own subdomain over HTTPS by etra's Caddy.
    baseURL = "https://litellm.etra.priv.nb.net.int.kdn.im/v1";
    # Non-admin client key (all models), not the master key.
    apiKeyFile = "/run/configs/llms/litellm/client-key";
    # Static, not discovered. Measured 2026-11-20: a discovery-only provider is listed by
    # `opencode models` but `opencode run --model litellm/<id>` answers "Model unavailable" —
    # opencode validates the id against the static catalog before the discovery plugin's
    # `models.set` runs. The four names are the fleet's whole local surface at the gateway, so
    # declaring them is both smaller and deterministic.
    discovery.enable = false;
    models = {
      qfn = {
        name = "qfn";
        context = 1048576;
        output = 32768;
      };
      qfn-max = {
        name = "qfn-max";
        context = 1048576;
        output = 32768;
      };
      qfn-colo = {
        name = "qfn-colo";
        context = 1048576;
        output = 32768;
      };
      qwen3-omni = {
        name = "qwen3-omni";
        context = 16384;
        output = 8192;
      };
    };
  };

  # On oams itself, keep a direct loopback path to the local llama-swap so this
  # host still works offline (no gateway, no network). The remote `brys` direct
  # endpoint is dropped: off-host traffic goes through the gateway.
  kdn.llm.client.upstreams.oams = {
    enable = true;
    baseURL = "http://127.0.0.1:9530/v1";
    apiKeyFile = "/run/configs/llms/llama-server/api-keys/default";
    discovery.enable = true;
  };
}
