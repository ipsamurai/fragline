#!/usr/bin/env python3
"""Serve the web build on your LAN with gzip, plus the room-code signaling service for LAN PvP.

Usage:  python3 tools/serve.py [--port 8000] [--host 0.0.0.0] [--dir build/web]
Then open http://<this-machine's-LAN-IP>:8000 on any device on the network.

Signaling (JSON over HTTP, same origin as the game): players swap WebRTC connection details
through a short room code, then talk to each other directly. Endpoints:
  GET  /signal/info                          -> {"lan": "http://<ip>:<port>"}
  POST /signal/host                          -> {"code", "id": 1, "token"}
  POST /signal/join   {"code"}               -> {"id", "token"}        (the host is notified)
  POST /signal/send   {"code","token","to","msg"}    msg = {"type": "offer"|"answer"|"candidate", ...}
  POST /signal/poll   {"code","token"}       -> {"msgs": [{"from", "msg"}, ...]}
  POST /signal/leave  {"code","token"}

Hardening (it's meant to run on a shared venue network): only regular, non-hidden files inside
--dir are served (no listings, no symlink/junction escapes); POSTs must be same-origin JSON;
every room/peer/queue/message is size-capped; failed joins are throttled per IP (no brute-forcing
room codes); each device can hold only a few rooms (its oldest is dropped, so one device can't fill
the server); connections are capped per IP; stalled requests time out.
"""
from __future__ import annotations   # lets the dict[...] annotations below run on Python 3.8

import argparse
import functools
import gzip
import http.server
import json
import os
import secrets
import socket
import sys
import threading
import time
from urllib.parse import urlsplit

COMPRESS = {".wasm", ".js", ".pck", ".html"}
_cache: dict[str, tuple[float, bytes]] = {}   # path -> (mtime, gzipped bytes); one entry per file


def _gzipped(path: str, mtime: float) -> bytes:
    hit = _cache.get(path)
    if hit is None or hit[0] != mtime:
        with open(path, "rb") as f:
            hit = _cache[path] = (mtime, gzip.compress(f.read(), 6))
    return hit[1]


def _warm(root: str) -> None:
    """Gzip the build at startup (the .wasm takes ~2 s) so the first visitor doesn't wait for it."""
    for name in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        path = os.path.join(root, name)
        if os.path.splitext(name)[1] in COMPRESS and os.path.isfile(path) and not name.startswith("."):
            try:
                _gzipped(path, os.path.getmtime(path))
            except OSError:
                pass

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O or 1/I mix-ups (32^6 ~ 1e9 codes)
CODE_LEN = 6
MAX_ROOMS = 100
MAX_ROOMS_PER_IP = 8                                 # a device hosting more drops its oldest room
MAX_PEERS = 8
MAX_BODY = 16 * 1024
MAX_MSG = 8 * 1024                                   # one offer/answer/candidate (real SDP is ~1-3 KB)
MAX_QUEUE = 200
MAX_QUEUE_BYTES = 64 * 1024                          # per peer, until it polls
MSG_TYPES = {"offer", "answer", "candidate"}         # "joined"/"left" come only from the server
JOIN_BURST = 20                                      # failed joins per IP: this many at once...
JOIN_REFILL = 1.0                                    # ...then one per second (~1e9 codes: hopeless)
MAX_CONNS = 256                                      # open connections, total and per IP
MAX_CONNS_PER_IP = 48
ROOM_TTL = 15 * 60                                   # seconds of inactivity before a room expires
PEER_TTL = 15                                        # seconds without a poll before a peer counts as gone
                                                     # (net.gd polls every 0.25 s as host, 1 s as client)
ROUTES = {"info", "host", "join", "send", "poll", "leave"}

# Content-Security-Policy for everything we serve. Godot's web build needs 'unsafe-eval'
# (JavaScriptBridge.eval) and wasm compilation; the shell and Godot's head include are inline
# scripts; fonts and the favicon are data: URLs. Everything else is same-origin only: no
# third-party scripts, no exfiltration via fetch to other hosts, no framing (clickjacking).
CSP = ("default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'; "
       "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; "
       "media-src 'self' data: blob:; connect-src 'self'; worker-src 'self' blob:; "
       "object-src 'none'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'")
SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": CSP,
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",                # join links carry the room code
    "Cross-Origin-Resource-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
}

_rooms: dict[str, dict] = {}   # code -> {"peers": {id: peer}, "next": int, "seen": float, "ip": str, "born": float}
                               # peer = {"token", "queue": [], "qbytes": int, "seen": float}
_join_fails: dict[str, list] = {}   # ip -> [tokens, last refill time]
_lock = threading.Lock()
_lan_url = ""


def _new_peer(token: str, now: float) -> dict:
    return {"token": token, "queue": [], "qbytes": 0, "seen": now}


def _enqueue(peer: dict, item: dict, size: int) -> bool:
    if len(peer["queue"]) >= MAX_QUEUE or peer["qbytes"] + size > MAX_QUEUE_BYTES:
        return False
    peer["queue"].append(item)
    peer["qbytes"] += size
    return True


def _expire_rooms() -> None:
    now = time.time()
    for code in [c for c, r in _rooms.items() if now - r["seen"] > ROOM_TTL]:
        del _rooms[code]
    # Closed tabs never send "leave": drop clients that stopped polling so they don't fill the room.
    for room in _rooms.values():
        for pid in [p for p, peer in room["peers"].items() if p != 1 and now - peer["seen"] > PEER_TTL]:
            del room["peers"][pid]
            host = room["peers"].get(1)
            if host:
                _enqueue(host, {"from": pid, "msg": {"type": "left"}}, 40)
    for ip in [i for i, b in _join_fails.items() if b[0] + (now - b[1]) * JOIN_REFILL >= JOIN_BURST]:
        del _join_fails[ip]


def _join_allowed(ip: str, failed: bool = False) -> bool:
    """Token bucket of FAILED joins per IP (a wrong code costs a token; a right one is free)."""
    now = time.time()
    b = _join_fails.setdefault(ip, [float(JOIN_BURST), now])
    b[0], b[1] = min(float(JOIN_BURST), b[0] + (now - b[1]) * JOIN_REFILL), now
    if failed:
        b[0] -= 1.0
    return b[0] >= 1.0


def _text(v, limit: int) -> str:
    """A client-sent string field, or "" if it's missing, not a string, or absurdly long."""
    return v if isinstance(v, str) and len(v) <= limit else ""


def _peer(body: dict):
    """The (code, room, peer id) a request's code + token belong to, or (None, None, None)."""
    code = _text(body.get("code"), 16).upper()
    token = _text(body.get("token"), 64).encode("utf-8")
    room = _rooms.get(code)
    if not room or not token:
        return None, None, None
    for pid, p in room["peers"].items():
        if secrets.compare_digest(p["token"].encode(), token):
            room["seen"] = p["seen"] = time.time()
            return code, room, pid
    return None, None, None


def signal(route: str, body: dict, ip: str = "") -> tuple[int, dict]:
    with _lock:
        _expire_rooms()
        if route == "info":
            return 200, {"lan": _lan_url}
        if route == "host":
            mine = sorted((r["born"], c) for c, r in _rooms.items() if r["ip"] == ip)
            for _, old in mine[:max(0, len(mine) - MAX_ROOMS_PER_IP + 1)]:
                del _rooms[old]                      # this device's oldest rooms make way
            if len(_rooms) >= MAX_ROOMS:
                return 503, {"error": "too many rooms"}
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))
            while code in _rooms:
                code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))
            token, now = secrets.token_hex(16), time.time()
            _rooms[code] = {"peers": {1: _new_peer(token, now)}, "next": 2, "seen": now, "ip": ip, "born": now}
            return 200, {"code": code, "id": 1, "token": token}
        if route == "join":
            if not _join_allowed(ip):
                return 429, {"error": "too many attempts, wait a few seconds"}
            room = _rooms.get(_text(body.get("code"), 16).upper())
            if not room or 1 not in room["peers"]:
                _join_allowed(ip, failed=True)
                return 404, {"error": "no room with that code"}
            if time.time() - room["peers"][1]["seen"] > PEER_TTL:
                return 404, {"error": "host is gone"}
            if len(room["peers"]) >= MAX_PEERS:
                return 409, {"error": "room is full"}
            pid, token, now = room["next"], secrets.token_hex(16), time.time()
            room["next"] += 1
            room["peers"][pid] = _new_peer(token, now)
            _enqueue(room["peers"][1], {"from": pid, "msg": {"type": "joined"}}, 40)
            room["seen"] = now
            return 200, {"id": pid, "token": token}
        code, room, pid = _peer(body)
        if room is None:
            return 403, {"error": "unknown room or token"}
        if route == "send":
            to_id = body.get("to")
            if isinstance(to_id, float) and to_id.is_integer():
                to_id = int(to_id)
            if not isinstance(to_id, int) or isinstance(to_id, bool) or to_id == pid:
                return 400, {"error": "bad peer id"}
            to = room["peers"].get(to_id)
            if to is None:
                return 404, {"error": "no such peer"}
            msg = body.get("msg")
            if not isinstance(msg, dict) or msg.get("type") not in MSG_TYPES:
                return 400, {"error": "bad message"}
            size = len(json.dumps(msg))
            if size > MAX_MSG:
                return 413, {"error": "message too large"}
            if not _enqueue(to, {"from": pid, "msg": msg}, size):
                return 429, {"error": "peer's queue is full"}
            return 200, {}
        if route == "poll":
            peer = room["peers"][pid]
            msgs, peer["queue"], peer["qbytes"] = peer["queue"], [], 0
            return 200, {"msgs": msgs}
        if route == "leave":
            del room["peers"][pid]
            if pid == 1 or not room["peers"]:
                _rooms.pop(code, None)
            elif 1 in room["peers"]:
                _enqueue(room["peers"][1], {"from": pid, "msg": {"type": "left"}}, 40)
            return 200, {}
    return 404, {"error": "unknown endpoint"}


def _no_constants(name: str):
    raise ValueError("NaN/Infinity not allowed")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream"}
    timeout = 10        # socket timeout: a stalled request (e.g. short body, big Content-Length) can't hold a thread
    _no_store = False

    def log_message(self, fmt, *args):
        path = getattr(self, "path", None)          # unset when the request line itself was malformed
        if path is None:
            if getattr(self, "_bad_logged", False):     # send_error logs twice; say it once
                return
            self._bad_logged = True
            # Usually a browser trying https:// on this plain-HTTP port (a TLS handshake isn't HTTP).
            hint = " (https:// on an http port? open the http:// address instead)" \
                if getattr(self, "raw_requestline", b"")[:1] == b"\x16" else ""
            sys.stderr.write("%s - rejected a malformed request%s\n" % (self.address_string(), hint))
            return
        if "/signal/poll" not in path:              # polling is chatty; keep the log readable
            super().log_message(fmt, *args)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store" if self._no_store else "no-cache")
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, v)
        super().end_headers()

    def list_directory(self, path):
        # Never expose directory listings; only the build files are served.
        self.send_error(404)
        return None

    def _local_path(self) -> str | None:
        """The file system path for this GET/HEAD, or None if it must not be served: anything that
        resolves (through symlinks/junctions) outside --dir, hidden (dot) files and folders, and
        anything that's neither a regular file nor a folder (e.g. Windows device names like CON)."""
        try:
            path = self.translate_path(self.path)
            root = os.path.normcase(os.path.realpath(self.directory))
            real = os.path.normcase(os.path.realpath(path))
            if os.path.commonpath([root, real]) != root:
                return None
            rel = os.path.relpath(real, root)
        except (ValueError, OSError):                # other drive, device path (NUL), NUL byte...
            return None
        if rel != "." and any(part.startswith(".") for part in rel.split(os.sep)):
            return None
        if not (os.path.isfile(real) or os.path.isdir(real)):
            return None
        return path

    def send_head(self):                             # used by the stock GET (uncompressed) and HEAD
        if self._local_path() is None:
            self.send_error(404)
            return None
        return super().send_head()

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self._no_store = True
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _same_origin(self) -> bool:
        """Browsers send Origin on POSTs: refuse other sites' pages poking the signaling API
        (a page on the internet can't make your browser create or join rooms here)."""
        origin = self.headers.get("Origin")
        if origin is None:
            return True                              # not a browser (e.g. a desktop build)
        return urlsplit(origin).netloc.lower() == (self.headers.get("Host") or "").lower() != ""

    def do_POST(self):
        route_path = self.path.split("?")[0]
        route = route_path[len("/signal/"):] if route_path.startswith("/signal/") else ""
        if route not in ROUTES or route == "info":
            return self._json(404, {"error": "unknown endpoint"})
        if not self._same_origin():
            return self._json(403, {"error": "cross-origin request refused"})
        # Requiring JSON also forces a CORS preflight for any cross-site fetch (which we never allow).
        if self.headers.get("Content-Type", "").split(";")[0].strip().lower() != "application/json":
            return self._json(415, {"error": "send application/json"})
        try:
            length = int(self.headers.get("Content-Length", 0) or 0)
        except ValueError:
            return self._json(400, {"error": "bad length"})
        if not 0 <= length <= MAX_BODY:
            return self._json(413, {"error": "too large"})
        try:
            raw = self.rfile.read(length)
        except OSError:                              # timed out waiting for the body
            self.close_connection = True
            return
        try:
            body = json.loads(raw or b"{}", parse_constant=_no_constants)
            if not isinstance(body, dict):
                raise ValueError
        except (ValueError, RecursionError):        # (UnicodeDecodeError is a ValueError)
            return self._json(400, {"error": "bad json"})
        try:
            result = signal(route, body, self.client_address[0])
        except Exception as e:                       # never leak a traceback to the client
            self.log_error("signal %s failed: %r", route, e)
            result = 500, {"error": "server error"}
        self._json(*result)

    def do_GET(self):
        url_path = self.path.split("?")[0]
        if url_path == "/signal/info":
            return self._json(*signal("info", {}))
        if url_path.startswith("/signal/"):
            return self._json(404, {"error": "unknown endpoint"})
        path = self._local_path()
        if path is None:
            return self.send_error(404)
        if os.path.isdir(path):
            path = os.path.join(path, "index.html")
        ext = os.path.splitext(path)[1]
        if ext in COMPRESS and "gzip" in self.headers.get("Accept-Encoding", "") and os.path.isfile(path):
            mtime = os.path.getmtime(path)
            # Validators so reloads revalidate (Cache-Control: no-cache) with a tiny 304 instead of
            # re-downloading ~15 MB; a rebuild changes size/mtime. Chrome ignores ETag on these HTTP/1.0
            # responses and won't cache them without Last-Modified, so send both.
            etag = f'"{os.path.getsize(path):x}-{int(mtime * 1000):x}-gz"'
            last_mod = self.date_time_string(int(mtime))
            if etag in self.headers.get("If-None-Match", "") or self.headers.get("If-Modified-Since") == last_mod:
                self.send_response(304)
                self.send_header("ETag", etag)
                self.send_header("Last-Modified", last_mod)
                self.send_header("Vary", "Accept-Encoding")
                self.end_headers()
                return
            body = _gzipped(path, mtime)
            self.send_response(200)
            self.send_header("Content-Type", self.guess_type(path))
            self.send_header("Content-Encoding", "gzip")
            self.send_header("ETag", etag)
            self.send_header("Last-Modified", last_mod)
            self.send_header("Vary", "Accept-Encoding")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            # Write in chunks: the socket timeout bounds each sendall() as a whole, so one big write
            # of the .wasm over slow Wi-Fi could time out mid-download.
            view = memoryview(body)
            for i in range(0, len(view), 64 * 1024):
                self.wfile.write(view[i:i + 64 * 1024])
            return
        super().do_GET()


class Server(http.server.ThreadingHTTPServer):
    """One thread per connection, but a bounded number of them (total and per IP), so a flood of
    idle sockets (slowloris) can't exhaust threads; extra connections are closed at once."""
    daemon_threads = True
    if os.name == "nt":
        allow_reuse_address = False                  # Windows SO_REUSEADDR lets another process share the port

    def __init__(self, *args, **kwargs):
        self._open: dict[str, int] = {}
        self._open_total = 0
        self._open_lock = threading.Lock()
        super().__init__(*args, **kwargs)

    def server_bind(self):
        if os.name == "nt" and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()

    def process_request(self, request, client_address):
        ip = client_address[0]
        with self._open_lock:
            if self._open_total >= MAX_CONNS or self._open.get(ip, 0) >= MAX_CONNS_PER_IP:
                full = True
            else:
                full = False
                self._open_total += 1
                self._open[ip] = self._open.get(ip, 0) + 1
        if full:
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self._release(ip)
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._release(client_address[0])

    def _release(self, ip: str) -> None:
        with self._open_lock:
            self._open_total -= 1
            if self._open.get(ip, 0) <= 1:
                self._open.pop(ip, None)
            else:
                self._open[ip] -= 1

    def handle_error(self, request, client_address):
        if isinstance(sys.exc_info()[1], (ConnectionError, TimeoutError)):
            return                                   # client went away: not worth a traceback
        super().handle_error(request, client_address)


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
    if args.host not in ("127.0.0.1", "localhost", "::1"):
        print("  (anyone on this network can load the game and use room codes; --host 127.0.0.1 keeps it local)")
    threading.Thread(target=_warm, args=(os.path.abspath(args.dir),), daemon=True).start()
    Server((args.host, args.port), handler).serve_forever()
