#!/usr/bin/env python3
"""A dual-stack HTTP proxy from llama-swap's port to the Strata engine, with a drain lease.

Two jobs:

1. **Dual stack.** llama-swap health-checks `localhost`, which resolves to `::1` first on this host,
   so a proxy bound only to 127.0.0.1 looks dead to it. One IPv6 socket with `IPV6_V6ONLY=0`
   accepts both families.

2. **Never cut a request that the engine's profile switch interrupts.** The manager on :8181 stops
   the engine to change profile. This proxy therefore takes one lease per request *before*
   forwarding, releases it when the response has been relayed, and waits (retrying) while the
   manager reports that it is draining. A request that arrives mid-switch is delayed until the new
   engine answers instead of failing; a request already in flight when the switch starts makes the
   switch wait for it.

The lease needs the request boundary, so this is an HTTP/1.1 proxy, not a byte pump: it reads one
request (headers plus `Content-Length`/chunked body), forwards it with `Connection: close`, streams
the response back verbatim, and closes both sides. llama-swap speaks HTTP/1.1 to its cmd, so that is
enough, and `Connection: close` makes the response boundary unambiguous.

Usage: strata-proxy <listen-port> <target-port>
"""

import json
import socket
import sys
import threading
import time
import urllib.request

listen_port = int(sys.argv[1])
target_port = int(sys.argv[2])
MANAGER = "http://127.0.0.1:8181"
# How long a request may wait for a switching engine to come back before it gives up.
WAIT_SECONDS = 900


def manager_post(path, body=None):
    req = urllib.request.Request(
        f"{MANAGER}{path}",
        json.dumps(body or {}).encode(),
        {"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def manager_get(path):
    with urllib.request.urlopen(f"{MANAGER}{path}", timeout=10) as r:
        return json.load(r)


def acquire_lease():
    """One lease for one request, waiting while the manager is switching profiles."""
    deadline = time.time() + WAIT_SECONDS
    while time.time() < deadline:
        try:
            reply = manager_post("/lease")
        except Exception:
            time.sleep(0.5)
            continue
        if "lease" in reply:
            return reply["lease"]
        time.sleep(0.5)
    return None


def is_draining():
    try:
        return bool(manager_get("/status").get("draining"))
    except Exception:
        return False


def release_lease(ident):
    try:
        manager_post("/release", {"lease": ident})
    except Exception:
        pass


def read_request(sock):
    """Read one HTTP request: head plus a Content-Length or chunked body. None on a clean close."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(65536)
        if not chunk:
            return None
        buf += chunk
    head, rest = buf.split(b"\r\n\r\n", 1)
    lines = head.split(b"\r\n")
    headers = {}
    for line in lines[1:]:
        if b":" in line:
            k, v = line.split(b":", 1)
            headers[k.strip().lower()] = v.strip()
    body = rest
    if b"content-length" in headers:
        need = int(headers[b"content-length"])
        while len(body) < need:
            chunk = sock.recv(65536)
            if not chunk:
                break
            body += chunk
    elif headers.get(b"transfer-encoding", b"").lower() == b"chunked":
        # Read until the terminating zero-length chunk.
        while not body.endswith(b"0\r\n\r\n"):
            chunk = sock.recv(65536)
            if not chunk:
                break
            body += chunk
    return head, body


def answer_health(client):
    """Keep llama-swap's health check green while the manager swaps the engine underneath.

    The proxy is alive and the engine is coming back, so reporting 500 here would make llama-swap
    kill this process and lose the requests it is holding. Any other path waits for the engine.
    """
    body = b'{"status":"switching"}'
    client.sendall(
        b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
        b"Content-Length: "
        + str(len(body)).encode()
        + b"\r\nConnection: close\r\n\r\n"
        + body
    )
    client.close()


def forward(client, method_path, headers, body):
    upstream = socket.create_connection(("127.0.0.1", target_port), timeout=30)
    # The connect timeout must not become a read timeout: a 32k-token prefill on the slow profile
    # takes about 23 s before the first byte, and a 30 s ceiling turned that into an EOF and a
    # llama-swap 502 (measured 2026-11-20 on `omni-max`). A client that gives up closes the socket,
    # which ends the pump anyway.
    upstream.settimeout(None)
    try:
        head = b"\r\n".join(
            [method_path]
            + [
                b"%s: %s" % (k, v)
                for k, v in headers.items()
                if k.lower()
                not in (b"connection", b"keep-alive", b"proxy-connection", b"host")
            ]
            + [b"Connection: close", b"Host: 127.0.0.1"]
        )
        upstream.sendall(head + b"\r\n\r\n" + body)
        while True:
            chunk = upstream.recv(65536)
            if not chunk:
                break
            client.sendall(chunk)
    finally:
        for s in (upstream, client):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                s.close()
            except OSError:
                pass


def serve(client):
    try:
        req = read_request(client)
        if req is None:
            client.close()
            return
        head, body = req
        lines = head.split(b"\r\n")
        method_path = lines[0]
        headers = {}
        for line in lines[1:]:
            if b":" in line:
                k, v = line.split(b":", 1)
                headers[k.strip().lower()] = v.strip()
        # A health probe must never block: llama-swap would decide the model died and kill us,
        # taking every request we are holding with it.
        if (
            method_path.split(b" ")[0] == b"GET"
            and method_path.split(b" ")[1] == b"/health"
            and is_draining()
        ):
            answer_health(client)
            return
        lease = acquire_lease()
        if lease is None:
            # The switch never finished. Say so instead of hanging the client forever.
            client.sendall(
                b"HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\n"
                b"Content-Length: 62\r\nConnection: close\r\n\r\n"
                b'{"error":"the engine did not come back from a profile switch in time"}'
            )
            client.close()
            return
        try:
            forward(client, method_path, headers, body)
        finally:
            release_lease(lease)
    except OSError:
        try:
            client.close()
        except OSError:
            pass


srv = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
srv.bind(("::", listen_port))
srv.listen(128)
print(f"strata-proxy :{listen_port} -> 127.0.0.1:{target_port}", flush=True)

while True:
    conn, _ = srv.accept()
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
