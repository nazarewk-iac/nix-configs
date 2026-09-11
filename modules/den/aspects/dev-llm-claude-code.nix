# The `development/llm/claude-code` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It registers the Claude Code command-line harness as an application entry, so the `apps` aspect
# installs it and keeps its data directory and its configuration file across a wipe.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **One class only.** The old module holds a Home Manager half and a forward half. den needs no
#    forward: a consumer names the class it wants.
# 3. **The `apps` aspect comes in through `includes`.** It declares `kdn.apps`, and den collapses a
#    diamond, so several aspects may name it.
#
# The `enable` inside `kdn.apps.<name>` is an option of the `apps` submodule, not an option of this
# aspect. A submodule `enable` is allowed.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `pkgs` only.
{ kdn, ... }:
{
  kdn.dev-llm-claude-code.includes = [ kdn.apps ];

  kdn.dev-llm-claude-code.homeManager =
    { pkgs, ... }:
    {
      kdn.apps.claude-code.enable = true;
      kdn.apps.claude-code.package.original = pkgs.claude-code;
      kdn.apps.claude-code.dirs.data = [ "/.claude" ];
      kdn.apps.claude-code.files.config = [ "/.claude.json" ];
    };
}
