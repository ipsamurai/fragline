# Changelog

## 2.0.0 — 2026-10-11

### Performance
- Rewrote all dynamic drawing (fighters, particles, pickups, projectiles) to use quads from one shared texture atlas (`DrawUtil`), which the GL Compatibility renderer batches into a few instanced draw calls.
- Baked level tiles, decoration and parallax backgrounds into one mesh per layer (`StaticDraw`).
- Pickups and traps redraw only on state changes; pooled particles with no per-frame allocation; cached living-players list; nav graphs built once per map; sounds preloaded and registered as web samples.
- `allow_hidpi=false`, capped physics catch-up steps, and the menu's background match freezes on sub-screens.
- Result in Chrome on an Intel i3-1215U with UHD graphics, 8 fighters: 17-20 FPS → a steady 68 FPS (display refresh), 516-1294 → about 40 draw calls a frame.
- Auto quality: a match that keeps missing frames drops to Low quality once and says so.

### Features
- **X-Ray vision** (key X, offline only): the bot navigation graph, each bot's route, goal, intent and target, and item respawn timers.
- **Game modes:** Gun Game, Instagib and Rocket Arena, plus a Low Gravity mutator. Bots play every mode, offline and over LAN.
- **Blackout Relay**, a 7th arena with a hidden tunnel and a secret wall shaft.
- **Armory** screen with stats and test fire for every weapon, and a rotating weapon showcase on the main menu.
- **Results screen** with accuracy, favourite weapon, award cards, and **Save recap** (a 1200x630 PNG).
- **Announcer** using the browser's speech synthesis (first blood, multi-kills, sprees, lead changes, time left, victory).
- **Game feel:** shell casings, per-weapon muzzle flashes, wall sparks and cooling scorch marks, layered explosions, rocket smoke trails, recoil kick, hit-stop on kills, slow-motion final kill, death cam.

### Audio & Art
- Pixel-art weapon sprites from SnoopethDuckDuck's CC0 "Guns" pack, in one atlas.
- Weapon sounds from LMGLolo's FREE FPS SFX Pack (CC BY-ND 4.0, used unmodified and always at original pitch) and SnakeF8's Snake's Authentic Gun Sounds (free; trimmed only by Godot's importer).
- Equip racks, shotgun pumps, robot deaths, boot footsteps, rocket loops, kill-confirm and headshot pings, mixed with per-sound levels and per-sound voice limits on a limited SFX bus.

### Multiplayer
- **Phone play:** twin-stick touch controls with aim assist, appearing automatically on touch screens; fullscreen and landscape on first tap.
- **QR code** in the LAN lobby (Kenyoni QR Code addon, MIT) next to the room code and join link.
- Plain-HTTP LAN addresses now work in Chrome thanks to an audio fallback in the loading shell.

### Web
- Branded loading shell (`tools/web/shell.html`): progress, tips, clear errors for missing WebGL 2 or failed downloads, click-to-play audio gate, social card and icons.
- `build_web.sh` gained `OUT=` and `PUBLIC_URL=`; `serve.py` gzips the build once at startup and answers reloads with 304s.
- Built-in benchmark (`?bench=SECONDS&map=N&bots=N[&xray=1]`, results in `window.__bench`) and new URL parameters (`quality`, `touch`, `gate`, `fs`, `debug`, `host`/`autostart`).

### Fixes
- Around 40 bug fixes across combat, bots, menus, networking, audio and the web build. Many of them have checks in the new `regress` suite.

### Tests
- From 4 to 11 headless suites: added regression, game modes, touch controls (including the QR code), announcer, match stats, audio loading and sound hooks. Added screenshot tools for menus and the results screen.

### Docs
- README rewritten for this release: features, controls, LAN and phone setup, URL parameters, performance, deployment.
- New CHANGELOG.md, docs/ARCHITECTURE.md and SECURITY.md; CREDITS.md lists every audio file and its source; fresh screenshots.

## 1.0.0 — 2026-10-11

Hackathon release.

- LAN multiplayer: room codes over WebRTC, host-authoritative, up to 8 players.
- Six arenas, 9 weapons with alt fires, bots with five skill levels, Training Room, 12 customisable fighters.
- Removed unused code; hardened the signaling server against malformed requests.
- README with screenshots, architecture overview and quick start; four headless test suites.
