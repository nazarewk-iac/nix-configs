# Local LLM client slot.
#
# Generic consumer of a LAN-exposed local/remote llama-server (see the sibling
# `kdn.llm.local` server slot). It trusts the endpoint's self-signed certificate
# and injects an API key, then configures whatever consumes it (NixOS system CA
# trust; a devenv opencode provider bound to the endpoint).
#
# It is deliberately BARE and generic: no brys, no domain, no any specific
# endpoint. The consuming host supplies every input:
#   - baseURL     (e.g. https://brys.lan.etra.net.int.kdn.im)
#   - caCertFile  (path to the endpoint's self-signed public cert)
#   - apiKeyFile  (path to a text file holding the API key)
#   - models      (name -> displayName/limits for the opencode provider)
#
# This slot is STANDALONE. It must not reference or assign any option declared
# by modules/universal/ or modules/meta/. It uses only `lib`, `pkgs`, `config`,
# and plain nixpkgs options. See .agents/rules/slots-standalone.md.
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.llm.client;
in {
  options.kdn.llm.client = {
    enable = lib.mkEnableOption "local LLM client (LAN llama-server consumer)";

    baseURL = lib.mkOption {
      type = lib.types.str;
      example = "https://brys.lan.etra.net.int.kdn.im/v1";
      description = "Base URL of the LAN llama-server (through its TLS proxy).";
    };

    caCertFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the self-signed PEM public certificate of the LAN endpoint, to
        trust. null does not install any CA.
      '';
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file holding the API key (one line). Devenv maps it to
        KDN_LLM_API_KEY so an @ai-sdk/openai-compatible provider can authenticate.
        null means the endpoint needs no key.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          {...}: {
            options.displayName = lib.mkOption {
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
      description = "Models exposed by the LAN endpoint, as opencode provider entries.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixos = {...}: {
      # Trust the endpoint's self-signed cert system-wide so curl / HTTPS
      # clients on this host accept it.
      security.pki.certificateFiles = lib.optional (cfg.caCertFile != null) cfg.caCertFile;
    };

    devenv = {...}: let
      keyEnv =
        if cfg.apiKeyFile != null
        then "\"$(cat ${cfg.apiKeyFile})\""
        else "";
    in {
      # A wrapper that injects KDN_LLM_API_KEY from the file and points
      # NODE at the self-signed CA before exec'ing opencode, so the
      # @ai-sdk/openai-compatible provider authenticates and the TLS chain
      # verifies. Run `opencode-kdn-lan` inside the devenv shell.
      packages = [
        (pkgs.writeShellScriptBin "opencode-kdn-lan" ''
          set -euo pipefail
          export KDN_LLM_API_KEY="${keyEnv}"
          if [ -n "${cfg.caCertFile}" ]; then
            export NODE_EXTRA_CA_CERTS="${cfg.caCertFile}"
          fi
          exec ${pkgs.opencode}/bin/opencode "$@"
        '')
      ];

      opencode.settings = {
        provider.lan = {
          npm = "@ai-sdk/openai-compatible";
          name = "Local LLM (LAN llama-server)";
          options = {
            baseURL = cfg.baseURL;
            apiKey = "{env:KDN_LLM_API_KEY}";
          };
          models =
            lib.mapAttrs (_: m: {
              name = m.displayName;
              limit.context = m.context;
              limit.output = m.output;
            })
            cfg.models;
        };
      };
    };
  };
}
