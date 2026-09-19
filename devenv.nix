{
  inputs,
  pkgs,
  ...
}:
let
  # The aspects this repository's own shell turns on. An aspect has no `enable` option:
  # inclusion in this list is the switch.
  #
  # `mcp` and `mcp-pretty-print` stay out: `nix` and `jj` include `mcp`, and
  # `mcp-basic-memory` includes `mcp-pretty-print`. den collapses the diamond, so one shell
  # holds one gateway.
  #
  # `jj-fork` stays out. This repository is the public upstream, not a fork, so it carries
  # no private remote and no denied pattern. A downstream fork adds that aspect in its own
  # tree.
  aspects = [
    "gh"
    "nix"
    "jj"
    "zellij"
    "mcp-snoop"
    "mcp-basic-memory"
    "opencode"
  ];
in
{
  imports = inputs.nix-configs.denLib.imports {
    class = "devenv";
    inherit aspects;
  };

  config = {
    # argc drives the subcommand dispatch in the zellij-llm/kdn-slug bash packages; keep it
    # on PATH so the standalone scripts run and get tested in the shell.
    packages = [ pkgs.argc ];

    # This repository authors the agent instruction files, so it asks for every one of
    # them. Each `installAgentRules` option defaults to false, so an adopter states its own
    # work mandate. `kdn.isSourceRepo = true` makes every one of these inert here, because
    # this repository commits the files itself. They stay as the explicit intent.
    kdn.isSourceRepo = true;
    kdn.nix.installAgentRules = true;
    kdn.jj.installAgentRules = true;
    kdn.zellij.installAgentRules = true;
    kdn.mcp.basic-memory.installAgentRules = true;

    # This repository's own formatter app. The aspect allow-lists no app name, so this line
    # keeps the Bash allow rule that the slot used to carry.
    kdn.nix.extraBashAllow = [ "nix run .#kdn-nix-fmt -- *" ];

    # This value belongs to this repository, not to the aspect. The aspect default is
    # neutral (`origin`), so this line keeps the behaviour.
    kdn.jj.upstream.remote = "kdn";

    # `mcp-servers-nix` is a `devenv.yaml` input, so the aspect cannot reach it. The shell
    # passes it here; without it every `kdn.mcp.programs` entry stays inert.
    kdn.mcp.serversNix = inputs.mcp-servers-nix;

    # This repository's own knowledge root. The aspect default names no repository.
    kdn.mcp.basic-memory.knowledgeRoot = "$HOME/.local/share/kdn-nix-configs/knowledge";
    # The aspect names no base. These two entries keep the backends and the note paths.
    kdn.mcp.basic-memory.bases.public = {
      aliases = [ "bmp" ];
      description = "basic-memory public knowledge base (open-source tooling, public knowledge)";
    };
    kdn.mcp.basic-memory.bases.sensitive = {
      aliases = [ "bms" ];
      description = "basic-memory sensitive knowledge base (private, internal)";
    };

    # In-devenv opencode capability: a project `opencode.jsonc` and an `opencode` wrapper
    # (key/svc auth) on PATH. The brys-specific model/proxy wiring lives in the
    # hostname-gated profile below.
    #
    # These three values belong to this repository, not to the aspect. The aspect defaults
    # are neutral (an empty provider set, the store path only, and no credential).
    kdn.opencode.settings.provider.requesty = { };
    kdn.opencode.allowedPaths = [
      "/nix/store/**"
      "~/dev/**"
    ];
    kdn.opencode.authKeys.REQUESTY_API_KEY = "requesty";

    # brys-specific profile: feeds the rich provider/model config and the model proxies
    # (requesty :9526, local llama-swap :9533). Auto-activated only on a host whose hostname
    # is "brys"; every other host keeps the benign global opencode skeleton.
    profiles.hostname."brys".module = import ./hosts/brys/devenv.nix;

    # oams-specific profile: opencode pointed at the LAN llama-server on brys over HTTPS
    # (shared /run/configs/llms cert + API key). Auto-activated only on a host whose hostname
    # is "oams".
    profiles.hostname."oams".module = import ./hosts/oams/devenv.nix;
  };
}
