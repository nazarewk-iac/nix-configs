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
#   * `strata data host` — the Strata frontier: the deployment's `profiles`, `textProfiles`,
#     `aliases`, `frontierIDs` and `coloProfiles`, plus the models themselves so the placement
#     policy quotes their measured facts. Every one of those is derived from the per-model
#     `hosts.<host>.serving` block.
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

  # `auto` is not an operating point. It lands on whatever profile is current, so the only window
  # it can promise a client is the smallest one a text profile serves — a 1M promise would be
  # rejected the moment somebody rests on the 256k swarm.
  smallestTextWindow = lib.foldl' lib.min 1073741824 (
    lib.concatMap (
      n:
      lib.mapAttrsToList (_: h: (h.serving or { }).maxContext or 1073741824) (
        data.models.${n}.hosts or { }
      )
    ) (builtins.attrNames data.models)
  );

  isAutoEntry = m: lib.any (h: ((h.serving or { }).profile or "") == "auto") (lib.attrValues m.hosts);

  # The client view of one SERVED MODEL, one entry per name it answers to.
  #
  # Pi lists and selects by the entry `id`. Since the purpose aliases were dropped (2026-11-23) the
  # name is the model id itself, plus any genuine alternate name the model still declares (the
  # `qfn-max` alias on `qfn-max-long`).
  piEntries =
    name:
    let
      m = data.models.${name};
      # A model may set its OWN `pi.contextWindow` (a client budget below the served size) and
      # `pi.maxTokens`. Absent, the client-wide defaults apply, clamped to the native window.
      # A Strata entry serves exactly the window its operating point declares, and the engine
      # rejects a request over it. `pi.defaults.contextWindow` (384k) is a conservative budget for
      # a llama.cpp model, not a description of a 1M slot or a 256k one, so a frontier entry takes
      # the window from its own `serving.maxContext`. Measured 2026-11-23: every qfn name listed
      # 393.2K, which is the client default clamped by nothing at all.
      servedCtx = lib.filter (w: w != null) (
        lib.mapAttrsToList (_: h: (h.serving or { }).maxContext or null) m.hosts
      );
      ctx = lib.min (m.pi.contextWindow or (
        if servedCtx != [ ] then
          lib.foldl' lib.min (builtins.head servedCtx) servedCtx
        else if isAutoEntry m then
          smallestTextWindow
        else
          data.pi.defaults.contextWindow
      )
      ) m.contextSize;
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
      # BOTH the served id and every extra name it answers to. A model with an alias used to be
      # listed under the alias alone, which hid the id the engine actually serves (`qfn-max-long`
      # vanished behind `qfn-max`).
      ids = [ name ] ++ (m.aliases or [ ]);
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

  # The measured cold-load seconds of a model: what it declares on `capabilities`, or what its
  # serving block measured (`hosts.<host>.serving.loadSeconds`). One number, not two — the frontier's
  # `capabilities` no longer repeats the load time the placement policy quotes.
  loadSecondsOf =
    m:
    let
      declared = (m.capabilities or { }).loadSeconds or null;
      measured = builtins.filter (x: x != null) (
        lib.mapAttrsToList (_: h: (h.serving or { }).loadSeconds or null) (m.hosts or { })
      );
    in
    if declared != null then declared else lib.head (measured ++ [ null ]);

  # The orchestrator's model catalog, as a compact aligned table for the system prompt.
  #
  # One row per served name, not per model: the orchestrator names a model id in `delegate`.
  # Columns are what the id does not already say:
  #
  #   alias      the name the orchestrator uses (the model id, or its second name)
  #   ctx        served context (tokens) — the hard filter
  #   op         cpu | gpu — where it runs
  #   load~s     estimated cold-load seconds — is a switch affordable?
  #   vision     `yes` when the model accepts images
  #   model      the served base id, for a human reading a trace
  #
  # A model with no `capabilities` still appears, with `-` for op/load, so the row count matches
  # what can actually be delegated to. Sorted by alias, so the prompt is stable across renders.
  # The client-facing window of one model: the same rule `piEntries` uses, so the orchestrator
  # catalog and the Pi list never quote different numbers for the same name.
  piCtx =
    name:
    let
      m = data.models.${name};
      served = lib.filter (w: w != null) (
        lib.mapAttrsToList (_: h: (h.serving or { }).maxContext or null) m.hosts
      );
    in
    lib.min (m.pi.contextWindow or (
      if served != [ ] then
        lib.foldl' lib.min (builtins.head served) served
      else if isAutoEntry m then
        smallestTextWindow
      else
        data.pi.defaults.contextWindow
    )
    ) m.contextSize;

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
          load =
            let
              seconds = loadSecondsOf m;
            in
            if seconds != null then toString seconds else "-";
          vision = if m.vision or false then "yes" else "-";
        }) ([ name ] ++ aliases)
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

  # ---------------------------------------------------------------- the Strata frontier
  #
  # The brys frontier is one engine with several operating points. Every knob of one point — the
  # pack, the window, the slot count, the VRAM reserve, the resident K/V, the park pool and the
  # n-gram backing store — is written on the model itself, in `hosts.<host>.serving`, and this
  # projection is the only reader. It yields what each consumer needs:
  #
  #   profiles      the deployment's `profiles` map, keyed by profile name (config.json)
  #   textProfiles  the chat points in `rank` order; the first one rests (config.json)
  #   aliases       every name llama-swap answers to -> the point it forces (config.json)
  #   frontierIDs   the same names, so a switch can tell a frontier entry from a companion
  #   coloProfiles  the points that keep a reserve for a companion, in `rank` order
  #   frontier      the models themselves, for the policy's measured-facts rows
  #
  # `ropeScale` is derived from the window, never written: the yarn factor is the served window
  # over the model's native one. `qfn` is `profile = "auto"` — a name, not a point — so it reaches
  # `aliases` and `frontierIDs` but no `profiles` row.
  strata =
    data: host:
    let
      frontier = lib.filterAttrs (
        _: m: ((m.hosts or { }) ? ${host}) && ((m.hosts.${host}.serving or { }) ? profile)
      ) data.models;
      serving = name: frontier.${name}.hosts.${host}.serving;
      # The yarn factor of one point: the window it serves over the window the model was trained on.
      ropeScale = maxContext: maxContext / (data.servers.${host}.frontier.nativeContext * 1.0);
      # The entries that materialise a shape. `qfn` is `auto`: a name, not an operating point.
      points = lib.filterAttrs (name: _: (serving name).profile != "auto") frontier;
      ranked = map (name: {
        inherit name;
        inherit (serving name) profile;
        rank = (serving name).rank;
        colo = (serving name).colo or false;
      }) (lib.sort (a: b: (serving a).rank < (serving b).rank) (lib.attrNames points));
      # Every name llama-swap answers to for one entry: its own id and the model's declared aliases.
      namesOf = name: [ name ] ++ (frontier.${name}.aliases or [ ]);
    in
    {
      inherit frontier;
      profiles = lib.listToAttrs (
        map (p: {
          name = p.profile;
          value = {
            inherit (serving p.name)
              base
              maxContext
              parallel
              reserveMiB
              kvResident
              ;
            inherit (serving p.name) conversationCacheMiB pleIO;
            ropeScale = ropeScale (serving p.name).maxContext;
          };
        }) ranked
      );
      textProfiles = map (p: p.profile) ranked;
      aliases = lib.listToAttrs (
        lib.concatMap (name: map (alias: lib.nameValuePair alias (serving name).profile) (namesOf name)) (
          lib.attrNames frontier
        )
      );
      frontierIDs = lib.sort (a: b: a < b) (lib.concatMap namesOf (lib.attrNames frontier));
      coloProfiles = map (p: p.profile) (lib.filter (p: p.colo) ranked);
    };

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
      serving = h.serving or { };
    in
    if p ? servedContext then
      p.servedContext
    else if serving ? maxContext then
      # A Strata entry serves the window its own operating point declares, so there is no second
      # `servedContext` to keep in step with it.
      serving.maxContext
    else if ((serving.profile or "") == "auto") then
      # `auto` lands on whatever profile is current; the only window the entry can promise is the
      # smallest one a text profile serves, and it must match what `piCtx` tells the client.
      smallestTextWindow
    else
      h.servedContext or m.contextSize;

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
      # A model that is not llama.cpp names either a complete llama-swap command or the Strata
      # operating point its command is generated from.
      command = m.command or null;
      strataProfile = (h.serving or { }).profile or null;
      # A command prefix for the generated invocation (the companion gate), and an idle ttl after
      # which llama-swap unloads the model by itself.
      wrapper = m.wrapper or null;
      ttl = m.ttl or null;
      # A model that is not an OpenAI server: the path llama-swap polls instead of its own health
      # check, whether it belongs in `/v1/models` at all, and the command that releases what it
      # proxied when llama-swap unloads it.
      checkEndpoint = m.checkEndpoint or null;
      unlisted = m.unlisted or false;
      cmdStop = m.cmdStop or null;
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
  inherit
    data
    aliasToModel
    purposeAliases
    strata
    ;
  inherit
    mkPiModelsJson
    mkCatalog
    mkServerModels
    mkMemberView
    piCtx
    servedOn
    ;
}
