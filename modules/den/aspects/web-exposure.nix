# The `web-exposure` aspect: one Caddy reverse proxy on a host's default HTTPS
# port, serving its HTTP services under path prefixes with an index page at `/`.
#
# ## Why it exists
#
# It is for a host that runs services but has no other Caddy vhost (etra runs the
# LiteLLM gateway and a Prometheus). A host that serves llama-swap already gets a
# vhost from the `llm` aspect, which renders the same shape with `lib/web.nix`.
#
# ## Certificates and the border router
#
# The TLS leaf comes from `kdn.certificates.certs.<certName>` (an internal-CA
# leaf); the key is handed to Caddy with `LoadCredential`, so no store path holds
# it. The firewall opens 80/443 ONLY on `firewallInterfaces` (default `nb-priv`):
# etra is the border router, so a global `allowedTCPPorts` would expose the
# unauthenticated metrics and gateway to the WAN.
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

      indexDir = pkgs.writeTextDir "index.html" (
        web.mkIndexHtml {
          inherit (cfg) title;
          links = lib.mapAttrsToList (path: r: {
            inherit path;
            label = if r.label == "" then lib.removePrefix "/" path else r.label;
          }) cfg.routes;
        }
      );

      routes = web.mkCaddyRoutes {
        indexPath = indexDir;
        inherit (cfg) routes;
      };
    in
    {
      options.kdn.web.exposure = {
        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Primary vhost name. `null` makes the aspect a no-op.";
        };
        certName = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Key into `kdn.certificates.certs` for the TLS leaf.";
        };
        title = lib.mkOption {
          type = lib.types.str;
          default = config.kdn.hostName;
          description = "The index page heading.";
        };
        listenAddresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0" ];
          description = "Addresses Caddy binds for this vhost.";
        };
        firewallInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "nb-priv" ];
          description = "Interfaces on which 80/443 open. Never WAN on the border router.";
        };
        routes = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                upstream = lib.mkOption { type = lib.types.str; };
                strip = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Strip the path prefix before proxying (handle_path).";
                };
                label = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Index-page link text. `\"\"` means the path.";
                };
              };
            }
          );
          default = { };
        };
      };

      config = lib.mkIf (cfg.domain != null && cfg.routes != { }) (lib.mkMerge [
        { services.caddy.enable = true; }

        {
          systemd.services.caddy.serviceConfig.LoadCredential = [
            "web-key:${cert.keyPath}"
          ];
          # The key is a sops secret; start Caddy only after it is decrypted.
          systemd.services.caddy = {
            after = [ "sops-install-secrets.service" ];
            wants = [ "sops-install-secrets.service" ];
          };

          services.caddy.virtualHosts.${cfg.domain} = {
            inherit (cfg) listenAddresses;
            serverAliases = lib.remove cfg.domain cert.sans;
            extraConfig = ''
              tls ${cert.certPath} /run/credentials/caddy.service/web-key
              ${routes}'';
          };

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
