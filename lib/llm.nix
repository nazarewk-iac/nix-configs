# Render each client's config from the single LLM source of truth, `data/llm.nix`.
#
# One function per consumer. Nothing here declares a model id, an alias or a context size; every
# value is read from the data file, so the only place to edit is `data/llm.nix`.
{ lib }:
let
  data = import ../data/llm.nix;

  # alias -> model id, inverted once. A model may answer to several aliases.
  aliasToModel = lib.foldl' (
    acc: name: lib.foldl' (a: alias: a // { ${alias} = name; }) acc data.models.${name}.aliases or [ ]
  ) { } (builtins.attrNames data.models);

  # The client view of one SERVED MODEL, expanded to one entry PER ALIAS.
  #
  # Pi lists and selects by the entry `id`, and a caller names an intent (`chat-std-fast`), not a
  # base model id. So each alias becomes its own entry against the same served model. A model with
  # no alias also gets one entry under its base id, so nothing is unreachable.
  piEntries =
    name:
    let
      m = data.models.${name};
      # A model may set its OWN `pi.contextWindow` (a client budget below the served size) and
      # `pi.maxTokens`. Absent, the client-wide defaults apply, clamped to the served window.
      ctx = lib.min (m.pi.contextWindow or data.pi.defaults.contextWindow) m.contextSize;
      base = {
        contextWindow = ctx;
        # `maxTokens` is an explicit number (per model in data/llm.nix, else `pi.defaults`). Clamp
        # it to the window so an output cap can never exceed the context it shares with the prompt.
        maxTokens = lib.min (m.pi.maxTokens or data.pi.defaults.maxTokens) ctx;
      }
      // lib.optionalAttrs (m.vision or false) {
        input = [
          "text"
          "image"
        ];
      };
      ids = if (m.aliases or [ ]) == [ ] then [ name ] else m.aliases;
    in
    map (id: base // { inherit id; }) ids;

  # One provider entry per endpoint. `models` is every model PLUS the label-only context tiers of
  # the frontier, each tier pointing at the same served model with a different client window.
  mkPiModelsJson =
    let
      frontier = "qwen3.8-flash-next";
      # `models.json` has NO alias-to-model field: the entry `id` is the model name Pi sends to
      # the server. A `"model": ...` hint is ignored, so an invented id such as
      # `qwen3.8-flash-next-longest` gets a 404 "no router for requested model".
      #
      # So a context tier is NOT a new pi entry. It is the SAME id with a different budget, which
      # pi cannot express twice in one provider. Keep the tiers in data/llm.nix for documentation
      # and for any client that can express them, but do not emit them as pi models.
      tierModels = [ ];
    in
    lib.mapAttrs (_: ep: {
      baseUrl = ep.baseUrl;
      api = ep.api;
      apiKey = ep.apiKey;
      models = builtins.concatLists (map piEntries (builtins.attrNames data.models)) ++ tierModels;
    }) data.endpoints;

  # The purpose aliases only (legacy bare ids like `fast` are not purposes).
  purposeAliases = lib.filterAttrs (
    name: _: builtins.match "[a-z]+-(dumb|quick|std|deep)-[a-z]+(-[a-z]+)*(-alt)?" name != null
  ) aliasToModel;
in
{
  inherit data aliasToModel purposeAliases;
  inherit mkPiModelsJson;
}
