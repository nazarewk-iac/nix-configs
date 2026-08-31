# LAN LLM client slot.
#
# Adds opencode providers for one or more LAN llama-servers exposed over HTTPS
# (see the sibling `kdn.llm.local` server slot). Each upstream is keyed by
# name in `kdn.llm.client.upstreams.<name>`. For each upstream the slot:
#   - writes a `provider.<name>` into opencode's settings
#   - ships an `opencode-kdn-<name>` wrapper that injects the API key and
#     points NODE_EXTRA_CA_CERTS at the endpoint's self-signed cert before
#     exec'ing opencode
#
# It does NOT enable opencode itself — the consumer enables `kdn.opencode`
# (which turns opencode on and supplies the default permission skeleton). This
# slot only adds `provider.<name>` settings and wrapper packages.
#
# The consumer is a thin passthrough: it only supplies, per upstream, the
# required info (baseURL, caCertFile, apiKeyFile, models).
#
# This slot is STANDALONE. It must not reference or assign any option declared
# by modules/universal/ or modules/meta/. It uses only `lib`, `pkgs`, `config`,
# and plain devenv options (opencode.settings, packages). See
# .agents/rules/slots-standalone.md.
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.llm.client;

  enabledUpstreams = lib.filterAttrs (_: u: u.enable) cfg.upstreams;

  # Build one provider entry for an upstream.
  toProvider = _: u: {
    provider.${u.name} = {
      npm = "@ai-sdk/openai-compatible";
      name = u.displayName;
      options = {
        baseURL = u.baseURL;
        apiKey = "{env:KDN_LLM_API_KEY_${u.name}}";
      };
      models =
        lib.mapAttrs (_: m: {
          name = m.name;
          limit.context = m.context;
          limit.output = m.output;
        })
        u.models;
    };
  };

  # Build the key-injecting wrapper for an upstream: run `opencode-kdn-<name>`.
  toWrapper = _: u:
    pkgs.writeShellScriptBin "opencode-kdn-${u.name}" ''
      set -euo pipefail
      ${lib.optionalString (u.apiKeyFile != null) ''
        export KDN_LLM_API_KEY_${u.name}="$(cat ${u.apiKeyFile})"
      ''}
      ${lib.optionalString (u.caCertFile != null) ''
        export NODE_EXTRA_CA_CERTS="${u.caCertFile}"
      ''}
      exec ${lib.getExe pkgs.opencode} "$@"
    '';
in {
  options.kdn.llm.client = {
    enable = lib.mkEnableOption "LAN LLM client (opencode pointed at HTTPS llama-servers)";

    upstreams = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule (
        {name, ...}: {
          options = {
            enable = lib.mkEnableOption "this upstream in opencode";

            # Canonical provider/wrapper key; defaults to the attr name so a
            # consumer writes `upstreams.brys` and gets `provider.brys` +
            # `opencode-kdn-brys`, but can still override.
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Provider/wrapper key for this upstream.";
            };

            displayName = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Human-readable provider name shown in opencode.";
            };

            baseURL = lib.mkOption {
              type = lib.types.str;
              example = "https://brys.lan.etra.net.int.kdn.im/v1";
              description = "Base URL of the LAN llama-server (through its TLS proxy).";
            };

            # Trusted CA certificate. null => opencode trusts the system store only.
            caCertFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to the self-signed PEM public certificate of the endpoint,
                used by the opencode-kdn-<name> wrapper via NODE_EXTRA_CA_CERTS so
                opencode's Node runtime trusts it. null does not add any CA.
              '';
            };

            # API key. null => the endpoint needs no key.
            apiKeyFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to a file holding the API key (one line). The
                opencode-kdn-<name> wrapper loads it as KDN_LLM_API_KEY_<name> so
                the provider can authenticate. null means the endpoint needs no key.
              '';
            };

            models = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule (
                  {...}: {
                    options.name = lib.mkOption {
                      type = lib.types.str;
                      description = "Human-readable model name shown in opencode.";
                    };
                    options.context = lib.mkOption {
                      type = lib.types.int;
                      default = 65536;
                      description = "Context window limit for opencode.";
                    };
                    options.output = lib.mkOption {
                      type = lib.types.int;
                      default = 8192;
                      description = "Output token limit for opencode.";
                    };
                  }
                )
              );
              default = {};
              description = "Models exposed by this LAN endpoint, as opencode provider entries.";
            };
          };
        }
      ));
      default = {};
      description = "Upstream LAN llama-servers to expose as opencode providers, keyed by name.";
    };
  };

  config = lib.mkIf cfg.enable {
    devenv = {
      # Merge provider.<name> for every enabled upstream into opencode's
      # settings. The consumer must enable `kdn.opencode` (which turns opencode
      # on and supplies the default permission skeleton); this slot does not
      # enable opencode itself.
      opencode.settings = lib.mkMerge (lib.mapAttrsToList toProvider enabledUpstreams);

      # One key-injecting wrapper per enabled upstream.
      packages = lib.mapAttrsToList toWrapper enabledUpstreams;
    };
  };
}
