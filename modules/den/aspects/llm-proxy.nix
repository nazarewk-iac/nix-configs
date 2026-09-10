# The `llm.proxy` slot, as a den aspect. It ports `modules/slots/llm/proxy/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs one or more `opencode-compat-proxy` instances. Each instance is a thin FastAPI layer
# between opencode and one LLM backend. It translates a DeepSeek DSML or a Qwen XML raw tool call
# into OpenAI-compatible `tool_calls` JSON on the stream, and it passes every other path through.
#
# Each instance names its own upstream and its own port, so one host runs several at once: for
# example one in front of a commercial router API and one in front of a local llama-server.
#
# `forwardClientAuth` forwards the client's `Authorization` header on the streaming path too. The
# original proxy forwards it on the non-streaming path only, and a patch in this repository extends
# it. See `packages/opencode-compat-proxy/patches/forward-auth.patch`.
#
# ## The classes — the first aspect in this tree with two
#
# `nixos` **and** `devenv`. The slot emits both targets, so this aspect declares both classes. A
# NixOS host gets one systemd unit per instance; a devenv shell gets one `processes` entry per
# instance and the package on PATH.
#
# The two classes share one option set. The declarations live in one module in this file's `let`, and
# both class modules import it, exactly as ./devenv-cli.nix shares one `systemModule` between `nixos`
# and `darwin`. Each class is a separate evaluation, so one option path exists in both with no clash.
#
# No slot in this family emits `darwin`, `home` or `users`.
#
# ## The option path stays as the slot spells it
#
# The aspect is `llm-proxy`, because a den aspect name holds no dot. Its option path stays
# `kdn.llm.proxy.*`. ./jj-fork.nix does the same: the aspect is `jj-fork` and the options are
# `kdn.jj.fork.*`.
#
# ## Nothing personal to neutralize
#
# The slot named two upstream URLs in one description: a commercial router API and a loopback
# address. Neither one is personal data, and both stay, because they show the two real shapes of an
# upstream.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The slot's `kdn.llm.proxy.enable` is gone. The
#    per-instance `enable` flag stays: it selects a member of an attribute set, and an empty set is
#    already a no-op. See ./ca.nix.
# 3. **No custom module argument.** Both target modules below take `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The shared option declarations. Both classes import this one module, so the two class trees hold
  # one identical option set and no declaration is ever copied.
  optionsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.llm.proxy;

      instanceSubmodule = {
        options.enable = lib.mkEnableOption "this proxy instance";

        options.upstreamUrl = lib.mkOption {
          type = lib.types.str;
          example = "http://127.0.0.1:39703";
          description = ''
            Base URL of the upstream LLM backend. The proxy appends the request path to it. A
            commercial router API and a local llama-server are both valid, for example
            `https://router.requesty.ai` or `http://127.0.0.1:39703`.

            The proxy passes the client's `Authorization` header through unchanged, so name only a
            backend that may receive that client's key.
          '';
        };

        options.host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address the proxy binds.";
        };

        options.port = lib.mkOption {
          type = lib.types.port;
          default = 9526;
          description = "Port the proxy listens on.";
        };

        options.openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Open this port in the NixOS firewall. It applies to the `nixos` class only; the `devenv`
            class has no firewall.
          '';
        };

        options.forwardClientAuth = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Forward the client's `Authorization` header to the upstream on the streaming chat path.
            The original proxy forwards it on a non-streaming request only, and this repository's own
            patch extends it when this option is true.

            Turn it on when the upstream authenticates with the client's own API key. Keep it off for
            a local backend that needs no key.
          '';
        };

        options.package = lib.mkOption {
          type = lib.types.package;
          default = cfg.package;
          defaultText = lib.literalExpression "config.kdn.llm.proxy.package";
          description = "The proxy package of this instance. It defaults to the aspect's package.";
        };
      };
    in
    {
      options.kdn.llm.proxy.package = lib.mkOption {
        type = lib.types.package;
        # A plain `callPackage` route, with no overlay. The slot reads
        # `pkgs.kdn.opencode-compat-proxy`, so a consumer must add this repository's `packages`
        # overlay first. A relative path needs no overlay. ./jj.nix carries the same pattern.
        default = pkgs.callPackage ../../../packages/opencode-compat-proxy { };
        defaultText = lib.literalExpression "pkgs.callPackage ../../../packages/opencode-compat-proxy { }";
        description = "The default `opencode-compat-proxy` package that every instance uses.";
      };

      options.kdn.llm.proxy.instances = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule instanceSubmodule);
        default = { };
        description = ''
          The proxy instances to run, each one in front of one upstream.

          An empty set runs nothing, so inclusion alone changes no behaviour.
        '';
      };
    };

  # The enabled instance set of one evaluation. Both classes read it.
  enabledOf = lib: config: lib.filterAttrs (_: i: i.enable) config.kdn.llm.proxy.instances;

  # The environment both classes pass to the proxy. One function keeps the two in step.
  #
  # `FORWARD_AUTHORIZATION` is `"true"` or the empty string. The proxy reads `1`, `true` or `yes` as
  # true, so an empty value is the off state.
  envOf = inst: {
    UPSTREAM_URL = inst.upstreamUrl;
    PROXY_HOST = inst.host;
    PROXY_PORT = toString inst.port;
    FORWARD_AUTHORIZATION = if inst.forwardClientAuth then "true" else "";
  };
in
{
  kdn.llm-proxy.nixos =
    {
      config,
      lib,
      ...
    }:
    let
      enabledInstances = enabledOf lib config;

      # One systemd unit per instance.
      toService = name: inst: {
        "kdn-llm-proxy-${name}" = {
          description = "OpenCode DSML compat proxy to ${inst.upstreamUrl}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment = envOf inst;

          serviceConfig = {
            ExecStart = lib.getExe inst.package;
            Restart = "always";
            RestartSec = "5s";
            DynamicUser = true;
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
          };
        };
      };
    in
    {
      imports = [ optionsModule ];

      config = {
        systemd.services = lib.mkMerge (lib.mapAttrsToList toService enabledInstances);

        networking.firewall.allowedTCPPorts = lib.concatMap (
          inst: lib.optionals inst.openFirewall [ inst.port ]
        ) (lib.attrValues enabledInstances);
      };
    };

  kdn.llm-proxy.devenv =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.kdn.llm.proxy;
      enabledInstances = enabledOf lib config;

      # One devenv process per instance. Every value goes through `escapeShellArg`, so a URL with a
      # shell metacharacter cannot break the line. The slot interpolated the values raw.
      toProcess = name: inst: {
        "proxy-${name}".exec = lib.concatStringsSep " " (
          lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") (envOf inst)
          ++ [ (lib.getExe inst.package) ]
        );
      };
    in
    {
      imports = [ optionsModule ];

      config = {
        processes = lib.mkMerge (lib.mapAttrsToList toProcess enabledInstances);

        packages = [ cfg.package ];

        # `openFirewall` belongs to the `nixos` class. A devenv shell opens no port, so a definition
        # here would be silently ignored.
        warnings = lib.mapAttrsToList (
          name: _: "kdn.llm.proxy.instances.${name}.openFirewall has no effect in a devenv shell."
        ) (lib.filterAttrs (_: i: i.openFirewall) enabledInstances);

        # The aspect's own smoke test. It stays offline: the sandbox has no network, so nothing here
        # starts the proxy or reaches an upstream.
        enterTest = ''
          echo "• llm-proxy: the proxy binary is executable" >&2
          test -x ${lib.getExe cfg.package}
        '';
      };
    };
}
