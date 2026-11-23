# The `dyn-*` intent names as data, before any host renders them.
#
# `lib/llm.nix` derives three text presets, two modality groups and the Pi projection of all five
# from `data/llm.nix`. `hosts/etra/litellm.nix` turns those values into deployments and
# `hosts/etra/litellm_resident.py` reads them as facts. A drift here is a name that answers with
# the wrong shape, or a `dyn-*` model that would make brys emit a llama-swap `cmd` for it.
{
  pkgs,
  lib,
  ...
}:
let
  llm = import ../../lib/llm.nix { inherit lib; };
  data = import ../../data/llm.nix;

  writeJson = name: value: pkgs.writeText "dyn-${name}.json" (builtins.toJSON value);
  presets = writeJson "text-presets" llm.dynTextPresets;
  groups = writeJson "modality-groups" llm.dynModalityGroups;
  piModels = writeJson "pi-litellm-models" (llm.mkPiModelsJson { host = "oams"; }).litellm.models;
  modelNames = writeJson "model-names" (builtins.attrNames data.models);
in
pkgs.runCommand "check-dyn-aliases-config"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    set -eu

    # Print what the file actually holds, not only that jq said no.
    assert_jq() {
      what=$1
      actual=$2
      expr=$3
      if ! printf '%s' "$actual" | jq -e "$expr" >/dev/null; then
        printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$what" "$expr" "$actual" >&2
        exit 1
      fi
    }

    assert_jq "dynTextPresets" "$(cat ${presets})" '
      sort_by(.name) == [
        {
          name: "dyn-avg", base: "qfn", maxTokens: 8192, level: "low",
          kwargs: {enable_thinking: true, reasoning_effort: "low"}, context: 262144
        },
        {
          name: "dyn-fast", base: "qfn", maxTokens: 2048, level: "off",
          kwargs: {enable_thinking: false}, context: 262144
        },
        {
          name: "dyn-max", base: "qfn", maxTokens: 32768, level: "high",
          kwargs: {enable_thinking: true, reasoning_effort: "xhigh"}, context: 262144
        }
      ]'

    assert_jq "dynModalityGroups" "$(cat ${groups})" '
      sort_by(.name) == [
        {
          name: "dyn-audio", kind: "audio", models: ["qwen3-omni"],
          base: "qwen3-omni", context: 32768, maxTokens: 4096
        },
        {
          name: "dyn-image", kind: "image",
          models: ["qwen3-vl-30b-a3b", "ornith-1.5-35b-a3b", "qwen2.5-vl-7b"],
          base: "qwen3-vl-30b-a3b", context: 32768, maxTokens: 4096
        }
      ]'

    # The gateway provider carries all five, and each one inherits the right base: the presets keep
    # the base model's thinking vocabulary, `dyn-image` accepts an image.
    pi_dyn=$(jq -c '[.[] | select(.id | startswith("dyn-"))]' ${piModels})
    assert_jq "mkPiModelsJson { host = \"oams\"; }.litellm.models" "$pi_dyn" '
      def one($id):
        map(select(.id == $id))
        | if length == 1 then .[0] else error("want exactly one \($id)") end;
      (length == 5)
      and (map(.id) | sort == ["dyn-audio", "dyn-avg", "dyn-fast", "dyn-image", "dyn-max"])
      and (one("dyn-fast") | .baseId == "qfn" and .reasoning == true
           and .thinkingLevelMap.high == "xhigh" and .maxTokens == 2048
           and .contextWindow == 262144)
      and (one("dyn-avg") | .baseId == "qfn" and .reasoning == true
           and .thinkingLevelMap.low == "low" and .maxTokens == 8192)
      and (one("dyn-max") | .baseId == "qfn" and .reasoning == true
           and .thinkingLevelMap.high == "xhigh" and .maxTokens == 32768)
      and (one("dyn-audio") | .baseId == "qwen3-omni")
      and (one("dyn-image") | .baseId == "qwen3-vl-30b-a3b"
           and ((.input // []) | index("image")) != null)'

    # The invariant that keeps a `dyn-*` name off brys: an entry in `data.models` would emit a
    # llama-swap `cmd` and a second gateway group with the same name.
    assert_jq "data.models has no dyn-* entry" "$(cat ${modelNames})" '
      map(select(startswith("dyn-"))) | length == 0'

    echo "dyn aliases: presets, modality groups, Pi projection and the no-model invariant hold"
    touch "$out"
  ''
