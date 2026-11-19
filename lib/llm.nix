# Render each consumer's config from the single LLM source of truth, `data/llm.nix`.
#
# One function per consumer. Nothing here declares a model id, an alias or a context size; every
# value is read from the data file, so the only place to edit is `data/llm.nix`.
#
#   * `mkServerModels data host profile` — the server view: what a host loads, which router, and
#     the per-host perf. Used by `hosts-den/brys/llm.nix` to fill `kdn.llm.local.models`.
#   * `mkPiModelsJson` — the Pi client's `models.json`, one entry per served alias.
#   * `mkCatalog` — the orchestrator's intent table for the system prompt.
#   * `mkMemberView data host` — a fleet member's view: the endpoint and the alias-to-model map,
#     with the serving plumbing physically absent.
#
# See docs/tasks/2026-11/fleet-llm-data-model/design.md for the shape.
{ lib }:
let
  data = import ../data/llm.nix;

  hostNames = builtins.attrNames data.servers;

  # A host serves a model when it sits on one of that host's boot-profile `sets` AND
  # its serving block leaves it enabled. `set` decides which router runs the model — a
  # `retired` model (or any set no profile lists) is NOT served even with `enable =
  # true`; enable only governs the serving block (download, perf), the profile governs
  # the router. Same predicate the gateway uses (hosts/etra/litellm.nix folds
  # `mkServerModels` over the profiles), so the client advertises exactly what a host
  # can boot. `qwen3.5-9b` (enable = false) is therefore not advertised either. A
  # remote model (a cloud endpoint) has no `hosts` block at all, so the check must not
  # assume one.
  servedOn =
    host: m:
    let
      h = m.hosts or { };
    in
    (h ? ${host})
    && (h.${host}.common.enable or true)
    && lib.any (prof: builtins.elem h.${host}.set data.servers.${host}.profiles.${prof}.sets) (
      builtins.attrNames data.servers.${host}.profiles
    );
  isServed = m: lib.any (host: servedOn host m) hostNames;

  # The models a client or catalog may name: only those served somewhere.
  servedModels = lib.filterAttrs (_: m: isServed m) data.models;

  # Which endpoint a model answers through. A local model omits the field and belongs to `brys`;
  # a remote model (a cloud router) names its endpoint and has no host block.
  endpointOf = m: m.endpoint or "brys";

  # A model is listed under one endpoint. A local endpoint additionally requires the model to be
  # enabled on some host; a remote endpoint accepts everything that names it, so a cloud model
  # needs no local serving block.
  modelsForEndpoint =
    ep:
    lib.filterAttrs (_: m: endpointOf m == ep && (!(data.servers ? ${ep}) || isServed m)) data.models;

  # alias -> model id, inverted once over the served models. A model may answer to several aliases.
  aliasToModel = lib.foldl' (
    acc: name: lib.foldl' (a: alias: a // { ${alias} = name; }) acc (data.models.${name}.aliases or [ ])
  ) { } (builtins.attrNames servedModels);

  # The client view of one SERVED MODEL, expanded to one entry PER ALIAS.
  #
  # Pi lists and selects by the entry `id`, and a caller names an intent (`chat-std-fast`), not a
  # base model id. So each alias becomes its own entry against the same served model. A model with
  # no alias also gets one entry under its base id, so nothing is unreachable.
  piEntries =
    name:
    let
      m = data.models.${name};
      # A model may set its OWN `pi.contextWindow` (a client budget below the served size) and
      # `pi.maxTokens`. Absent, the client-wide defaults apply, clamped to the native window.
      ctx = lib.min (m.pi.contextWindow or data.pi.defaults.contextWindow) m.contextSize;
      base = {
        contextWindow = ctx;
        # `maxTokens` is an explicit number (per model in data/llm.nix, else `pi.defaults`). Clamp
        # it to the window so an output cap can never exceed the context it shares with the prompt.
        maxTokens = lib.min (m.pi.maxTokens or data.pi.defaults.maxTokens) ctx;
        # The SERVED model id behind this alias. Pi ignores an unknown field, but
        # model-discovery reads the rendered catalog: a gateway lists a remote model
        # under a provider-scoped id (`requesty/deepinfra/<baseId>`), and this field
        # is how the curated context and modality reach that live entry.
        baseId = name;
      }
      // lib.optionalAttrs (m.vision or false) {
        input = [
          "text"
          "image"
        ];
      }
      # A reasoning model declares `<model>.reasoning` (an identity fact: the model thinks). Pi
      # auto-detects reasoning from the provider URL, but llama-swap does not advertise it, so
      # without this Pi lists the model as non-thinking and pins `--thinking off`. `format` is the
      # request shape (`qwen` = top-level `enable_thinking` + `reasoning_effort`); `levels` maps Pi
      # thinking levels to the values that alias' template accepts. Pi needs `reasoning = true`
      # before it will offer any level at all.
      // lib.optionalAttrs (m.reasoning or null != null) {
        reasoning = true;
      }
      // lib.optionalAttrs (m.reasoning or null != null) {
        thinkingLevelMap = m.reasoning.levels;
      };
      ids = if (m.aliases or [ ]) == [ ] then [ name ] else m.aliases;
    in
    map (id: base // { inherit id; }) ids;

  # One provider entry per endpoint. `models` is every SERVED model, one entry per alias.
  #
  # The `litellm` gateway is special: it does not OWN models (none name `endpoint =
  # "litellm"`); it FRONT-ENDS the fleet and exposes the same aliases the local hosts
  # serve. So its provider lists every served model, same as the union — a client picks
  # an alias and the gateway routes to a host.
  #
  # An endpoint may name `localHost = "<name>"`: it is a direct path to a serving
  # host, valid only for a client RUNNING on that host (offline capability). Such
  # an endpoint is included only when the caller passes the matching `host`.
  mkPiModelsJson =
    {
      host ? null,
    }:
    lib.mapAttrs
      (epName: ep: {
        baseUrl = ep.baseUrl;
        api = ep.api;
        apiKey = ep.apiKey;
        models = builtins.concatLists (
          map piEntries (
            builtins.attrNames (
              if epName == "litellm" then
                servedModels
              else if data.servers ? ${epName} then
                # A direct host endpoint lists only the models THAT host serves (profile sets).
                lib.filterAttrs (_: m: servedOn epName m) data.models
              else
                modelsForEndpoint epName
            )
          )
        );
      })
      (
        lib.filterAttrs (
          _: ep: (ep.localHost or null) == null || (ep.localHost or null) == host
        ) data.endpoints
      );

  # The purpose aliases only (legacy bare ids like `fast` are not purposes).
  purposeAliases = lib.filterAttrs (
    name: _: builtins.match "[a-z]+-(dumb|quick|std|deep)-[a-z]+(-[a-z]+)*(-alt)?" name != null
  ) aliasToModel;

  # The orchestrator's model catalog, as a compact aligned table for the system prompt.
  #
  # One row per PURPOSE ALIAS, not per model: the orchestrator picks an intent (`chat-std-fast`),
  # so the alias is the key it needs. Columns are what the alias name does not already say:
  #
  #   alias      the intent the orchestrator names in `delegate`
  #   ctx        served context (tokens) — the hard filter
  #   op         cpu | gpu — where it runs
  #   load~s     estimated cold-load seconds — is a switch affordable?
  #   vision     `yes` when the model accepts images
  #   model      the served base id, for a human reading a trace
  #
  # A model with no `capabilities` still appears, with `-` for op/load, so the row count matches
  # what can actually be delegated to. Sorted by alias, so the prompt is stable across renders.
  mkCatalog =
    let
      rows = lib.concatMap (
        name:
        let
          m = data.models.${name};
          caps = m.capabilities or { };
          aliases = m.aliases or [ ];
          ctx = toString (lib.min (m.pi.contextWindow or data.pi.defaults.contextWindow) m.contextSize);
        in
        map (alias: {
          inherit alias ctx name;
          op = caps.operation or "-";
          load = if caps ? loadSeconds then toString caps.loadSeconds else "-";
          vision = if m.vision or false then "yes" else "-";
        }) aliases
      ) (builtins.attrNames servedModels);

      table = lib.sort (a: b: a.alias < b.alias) rows;

      fmt = r: "${r.alias}\t${r.ctx}\t${r.op}\t${r.load}\t${r.vision}\t${r.name}";
      headerRow = {
        alias = "alias";
        ctx = "ctx";
        op = "op";
        load = "load~s";
        vision = "vision";
        name = "model";
      };
    in
    lib.concatStringsSep "\n" (map fmt ([ headerRow ] ++ table));

  # ---------------------------------------------------------------- server projection
  #
  # The model set a host serves for a boot profile: every model whose `set` is one of the
  # profile's enabled routers. The entry is exactly what `kdn.llm.local.models.<id>` accepts; the
  # module fills every unset option with its own default.
  servedContextFor =
    host: profile: m:
    let
      h = m.hosts.${host};
      p = h.profiles.${profile} or { };
    in
    p.servedContext or h.servedContext or m.contextSize;

  serverEntry =
    host: profile: m:
    let
      h = m.hosts.${host};
      p = h.profiles.${profile} or { };
      c = h.common;
      perf =
        (c.perf or { })
        // (p.perf or { })
        // {
          contextSize = servedContextFor host profile m;
        };
    in
    {
      aliases = m.aliases or [ ];
      # A model that is not llama.cpp names a complete llama-swap command; the rest leave it null.
      command = m.command or null;
      enable = c.enable or true;
      mainRouter = h.set;
      inherit (c) hfRepo hfFile;
      download = c.download or { };
      mmproj = c.mmproj or { };
      draft = c.draft or { };
      perf = perf;
    };

  mkServerModels =
    data: host: profile:
    let
      srv = data.servers.${host};
      enabled = srv.profiles.${profile}.sets;
    in
    lib.mapAttrs (_id: m: serverEntry host profile m) (
      lib.filterAttrs (
        _: m: (m.hosts or { }) ? ${host} && builtins.elem m.hosts.${host}.set enabled
      ) data.models
    );

  # ---------------------------------------------------------------- member projection
  #
  # Host-presence only: every model this host has a serving block for, regardless of the boot
  # profile. The serving plumbing (file, perf, ports, device pins) is physically absent, so it
  # cannot leak into a member.
  modelsOnHost = data: host: lib.filterAttrs (_: m: (m.hosts or { }) ? ${host}) data.models;

  mkMemberView =
    data: host:
    let
      onHost = modelsOnHost data host;
    in
    {
      endpoint = data.endpoints.${host};
      # alias -> base id, over every model this host serves.
      aliasToModel = lib.foldl' (
        acc: id: lib.foldl' (a: alias: a // { ${alias} = id; }) acc (data.models.${id}.aliases or [ ])
      ) { } (builtins.attrNames onHost);
      # Identity only; serving keys physically absent.
      models = lib.mapAttrs (_id: m: {
        aliases = m.aliases or [ ];
        inherit (m) contextSize vision capabilities;
      }) onHost;
    };
in
{
  inherit data aliasToModel purposeAliases;
  inherit
    mkPiModelsJson
    mkCatalog
    mkServerModels
    mkMemberView
    ;
}
