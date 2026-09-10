# A stand-in for the `lib` that `mcp-servers-nix` ships. It exists only for the den MVP checks.
#
# `modules/den/aspects/mcp.nix` takes the `mcp-servers-nix` source as the option
# `kdn.mcp.serversNix`, because that flake is a `devenv.yaml` input and no den evaluation reaches
# it. So the checks have no real source to pass, and the aspect's translation code would go
# untested.
#
# This file gives the checks a source. It implements the one function the aspect calls, and nothing
# else. It also documents the exact contract the aspect needs:
#
#   evalModule :: pkgs -> module -> { config.settings.servers = { <name> = <server>; }; }
#
# where a server holds `type`, plus `command` and `args` for a stdio server, or `url` for an HTTP
# server, plus optional `env` and `headers`.
#
# The stub turns each enabled `programs` entry into one stdio server, so a check proves the aspect
# passes `programs` through and folds `args` into the command string. It adds one HTTP server that
# no `programs` entry produces, so the `http_url` branch of the translation also gets a test.
#
# It uses `builtins` only. The real `mcp-servers-nix` `lib` takes no arguments either.
{
  evalModule =
    _pkgs: module:
    let
      programs = module.programs or { };
      enabled = builtins.filter (name: programs.${name}.enable or false) (builtins.attrNames programs);
      toServer = name: {
        inherit name;
        value = {
          type = "stdio";
          command = "/den-mvp/bin/${name}";
          args = programs.${name}.args or [ ];
          env = { };
        };
      };
    in
    {
      config.settings.servers = builtins.listToAttrs (map toServer enabled) // {
        stub-http = {
          type = "http";
          url = "http://127.0.0.1:39401/mcp";
          headers.Authorization = "Bearer stub";
        };
      };
    };
}
