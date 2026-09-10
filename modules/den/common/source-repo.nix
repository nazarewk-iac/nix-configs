# One declaration of `kdn.isSourceRepo`, shared by every aspect that installs a repository file.
#
# ## What the option means
#
# Several aspects install an agent rule or an agent skill into the consumer's own working tree.
# This repository is the source of those files, so it must not put a store symlink over its own
# tracked copy. Each such aspect reads `config.kdn.isSourceRepo` and skips its `files` block when
# the value is true. An adopter repository leaves the value false and gets the files.
#
# ## Why a separate file, and why an import by path
#
# The module system rejects two inline declarations of one option. It does dedupe an import **by
# path**. So every aspect that needs this option writes one line in its target module:
#
#     imports = [ ../common/source-repo.nix ];
#
# Any number of such aspects then load together, and the option keeps exactly one declaration.
#
# This file declares an option and sets no config, so it is safe in every class. It takes `lib`
# only, so it needs no `specialArgs` from the consumer.
{ lib, ... }:
{
  options.kdn.isSourceRepo = lib.mkEnableOption ''
    this consumer as the repository that holds the agent rules and the agent skills.

    When true, an aspect installs no rule file and no skill file. This repository commits those
    files itself, so a store symlink would hide the tracked copy
  '';
}
