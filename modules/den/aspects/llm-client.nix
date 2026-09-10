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
# ## The class
#
# `devenv` only. The slot emits one target, `devenv`, so this aspect declares one class.
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

      # The environment variable that carries one upstream's key. The provider block references it,
      # and the opencode wrapper exports it, so both sides read this one function.
      keyVar = u: "KDN_LLM_API_KEY_${u.name}";

      # One provider block per upstream.
      toProvider = _: u: {
        provider.${u.name} = {
          npm = "@ai-sdk/openai-compatible";
          name = u.displayName;
          options = {
            baseURL = u.baseURL;
            apiKey = "{env:${keyVar u}}";
          };
          models = lib.mapAttrs (_: m: {
            name = m.name;
            limit.context = m.context;
            limit.output = m.output;
          }) u.models;
        };
      };

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

              The slot's example named one real host of a private network. The example here names a
              placeholder domain.
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
              }
            );
            default = { };
            description = "The models this endpoint serves, as opencode provider entries.";
          };
        };
    in
    {
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
      };
    };
}
