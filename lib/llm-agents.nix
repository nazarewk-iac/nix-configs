# OpenCode sub-agents for the brys LLM fleet, one per served model.
#
# ## Why
#
# An orchestrator delegates sub-tasks to a sub-agent. A sub-agent with no `model` inherits the
# caller's model (OpenCode docs, Agents > Model), so the built-in `explore`/`general` agents would
# run the slow orchestrator model for every sub-task. This file registers one sub-agent per model
# brys serves, so a caller names a model and gets that model.
#
# ## The name is the served model id
#
# Until 2026-11-23 this file registered one agent per **purpose alias** (`chat-std-fast`,
# `vision-std-fast`, ...). The alias families were dropped: an alias hides which model answers, six
# of them pointed at models the fleet no longer served, and a stale alias looks exactly like a live
# one. A caller now names the model id, which is the same string llama-swap answers to and the same
# string `pi --list-models` and `status --long` print.
#
# ## The frontier models are not sub-agents
#
# The models on the `main` set are the orchestrator itself (`qfn*`); registering them as
# sub-agents would only let a turn recurse into the same model. Every other model brys serves
# becomes one agent.
#
# ## The description
#
# OpenCode shows an agent's `description` to the caller, and the caller picks a subagent by it. It
# therefore states what the model is: modality, context window and measured decode rate, all read
# from the model's own entry in `data/llm.nix`.
{ lib }:
let
  data = import ../data/llm.nix;

  # Every model brys actually serves except the orchestrator. `servedOn` is the same predicate the
  # llama-swap entry list uses: the model's `set` must be one of the host's boot-profile sets. A
  # model that only carries measurements (`hosts.brys` present, `set = "surveyed"` outside the
  # profiles) is not served and must not become an agent.
  llm = import ./llm.nix { inherit lib; };

  agentModels = lib.filterAttrs (
    _: m: llm.servedOn "brys" m && (m.hosts.brys.set or "") != "main"
  ) data.models;

  describe =
    id: m:
    let
      caps = m.capabilities or { };
      rate = (caps.rates or { }).decode or null;
      ctx = m.contextSize or 0;
      vision = m.vision or false;
      op = caps.operation or null;
      kind = if vision then "text+vision" else "text";
    in
    "${id}: ${kind} model, ${toString (ctx / 1024)}k context"
    + lib.optionalString (rate != null) ", ${toString rate} t/s decode"
    + lib.optionalString (op != null && op != "gpu") " (${op})"
    + ".";
in
lib.mapAttrs (id: m: {
  description = describe id m;
  mode = "subagent";
  model = "brys/${id}";
}) agentModels
