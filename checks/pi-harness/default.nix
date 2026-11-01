# Tier-3 smoke checks for the Pi harness. Each check starts its OWN llama-server on a tiny GGUF, so
# it needs no `brys`, no network after the first fetch, and no GPU: it runs on any machine. The
# models are deliberately tiny (1 MB and 15 MB), so these prove PLUMBING — connect, text
# round-trip, event stream, the timestamps extension, and system-prompt stability — not model
# quality.
#
# Everything here is a normal derivation. Nothing activates anything, nothing needs root.
{ pkgs, lib, ... }:
let
  pi = pkgs.pi-coding-agent;
  models = import ./fixtures.nix { inherit pkgs; };

  # A models.json that points Pi at the in-test server only.
  modelsJson = pkgs.writeText "pi-test-models.json" (
    builtins.toJSON {
      providers.llamatest = {
        baseUrl = "http://127.0.0.1:18080/v1";
        api = "openai-completions";
        apiKey = "test";
        models = [
          {
            id = "test";
            contextWindow = 4096;
            maxTokens = 128;
          }
        ];
      };
    }
  );

  # One hermetic run: start llama-server on a tiny model, wait for health, set up an isolated Pi
  # agent dir, then run `script` (which may use $PI_CODING_AGENT_DIR and the `pi` CLI on PATH).
  mkRun =
    {
      name,
      model,
      script,
    }:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          pi
          pkgs.llama-cpp
          pkgs.curl
          pkgs.jq
          pkgs.gnugrep
          pkgs.coreutils
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.pi/agent"
        export PI_CODING_AGENT_DIR="$HOME/.pi/agent"
        cp ${modelsJson} "$PI_CODING_AGENT_DIR/models.json"

        llama-server --host 127.0.0.1 --port 18080 --model ${model} \
          --ctx-size 4096 --threads 2 -n 0 --no-warmup >llama.log 2>&1 &
        server=$!
        trap 'kill $server 2>/dev/null || true' EXIT

        ready=0
        for _ in $(seq 1 120); do
          curl -sf -m1 http://127.0.0.1:18080/health >/dev/null 2>&1 && { ready=1; break; }
          sleep 1
        done
        if [ "$ready" != 1 ]; then
          echo "FAIL ${name}: llama-server never became healthy"; cat llama.log; exit 1
        fi

        ${script}

        touch $out
      '';

  # The timestamps extension source, copied in so the check does not depend on a live ~/.pi.
  timestampsExt = ./extensions/timestamps.ts;
in
{
  # 1. Plumbing: Pi talks to the server and completes a run. Proves the whole client/server path on
  #    a 1 MB model.
  pi-harness-plumbing = mkRun {
    name = "pi-harness-plumbing";
    model = models.stories260K;
    script = ''
      printf 'Say OK' | pi --mode json -p --provider llamatest --model test \
        --no-context-files --no-skills --no-tools >out.jsonl 2>err.txt \
        || { echo "FAIL: pi exited non-zero"; cat err.txt; exit 1; }
      jq -rs '[.[]|select(.type=="agent_settled")]|length' out.jsonl | grep -qx 1 \
        || { echo "FAIL: no agent_settled event"; exit 1; }
    '';
  };

  # 2. System prompt has NO date/time and is byte-identical across two runs. This is the overnight-
  #    roll regression: a date in the prompt invalidates the cached context every midnight.
  pi-harness-prompt-stable = mkRun {
    name = "pi-harness-prompt-stable";
    # The tiny model is enough: this check captures the system prompt, it does not need instruction
    # following. Keep the 98 MB stories15M out of the common path.
    model = models.stories260K;
    script = ''
      # The system prompt is a SESSION entry, not a --mode json event, so read the session JSONL.
      # Each run gets its own session dir, so "newest file" is unambiguous.
      # Run once and HOIST the session file to the given path, so a later run's wipe cannot delete it.
      run_to() {
        local dest="$1" f
        rm -rf "$PI_CODING_AGENT_DIR/sessions"
        printf 'Say OK' | pi --mode json -p --provider llamatest --model test \
          --no-skills --no-tools >/dev/null 2>&1 || true
        for f in "$PI_CODING_AGENT_DIR"/sessions/*/*.jsonl; do
          [ -f "$f" ] && { cp "$f" "$dest"; return 0; }
        done
        return 1
      }
      prompt_sections() {
        jq -cS 'select(.type=="message" and .message.role=="system")|.message.sections' "$1"
      }
      run_to a.jsonl || true; run_to b.jsonl || true
      a=a.jsonl; b=b.jsonl
      [ -n "$a" ] && [ -f "$a" ] || {
        echo "FAIL: first run wrote no session file (a='$a')"
        ls -la "$PI_CODING_AGENT_DIR"/sessions/*/ 2>&1 | head -5
        exit 1
      }
      [ -n "$b" ] && [ -f "$b" ] || { echo "FAIL: second run wrote no session file"; exit 1; }
      # Guard against a vacuous pass: the system message must exist and be non-trivial.
      [ -n "$(prompt_sections "$a")" ] || { echo "FAIL: session has no system message"; exit 1; }
      [ "$(prompt_sections "$a" | sha256sum)" = "$(prompt_sections "$b" | sha256sum)" ] \
        || { echo "FAIL: system prompt differs between runs"; exit 1; }
      text=$(jq -rs '[.[]|select(.type=="message" and .message.role=="system")|.message.sections|to_entries[]|.value]|join("\n")' "$a")
      [ -n "$text" ] || { echo "FAIL: system sections are empty"; exit 1; }
      if printf '%s' "$text" | grep -Eq '20[0-9]{2}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}:[0-9]{2}|today|current date|UTC time'; then
        echo "FAIL: system prompt contains a date/time"; exit 1
      fi
      echo "OK: prompt stable, no date, $(printf '%s' "$text" | wc -c) bytes"
    '';
  };

  # 3. timestamps extension: appends non-context `kdn-timestamp` entries and never leaks them into
  #    the prompt (sections stay identical), so it cannot invalidate a cached prefix.
  pi-harness-timestamps = mkRun {
    name = "pi-harness-timestamps";
    model = models.stories260K;
    script = ''
      printf 'Say OK' | pi --mode json -p --provider llamatest --model test \
        --extension ${timestampsExt} --no-context-files --no-skills --no-tools >ts.jsonl 2>err.txt \
        || { echo "FAIL: pi exited non-zero"; cat err.txt; exit 1; }
      n=$(jq -rs '[.[]|select(.type=="entry_appended" and .entry.customType=="kdn-timestamp")]|length' ts.jsonl)
      [ "$n" -ge 1 ] || { echo "FAIL: no kdn-timestamp entries appended"; exit 1; }
      # The prompt lives in the session file; assert the timestamp entries never reach it.
      sess=""
      for f in "$PI_CODING_AGENT_DIR"/sessions/*/*.jsonl; do [ -f "$f" ] && { sess=$f; break; }; done
      [ -n "$sess" ] || { echo "FAIL: no session file"; exit 1; }
      if jq -rs '[.[]|select(.type=="message" and .message.role=="system")|.message.sections|to_entries[]|.value]|join("\n")' "$sess" \
           | grep -q 'kdn-timestamp'; then
        echo "FAIL: timestamp leaked into the system prompt"; exit 1
      fi
      echo "OK: $n timestamp entries, none in the prompt"
    '';
  };
}
