"""A fake brys for the `dyn-*` end-to-end check: llama-swap's `/v1/models` and the tree's `/decide`.

Three endpoints, all on loopback:

  * `GET /v1/models` — the ids llama-swap reports as loaded. `litellm_resident._fetch_loaded` reads
    `data[].id` where `data[].status.value == "loaded"`, so the state file holds a plain list of ids
    and every entry is rendered as loaded.
  * `POST /decide` — one verdict per model, from the mode file: `admit-all` admits every candidate,
    `refuse-all` refuses every candidate with a `fits-beside` failure, and `admit-third` admits the
    candidate at index 2 of its group in the policy file and refuses the rest. The order comes from
    the policy file, so the fake holds no second copy of the candidate list.
  * `POST /v1/chat/completions` — records the request body, then answers `content: "ok"`. It adds
    `reasoning_content` only when the request carried `chat_template_kwargs.enable_thinking == true`,
    which is what makes it the proof of the preset enforcement: the gateway must send that flag.

The state directory is the test's control surface: `loaded.json`, `mode` and `profile`. The two
record files are `requests.jsonl` and `decides.jsonl`, one JSON object per line.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = os.environ.get("DYN_E2E_STATE", "/var/lib/dyn-e2e")
POLICY = os.environ.get("DYN_E2E_POLICY", "/etc/dyn-e2e/resident-policy.json")
PORT = int(os.environ.get("DYN_E2E_PORT", "18080"))

REFUSAL = {
    "verdict": "refuse",
    "refusal": {
        "reason": "does not fit beside the resident engine",
        "alternatives": ["qfn-fast-colo", "qfn-max-colo"],
    },
    # The action node comes last and carries no verb: the refusal must still name `fits-beside`.
    "why": [
        {"verb": "fits-beside", "result": "failure"},
        {"node": "root.5.2", "result": "failure"},
    ],
}


def read_state(name, default):
    """A state file, or the default when the test has not written it yet."""
    try:
        with open(os.path.join(STATE, name), encoding="utf-8") as handle:
            return handle.read().strip()
    except FileNotFoundError:
        return default


def append_record(name, payload):
    with open(os.path.join(STATE, name), "a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload) + "\n")


def candidate_index(model):
    """The position of `model` in its group's candidate list, from the gateway's own facts file."""
    try:
        with open(POLICY, encoding="utf-8") as handle:
            groups = json.load(handle).get("groups") or {}
    except Exception:
        return None
    for group in groups.values():
        models = group.get("models") or []
        if model in models:
            return models.index(model)
    return None


def verdict_for(model):
    mode = read_state("mode", "admit-all")
    if mode == "admit-all":
        return {"verdict": "admit"}
    if mode == "admit-third" and candidate_index(model) == 2:
        return {"verdict": "admit"}
    return REFUSAL


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def reply(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.rstrip("/")
        if path == "/v1/models":
            loaded = json.loads(read_state("loaded.json", "[]"))
            self.reply(
                200,
                {
                    "object": "list",
                    "data": [
                        {"id": name, "object": "model", "status": {"value": "loaded"}}
                        for name in loaded
                    ],
                },
            )
            return
        if path == "/status":
            self.reply(200, {"profile": read_state("profile", "omni-max")})
            return
        self.reply(404, {"error": "not found: " + self.path})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}") if length else {}
        path = self.path.rstrip("/")

        if path == "/decide":
            append_record("decides.jsonl", {"model": body.get("model")})
            self.reply(200, verdict_for(str(body.get("model") or "")))
            return

        if path == "/v1/chat/completions":
            append_record("requests.jsonl", {"path": path, "body": body})
            thinking = (body.get("chat_template_kwargs") or {}).get(
                "enable_thinking"
            ) is True
            message = {"role": "assistant", "content": "ok"}
            if thinking:
                message["reasoning_content"] = "a thought from the fake"
            self.reply(
                200,
                {
                    "id": "chatcmpl-fake",
                    "object": "chat.completion",
                    "created": 1,
                    "model": body.get("model"),
                    "choices": [
                        {"index": 0, "message": message, "finish_reason": "stop"}
                    ],
                    "usage": {
                        "prompt_tokens": 1,
                        "completion_tokens": 1,
                        "total_tokens": 2,
                    },
                },
            )
            return

        self.reply(404, {"error": "not found: " + path})


if __name__ == "__main__":
    os.makedirs(STATE, exist_ok=True)
    print(f"fake brys on 127.0.0.1:{PORT}, state in {STATE}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
