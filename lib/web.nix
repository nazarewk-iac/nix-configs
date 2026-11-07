# Small, pure helpers that render the Caddy pieces of a per-host web exposure.
#
# Two consumers share this file: the `web-exposure` aspect (a host with no other
# vhost, e.g. etra) and the `llm` aspect (a host that serves llama-swap, e.g. brys
# and oams). One renderer keeps the index page and the sub-path routing identical
# on every host.
{ lib }:
let
  # A route path with a leading slash, so the caller may write "/litellm" or
  # "litellm" and get the same Caddyfile line.
  slash = p: if lib.hasPrefix "/" p then p else "/${p}";

  link = l: ''<li><a href="${slash l.path}/">${l.label}</a></li>'';
in
{
  # The body of a host's index page: a title and one link per exposed service.
  # `links` is a list of `{ path, label }`.
  mkIndexHtml =
    { title, links }:
    ''
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>${title}</title>
          <style>
            body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 4rem auto; padding: 0 1rem; }
            h1 { font-size: 1.4rem; }
            code { background: #eee; padding: .1rem .3rem; border-radius: 3px; }
          </style>
        </head>
        <body>
          <h1>${title}</h1>
          <ul>
      ${lib.concatMapStrings link links}
          </ul>
        </body>
      </html>
    '';

  # A Caddyfile fragment. Each route becomes one handler; the last handler serves
  # the static index. `strip = true` (the default) uses `handle_path`, which
  # removes the prefix, so an OpenAI-compatible API backend sees `/v1/...` and is
  # unaware of the sub-path. `strip = false` keeps the prefix for a backend that
  # sets its own route-prefix (Prometheus does).
  #
  # `routes` is an attrset: path -> `{ upstream, strip ? true }`.
  mkCaddyRoutes =
    { indexPath, routes }:
    lib.concatStrings (
      lib.mapAttrsToList (
        path: r:
        let
          p = slash path;
        in
        if (r.strip or true) then
          "handle_path ${p}/* {\n\treverse_proxy ${r.upstream}\n}\n"
        else
          "handle ${p}/* {\n\treverse_proxy ${r.upstream}\n}\n"
      ) routes
    )
    + ''
      handle {
      	root * ${indexPath}
      	file_server
      }
    '';
}
