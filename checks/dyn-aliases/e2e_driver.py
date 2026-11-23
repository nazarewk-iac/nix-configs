"""The five assertions of the `dyn-*` contract, played as a client of the real gateway.

`e2e.nix` starts the gateway and the fake brys, then runs this file inside the VM. Everything is on
loopback: the gateway on 4000, the fake on 18080. The fake is the oracle — it records the bodies the
gateway sends upstream, and it answers the residency and fit questions — so each assertion below
reads one fact from the client and one from upstream.

A failure prints the response body and the gateway journal, because a wrong status alone does not
say which rung of the ladder answered.
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

STATE = os.environ.get("DYN_E2E_STATE", "/var/lib/dyn-e2e")
GATEWAY = os.environ.get("DYN_E2E_GATEWAY", "http://127.0.0.1:4000")
KEY = os.environ.get("LITELLM_MASTER_KEY", "sk-dyn-e2e")
# The group's candidate list, in preference order, from `data/llm.nix`.
IMAGE = ["qwen3-vl-30b-a3b", "ornith-1.5-35b-a3b", "qwen2.5-vl-7b"]
# `litellm_resident._fetch_loaded` caches for 2 s, so a change of residency needs one cache lifetime
# to become visible.
CACHE_SECONDS = 2.5


def state(name, value):
    with open(os.path.join(STATE, name), "w", encoding="utf-8") as handle:
        handle.write(value)


def records(name):
    try:
        with open(os.path.join(STATE, name), encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]
    except FileNotFoundError:
        return []


def clear():
    """Forget the recorded calls, so one scenario asserts on its own traffic only."""
    for name in ("requests.jsonl", "decides.jsonl"):
        try:
            os.unlink(os.path.join(STATE, name))
        except FileNotFoundError:
            pass


def post(path, body):
    request = urllib.request.Request(
        GATEWAY + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY},
        method="POST",
    )
    # No proxy: the VM has no egress, and an inherited HTTP_PROXY must not capture loopback.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=120) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except ValueError:
            return error.code, {"raw": raw.decode(errors="replace")}


def chat(model, **extra):
    body = {"model": model, "messages": [{"role": "user", "content": "hi"}]}
    body.update(extra)
    return post("/v1/chat/completions", body)


def journal():
    try:
        tail = subprocess.run(
            ["journalctl", "-u", "litellm", "--no-pager", "-n", "60"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return tail.stdout
    except Exception as error:  # noqa: BLE001 - a missing journal must not hide the failure
        return "no journal: %s" % error


def note(message):
    """One line per assertion, so a passing build log says what was proven."""
    print(message, flush=True)


def check(condition, message, payload=None):
    if condition:
        return
    print("FAIL: " + message, file=sys.stderr)
    if payload is not None:
        print(json.dumps(payload, indent=2, sort_keys=True), file=sys.stderr)
    print("--- gateway journal ---\n" + journal(), file=sys.stderr)
    raise SystemExit(1)


def upstream():
    """The body of the one upstream completion the gateway made for the current scenario."""
    sent = records("requests.jsonl")
    check(
        len(sent) == 1,
        "the gateway made %d upstream requests, want 1" % len(sent),
        sent,
    )
    return sent[0]["body"]


def wait_ready():
    """The proxy's startup is a full FastAPI/uvicorn boot, so poll its liveness route."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.time() + 240
    while time.time() < deadline:
        try:
            with opener.open(GATEWAY + "/health/liveliness", timeout=2) as response:
                if response.status == 200:
                    return
        except Exception:  # noqa: BLE001 - not up yet is the normal case here
            pass
        time.sleep(1)
    check(False, "the gateway did not answer /health/liveliness within 240 s")


def preset(step, name, max_tokens, enable_thinking, reasoning):
    """One text preset: the cap and the thinking flag are fixed by the gateway, not by the client."""
    clear()
    status, body = chat(name, max_tokens=1)
    check(status == 200, "%s answered %s" % (name, status), body)
    message = body["choices"][0]["message"]
    check(message.get("content") == "ok", "%s did not answer ok" % name, body)
    check(
        bool(message.get("reasoning_content")) == reasoning,
        "%s reasoning_content is %r, want %r"
        % (name, message.get("reasoning_content"), reasoning),
        body,
    )
    sent = upstream()
    check(
        (sent.get("chat_template_kwargs") or {}).get("enable_thinking")
        == enable_thinking,
        "%s sent enable_thinking %r"
        % (name, (sent.get("chat_template_kwargs") or {}).get("enable_thinking")),
        sent,
    )
    check(
        sent.get("max_tokens") == max_tokens,
        "%s sent max_tokens %r, want %d (the client sent 1)"
        % (name, sent.get("max_tokens"), max_tokens),
        sent,
    )
    note(
        "%d. %s: 200, reasoning_content %s, upstream enable_thinking=%s, max_tokens=%d (client sent 1)"
        % (
            step,
            name,
            "present" if reasoning else "absent",
            str(enable_thinking).lower(),
            sent.get("max_tokens"),
        )
    )


def resident(step):
    """Rung 1: a candidate llama-swap reports as loaded wins, and the tree is not asked."""
    clear()
    state("loaded.json", json.dumps([IMAGE[0]]))
    time.sleep(CACHE_SECONDS)
    status, body = chat("dyn-image")
    check(status == 200, "dyn-image (resident) answered %s" % status, body)
    sent = upstream()
    check(
        sent.get("model") == IMAGE[0],
        "the resident rung sent %r" % sent.get("model"),
        sent,
    )
    asked = records("decides.jsonl")
    check(asked == [], "the resident rung asked the tree: %r" % asked)
    note("%d. dyn-image with %s loaded: 200 on it, no /decide call" % (step, IMAGE[0]))


def refusal(step):
    """Rung 3: nothing admits, so the answer is a 409 built from the tree's own reasons."""
    clear()
    state("loaded.json", "[]")
    state("mode", "refuse-all")
    time.sleep(CACHE_SECONDS)
    status, body = chat("dyn-image")
    check(status == 409, "dyn-image (refuse-all) answered %s, want 409" % status, body)
    # LiteLLM renders a dict `detail` as the error's `provider_specific_fields`; the readable
    # summary is `error.message`. Verified against litellm 1.108.0.
    error = body.get("error") or {}
    fields = error.get("provider_specific_fields") or {}
    check(error.get("code") == "409", "the error code is %r" % error.get("code"), body)
    check(
        "no dyn-image (image) candidate" in str(error.get("message")), "message", body
    )
    check(fields.get("current_profile") == "omni-max", "current_profile", body)
    candidates = fields.get("candidates") or []
    check(
        [candidate.get("model") for candidate in candidates] == IMAGE,
        "the candidates are %r, want %r"
        % ([c.get("model") for c in candidates], IMAGE),
        body,
    )
    for candidate in candidates:
        check(
            candidate.get("check") in ("fits-beside", "profile-met"),
            "candidate %r names the check %r, want a verb"
            % (candidate.get("model"), candidate.get("check")),
            candidate,
        )
        check(candidate.get("verdict") == "refuse", "candidate verdict", candidate)
    check(
        fields.get("alternatives") == ["qfn-fast-colo", "qfn-max-colo"],
        "alternatives",
        body,
    )
    check(len(fields.get("remedy") or []) == 2, "remedy", body)
    check(
        (fields.get("select") or {}).get("entries") == fields.get("remedy"),
        "select does not name the entries",
        body,
    )
    # The gateway never switches, so it must not advertise the tree's switch field as a request
    # field: a caller that sent one would get the same refusal back.
    check(
        "confirm" not in json.dumps(body), "the refusal carries a confirm field", body
    )
    asked = [entry["model"] for entry in records("decides.jsonl")]
    check(asked == IMAGE, "the refusal asked the tree %r, want %r" % (asked, IMAGE))
    note(
        "%d. dyn-image with nothing loaded and refuse-all: 409, %d candidates (%s), alternatives, "
        "remedy, select, no confirm; /decide asked %s"
        % (
            step,
            len(candidates),
            ", ".join(sorted({str(c.get("check")) for c in candidates})),
            ", ".join(asked),
        )
    )


def admit_third(step):
    """Rung 2: one fit question per candidate in order, and the first admit is the one served."""
    clear()
    state("mode", "admit-third")
    status, body = chat("dyn-image")
    check(status == 200, "dyn-image (admit-third) answered %s" % status, body)
    sent = upstream()
    check(
        sent.get("model") == IMAGE[2],
        "the admit rung sent %r" % sent.get("model"),
        sent,
    )
    asked = [entry["model"] for entry in records("decides.jsonl")]
    check(asked == IMAGE, "the ladder asked %r, want %r" % (asked, IMAGE))
    note(
        "%d. dyn-image with admit-third: 200 on %s after /decide asked %s"
        % (step, sent.get("model"), ", ".join(asked))
    )


def main():
    wait_ready()
    state("profile", "omni-max")
    state("loaded.json", "[]")
    state("mode", "admit-all")

    # 1 and 2: the two text presets, each with a client cap of 1 that the gateway must override.
    preset(1, "dyn-fast", max_tokens=2048, enable_thinking=False, reasoning=False)
    preset(2, "dyn-max", max_tokens=32768, enable_thinking=True, reasoning=True)
    # 3, 4 and 5: the three rungs of the modality ladder.
    resident(3)
    refusal(4)
    admit_third(5)

    print("dyn-* end to end: the two presets and the three rungs of the ladder hold")


main()
