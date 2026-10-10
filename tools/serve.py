#!/usr/bin/env python3
"""Serve the web build on your LAN with gzip, plus the room-code signaling service for LAN PvP.

Usage:  python3 tools/serve.py [--port 8000] [--dir build/web]
Then open http://<this-machine's-LAN-IP>:8000 on any device on the network.

Signaling (JSON over HTTP, same origin as the game): players swap WebRTC connection details
through a short room code, then talk to each other directly. Endpoints:
  GET  /signal/info                          -> {"lan": "http://<ip>:<port>"}
  POST /signal/host                          -> {"code", "id": 1, "token"}
  POST /signal/join   {"code"}               -> {"id", "token"}        (the host is notified)
  POST /signal/send   {"code","token","to","msg"}
  POST /signal/poll   {"code","token"}       -> {"msgs": [{"from", "msg"}, ...]}
  POST /signal/leave  {"code","token"}
"""
import argparse
import functools
import gzip
import http.server
import json
import os
import secrets
import socket
import threading
import time

COMPRESS = {".wasm", ".js", ".pck", ".html"}
_cache: dict[str, tuple[float, bytes]] = {}   # path -> (mtime, gzipped bytes); one entry per file

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O or 1/I mix-ups
MAX_ROOMS = 100
MAX_PEERS = 8
MAX_BODY = 16 * 1024
MAX_QUEUE = 200
ROOM_TTL = 15 * 60                                   # seconds of inactivity before a room expires

_rooms: dict[str, dict] = {}   # code -> {"peers": {id: {"token", "queue": []}}, "next": int, "seen": float}
_lock = threading.Lock()
_lan_url = ""


def _expire_rooms() -> None:
    now = time.time()
    for code in [c for c, r in _rooms.items() if now - r["seen"] > ROOM_TTL]:
        del _rooms[code]


def _peer(body: dict):
    """The (room, peer id) a request's code + token belong to, or (None, None)."""
    room = _rooms.get(str(body.get("code", "")).upper())
    if not room:
        return None, None
    for pid, p in room["peers"].items():
        if secrets.compare_digest(p["token"], str(body.get("token", ""))):
            room["seen"] = time.time()
            return room, pid
    return None, None


def signal(route: str, body: dict) -> tuple[int, dict]:
    with _lock:
        _expire_rooms()
        if route == "info":
            return 200, {"lan": _lan_url}
        if route == "host":
            if len(_rooms) >= MAX_ROOMS:
                return 503, {"error": "too many rooms"}
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(6))
            while code in _rooms:
                code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(6))
            token = secrets.token_hex(16)
            _rooms[code] = {"peers": {1: {"token": token, "queue": []}}, "next": 2, "seen": time.time()}
            return 200, {"code": code, "id": 1, "token": token}
        if route == "join":
            room = _rooms.get(str(body.get("code", "")).upper())
            if not room or 1 not in room["peers"]:
                return 404, {"error": "no room with that code"}
            if len(room["peers"]) >= MAX_PEERS:
                return 409, {"error": "room is full"}
            pid, token = room["next"], secrets.token_hex(16)
            room["next"] += 1
            room["peers"][pid] = {"token": token, "queue": []}
            room["peers"][1]["queue"].append({"from": pid, "msg": {"type": "joined"}})
            room["seen"] = time.time()
            return 200, {"id": pid, "token": token}
        room, pid = _peer(body)
        if room is None:
            return 403, {"error": "unknown room or token"}
        if route == "send":
            try:
                to = room["peers"].get(int(body.get("to", 0)))
            except (TypeError, ValueError):
                return 400, {"error": "bad peer id"}
            if to is None:
                return 404, {"error": "no such peer"}
            if len(to["queue"]) < MAX_QUEUE:
                to["queue"].append({"from": pid, "msg": body.get("msg")})
            return 200, {}
        if route == "poll":
            msgs, room["peers"][pid]["queue"] = room["peers"][pid]["queue"], []
            return 200, {"msgs": msgs}
        if route == "leave":
            del room["peers"][pid]
            if pid == 1 or not room["peers"]:
                _rooms.pop(str(body.get("code")).upper(), None)
            elif 1 in room["peers"]:
                room["peers"][1]["queue"].append({"from": pid, "msg": {"type": "left"}})
            return 200, {}
    return 404, {"error": "unknown endpoint"}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream"}

    def log_message(self, fmt, *args):
        if "/signal/poll" not in self.path:         # polling is chatty; keep the log readable
            super().log_message(fmt, *args)

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def list_directory(self, path):
        # Never expose directory listings; only the build files are served.
        self.send_error(404)
        return None

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if not self.path.startswith("/signal/"):
            return self.send_error(404)
        try:
            length = int(self.headers.get("Content-Length", 0) or 0)
        except ValueError:
            return self._json(400, {"error": "bad length"})
        if not 0 <= length <= MAX_BODY:
            return self._json(413, {"error": "too large"})
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(body, dict):
                raise ValueError
        except ValueError:
            return self._json(400, {"error": "bad json"})
        self._json(*signal(self.path[len("/signal/"):].split("?")[0], body))

    def do_GET(self):
        if self.path.startswith("/signal/info"):
            return self._json(*signal("info", {}))
        path = self.translate_path(self.path.split("?")[0])
        if os.path.isdir(path):
            path = os.path.join(path, "index.html")
        ext = os.path.splitext(path)[1]
        if ext in COMPRESS and "gzip" in self.headers.get("Accept-Encoding", "") and os.path.isfile(path):
            mtime = os.path.getmtime(path)
            if path not in _cache or _cache[path][0] != mtime:
                with open(path, "rb") as f:
                    _cache[path] = (mtime, gzip.compress(f.read(), 6))
            body = _cache[path][1]
            self.send_response(200)
            self.send_header("Content-Type", self.guess_type(path))
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()


def lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--host", default="0.0.0.0", help="0.0.0.0 = reachable on your LAN; 127.0.0.1 = this machine only")
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(__file__), "..", "build", "web"))
    args = ap.parse_args()
    _lan_url = f"http://{lan_ip() if args.host != '127.0.0.1' else '127.0.0.1'}:{args.port}"
    handler = functools.partial(Handler, directory=os.path.abspath(args.dir))
    print(f"Serving {os.path.abspath(args.dir)}")
    print(f"  this machine: http://localhost:{args.port}")
    print(f"  LAN:          {_lan_url}")
    http.server.ThreadingHTTPServer((args.host, args.port), handler).serve_forever()
