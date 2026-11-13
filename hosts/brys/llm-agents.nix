# OpenCode sub-agents for the brys LLM fleet, one per purpose alias.
#
# ## Why
#
# An orchestrator delegates sub-tasks to a sub-agent. A sub-agent with no
# `model` inherits the caller's model (OpenCode docs, Agents > Model), so the
# built-in `explore`/`general` agents would run the slow orchestrator model for
# every sub-task. This file registers one sub-agent per **purpose alias** on the
# brys router, so a caller names an intent (`chat-std-fast`) and gets the model
# the fleet serves for that intent.
#
# ## The single source of truth
#
# The alias set is not written here. It is read from `data/llm.nix`, the same
# file the server serves from. When an alias moves to another model there, the
# client agent follows with no second edit. A client that names an intent never
# names a base model id (see
# ../../docs/tasks/2026-10/llm-model-expansion/alias-scheme.design.md).
#
# ## The frontier models are not sub-agents
#
# The models on the `main` router are the orchestrator itself; registering them
# as sub-agents would only let a turn recurse into the same slow model. The
# frontier (DeepSeek V4 Flash, then Qwen3.8-Flash-Next) is since 2026-11-13
# retired from brys, so `main` is empty and every served model is a
# grunt/surveyed intent model that becomes an agent.
#
# ## The name of one agent
#
# The agent name is the alias itself (`chat-std-fast`), so the Task tool's
# `subagent_type` and the server id are the same string. There is one agent per
# intent, not one per (model, thinking level): the level is already part of the
# alias.
#
# ## The description
#
# OpenCode shows an agent's `description` to the caller, and the caller picks a
# subagent by it. So the description states **when to use this agent**, not just
# what it runs: the purpose's job, the complexity and speed trade, the meaning of
# any tag, and the served model. The strings follow the intent tables in
# ../../docs/tasks/2026-10/llm-model-expansion/alias-scheme.design.md and
# model-selection-guide.md.
#
# ## Thinking
#
# A purpose alias carries its own thinking behaviour on the server, so an agent
# overrides nothing. A caller that needs a different depth picks a different
# alias. The `-alt` aliases are registered too, so a caller can shift the served
# model without a config change.
{ lib }:
let
  data = import ../../data/llm.nix;

  # The non-frontier models brys serves: a model with a `hosts.brys` block that is
  # enabled and not on the `main` router (the orchestrator itself).
  agentModels = lib.filterAttrs (
    _: m: (m.hosts or { }) ? brys && (m.hosts.brys.common.enable or true) && m.hosts.brys.set != "main"
  ) data.models;

  # alias -> base model id, inverted from every agent model's `aliases` list.
  aliasToModel = lib.foldl' (
    acc: id: lib.foldl' (a: alias: a // { ${alias} = id; }) acc (agentModels.${id}.aliases or [ ])
  ) { } (builtins.attrNames agentModels);

  # The purpose aliases only. The bare `fast`/`balanced`/`grunt` ids are legacy
  # router aliases, not purposes; the scheme's rule is `<purpose>-<complexity>-<speed>`.
  purposeAliases = lib.filterAttrs (
    name: _: builtins.match "[a-z]+-(dumb|quick|std|deep)-[a-z]+(-[a-z]+)*(-alt)?" name != null
  ) aliasToModel;

  # What each purpose does, and the shape of task it fits. Lifted from the
  # alias-scheme intent tables.
  purposeIntent = {
    chat = "Chat, Q&A, and writing. Use for text generation and explanation, not for code or tool calls.";
    code = "Code generation and edits. Use for writing, changing, or explaining source code.";
    vision = "Image understanding. Use when the task carries an image (screenshots, photos, OCR, diagrams).";
    audio = "Speech understanding. Use when the task carries audio; this model also accepts images and text.";
    reason = "Step-by-step reasoning. Use for logic, math, or multi-step planning where the answer needs working out.";
    tools = "Tool and function calling, and agentic control. Use when the task must emit structured tool calls or drive a terminal.";
    embed = "Text embeddings for retrieval. NOT a chat model: it uses the /v1/embeddings endpoint.";
    rank = "Text reranking for retrieval. NOT a chat model: it uses the /v1/rerank endpoint.";
    tiny = "Always-on, latency-first micro-tasks. Use for routing, classification, and tiny rewrites.";
    orchestrate = "Heavy long-horizon planning and review, with a very large context. Use sparingly: only one such model fits in RAM at a time.";
  };

  # What each complexity tier means, as a short pick hint.
  complexityHint = {
    dumb = "Mechanical, tightly-specified work; fast and predictable, fails on open-ended tasks.";
    quick = "Trivial work that needs a little judgment.";
    std = "Normal work; the default tier.";
    deep = "Hard, long, or creative work; much slower, so spend it only when needed.";
  };

  # What each speed class means.
  speedHint = {
    fast = "interactive latency";
    mid = "a few seconds";
    slow = "a minute or more is fine";
  };

  # Tags that narrow an id, from the design doc's tag table.
  tagHint = {
    long = "long-context";
    moe = "fast mixture-of-experts";
    vision = "vision-capable";
    tools = "tool-capable";
    gpu = "runs fully on the GPU";
    think = "exposes a thinking trace";
  };

  # Build the caller-facing description: purpose intent (the differentiator
  # against sibling purposes), then a short tier hint, then any tags, then the
  # served model and the literal alias.
  describe =
    alias: model:
    let
      parts = lib.splitString "-" alias;
      purpose = builtins.elemAt parts 0;
      complex = builtins.elemAt parts 1;
      speed = builtins.elemAt parts 2;
      # Everything after `<purpose>-<complexity>-<speed>`, minus a trailing
      # `-alt`, is a set of tags.
      rest = lib.drop 3 parts;
      tags = if lib.last parts == "alt" then lib.dropEnd 1 rest else rest;
      isAlt = lib.last parts == "alt";
      tagText =
        lib.optionalString (tags != [ ])
          " Tags: ${lib.concatStringsSep ", " (map (t: tagHint.${t} or t) tags)}.";
      altText = lib.optionalString isAlt " Alternate for this slot; prefer the bare id unless it is busy.";
    in
    "${purposeIntent.${purpose} or purpose} Tier: ${complex} (${
      complexityHint.${complex} or complex
    }), speed ${speed} (${speedHint.${speed} or speed})."
    + tagText
    + altText
    + " Served now: ${model}. (alias ${alias})";
in
lib.mapAttrs (alias: model: {
  description = describe alias model;
  mode = "subagent";
  model = "brys/${alias}";
}) purposeAliases
