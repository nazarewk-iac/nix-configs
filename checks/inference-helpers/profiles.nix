# The single-source guard for the frontier profiles.
#
# `.agents/rules/config-single-source.md` says a profile's window, slot count, VRAM reserve and
# resident K/V have exactly one home: `hosts-den/brys/strata-profiles.nix`. This check proves it,
# by reading the three artifacts that could disagree:
#
#   1. the deployment file, imported and evaluated — its generated `config.json` is the artifact the
#      manager and `strata-serve.sh` both read;
#   2. the list of profiles that serve chat (`textProfiles`), and the policy row that must carry
#      each one's measured facts;
#   3. the argv `strata-serve.sh` would really build: the script resolves a profile with `jq` and,
#      with `--print`, prints the exec argv and the patched engine arguments instead of starting
#      the engine.
#
# It also trips on the two shapes the drift took before: a context literal in `strata-serve.sh` and
# a built-in profile table in `strata.go`.
#
# The failure messages name the profile and both values, because "the numbers disagree" costs an
# hour on a host that is already loaded.
{
  pkgs,
  lib,
  ...
}:
let
  brys = import ../../hosts-den/brys/strata-profiles.nix { inherit lib pkgs; };
  configJson = brys.environment.etc."kdn-inference-helpers/config.json".text;
  policyJson = brys.environment.etc."kdn-inference-helpers/policy.json".text;
  script = ../../hosts-den/brys/strata-serve.sh;
  engine = ../../packages/kdn-inference-helpers/internal/engine/strata/strata.go;
in
pkgs.runCommand "check-inference-helpers-profiles"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    set -eu
    : "$TMPDIR"
    cfg="$TMPDIR/config.json"
    policy="$TMPDIR/policy.json"
    install="$TMPDIR/data/strata/install"
    mkdir -p "$install"

    cp ${pkgs.writeText "config.json" configJson} "$cfg"
    cp ${pkgs.writeText "policy.json" policyJson} "$policy"

    # The script patches the Terminal's per-model config, which lives on the host's dataset. A
    # minimal stand-in with the same shape is enough: the check is about the profile flags.
    for base in $(jq -r '.profiles[].base' "$cfg" | sort -u); do
      printf '{"args": ["--pack", "/packs/%s", "--max-context", "1048576", "--rope-scale", "4", "--kv-resident", "4096", "--vram-reserve-mib", "21500"]}\n' \
        "$base" > "$install/strata-$base.json"
    done

    export KDN_INFERENCE_HELPERS_CONFIG="$cfg"
    export STRATA_DATA_HOME="$TMPDIR/data"

    fail=0
    err() {
      printf 'FAIL: %s\n' "$*" >&2
      fail=1
    }

    # A value of one engine flag in the plan the script printed.
    engine_arg() {
      jq -r --arg f "$1" \
        '[.engineArgs as $a | range(0; ($a | length)) as $i | select($a[$i] == $f) | $a[$i + 1]][0] // ""' \
        <<<"$2"
    }

    # A rope factor is a float on one side and the engine's own printing on the other (`2.0` against
    # `2`); the number is what must agree, not the spelling.
    same_number() {
      jq -n --arg a "$1" --arg b "$2" '($a | tonumber) == ($b | tonumber)' 2>/dev/null || echo false
    }

    for profile in $(jq -r '.textProfiles[]' "$cfg"); do
      deploy=$(jq -c --arg p "$profile" '.profiles[$p]' "$cfg")
      if [ "$deploy" = "null" ]; then
        err "profile $profile is in textProfiles but has no row in .profiles"
        continue
      fi

      want_ctx=$(jq -r '.maxContext' <<<"$deploy")
      want_slots=$(jq -r '.parallel' <<<"$deploy")
      want_reserve=$(jq -r '.reserveMiB' <<<"$deploy")
      want_kv=$(jq -r '.kvResident' <<<"$deploy")
      want_rope=$(jq -r '.ropeScale' <<<"$deploy")

      # The script fails loudly on its own when a key is missing; `set -e` turns that into a check
      # failure that names the key.
      plan=$(bash ${script} "$profile" --port 8080 --print)

      got_ctx=$(engine_arg --max-context "$plan")
      got_reserve=$(engine_arg --vram-reserve-mib "$plan")
      got_kv=$(engine_arg --kv-resident "$plan")
      got_rope=$(engine_arg --rope-scale "$plan")
      got_slots=$(jq -r '.parallel' <<<"$plan")
      argv_slots=$(jq -r '.argv as $a | ($a | index("--parallel")) as $i | if $i == null then "" else $a[$i + 1] end' <<<"$plan")

      [ "$got_ctx" = "$want_ctx" ] || err "profile $profile: maxContext is $want_ctx in strata-profiles.nix (config.json) but $got_ctx in the argv strata-serve.sh builds"
      [ "$got_slots" = "$want_slots" ] || err "profile $profile: parallel is $want_slots in strata-profiles.nix (config.json) but $got_slots in the plan strata-serve.sh prints"
      [ "$argv_slots" = "$want_slots" ] || err "profile $profile: --parallel is $want_slots in strata-profiles.nix (config.json) but $argv_slots in the exec argv strata-serve.sh builds"
      [ "$got_reserve" = "$want_reserve" ] || err "profile $profile: reserveMiB is $want_reserve in strata-profiles.nix but $got_reserve in the engine argv strata-serve.sh builds"
      [ "$got_kv" = "$want_kv" ] || err "profile $profile: kvResident is $want_kv in strata-profiles.nix but $got_kv in the engine argv strata-serve.sh builds"
      [ "$(same_number "$want_rope" "$got_rope")" = "true" ] || err "profile $profile: ropeScale is $want_rope in strata-profiles.nix but $got_rope in the engine argv strata-serve.sh builds"

      # The policy is the only source of measured facts, and `status` joins the two vocabularies
      # through `profile`. A frontier profile without a row shows no numbers.
      rows=$(jq -r --arg p "$profile" '[.models[] | select(.profile == $p)] | length' "$policy")
      if [ "$rows" = 0 ]; then
        err "profile $profile has no policy model with profile = $profile; status shows it without facts"
      else
        vram=$(jq -r --arg p "$profile" '[.models[] | select(.profile == $p)][0].vramMiB // 0' "$policy")
        kv=$(jq -r --arg p "$profile" '[.models[] | select(.profile == $p)][0].kvReserveMiB // 0' "$policy")
        switch=$(jq -r --arg p "$profile" '[.models[] | select(.profile == $p)][0].switchSeconds // 0' "$policy")
        [ "$vram" -gt 0 ] || err "profile $profile: its policy row has no vramMiB"
        [ "$kv" -gt 0 ] || err "profile $profile: its policy row has no kvReserveMiB"
        [ "$switch" -gt 0 ] || err "profile $profile: its policy row has no switchSeconds"
      fi
    done

    # An alias must land on something the deployment can actually serve.
    for alias in $(jq -r '.aliases | keys[]' "$cfg"); do
      target=$(jq -r --arg a "$alias" '.aliases[$a]' "$cfg")
      if [ "$target" = "auto" ]; then
        continue
      fi
      known=$(jq -r --arg t "$target" \
        '(.textProfiles | index($t)) != null or (.commands | has($t)) or (.profiles | has($t))' "$cfg")
      [ "$known" = "true" ] || err "alias $alias resolves to $target, which is not a text profile, a command profile or a declared profile"
    done

    # The two shapes the drift took before. A profile number belongs in the deployment file, not in
    # a consumer: the script must read every one of them with `jq`, and the adapter must read them
    # from the deployment config.
    if grep -nE '(524288|262144|1048576|393216)' ${script}; then
      err "strata-serve.sh carries a context literal; the deployment file is the only source"
    fi
    if grep -nE 'Name:[[:space:]]*"(max-|fast-swarm|omni-)' ${engine}; then
      err "strata.go carries a built-in profile table; the deployment file is the only source"
    fi

    if [ "$fail" -ne 0 ]; then
      exit 1
    fi
    echo "every frontier profile agrees: strata-profiles.nix, config.json and the strata-serve.sh argv"
    touch "$out"
  ''
