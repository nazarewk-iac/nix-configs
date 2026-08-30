# OpenCode DSML compatibility proxy slot.
#
# Runs one or more `opencode-compat-proxy` instances. Each instance is a thin
# FastAPI layer that sits between OpenCode and an LLM backend, translating
# DeepSeek DSML / Qwen XML raw tool calls into OpenAI-compatible `tool_calls`
# JSON on the stream. It forwards the client's `Authorization` header through
# unchanged, so a Requesty key supplied by OpenCode flows straight to the
# upstream with no server-side secret needed.
#
# The `instances` attrset lets a host run several proxies at once — for example
# one pointed at the Requesty router and one pointed at a local llama-swap model
# (`http://127.0.0.1:39703`) — each on its own port.
#
# Per-instance `forwardClientAuth` enables forwarding the client Authorization
# header on the streaming path (a patch to proxy.py). See packages/
# opencode-compat-proxy/patches/forward-auth.patch.
#
# This slot is STANDALONE. It uses only `lib`, `pkgs`, `config`, and plain
# NixOS / devenv options (systemd.services.*, networking.firewall.*,
# processes.*). It never references or assigns an option declared by
# modules/universal/ or modules/meta/. See .agents/rules/slots-standalone.md.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.llm.proxy;

  enabledInstances = lib.filterAttrs (_: i: i.enable) cfg.instances;

  # Build a systemd service for one instance.
  toService =
    name: inst:
    let
      svcName = "kdn-llm-proxy-${name}";
      exec = "${lib.getExe inst.package}";
    in
    {
      "${svcName}" = {
        description = "OpenCode DSML compatibility proxy → ${inst.upstreamUrl}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        environment = {
          UPSTREAM_URL = inst.upstreamUrl;
          PROXY_HOST = inst.host;
          PROXY_PORT = toString inst.port;
          # 1/true/yes forwards the client's Authorization header to the
          # upstream on the streaming path too (patched into proxy.py). The
          # non-streaming path already forwards it.
          FORWARD_AUTHORIZATION = if inst.forwardClientAuth then "true" else "";
        };

        serviceConfig = {
          ExecStart = exec;
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

  toDevenvProcess = name: inst: {
    "proxy-${name}".exec = ''
      UPSTREAM_URL=${inst.upstreamUrl} PROXY_HOST=${inst.host} PROXY_PORT=${toString inst.port} FORWARD_AUTHORIZATION=${
        if inst.forwardClientAuth then "true" else ""
      } ${lib.getExe inst.package}
    '';
  };
in
{
  options.kdn.llm.proxy = {
    enable = lib.mkEnableOption "OpenCode DSML compatibility proxy (ladiossoop5star/opencode_compat_proxy)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kdn.opencode-compat-proxy;
      description = "opencode-compat-proxy package to use.";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { lib, ... }:
          {
            options = {
              enable = lib.mkEnableOption "this proxy instance";

              upstreamUrl = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Upstream LLM backend base URL (the proxy appends the request
                  path). Examples: Requesty "https://router.requesty.ai" or a
                  local llama-swap "http://127.0.0.1:39703".

                  Note: the proxy passes the client Authorization header through
                  unchanged, so point it only at backends that should receive
                  that client's key.
                '';
              };

              host = lib.mkOption {
                type = lib.types.str;
                default = "127.0.0.1";
                description = "Address the proxy binds.";
              };

              port = lib.mkOption {
                type = lib.types.port;
                default = 9526;
                description = "Port the proxy listens on.";
              };

              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Open this port in the nixos firewall.";
              };

              forwardClientAuth = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Forward the client's Authorization header to the upstream on
                  the streaming chat path. The original proxy only forwards it
                  on non-streaming requests; our patch extends that to streaming
                  when this is true. Enable when the upstream (e.g. Requesty)
                  authenticates via the client's API key. Leave false for a
                  local auth-less backend.
                '';
              };

              package = lib.mkOption {
                type = lib.types.package;
                default = cfg.package;
                description = "opencode-compat-proxy package for this instance (defaults to the slot's package).";
              };
            };
          }
        )
      );
      default = { };
      description = "Proxy instances to run, each pointing at one upstream.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixos = {
      systemd.services = lib.mkMerge (lib.mapAttrsToList toService enabledInstances);

      networking.firewall.allowedTCPPorts =
        lib.mkIf (lib.any (inst: inst.openFirewall) (lib.attrValues enabledInstances))
          (
            lib.concatMap (inst: lib.optionals inst.openFirewall [ inst.port ]) (
              lib.attrValues enabledInstances
            )
          );
    };

    devenv = lib.mkIf (enabledInstances != { }) {
      processes = lib.mkMerge (lib.mapAttrsToList toDevenvProcess enabledInstances);
      packages = [ cfg.package ];
    };
  };
}
