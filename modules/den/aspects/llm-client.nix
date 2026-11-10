# The `llm.client` slot, as a den aspect. It ports `modules/slots/llm/client/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It adds one opencode provider per remote llama-server endpoint. Each endpoint is one entry of
# `kdn.llm-client.upstreams`, and each entry becomes one `provider.<name>` block in
# `opencode.jsonc`: the base URL, an API-key reference, and one model entry per served model.
#
# ## The classes
#
# `devenv` and `homeManager`. The `devenv` target wires the opencode provider, the wrapper key and
# the plugins; it also installs the `kdn-llms` agent skill. The `homeManager` target installs that
# same skill into a user's home, so a home-manager config reaches it too.
#
# ## The skill path is harness-agnostic
#
# The skill installs to `.agents/skills/kdn-llms/SKILL.md` (project) and `~/.agents/skills/...`
# (home). `.agents/skills/` is the cross-harness convention: opencode, Codex CLI, Cursor, Gemini
# CLI, Amp, Copilot/VS Code and others read it, and it ties the skill to no single harness. Claude
# Code does NOT read `.agents/skills/`; it needs a symlink from `.claude/skills` to
# `../.agents/skills`. This repository already carries that symlink at the project root.
#
# ## Why it includes `opencode`
#
# The provider block reaches opencode through `opencode.settings`, and a provider block with no
# opencode does nothing. The slot writes the settings and refuses to turn opencode on, so a consumer
# that forgets `kdn.opencode.enable` gets a silent no-op.
#
# An aspect has no `enable` option, so inclusion is the whole statement of intent: "this shell talks
# to a remote llama-server through opencode". `includes` puts both target modules into one
# evaluation, so this file writes ./opencode.nix's own options directly. den collapses the diamond,
# so a shell that also includes `opencode` itself still holds one wrapper. See ./jj.nix, which uses
# the same route to write `kdn.mcp.extraBackends`.
#
# DECISION TO REVISE: this is the one deliberate behaviour change against the slot. It also lets the
# aspect wire the API key itself (see below). The other route is no `includes` at all, plus a plain
# `opencode.settings` write and a warning when opencode is off. That route keeps the slot's exact
# behaviour and it keeps the footgun.
#
# ## The aspect wires the key; the slot left it to the consumer
#
# The provider block names `{env:KDN_LLM_API_KEY_<name>}`, so this aspect owns that environment
# variable's name. The slot still made the consumer write
# `kdn.opencode.wrapper.envFiles.KDN_LLM_API_KEY_<name>` by hand, and a typo there fails at run time
# with an empty key. This aspect writes the entry itself, from `apiKeyFile`. A consumer that names no
# key file gets no entry, exactly as before.
#
# ## The de-personalized port
#
# `baseURL` gave one homelab fully-qualified name as its example. The example here names a
# placeholder domain.
#
# ## The option path stays as the slot spells it
#
# The aspect is `llm-client`, because a den aspect name holds no dot. Its option path stays
# `kdn.llm.client.*`, exactly as the slot spells it. ./jj-fork.nix does the same: the aspect is
# `jj-fork` and the options are `kdn.jj.fork.*`. So a consumer moves one line and keeps its data.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The slot's `kdn.llm.client.enable` is gone. The
#    per-upstream `enable` flag stays: it selects a member of an attribute set, and an empty set is
#    already a no-op. See ./ca.nix.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ kdn, ... }:
{
  kdn.llm-client.includes = [ kdn.opencode ];

  kdn.llm-client.devenv =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.kdn.llm.client;

      enabledUpstreams = lib.filterAttrs (_: u: u.enable) cfg.upstreams;

      # The opencode provider ids of the enabled upstreams. The session plugin injects
      # `x-session-id` only for these, so a commercial upstream never sees the header.
      providerIds = map (u: u.name) (lib.attrValues enabledUpstreams);

      # An opencode plugin that tags every request to a LAN llama-server with the opencode
      # session id as `x-session-id`. llama-server's session-keyed save/restore (llama.cpp
      # PR #29738) reads that header and persists/resumes the conversation's KV state on
      # disk. Written into `.opencode/plugins/` by devenv, so opencode in the consumer
      # project auto-loads it.
      #
      # OpenCode 2 replaced the V1 `chat.headers` hook with the `model.request` session hook.
      # One hook per LAN provider keeps the header off a commercial upstream; the third
      # argument scopes the hook to that provider id, so the callback needs no lookup.
      sessionPlugin = ''
        import { Plugin } from "@opencode/plugin"

        // Generated by the kdn.llm-client aspect. The header names the LAN llama-server
        // session (see --slot-save-sessions on the server).
        const PROVIDERS = ${builtins.toJSON providerIds}

        export default Plugin.define({
          id: "kdn.llm.session-id",
          async setup(ctx) {
            for (const providerID of PROVIDERS) {
              await ctx.session.hook(
                "model.request",
                (event) => {
                  event.headers["x-session-id"] = event.sessionID
                },
                { providerID },
              )
            }
          },
        })
      '';

      # The environment variable that carries one upstream's key. The provider block references it,
      # and the opencode wrapper exports it, so both sides read this one function.
      keyVar = u: "KDN_LLM_API_KEY_${u.name}";

      # One opencode model entry from a hand-listed model. The shape is native OpenCode 2:
      # `limit`, `capabilities`, `body` (request-body fields) and a variant array. The same
      # entry is the *overlay* the discovery plugin spreads over a discovered id.
      toModelEntry =
        m:
        {
          name = m.name;
          limit = {
            inherit (m) context output;
          };
        }
        // lib.optionalAttrs m.reasoning {
          capabilities.reasoning.supported = true;
        }
        // lib.optionalAttrs (m.options != { }) {
          body = m.options;
        }
        // lib.optionalAttrs (m.variants != { }) {
          variants = lib.mapAttrsToList (id: body: { inherit id body; }) m.variants;
        };

      # The provider block of one upstream. It always carries the settings: discovery never
      # replaces the endpoint or the credential, and a config provider outranks a plugin one.
      # `models` stays out when discovery is on: the plugin below owns the id list then, so the
      # two owners never write the same key.
      toProvider = _: u: {
        provider.${u.name} = {
          npm = "@ai-sdk/openai-compatible";
          name = u.displayName;
          options = {
            baseURL = u.baseURL;
            apiKey = "{env:${keyVar u}}";
          };
        }
        // lib.optionalAttrs (!u.discovery.enable) {
          models = lib.mapAttrs (_: toModelEntry) u.models;
        };
      };

      # One local plugin that discovers the model list of every discovering upstream. OpenCode 2
      # removed the V1 `config` hook, so this is a provider transform: fetch the OpenAI-compatible
      # list once, build one `Model.Info` per id, and merge it into the provider's model set with
      # `editor.models.set`. A failed fetch still registers the overlay ids, so the shell works
      # offline; a 60 s timer re-fetches and calls `ctx.provider.reload()` on a change.
      # See /build/plugins/server (transforms, reload) in the OpenCode 2 docs.
      discoveryPluginText =
        let
          discovering = lib.filterAttrs (_: u: u.enable && u.discovery.enable) cfg.upstreams;
          payload = lib.mapAttrsToList (_: u: {
            provider = u.name;
            # `<baseURL>/models` is the OpenAI-compatible list. A consumer may override the
            # full URL with `discovery.url`.
            url = if u.discovery.url != "" then u.discovery.url else "${u.baseURL}/models";
            apiKeyEnv = keyVar u;
            overlay = lib.mapAttrs (_: toModelEntry) u.models;
          }) discovering;
        in
        if discovering == { } then
          ""
        else
          ''
            import { Model, Plugin, Provider } from "@opencode/plugin"

            // Generated by the kdn.llm-client aspect. One entry per discovering upstream: the
            // opencode provider key, the models URL, the credential variable for that fetch, and
            // the per-model overlay the Nix config supplies (name, limit, capabilities, body,
            // variants).
            //
            // OpenCode 2 replaced the V1 `config` hook with domain transforms. The provider block
            // already exists in `opencode.jsonc` and owns the endpoint and the credential; this
            // plugin adds the discovered ids to that provider with `editor.models.set`. The
            // server's `context_length` is the real served window (llama-swap renders it from the
            // model's `capabilities.context`), so the size needs no per-model client config.
            type Upstream = {
              provider: string
              url: string
              apiKeyEnv: string
              overlay: Record<string, Record<string, any>>
            }

            const UPSTREAMS: Upstream[] = ${builtins.toJSON payload}

            const OUTPUT_CAP = 8192
            const REFRESH_MS = 60_000

            const modelEntry = (providerID: any, id: string, served: unknown, overlay: any) => {
              const base: any = Model.Info.default(providerID, Model.ID.make(id))
              const model: any = { ...base, name: overlay.name ?? id }
              const context =
                overlay.limit?.context ??
                (typeof served === "number" && served > 0 ? served : base.limit?.context ?? 65536)
              const output = overlay.limit?.output ?? Math.min(OUTPUT_CAP, Math.floor(context / 4))
              model.limit = { ...base.limit, context, output }
              // `Model.Info.default` advertises image input; a llama-swap model is text unless the
              // Nix overlay says otherwise.
              model.capabilities = {
                ...base.capabilities,
                input: overlay.capabilities?.input ?? ["text"],
                ...(overlay.capabilities ?? {}),
              }
              if (overlay.body) model.body = { ...(base.body ?? {}), ...overlay.body }
              if (overlay.variants) model.variants = overlay.variants
              return model
            }

            const load = async (u: Upstream, providerID: any) => {
              const key = process.env[u.apiKeyEnv]
              const served = new Map<string, unknown>()
              try {
                const headers: Record<string, string> = {}
                if (key) headers.authorization = "Bearer " + key
                const res = await fetch(u.url, { headers })
                const body: any = await res.json()
                for (const m of body.data ?? []) served.set(m.id, m.context_length)
              } catch {
                // Offline or unreachable: fall back to the overlay alone.
              }
              for (const id of Object.keys(u.overlay ?? {})) {
                if (!served.has(id)) served.set(id, undefined)
              }
              return [...served.entries()].map(([id, ctxLength]) =>
                modelEntry(providerID, id, ctxLength, u.overlay?.[id] ?? {}),
              )
            }

            export default Plugin.define({
              id: "kdn.llm.models",
              async setup(ctx) {
                const source = new Map<string, any[]>()
                for (const u of UPSTREAMS) {
                  const providerID = Provider.ID.make(u.provider)
                  source.set(u.provider, await load(u, providerID))
                  await ctx.provider.transform((editor) => {
                    // `editor.get` misses a config-declared provider, so guard with `add`.
                    // `models.set` merges with the config models and never deletes them.
                    if (!editor.get(providerID)) {
                      editor.add({
                        info: { ...Provider.Info.empty(providerID), activation: "enabled" },
                        models: [],
                      })
                    }
                    const kept = editor.get(providerID)?.models
                    const keptModels = kept ? [...kept.values()] : []
                    const ids = new Set(keptModels.map((m) => m.id))
                    const next = source.get(u.provider) ?? []
                    editor.models.set(providerID, [
                      ...keptModels,
                      ...next.filter((m) => !ids.has(m.id)),
                    ])
                  })
                }

                // A new alias appears without a shell restart. `reload()` replays every
                // transform registered so far, so the callback must stay cheap and repeatable.
                const timer = setInterval(async () => {
                  let changed = false
                  for (const u of UPSTREAMS) {
                    const providerID = Provider.ID.make(u.provider)
                    const next = await load(u, providerID)
                    const prev = source.get(u.provider) ?? []
                    if (JSON.stringify(next) === JSON.stringify(prev)) continue
                    source.set(u.provider, next)
                    changed = true
                  }
                  if (changed) await ctx.provider.reload()
                }, REFRESH_MS)
                return () => clearInterval(timer)
              },
            })
          '';

      upstreamSubmodule =
        { name, ... }:
        {
          options.enable = lib.mkEnableOption "this upstream in opencode";

          # The provider key. It defaults to the attribute name, so a consumer writes
          # `upstreams.moss` and gets `provider.moss`, and it can still name something else.
          options.name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = ''
              Provider key of this upstream. It also names the API-key environment variable, as
              `KDN_LLM_API_KEY_<name>`, so it must be a valid shell identifier. The assertion below
              states that rule.
            '';
          };

          options.displayName = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "The provider name that opencode shows.";
          };

          options.baseURL = lib.mkOption {
            type = lib.types.str;
            example = "https://llm.example.invalid/v1";
            description = ''
              Base URL of the remote llama-server, through its own TLS proxy.

              The example names a placeholder domain. A consumer writes its own endpoint.
            '';
          };

          options.caCertFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to the self-signed PEM public certificate of the endpoint. It is informational:
              the consumer trusts the certificate system-wide, and no aspect injects it per upstream.
              `null` means the endpoint carries a publicly trusted chain.
            '';
          };

          options.apiKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to a file that holds the API key, as one line. The provider references
              `{env:KDN_LLM_API_KEY_<name>}`, and this aspect loads the file into that variable
              through the opencode wrapper. `null` means the endpoint needs no key.

              The slot made the consumer write the wrapper entry by hand. This aspect writes it.
            '';
          };

          options.models = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.name = lib.mkOption {
                  type = lib.types.str;
                  description = "The model name that opencode shows.";
                };
                options.context = lib.mkOption {
                  type = lib.types.int;
                  default = 65536;
                  description = "Context window limit, for opencode.";
                };
                options.output = lib.mkOption {
                  type = lib.types.int;
                  default = 8192;
                  description = "Output token limit, for opencode.";
                };
                options.reasoning = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = ''
                    Mark this model as reasoning-capable in opencode, so it parses the model's
                    thinking output. It does not by itself turn thinking on; set `options` for that.
                  '';
                };
                options.options = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                  description = ''
                    Extra request-body fields that opencode sends verbatim for this model. opencode
                    merges them into the chat-completions body, so they reach llama-server. Use it
                    to turn on server-side thinking, for example:

                    ```nix
                    options = { chat_template_kwargs = { enable_thinking = true; }; };
                    ```

                    Verified 2026-10-06: a per-model `options` object reaches the server unchanged.
                  '';
                };
                options.variants = lib.mkOption {
                  type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
                  default = { };
                  description = ''
                    opencode model variants: a variant name to a set of request-body fields that
                    override this model's `options` when the variant is selected. Use it to expose a
                    thinking matrix on one model, for example:

                    ```nix
                    variants.low = {
                      chat_template_kwargs = { enable_thinking = true; reasoning_effort = "low"; };
                    };
                    ```

                    In the TUI, select the model and cycle the variant (the `variant_cycle`
                    keybind). The model's own `options` are the default variant.
                  '';
                };
              }
            );
            default = { };
            description = "The models this endpoint serves, as opencode provider entries.";
          };

          options.discovery = {
            enable = lib.mkEnableOption ''
              auto-discovery of this endpoint's models. When on, the provider block
              carries no hand-listed `models`; a generated local opencode plugin fetches
              the model list at load and merges it in. The `models` above then act as a
              per-model metadata overlay (context, output, reasoning, options, variants)
              applied to the discovered ids
            '';

            url = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = ''
                Full URL of the OpenAI-compatible model list. The default (empty) resolves
                to `<baseURL>/models`, which is what llama-server, vLLM and LM Studio serve.
                Set it to point at a non-standard path.
              '';
            };
          };
        };
    in
    {
      imports = [ ../common/source-repo.nix ];

      options.kdn.llm.client.upstreams = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule upstreamSubmodule);
        default = { };
        description = ''
          Remote llama-server endpoints to expose as opencode providers, keyed by name.

          An empty set adds no provider, so inclusion alone gives a plain opencode shell.
        '';
      };

      config = {
        # A provider key becomes part of an environment variable name, so it must hold shell
        # identifier characters only. A hyphen or a dot would make the wrapper's `export` line a
        # syntax error, and the shell script fails at run time instead of at evaluation time.
        assertions = lib.mapAttrsToList (_: u: {
          assertion = lib.match "^[A-Za-z_][A-Za-z0-9_]*$" u.name != null;
          message =
            "kdn.llm.client.upstreams.${u.name}.name must be a valid shell identifier, "
            + "because it names the ${keyVar u} environment variable.";
        }) enabledUpstreams;

        # One provider block per enabled upstream. The write goes to ./opencode.nix's own option, so
        # the permission baseline of that aspect still applies.
        kdn.opencode.settings = lib.mkMerge (lib.mapAttrsToList toProvider enabledUpstreams);

        # One wrapper environment entry per upstream that names a key file. The wrapper reads the
        # file at run time, so no store path holds the key.
        kdn.opencode.wrapper.envFiles = lib.listToAttrs (
          lib.mapAttrsToList (_: u: lib.nameValuePair (keyVar u) u.apiKeyFile) (
            lib.filterAttrs (_: u: u.apiKeyFile != null) enabledUpstreams
          )
        );

        # The session-id plugin for the LAN upstreams. Written into the project's
        # `.opencode/plugins/`, which opencode auto-loads.
        files = lib.mkMerge [
          (lib.mkIf (enabledUpstreams != { }) {
            ".opencode/plugins/kdn-llm-session-id.ts".text = sessionPlugin;
          })
          (lib.optionalAttrs (discoveryPluginText != "") {
            ".opencode/plugins/kdn-models-discovery.ts".text = discoveryPluginText;
          })
          # The skill describes the endpoint this aspect already configures, so a consumer finds it
          # useful whatever its upstreams hold. Install it unconditionally, except in the source
          # repository, which tracks the file itself and needs no copy.
          (lib.mkIf (!config.kdn.isSourceRepo) {
            ".agents/skills/kdn-llms/SKILL.md".source = ../../../.agents/skills/kdn-llms/SKILL.md;
          })
        ];
      };
    };

  # The home-manager route. It writes the same skill file, so a home-manager config gets the skill
  # too. The aspect's opencode provider lives in the devenv shell, so this target holds the skill
  # alone. No `enable` option and no entity argument, per the header rules.
  kdn.llm-client.homeManager =
    {
      config,
      lib,
      ...
    }:
    {
      imports = [ ../common/source-repo.nix ];
      home.file = lib.mkIf (!config.kdn.isSourceRepo) {
        ".agents/skills/kdn-llms/SKILL.md".source = ../../../.agents/skills/kdn-llms/SKILL.md;
      };
    };
}
