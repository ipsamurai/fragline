# Security

## Reporting a vulnerability

Please report security issues privately to the maintainers (a GitHub security advisory on
this repository, or a direct message) rather than in a public issue.

## Threat model

FRAGLINE is meant for a trusted-ish LAN: friends, a classroom, a venue's Wi-Fi.
`tools/serve.py` serves the static web build plus a small signaling service that swaps WebRTC
connection details for a 6-character room code. After players connect, game traffic goes
browser to browser and never through the server. The host's browser runs the match; clients
send only their inputs, movement and shots.

## What the server enforces (`tools/serve.py`)

- **Static files:** only regular, non-hidden files inside `--dir` are served, and there are no
  directory listings. Symlinks or junctions that point outside the folder, dotfiles and Windows
  device names (`NUL`, `CON`, ...) return 404. HEAD requests get the same checks.
- **Same-origin JSON only:** signaling `POST`s must be `application/json`, and any `Origin`
  header must match `Host`. Other websites can't use a visitor's browser to create or join rooms.
- **Room codes:** generated with a cryptographic random generator (32⁶ ≈ 1 billion codes).
  Wrong guesses are rate-limited per device (a burst of 20, then 1 per second, answered with
  429), so guessing a code isn't practical.
- **Tokens:** every peer gets a random 128-bit token. A peer can only read its own messages,
  send as itself or remove itself; the server stamps the sender on every message. Clients can
  only relay `offer`, `answer` and `candidate` messages, never fake server notices.
- **Size limits:** request body 16 KB, signaling message 8 KB, each peer's pending messages
  64 KB / 200 messages, 8 players per room, 100 rooms in total, and each device holds at most
  8 rooms (its oldest is dropped).
- **Timeouts and connections:** idle players are dropped after 15 s and idle rooms after
  15 min. Stalled requests time out after 10 s. Open connections are capped at 256 in total and
  48 per device. On Windows the port is bound exclusively.
- **Headers on every response:** a Content-Security-Policy that allows same-origin resources
  only (plus the inline scripts, `eval` and WebAssembly that Godot's web build needs),
  `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `Cross-Origin-Resource-Policy: same-origin`, and a Permissions-Policy that turns off camera,
  microphone, geolocation, payment and USB. JSON responses are `no-store`.
- **Errors** never send a stack trace to the browser; they're logged on the server only.

## What the host validates (`src/autoload/net.gd`, `src/game/world.gd`)

- Player names are trimmed and capped at 16 characters; character looks are checked against
  the valid characters, colours and helmets.
- Peer ids come from the WebRTC layer and can't be faked. Client-to-host RPCs check that this
  peer is the host and use the real sender id; host-to-client RPCs are authority-only.
- Weapon ids are range-checked, shots are rate-limited per weapon and must start near the
  shooter, and weapon ownership and ammo are checked on the host. Reported positions must be
  finite numbers. The lobby is capped at 8 players and the protocol version is checked.
- Room codes from `?join=` links are validated (6 characters from the server's alphabet)
  before anything is sent.
- Every value passed to `JavaScriptBridge.eval` is either a constant or escaped with
  `JSON.stringify`. Announcer lines are fixed text (no player names).

## Known limits

- Movement is client-reported so play stays responsive. A modified client can move
  unrealistically: this is a LAN party game, not anti-cheat.
- Signaling is plain HTTP on the LAN: there's no TLS and no internet relay.
- `?debug=1` publishes the page's own match state to `window.__fragline` for automated tests.
  It exposes nothing the page doesn't already hold.
- A DNS-rebinding page would pass the `Origin` check. Behind a reverse proxy every player shares
  one IP, so the per-device limits would apply to everyone together.

## Running serve.py at a venue

- `python3 tools/serve.py` listens on all interfaces (`0.0.0.0:8000`), so anyone on the same
  network can load the game. Use `--host 127.0.0.1` to keep it on your machine only.
- Use a network you trust or a dedicated hotspot. If you can, block port 8000 from guest or
  other VLANs. Don't port-forward it to the internet.
- Run it from a normal user account, and point `--dir` only at the build output (`build/web`,
  the default), never at the repo root or your home folder.
- Don't put it behind a reverse proxy without raising `MAX_ROOMS_PER_IP` and `JOIN_BURST`.
- Stop the server (Ctrl+C) when the event ends. Rooms only live in memory.
