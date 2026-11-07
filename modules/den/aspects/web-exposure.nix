# The `web-exposure` aspect: a per-host Caddy reverse proxy on the default HTTPS
# port that serves each service on its own subdomain, plus an index page on the
# bare host name.
#
# ## Why subdomains
#
# A service at its own subdomain root is served unchanged: an OpenAI/llama-swap
# backend keeps its absolute `/ui` and `/v1` paths, and Prometheus needs no
# `--web.external-url` prefix. Path-prefix routing (handle_path) broke those
# absolute links, so each service gets `https://<service>.<host>/`.
#
# ## DNS and certificates
#
# The subdomain names resolve through NetBird DNS zones (see
# docs/netbird-dns-zones.md). The TLS leaf `kdn.certificates.certs.<certName>`
# must carry every subdomain in its SANs; one leaf covers the whole host, and the
# key reaches Caddy through `LoadCredential`, so no store path holds it.
#
# ## The border router
#
# The firewall opens 80/443 only on `firewallInterfaces` (default `nb-priv`), so
# etra — the border router — never exposes these on the WAN.
#
# ## The three rules this tree holds for every aspect
#
# 1. No entity argument. 2. No reachable `enable` option — inclusion, plus a
# non-null `domain`, is the switch. 3. No custom module argument.
{ ... }:
{
  kdn.web-exposure.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.web.exposure;
      web = import ../../../lib/web.nix { inherit lib; };

      cert = config.kdn.certificates.certs.${cfg.certName};

      # One TLS line reused by every vhost of this host: the single leaf carries
      # all the SANs, and Caddy picks it per SNI.
      tlsLine = "tls ${cert.certPath} /run/credentials/caddy.service/web-key";

      indexDir = pkgs.writeTextDir "index.html" (
        web.mkIndexHtml {
          inherit (cfg) title;
          links = lib.mapAttrsToList (name: s: {
            href = "https://${s.subdomain}/";
            label = if s.label == "" then name else s.label;
          }) cfg.services;
        }
      );

      indexVhost = {
        inherit (cfg) listenAddresses;
        serverAliases = [ ];
        extraConfig = ''
          ${tlsLine}
          handle {
          	root * ${indexDir}
          	file_server
          }
        '';
      };

      serviceVhosts = lib.mapAttrs' (
        _: s:
        lib.nameValuePair s.subdomain {
          inherit (cfg) listenAddresses;
          serverAliases = [ ];
          extraConfig = ''
            ${tlsLine}
            reverse_proxy ${s.upstream}
          '';
        }
      ) cfg.services;
    in
    {
      options.kdn.web.exposure = {
        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Bare host FQDN that serves the index. `null` makes the aspect a no-op.";
        };
        certName = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Key into `kdn.certificates.certs` for the TLS leaf (must carry every subdomain in its SANs).";
        };
        title = lib.mkOption {
          type = lib.types.str;
          default = config.kdn.hostName;
          description = "The index page heading.";
        };
        listenAddresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0" ];
        };
        firewallInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "nb-priv" ];
          description = "Interfaces on which 80/443 open. Never WAN on the border router.";
        };
        services = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                subdomain = lib.mkOption {
                  type = lib.types.str;
                  description = "Full FQDN served for this service, e.g. litellm.etra.priv.nb.net.int.kdn.im.";
                };
                upstream = lib.mkOption {
                  type = lib.types.str;
                  description = "host:port Caddy proxies to, e.g. 127.0.0.1:4000.";
                };
                label = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Index-page link text. `\"\"` means the service name.";
                };
              };
            }
          );
          default = { };
          description = "Services, keyed by a short name; each gets its own subdomain vhost.";
        };
      };

      config = lib.mkIf (cfg.domain != null) (lib.mkMerge [
        { services.caddy.enable = true; }

        {
          systemd.services.caddy.serviceConfig.LoadCredential = [
            "web-key:${cert.keyPath}"
          ];
          # The key is a sops secret; start Caddy only after it is decrypted.
          # A config reload does NOT refresh the LoadCredential key, so restart
          # (not reload) whenever the certificate file changes — otherwise a new
          # cert meets the old key and TLS fails with "private key does not match".
          systemd.services.caddy = {
            after = [ "sops-install-secrets.service" ];
            wants = [ "sops-install-secrets.service" ];
            restartTriggers = [ cert.certPath ];
          };

          services.caddy.virtualHosts = {
            ${cfg.domain} = indexVhost;
          }
          // serviceVhosts;

          networking.firewall.interfaces = lib.genAttrs cfg.firewallInterfaces (_: {
            allowedTCPPorts = [
              80
              443
            ];
          });
        }
      ]);
    };
}
