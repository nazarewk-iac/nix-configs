# LAN LLM client slot.
#
# Adds opencode providers for one or more LAN llama-servers exposed over HTTPS
# (see the sibling `kdn.llm.local` server slot). Each upstream is keyed by
# name in `kdn.llm.client.upstreams.<name>` and the slot writes a
# `provider.<name>` into opencode's settings (baseURL, apiKey {env:...},
# models). It ships no per-upstream wrapper: key injection is delegated to the
# single `opencode-kdn` wrapper via `kdn.opencode.envFile`, and self-signed CA
# trust is handled system-wide (security.pki).
#
# It does NOT enable opencode itself — the consumer enables `kdn.opencode`
# (which turns opencode on, supplies the default permission skeleton, and the
# `opencode-kdn` wrapper). This slot only adds `provider.<name>` settings.
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

            # Trusted CA certificate (informational for the consumer). null => opencode
            # trusts the system store only; with a self-signed endpoint, the host wires
            # this via security.pki.certificateFiles (system-wide) instead.
            caCertFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to the self-signed PEM public certificate of the endpoint.
                Informational: the consumer trusts it system-wide via
                security.pki.certificateFiles (self-signed CA is not injected
                per-upstream). null means the endpoint uses a publicly-trusted
                cert chain.
              '';
            };

            # API key. The consumer injects it into opencode via
            # kdn.opencode.envFile. null => the endpoint needs no key.
            apiKeyFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to a file holding the API key (one line). The provider uses
                apiKey {env:KDN_LLM_API_KEY_<name>}; the consumer loads this file
                into that var via kdn.opencode.envFile. null means the endpoint
                needs no key.
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
      # on and supplies the single `opencode-kdn` wrapper); this slot does not
      # enable opencode itself nor ship per-upstream wrappers — key
      # injection for each upstream is done via kdn.opencode.envFile.
      opencode.settings = lib.mkMerge (lib.mapAttrsToList toProvider enabledUpstreams);
    };
  };
}
