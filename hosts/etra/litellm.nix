# LiteLLM gateway — a single OpenAI-compatible entrypoint for the local LLM fleet.
#
# Task: docs/tasks/2026-11/litellm-gateway/. Host-LOCAL module (like
# hosts-den/brys/llm.nix) because it is deployed only on etra.
#
# ## State: LIVE (2026-11-05)
#
# The container runs (`autoStart = true`) and reaches brys over the NetBird mesh:
# brys exposes llama-swap on `39704` via a narrow socat relay (hosts-den/brys/llm.nix,
# firewall-opened only on `nb-priv`), and `litellm-brys-egress` forwards to that
# mesh address. Verified end to end with a real completion.
#
# ## Why no database
#
# No Postgres (`DATABASE_URL` unset): no virtual keys, no budgets, no spend logs,
# one shared master key — which is what we want (research.md).
#
# ## Network shape (the repo's container rule: private network + narrow socat)
#
# The guest has a private veth (no host network). It reaches the outside ONLY
# through narrow host socat relays:
#   - ingress 0.0.0.0:4000       -> guest:4000   (clients -> gateway; the router
#                                                 firewall admits it only from nb-priv)
#   - egress  10.233.100.1:8443  -> brys netbird:39704 (gateway -> brys)
# The guest's api_base is http://10.233.100.1:8443/v1.
{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  hostAddress = "10.233.100.1";
  localAddress = "10.233.100.2";
  gatewayPort = 4000;
  egressPort = 8443;
  # brys over the NetBird mesh (nb-priv). Its llama-swap is exposed there on
  # 39704 by a narrow relay (hosts-den/brys/llm.nix); 39700 itself is loopback-only.
  brysHost = "100.79.164.36";
  brysPort = 39704;
  # oams over NetBird (nb-priv), same relay pattern on 39704.
  oamsHost = "100.79.80.79";
  oamsPort = 39704;
  oamsEgressPort = 8444;
  # The placement tree's advisory endpoint on brys (`POST /decide`, `GET /status`). The manager
  # binds loopback and brys exposes it on the mesh at 8182, so the container needs its own narrow
  # relay: the `dyn-*` ladder asks the TREE whether a candidate may be used, and keeps no second
  # copy of the fit arithmetic.
  decideEgressPort = 8446;
  brysDecidePort = 8182;
  # Requesty (SaaS) egress: the container reaches it through a TLS-terminating
  # socat relay (plaintext over the private veth -> TLS to requesty), so the
  # container itself has no direct internet egress.
  requestyHost = "router.requesty.ai";
  requestyPort = 443;
  requestyEgressPort = 8445;

  # HTTP CONNECT proxy for the container's SaaS egress. Bound to the litellm
  # bridge host address (reachable only from the guest, not the LAN). A CONNECT
  # tunnel preserves the real Host/SNI, so Requesty serves the right vhost —
  # unlike a raw socat TLS relay, which keeps the relay's Host and 404s.
  requestyProxyPort = 8888;

  # --- Gateway config, GENERATED from data/llm.nix (no flat file to sync) -------
  #
  # Every alias on brys is one deployment. The aliases oams also serves get a
  # SECOND deployment (second host), so those model groups load-balance across
  # both and fail over. `litellm_settings`/`router_settings` carry the health
  # checks (#1) and the long-TTFT streaming timeouts (#6).
  data = import ../../data/llm.nix;
  llm = import ../../lib/llm.nix { inherit lib; };
  views = {
    brys = llm.mkMemberView data "brys";
    oams = llm.mkMemberView data "oams";
  };
  # Deployments: one per (host, alias). `api_base`/`api_key` are per-host env vars
  # the container resolves at start (see the container ExecStart).
  # Measured rates for a base model id on this host, or null.
  # Measured rates from raw data (the member view forces `vision`/`capabilities`,
  # which throws on models that omit `vision`).
  ratesOf = host: baseId: (data.models.${baseId}.capabilities.rates or null);
  # `nameToBase` maps an exposed group name -> the base model id it serves.
  # Built from aliases AND from un-aliased served base ids, so the gateway mirrors
  # the full static catalog (lib/llm.nix lists aliases when a model has them, else
  # its base id; the gateway used to expose only aliases, dropping 18 base ids).
  deployments =
    host: baseEnv: keyEnv: nameToBase:
    map (
      name:
      let
        baseId = nameToBase.${name};
        r = ratesOf host baseId;
        # The window the entry ACTUALLY serves, from the same function the Pi list uses:
        # a Strata name carries its profile's `maxContext`, `auto` promises only the smallest
        # text window, and a llama.cpp model keeps the curated client budget. Surfaced via
        # /v1/models + /model/info as max_input_tokens/max_output_tokens so clients (and the
        # Pi discovery extension) see the same number the engine enforces.
        ctx = llm.piCtx baseId;
        # The same rule the Pi list uses (`llm.piMaxOut`), so a client that reads
        # `/v1/models` and one that reads the curated catalog see one number.
        maxOut = llm.piMaxOut baseId;
      in
      {
        model_name = name;
        litellm_params = {
          model = "openai/${baseId}";
          api_base = "os.environ/${baseEnv}";
          api_key = "os.environ/${keyEnv}";
        }
        # Measured throughput -> a tpm rate limit (decode t/s * 60 s, a loose ceiling
        # so latency-based/usage routing can use it; a busy host still refuses work).
        // lib.optionalAttrs (r != null) {
          tpm = builtins.floor (r.decode * 60);
          # (#4) Per-deployment streaming timeout = the first-token (prefill) wait for
          # a FULL context: servedContext / prefill_tokens_per_second, plus margin.
          # A deep model at 1M ctx and ~0.2 t/s prefill needs hours; a fast small
          # model needs seconds, so a dead one fails fast. Floor 120 s, no ceiling
          # (a slow-but-alive prefill MUST be allowed to finish).
          # Budget a FIRST TOKEN for at most 100k tokens of context (the policy:
          # never START a request above ~100k; a session may build past that via the
          # disk session cache / prefix reuse, not one huge cold prefill). Capped at
          # 2h so a dead-but-connected backend cannot hang a client for longer; a
          # genuinely running prefill resumes from checkpoints, not from scratch.
          stream_timeout =
            let
              prefill = if r.prefill <= 0 then 1 else r.prefill;
              startTokens = 100 * 1024;
              budget = 120 + builtins.floor (startTokens / prefill);
            in
            if budget > 7200 then 7200 else budget;
        };
        model_info = {
          id = "${host}-${name}";
          # No per-model health probe. A deployment probe is a real completion, and
          # llama-swap keeps one model resident, so a probe would evict it. Health is a
          # host property here: `litellm-host-probe` polls the backend's `/health`
          # endpoint, which never loads a model. See `general_settings` below.
          # The curated client budget (see the `let` above). Advertised, not enforced.
          max_input_tokens = ctx;
          max_output_tokens = maxOut;
        }
        // lib.optionalAttrs (r != null) {
          # Measured throughput, surfaced via /model/info for clients and docs.
          tokens_per_second = r.decode;
          prefill_tokens_per_second = r.prefill;
        };
      }
    ) (builtins.attrNames nameToBase);

  # brys deployment for every alias; oams only for aliases it also serves.
  brysAliases = builtins.attrNames views.brys.aliasToModel;
  oamsAliases = builtins.attrNames views.oams.aliasToModel;

  # A "fastest fit" pool: one model GROUP whose deployments are several fast chat
  # models, so the `fastest` callback can pick the quickest one that FITS the
  # request (context/vision) instead of always using one alias. Curated to fast
  # GPU models (cheap health checks, 16k context); extending the pool with a big
  # context model would let the same selector escalate on long prompts.
  # Only the two small models the fleet still serves: the rest were retired because they beat
  # neither the frontier's decode nor its prefill, and cannot co-reside with it on `max`.
  poolBaseIds = [
    "ministral-3-3b-reasoning"
    "gemma-4-e4b"
  ];
  poolDeployments = map (
    baseId:
    let
      # Read from the raw data model: the member view builds `vision`/`capabilities`
      # via `inherit`, so a model that omits `vision` throws when that field is
      # forced (and `or` cannot catch a throwing value).
      dm = data.models.${baseId};
      r = dm.capabilities.rates or null;
    in
    {
      model_name = "chat-fast";
      litellm_params = {
        model = "openai/${baseId}";
        api_base = "os.environ/BRYS_API_BASE";
        api_key = "os.environ/BRYS_API_KEY";
      };
      model_info = {
        id = "brys-chat-fast-${baseId}";
        # No per-model health probe; health is a host property (see `general_settings`).
        # Same served window as the alias groups; see `llm.piCtx`.
        max_input_tokens = llm.piCtx baseId;
        max_output_tokens = llm.piMaxOut baseId;
        supports_vision = dm.vision or false;
      }
      // lib.optionalAttrs (r != null) {
        tokens_per_second = r.decode;
        prefill_tokens_per_second = r.prefill;
      };
    }
  ) poolBaseIds;

  # --- `dyn-*` intent aliases (docs/tasks/2026-11/dyn-aliases/design.md) -------
  #
  # One scheduler: this gateway. No llama-swap entry, no proxy, no new endpoint.
  #
  # A TEXT PRESET is one deployment of its base model with the request shape fixed in
  # `extra_body`. Verified by the review in `litellm/utils.py:4814-4844`:
  #   * `extra_body.max_tokens` WINS over the client's own value, so the output cap holds;
  #   * `extra_body.chat_template_kwargs` does NOT: a client that sends its own
  #     `chat_template_kwargs` replaces this one wholesale. Thinking is therefore ADVERTISED,
  #     not enforced; a `pre_call` hook is the only way to make it non-negotiable (not built).
  dynTextDeployments = map (preset: {
    model_name = preset.name;
    litellm_params = {
      model = "openai/${preset.base}";
      # The same upstream and key as the plain `qfn` deployment above.
      api_base = "os.environ/BRYS_API_BASE";
      api_key = "os.environ/BRYS_API_KEY";
      extra_body = {
        chat_template_kwargs = preset.kwargs;
        max_tokens = preset.maxTokens;
      };
    };
    model_info = {
      id = "brys-${preset.name}";
      # The same window the Pi entry promises (`llm.dynTextPresets`), never a second number.
      max_input_tokens = preset.context;
      max_output_tokens = lib.min preset.maxTokens preset.context;
    };
  }) llm.dynTextPresets;

  # A MODALITY GROUP is one model group whose deployments are the candidates, in preference order.
  # `resident.resident_fit` walks them: resident candidate -> the first one the placement tree
  # admits -> a refusal built from the tree's own answer. No switch, no unload; this list is only
  # the set of deployments the callback may choose from.
  dynModalityDeployments = lib.concatMap (
    group:
    map (baseId: {
      model_name = group.name;
      litellm_params = {
        model = "openai/${baseId}";
        api_base = "os.environ/BRYS_API_BASE";
        api_key = "os.environ/BRYS_API_KEY";
      };
      model_info = {
        id = "brys-${group.name}-${baseId}";
        # The group's advertised window is its default route's (`llm.dynModalityGroups`).
        max_input_tokens = group.context;
        max_output_tokens = group.maxTokens;
      };
    }) group.models
  ) llm.dynModalityGroups;

  # The facts `resident.resident_fit` reads. They are NAMES ONLY: the candidate order, the text
  # profiles, and the entry that forces each profile. Every fit question goes to the placement tree
  # (`POST /decide`), so there is no second copy of `vramMiB`/`kvReserveMiB` arithmetic here.
  #
  # A text preset is a group with ONE candidate (`qfn`), and it is checked too: `qfn` is the
  # `auto` alias, which the tree refuses while an image profile is loaded. That turns a silent
  # upstream failure into a readable 409 naming the current profile.
  strata = llm.strata data "brys";
  residentPolicyFile = (pkgs.formats.json { }).generate "litellm-resident-policy.json" {
    groups =
      lib.listToAttrs (
        map (
          preset:
          lib.nameValuePair preset.name {
            kind = "text";
            models = [ preset.base ];
          }
        ) llm.dynTextPresets
      )
      // lib.listToAttrs (
        map (group: lib.nameValuePair group.name { inherit (group) kind models; }) llm.dynModalityGroups
      );
    # The profiles that serve chat, in `rank` order: the remedy a text preset names when the engine
    # rests on an image profile.
    inherit (strata) textProfiles;
    # profile -> the llama-swap entry that forces it, so a refusal names `qfn-max-colo` and not only
    # the manager's internal `omni-max`.
    profiles = lib.genAttrs strata.textProfiles (
      profile:
      lib.concatMap (name: [ name ] ++ (data.models.${name}.aliases or [ ])) (
        lib.filter (
          name: ((data.models.${name}.hosts or { }).brys.serving or { }).profile or "" == profile
        ) (builtins.attrNames data.models)
      )
    );
  };

  # Requesty deployments must be EXPLICIT: a `model_name: "requesty/*"` wildcard
  # does NOT route (404 "model group not found") and pollutes /v1/models with the
  # OpenAI price-map names, not Requesty's real catalog. These ids are a PINNED
  # SNAPSHOT of Requesty's /v1/models (which carries no context/pricing metadata);
  # refresh with hosts/etra/litellm_requesty_discover.py when the catalog changes.
  # A deployment's model_name is `requesty/<real id>`.
  requestyModelIds = [
    "deepinfra/deepseek-v4.1-flash-1017"
    "runware/deepseek-v4.1-flash-1017"
    "tensorx/qwen3.8-flash-next"
    # The cheaper sibling the user enabled on Requesty (2026-11-13); 1M context,
    # 128K max output, vision. The tensorx deployment above is 256K/256K.
    "alibaba/qwen3.8-flash"
  ];
  requestyDeployments = map (mid: {
    model_name = "requesty/${mid}";
    litellm_params = {
      model = "openai/${mid}";
      api_base = "https://${requestyHost}/v1";
      api_key = "os.environ/REQUESTY_API_KEY";
      # Requesty's /v1/models returns no context/pricing, so fit metadata is
      # unavailable; give a conservative first-token budget like the router default.
      stream_timeout = 1800;
    };
    model_info = {
      id = "requesty-${builtins.replaceStrings [ "/" ] [ "-" ] mid}";
    };
  }) requestyModelIds;

  # Every group name the gateway should expose on `host`: its aliases (alias -> base
  # id) PLUS every served base id (base id -> itself), so the gateway mirrors the static
  # catalogue and a caller can name either the id the engine serves or an extra name it answers
  # to. A model with an alias is listed under both; `qfn-max-long` used to vanish behind
  # `qfn-max`.
  #
  # `dyn-*` is deliberately NOT here: it is not a `data.models` entry (an entry would emit a brys
  # llama-swap `cmd` and a second gateway group with the same name). The five names are built by
  # `dynTextDeployments` and `dynModalityDeployments`, which carry the preset shape and the ladder,
  # and `mkPiModelsJson` projects them into the client catalog.
  nameToBaseFor =
    host:
    let
      aliases = views.${host}.aliasToModel;
      # ONLY what llama-swap actually serves: the same projection the host uses
      # (`mkServerModels` filters by the boot profile's `sets`, so `retired` models
      # — defined but not served — are correctly excluded). Mirroring just
      # `enable = true` earlier advertised retired base ids and 404'd on call.
      # The profile must match the host boot profile (brys/oams: "desktop").
      # Served = in the profile's `sets` AND enabled (llama-swap skips `enable =
      # false`, e.g. qwen3.5-9b, which the lms aspect filters out).
      # Union over every boot profile the host declares (brys has desktop +
      # appliance), so the gateway mirrors whatever set the host can boot.
      servedBaseIds = builtins.attrNames (
        lib.foldl' (
          acc: prof: acc // lib.filterAttrs (_: e: e.enable) (llm.mkServerModels data host prof)
        ) { } (builtins.attrNames data.servers.${host}.profiles)
      );
    in
    aliases // lib.genAttrs servedBaseIds (id: id);

  modelList =
    (deployments "brys" "BRYS_API_BASE" "BRYS_API_KEY" (nameToBaseFor "brys"))
    ++ (deployments "oams" "OAMS_API_BASE" "OAMS_API_KEY" (nameToBaseFor "oams"))
    ++ poolDeployments
    ++ dynTextDeployments
    ++ dynModalityDeployments
    ++ requestyDeployments;

  gatewayConfig = {
    model_list = modelList;
    litellm_settings = {
      callbacks = [
        "prometheus"
        "probe.host_probe"
        "fastest.fastest_fit"
        "resident.resident_fit"
        "enforce.scope"
      ];
      drop_params = true;
      # (#6) a very long first token (huge prefill) must not be cut off. These are
      # the proxy-wide defaults; the per-deployment streaming limit is what governs
      # a live stream (time since the last chunk, not wall-clock total).
      request_timeout = 3600;
      # /metrics needs no bearer token (Prometheus scrape). `public_routes` alone is
      # NOT enough: /metrics is in the "requires auth despite public" list, and only
      # this flag disables it (litellm/proxy/auth/user_api_key_auth.py).
      require_auth_for_metrics_endpoint = false;
    };
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
      # DB-less client auth: validate non-master keys against a sops keys file and
      # scope each to an allow-list of model groups. The hook also handles the
      # master key (full access), because custom_auth runs before LiteLLM's own
      # master-key check.
      custom_auth = "auth.user_api_key_auth";
      custom_auth_run_common_checks = true;
      # (#1) Health is a HOST property, not a model property. A per-deployment probe is a
      # real completion, and llama-swap keeps one model resident (`--models-max 1`), so
      # probing every deployment evicts the resident model to answer it. Measured on brys
      # 2026-11-12: 37 deployments at a 30 s interval produced about one completion per
      # second and a model-swap storm on every tick. So the per-model probes are off, and
      # the health signal comes from three places that never load a model:
      #   * `litellm-host-probe` (this host) polls each backend's llama-swap `GET /health`
      #     over NetBird and writes host-health.json;
      #   * `probe.host_probe` drops every deployment of a host that failed that probe,
      #     BEFORE any connect;
      #   * a real failed request still cools its deployment (`allowed_fails`,
      #     `cooldown_time`).
      background_health_checks = false;
      enable_health_check_routing = false;
      # /metrics carries no secrets (counters/latency) and is scraped by the
      # containerised Prometheus. `litellm_settings` sets the switch that makes it
      # unauthenticated (public_routes alone is overridden for /metrics).
      public_routes = [ "/metrics" ];
      # (#1) Durable routing state: the router's cooldown/usage/latency DualCache
      # uses this Redis via `coordination_redis` (router._update_redis_cache). A
      # local valkey/redis with AOF persists it across restarts; without it the
      # router is in-memory-per-worker and forgets on restart.
      coordination_redis = {
        host = hostAddress;
        port = 6379;
      };
    };
    router_settings = {
      timeout = 3600;
      # (#6) per-chunk idle limit for a live stream: allow a long gap for the first
      # token, but a genuinely silent backend still dies. Steady streaming is
      # unaffected once tokens flow.
      stream_timeout = 1800;
      num_retries = 1;
      cooldown_time = 30;
      allowed_fails = 2;
      routing_strategy = "simple-shuffle";
      enable_weighted_failover = true;
    };
  };
  # --- Optional Postgres for LiteLLM persistence (#3) --------------------------
  #
  # OFF by default. LiteLLM uses a DB for virtual keys, spend logs, budgets, and to
  # persist config-managed models — none required for routing. Enabling it needs a
  # working Prisma schema+query engine; on NixOS this means prisma-engines, whose
  # version must match the prisma pinned inside nixpkgs' litellm (see the task doc
  # for the exact compatibility note). `database.enable = true` wires it all.
  dbEnabled = false;
  dbUser = "litellm";
  dbName = "litellm";
  dbPasswordFile = "/var/lib/litellm/db-password";
  configFile = (pkgs.formats.json { }).generate "litellm-config.json" gatewayConfig;
in
{
  # State for the gateway. DB-less, so this is only logs / a local cache / the
  # generated master key, but it must survive a reboot (task requirement: a
  # persistence dataset before activation).
  kdn.disks.persist."sys/state".directories = [
    {
      directory = "/var/lib/litellm";
      mode = "0750";
    }
    # Prometheus TSDB (state, survives reboot). The prometheus container bind-mounts
    # it, and systemd-nspawn needs the host path to exist.
    {
      directory = "/var/lib/prometheus2";
      mode = "0750";
    }
    # Redis AOF for durable routing state (#1). systemd's redis `StateDirectory`
    # is /var/lib/redis-litellm; on this tmpfs-root host it must be persisted.
    {
      directory = "/var/lib/redis-litellm";
      mode = "0700";
    }
  ];
  # The container's writable root.
  kdn.disks.persist."sys/cache".directories = [
    {
      directory = "/var/lib/nixos-containers";
      mode = "0755";
    }
  ];

  containers.litellm = {
    autoStart = true;
    restartIfChanged = true;
    privateNetwork = true;
    inherit hostAddress localAddress;

    bindMounts."/etc/litellm/config.yaml" = {
      hostPath = "${configFile}";
      isReadOnly = true;
    };
    # The host-reachability callback, loaded from beside config.yaml (module
    # `probe`, instance `host_probe` — see litellm_settings.callbacks).
    bindMounts."/etc/litellm/probe.py" = {
      hostPath = "${./litellm_probe.py}";
      isReadOnly = true;
    };
    # The fastest-fit selector (module `fastest`, instance `fastest_fit`).
    bindMounts."/etc/litellm/fastest.py" = {
      hostPath = "${./litellm_fastest.py}";
      isReadOnly = true;
    };
    # The resident-first selector for the modality groups (module `resident`, instance
    # `resident_fit`).
    bindMounts."/etc/litellm/resident.py" = {
      hostPath = "${./litellm_resident.py}";
      isReadOnly = true;
    };
    # The facts that selector decides over: the candidate order (data/llm.nix) plus the placement
    # policy's rows and budget. One file, so no name or number is written twice.
    bindMounts."/etc/litellm/resident-policy.json" = {
      hostPath = "${residentPolicyFile}";
      isReadOnly = true;
    };
    bindMounts."/var/lib/litellm" = {
      hostPath = "/var/lib/litellm";
      isReadOnly = false;
    };
    # The SOPS-decrypted secrets, as individual FILES mounted under /etc — NOT
    # under /run: the container has its own /run tmpfs which SHADOWS any bind placed
    # there (observed: /run/configs/llms was empty inside the guest).
    bindMounts."/etc/litellm-master-key" = {
      hostPath = "/run/configs/llms/litellm/master-key";
      isReadOnly = true;
    };
    bindMounts."/etc/litellm-llama-key" = {
      hostPath = "/run/configs/llms/llama-server/api-keys/default";
      isReadOnly = true;
    };
    bindMounts."/etc/litellm-requesty-key" = {
      hostPath = "/run/configs/llms/requesty/api-key";
      isReadOnly = true;
    };
    # Client API keys (sops) and the custom-auth hook.
    bindMounts."/etc/litellm-keys-clients" = {
      hostPath = "/run/configs/litellm-keys/keys/clients";
      isReadOnly = true;
    };
    bindMounts."/etc/litellm/auth.py" = {
      hostPath = "${./litellm_auth.py}";
      isReadOnly = true;
    };
    bindMounts."/etc/litellm/enforce.py" = {
      hostPath = "${./litellm_enforce.py}";
      isReadOnly = true;
    };

    config =
      { pkgs, ... }:
      {
        networking.firewall.allowedTCPPorts = [ gatewayPort ];

        # The master key is a SOPS secret (llms.nonsensitive: litellm.master-key),
        # mounted read-only into the container at /run/configs/llms. One key for the
        # gateway AND every client (Pi/OpenCode read the same path on their host).
        # (No auto-generation: a generated key would not match the clients'.)
        # Nothing to create here; the container reads it directly below.

        systemd.services.litellm = {
          description = "LiteLLM OpenAI-compatible gateway";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = ''
              ${pkgs.writeShellScript "litellm-run" ''
                set -eu
                export LITELLM_MASTER_KEY="$(cat /etc/litellm-master-key)"
                # The probe callback (probe.host_probe) lives beside config.yaml.
                export PYTHONPATH="/etc/litellm''${PYTHONPATH:+:$PYTHONPATH}"
                # Upstream is brys' llama-swap over NetBird, reached through the
                # host egress relay. Plain HTTP (no TLS to verify), real API key.
                # `resident.resident_fit` reads residency from this same relay.
                export BRYS_API_BASE="http://${hostAddress}:${toString egressPort}/v1"
                export BRYS_API_KEY="$(cat /etc/litellm-llama-key)"
                export OAMS_API_BASE="http://${hostAddress}:${toString oamsEgressPort}/v1"
                # Same shared llama-server key as brys (one fleet api-key file).
                export OAMS_API_KEY="$(cat /etc/litellm-llama-key)"
                export REQUESTY_API_KEY="$(cat /etc/litellm-requesty-key)"
                # SaaS egress via the host CONNECT proxy; local relays bypass it.
                export HTTPS_PROXY="http://${hostAddress}:${toString requestyProxyPort}"
                export HTTP_PROXY="http://${hostAddress}:${toString requestyProxyPort}"
                export NO_PROXY="${hostAddress}"
                export no_proxy="${hostAddress}"
                export KDN_LITELLM_KEYS_FILE=/etc/litellm-keys-clients
                # The placement tree, for the dyn-* ladder: one POST /decide per candidate.
                export KDN_DECIDE_URL="http://${hostAddress}:${toString decideEgressPort}"
                export PROMETHEUS_MULTIPROC_DIR=/var/lib/litellm/prom
                install -d -m 0750 "$PROMETHEUS_MULTIPROC_DIR"
                ${lib.optionalString dbEnabled ''
                  # Prisma engines from nixpkgs (the packaged prisma has none).
                  export PRISMA_SCHEMA_ENGINE_BINARY="${pkgs.prisma-engines}/bin/schema-engine"
                  export PRISMA_QUERY_ENGINE_LIBRARY="${pkgs.prisma-engines}/lib/libquery_engine.so.node"
                  export DATABASE_URL="postgresql://${dbUser}:$(cat ${dbPasswordFile})@${hostAddress}:5432/${dbName}"
                ''}
                exec ${pkgs.litellm}/bin/litellm \
                  --config /etc/litellm/config.yaml \
                  --host 0.0.0.0 --port ${toString gatewayPort}
              ''}
            '';
            Restart = "always";
            RestartSec = 5;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

        system.stateVersion = "26.05";
      };
  };

  # --- Durable routing state: Redis with AOF (#1) -----------------------------
  #
  # The router's DualCache (cooldowns, usage, latency history) uses Redis when
  # `general_settings.coordination_redis` is set. A local redis with append-only
  # persistence keeps that state across proxy restarts and shares it across workers.
  # Bound to loopback; a narrow relay exposes it on the litellm bridge only, so the
  # guest reaches it and nothing else does. Routing counters are not secrets.
  services.redis.servers.litellm = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    appendOnly = true;
    appendFsync = "everysec";
  };

  # The keys file is a sops secret; the container bind-mounts it, so it must start
  # after sops has written the file (a missing bind source fails nspawn).
  systemd.services."container@litellm" = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };

  systemd.services.litellm-redis-ingress = {
    description = "Expose the routing-state Redis to the LiteLLM container";
    wantedBy = [ "multi-user.target" ];
    after = [ "redis-litellm.service" ];
    wants = [ "redis-litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:6379,bind=${hostAddress},fork,reuseaddr TCP:127.0.0.1:6379";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  # The prober's health file must exist before the container bind-mounts the dir
  # (a file bind-mount would break on the prober's atomic rename; the dir mount is
  # safe, so we only guarantee the file is present at boot).
  systemd.tmpfiles.rules = [ "f /var/lib/litellm/host-health.json 0644 root root -" ];

  # --- Host-side health prober (#1) -------------------------------------------
  #
  # Polls each host's llama-swap `GET /health` over NetBird DIRECTLY (a real connect
  # timeout, unlike the relay path). `/health` answers `OK` without loading a model, so
  # the probe never evicts a resident model. It writes host-health.json for the
  # container callback (`probe.host_probe`) to read. Only the two known hosts; extend
  # the map as hosts join.
  systemd.services.litellm-host-probe = {
    description = "Probe brys/oams llama-swap /health over NetBird";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
    ];
    serviceConfig = {
      Type = "oneshot";
      # Cheap, idempotent writer driven by the timer below.
      StartLimitIntervalSec = 0;
      StartLimitBurst = 0;
    };
    script = ''
      set -eu
      f=/var/lib/litellm/host-health.json
      tmp="$f.tmp"
      probe() {
        if [ "$(curl -fsS -m 3 "http://$1:39704/health" 2>/dev/null)" = "OK" ]; then
          printf true
        else
          printf false
        fi
      }
      printf '{"brys": %s, "oams": %s}\n' "$(probe ${brysHost})" "$(probe ${oamsHost})" > "$tmp"
      mv "$tmp" "$f"
    '';
  };
  systemd.timers.litellm-host-probe = {
    description = "Recheck host reachability";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "15s";
    };
  };

  # --- Prometheus scraping the gateway's /metrics (#2) ------------------------
  #
  # A confined Prometheus (the prometheus-container aspect) scrapes the gateway.
  # The gateway's /metrics is on a public route (no bearer token), so the scrape is
  # unauthenticated and needs no key. Prometheus reaches the gateway over the
  # container bridge; the gateway stays on its own private veth.
  kdn.prometheus-container = {
    hostAddress = "10.233.101.1";
    localAddress = "10.233.101.2";
    stateDir = "/var/lib/prometheus2";
    targets = [
      {
        job = "litellm";
        targets = [ "10.233.101.1:${toString gatewayPort}" ]; # unauthenticated /metrics (public_routes)
        interval = "15s";
        metricsPath = "/metrics/"; # trailing slash avoids the 307 to /metrics/
      }
    ];
  };

  # Host firewall on the container veth (the bridge is not trusted by nixos-fw).
  # `gatewayPort` lets the ingress relay reach the guest; `egressPort` lets the
  # guest reach the egress relay bound on the bridge address (without it the
  # backend calls are blackholed and every completion times out).
  # The prometheus container reaches the gateway through the bridge relay bound
  # at 10.233.101.1:4000; the veth is not trusted, so open just that port. Caddy
  # reaches the gateway over the caddy-only unix socket, not a TCP port.
  networking.firewall.interfaces.ve-prometheus.allowedTCPPorts = [ gatewayPort ];

  networking.firewall.interfaces.ve-litellm.allowedTCPPorts = [
    gatewayPort
    egressPort
    oamsEgressPort
    requestyProxyPort
    decideEgressPort
    6379 # routing-state Redis relay
  ];

  # Ingress for Caddy: a UNIX socket owned by the `caddy` user, so ONLY Caddy
  # reaches the gateway. No TCP listener exists on the host, so no other local
  # user (and nothing off-host) can reach it. Caddy proxies
  # unix//run/kdn/litellm.sock. The socket runs as caddy so the socket is
  # owned caddy:caddy (no chown, which a DynamicUser could not do).
  systemd.services.litellm-ingress-sock = {
    description = "Expose the LiteLLM container on a Caddy-only unix socket";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d UNIX-LISTEN:/run/kdn/litellm.sock,fork,unlink-early,mode=0660 TCP:${localAddress}:${toString gatewayPort}";
      User = "caddy";
      Group = "caddy";
      RuntimeDirectory = "kdn";
      RuntimeDirectoryMode = "0750";
      Restart = "always";
      RestartSec = 3;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  # Ingress for Prometheus: bound to the Prometheus container's host-bridge
  # address only, so the scraper reaches it and nothing else does (no 0.0.0.0,
  # no host loopback). The veth firewall opens just this port.
  systemd.services.litellm-ingress-prom = {
    description = "Relay the gateway to the Prometheus container over the bridge";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString gatewayPort},bind=10.233.101.1,fork,reuseaddr TCP:${localAddress}:${toString gatewayPort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  # Egress relay: guest -> brys' mesh-exposed llama-swap (39704).
  systemd.services.litellm-brys-egress = {
    description = "Relay the LiteLLM container to brys:${toString brysPort}";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString egressPort},bind=${hostAddress},fork,reuseaddr,connect-timeout=5 TCP:${brysHost}:${toString brysPort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  # HTTP CONNECT proxy for the container's SaaS egress, bound to the litellm
  # bridge host address so only the guest reaches it. `Allow` is a CLIENT-IP ACL
  # (the guest); `FilterDefaultDeny Yes` + `Filter` bound the DESTINATION to the
  # SaaS host, `ConnectPort 443` bounds the method. The container sets HTTPS_PROXY
  # to it (NO_PROXY covers the local relays), so it has no direct internet route.
  # See docs/litellm-connect-egress.md.
  systemd.services.litellm-requesty-proxy = {
    description = "HTTP CONNECT proxy for the LiteLLM container's SaaS egress";
    wantedBy = [ "multi-user.target" ];
    environment.HTTPS_PROXY = "";
    serviceConfig = {
      ExecStart = "${pkgs.tinyproxy}/bin/tinyproxy -d -c /etc/kdn/litellm-proxy.conf";
      # Config edits must take effect: the unit does not restart on a mere file
      # change, so key off the generated config's store path.
      Restart = "always";
      restartTriggers = [ config.environment.etc."kdn/litellm-proxy.conf".source ];
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };
  # NB: tinyproxy `Allow`/`Deny` are CLIENT-IP ACLs, not destination filters.
  # The only client is the container guest (localAddress). `ConnectPort` limits
  # the CONNECT method to 443 (HTTPS only). tinyproxy cannot restrict the
  # destination hostname; the layer-3 firewall (the container has no WAN route,
  # and the proxy itself is the only egress) is what bounds the target.
  environment.etc."kdn/litellm-proxy.conf".text = ''
    Port ${toString requestyProxyPort}
    Listen ${hostAddress}
    Timeout 600
    Allow ${localAddress}
    ConnectPort ${toString requestyPort}
    LogLevel Info
    # NOTE: egress is bounded by (a) the guest having NO WAN route (the proxy is its
    # only path out), (b) `ConnectPort 443`, and (c) the guest IP ACL above. tinyproxy
    # cannot hostname-filter a CONNECT destination without a filter FILE; if stricter
    # destination pinning is ever needed, add `Filter "/etc/kdn/litellm-proxy.filter"`
    # + `FilterExtended On` + `FilterDefaultDeny Yes` with a regex file.
  '';

  systemd.services.litellm-oams-egress = {
    description = "Relay the LiteLLM container to oams:${toString oamsPort}";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString oamsEgressPort},bind=${hostAddress},fork,reuseaddr,connect-timeout=5 TCP:${oamsHost}:${toString oamsPort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  # Egress relay: guest -> brys' placement tree (`POST /decide`, `GET /status`). Advisory only:
  # the ladder reads a verdict and never selects or admits, so this relay cannot switch the engine.
  systemd.services.litellm-brys-decide = {
    description = "Relay the LiteLLM container to brys' placement /decide";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString decideEgressPort},bind=${hostAddress},fork,reuseaddr,connect-timeout=5 TCP:${brysHost}:${toString brysDecidePort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };
}
