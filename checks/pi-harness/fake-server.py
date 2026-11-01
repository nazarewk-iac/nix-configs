#!/usr/bin/env python3
"""Minimal streaming (SSE) OpenAI-compatible server for the subagent spawn check.

Pi streams chat completions, so a plain JSON body fails with "Stream ended without
finish_reason". This server emits proper `data: {...}` SSE chunks and a final
`data: [DONE]`.

Behaviour: the FIRST chat completion answers with a `subagent` tool call, so the real
subagent extension spawns a child `pi`. Every later completion (the child) answers with
plain text. That exercises the spawn contract with no GGUF and no CPU-heavy inference.
"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

served_tool_call = False


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/v1/models"):
            return self._json(200, {"object": "list", "data": [
                {"id": "test", "object": "model", "context_length": 8192}]})
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        global served_tool_call
        n = int(self.headers.get("content-length", 0))
        self.rfile.read(n)

        tool_call = not served_tool_call
        if tool_call:
            served_tool_call = True

        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("cache-control", "no-cache")
        self.send_header("transfer-encoding", "chunked")
        self.end_headers()

        def chunk(delta, finish=None):
            body = {
                "id": "chatcmpl-test", "object": "chat.completion.chunk", "created": 0,
                "model": "test",
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
            }
            payload = f"data: {json.dumps(body)}\n\n".encode()
            self.wfile.write(f"{len(payload):X}\r\n".encode() + payload + b"\r\n")
            self.wfile.flush()

        if tool_call:
            chunk({"role": "assistant", "content": None,
                   "tool_calls": [{"index": 0, "id": "call_1", "type": "function",
                                   "function": {
                                       "name": "subagent",
                                       "arguments": json.dumps({"agent": "scout",
                                                                "model": "brys/chat-dumb-fast",
                                                                "task": "say hi"})}}]})
            chunk({}, "tool_calls")
        else:
            chunk({"role": "assistant", "content": "CHILD-OK"})
            chunk({}, "stop")

        done = b"data: [DONE]\n\n"
        self.wfile.write(f"{len(done):X}\r\n".encode() + done + b"\r\n")
        end = b""
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
