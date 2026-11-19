#!/usr/bin/env python3
"""A dual-stack TCP proxy from llama-swap's port to the Strata engine.

llama-swap health-checks `localhost`, which resolves to `::1` first on this host, so a proxy that
binds only 127.0.0.1 looks dead to it. One IPv6 socket with `IPV6_V6ONLY=0` accepts both families.

Usage: strata-proxy <listen-port> <target-port>
"""
import selectors
import socket
import sys
import threading

listen_port = int(sys.argv[1])
target_port = int(sys.argv[2])

srv = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
srv.bind(("::", listen_port))
srv.listen(128)
print(f"strata-proxy :{listen_port} -> 127.0.0.1:{target_port}", flush=True)


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


while True:
    client, _ = srv.accept()
    try:
        upstream = socket.create_connection(("127.0.0.1", target_port), timeout=30)
    except OSError:
        client.close()
        continue
    threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pump, args=(upstream, client), daemon=True).start()
