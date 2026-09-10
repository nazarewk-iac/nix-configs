# The two den namespaces. They make the split between reusable code and personal data structural
# instead of doc-only.
#
# | Namespace | Exported | Holds |
# |---|---|---|
# | `den.ful.kdn` | yes, as `flake.denful.kdn` | every reusable aspect. No personal data, ever. |
# | `den.ful.personal` | **no** | the creator's own data-carrying aspects. |
#
# `(inputs.den.namespace "<name>" <export>)` creates three things: the option `den.ful.<name>`, a
# module-argument alias `<name>`, and — when `<export>` is `true` — the output `flake.denful.<name>`
# **of den's own evaluation**. `./flake-module.nix` copies that one attribute out to this
# repository's flake. An adopter merges an exported namespace into their own den with
# `(inputs.den.namespace "kdn" [ inputs.nix-configs ])`.
#
# ## Why a non-exported namespace is the enforcement
#
# A namespace scopes names; by itself it does not stop an aspect from carrying personal data. But
# `personal` writes **no** flake output, so an adopter cannot name a `personal` aspect at all. The
# boundary is then a property of the module system, not a rule in a file.
#
# `kdn` stays data-free by the older rule that still does the real work: the aspect declares the
# option, and the consumer passes the value.
#
# ## Two spellings of `kdn`, and how to tell them apart
#
# The namespace name and this repository's option prefix are the same word. They live in different
# evaluations, so Nix resolves both, but one file holds both spellings. The scope tells them apart:
#
# - At the **top level** of an aspect file, `kdn.<name>` names an **aspect**. For example
#   `kdn.mcp-snoop.includes = [ kdn.mcp ]`.
# - **Inside a target module**, `kdn.<name>` is an **option path** of the consumer's own
#   configuration. For example `options.kdn.mcp` and `config.kdn.mcp.serversNix`.
#
# ## What stays out of a namespace
#
# An **entity** aspect stays in `den.aspects`. den finds a host's aspect by the host name and a
# user's aspect by the user name, and it looks in `den.aspects` only. A namespaced aspect never
# attaches to an entity on its own — an entity reaches one through `includes`. So
# `checks/den-mvp/host-darwin/default.nix` keeps `den.aspects.host-darwin`, and it includes
# `kdn.gh`.
#
# den's own batteries stay `den.batteries.*` too.
#
# ## The name is the merge key
#
# `nix/lib/namespace.nix` merges every source's `denful.<name>` into the one option
# `den.ful.<name>`. So two repositories that export the same namespace name **and** the same aspect
# name merge into one aspect: a list option such as `includes` concatenates, and a scalar option
# raises `defined multiple times`. den's `test-multiple-sources-merged` proves this is deliberate —
# it is how a team namespace works. There is no export-time alias, because `namespace.nix` writes
# `config.flake.denful.${name}`. So the option path, the module argument and the flake output all
# carry one name. `kdn` is unique enough to make an accidental merge unlikely.
{ inputs, ... }:
{
  imports = [
    (inputs.den.namespace "kdn" true)
    (inputs.den.namespace "personal" false)
  ];
}
