<div align="center">

# FRAGLINE

**Fast, neon 2D arena combat that runs in your browser, with bots and LAN multiplayer built in.**

A modern tribute to the Newgrounds classic *Unreal Flash*, built from scratch in Godot 4.7.

![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Web%20%7C%20Desktop-0f172a)
![Multiplayer](https://img.shields.io/badge/LAN%20PvP-WebRTC%20P2P-22d3ee)
![Game data](https://img.shields.io/badge/game%20data-~6%20MB-a855f7)
![Tests](https://img.shields.io/badge/tests-11%20headless%20suites-22c55e)

![FRAGLINE main menu over a live bot match](docs/screenshots/menu.jpg)

</div>

## Why FRAGLINE

- **Opens in a browser tab.** No install and no plugins. It runs on WebGL 2 using Godot's no-threads web build, so it works on any static host without special server headers.
- **Locked 60 FPS on a budget laptop.** Measured in Chrome on an Intel i3-1215U with integrated Intel UHD graphics: every arena holds the display's refresh rate with 8 fighters, at about 40 draw calls a frame. See [Performance](#performance).
- **See what's normally invisible.** Press **X** for X-Ray vision: the bots' navigation graph, each bot's planned route and goal, what it's trying to do ("GET ROCKET LAUNCHER", "HUNT VOLT"), who it's targeting, and respawn timers on taken items.
- **Play on your phone.** The LAN lobby shows a QR code. Scan it, and the game opens in your phone's browser with twin-stick touch controls and aim assist.
- **Small download.** The game data (art, levels, sound and music) is under 6 MB. Characters, levels and effects are drawn in code. Weapons use a CC0 pixel-art pack.
- **Bots that play properly.** Bots find their way around every arena using ladders, jump pads and drop-through floors. They pick up items, avoid traps, lead their shots and dodge. There are five skill levels, from Rookie to Godlike.
- **LAN multiplayer with a room code.** Host a match and share a 6-character code. Up to 8 players connect directly to each other, browser to browser, over WebRTC.
- **Tested.** Eleven headless test suites cover combat rules, regressions, menus, bot navigation, full bot matches on every arena, game modes, touch controls, the announcer, audio, sound hooks and match stats.

## Screenshots

| Foundry | Cryo Station |
|---|---|
| ![Foundry arena: molten pit, catwalks and a shock-rifle beam](docs/screenshots/foundry.jpg) | ![Cryo Station arena: icy research station with upper deck](docs/screenshots/cryo-station.jpg) |
| **Match setup** | **Customize** |
| ![Arena cards with mini-maps, bots, skill, frag and time limits](docs/screenshots/match-setup.jpg) | ![12 fighters, colour swatches, helmets and a live preview](docs/screenshots/customize.jpg) |

## Features

### Combat
- **9 weapons, each with an alternate fire mode:** Enforcer, Flak Cannon, Minigun, Shock Rifle (beam + combo ball), Pulse Gun, Rocket Launcher (volleys, rocket jumps), Grenade Launcher (sticky grenades), Sniper Rifle (headshots, wall-piercing shot) and the Redeemer.
- **Movement:** double jump, dodge-roll, drop-through platforms, ladders you can grab in mid-air, and jump pads.
- **Status effects:** burning, poisoned, chilled and jammed.
- **Smooth on fast screens:** physics runs at 60 Hz and rendering is interpolated, so the game stays smooth on 120 and 144 Hz displays.
- **Game feel:** shell casings that bounce, a different muzzle flash for each weapon, wall sparks with scorch marks that cool, layered explosions (a staged mushroom cloud for the Redeemer), rocket smoke trails, recoil camera kick, a short hit-stop on your kills, a slow-motion final kill, and a death cam that follows your killer.
- **Game modes:** Deathmatch, **Gun Game** (each frag moves you up an 8-weapon ladder that ends on the pistol), **Instagib** (shock rifle, one hit kills) and **Rocket Arena**, plus a Low Gravity mutator. Bots play all of them, over LAN too.

### Arenas
- **Seven PvP arenas:** Deck-17, Skyline, Foundry, Overgrowth, Cryo Station, Orbital and **Blackout Relay**, a red emergency-lit relay station with a hidden tunnel under the core and a secret shaft inside the wall (X-Ray shows them). Each arena is mirrored for fairness and has its own hazards: laser gates, floor vents, lava and void.
- **No spawn camping:** spawn rooms sit behind energy barriers and you can't fight inside them. A timer stops players from hiding in them, and you get a short shield when you step out.
- **Training Room:** an armory, a firing range, an agility course, and practice dummies you can set up (idle, moving, attacking or bot opponent), plus god mode and infinite ammo.

### Bots
- They plan routes over a navigation graph that covers walking, jumping, double jumps, drop-throughs, ladders and jump pads.
- They choose what to do (heal, armour up, grab a weapon, hunt, roam) by scoring each option.
- In a fight they pick a weapon for the range, lead moving targets, arc grenades, aim rockets at your feet, set up shock combos, and strafe, hop and dodge.

### Multiplayer (LAN)
- Host or join with a room code, a join link or a **QR code**. Players can join after a match has started. Phones get touch controls automatically.
- Works on plain-HTTP LAN addresses in Chrome, which normally treats them as insecure and blocks the game's audio setup.
- The host's game makes the final call on damage, pickups and scores. It checks each client's fire rate, ammo, weapon ownership and muzzle position.
- Your own movement runs locally, so it never feels laggy. Other players are updated 30 times a second and smoothed between updates. The host's bots fight alongside everyone.

### Presentation
- 12 fighters you can recolour, plus helmets and a live preview.
- Neon lighting, particles and screen shake.
- A full menu flow: an animated start menu over a live bot match with a rotating weapon showcase, an **Armory** with stats and test-fire for every weapon, match setup, settings (audio, graphics, key rebinding, gameplay), pause menu, countdown and an FPS / draw-call counter.
- **Results screen:** final standings with accuracy and favourite weapon, award cards (MVP, Sharpshooter, Rampage, Headhunter and more), and **Save recap**, which downloads a shareable 1200x630 image.
- **Announcer** in the style of Unreal Tournament, using the browser's built-in speech: countdown, first blood, multi-kills, killing sprees, headshots, lead changes, frags and time remaining, and victory.
- **Weapon audio:** real gunshots, shotgun pumps, a rack sound for each weapon when you equip it, robot death sounds, boot footsteps, rocket engine loops, plus kill-confirm and headshot pings. All mixed with per-sound levels and voice limits.
- A branded loading page with progress, tips and a clear message if WebGL 2 is missing.
- **Auto quality:** if a match keeps dropping frames (a laptop on battery saver, say), the game switches to Low quality once and tells you.
- A CC0 soundtrack: a synthwave menu theme and a drum-and-bass / trance track for each pair of arenas.

## Quick start

### Play in the browser (recommended)

Requires **Godot 4.7.2** on your `PATH` and its **web export templates** (Editor → Manage Export Templates).

```bash
./tools/build_web.sh        # export to build/web/
python3 tools/serve.py      # serve at http://localhost:8000 (also on your LAN, with gzip)
```

### Play on desktop

```bash
godot --path .              # run the game
godot -e --path .           # open the editor
```

### LAN multiplayer

1. On one machine, run `./tools/build_web.sh` and then `python3 tools/serve.py`. It prints a LAN address such as `http://192.168.1.20:8000`.
2. Everyone opens that address in a browser.
3. The host chooses **Play → Host LAN**, sets up the match and clicks **Host match**.
4. Everyone else chooses **Play → Join LAN** and types the room code, or opens the join link shown in the lobby.
5. The host clicks **Start**.

Use `python3 tools/serve.py --host 127.0.0.1` to keep the server on this machine only.

## Controls

| Action | Keys |
|---|---|
| Move | A / D (or arrow keys) |
| Jump, double jump, climb | W / Space |
| Drop through, climb down | S |
| Dodge | Shift (or S + direction) |
| Fire / alt fire | Left / right mouse button |
| Switch weapon | 1–9, mouse wheel, Q / E |
| Scoreboard | Tab |
| X-Ray vision (offline) | X |
| Pause | Esc |
| Training panel | T (in the Training Room) |

You can change any key in **Settings → Controls**.

## How it works

```mermaid
flowchart LR
    subgraph Host browser
        W[World<br/>rules + events]
        B[Bots]
        W --- B
    end
    subgraph Client browser
        P[Local player<br/>runs locally]
        R[Other players<br/>smoothed]
    end
    S[(serve.py<br/>room-code service)]
    P -- inputs + shots --> W
    W -- events, reliable --> R
    W -- snapshots 30 Hz, unreliable --> R
    S -. connection setup only .-> W
    S -. connection setup only .-> P
```

- **Events at the core.** The `World` node announces every game event (shots, hits, pickups, kills). Single-player handles those events locally. In multiplayer the host sends the same events to every client, so both modes run the same rules code.
- **Connections.** `tools/serve.py` serves the game and swaps WebRTC connection details using the room code. Once players are connected, game traffic goes straight between browsers and never passes through the server.
- **Levels are plain text.** Each arena is ASCII art in `src/data/maps.gd`, and the game builds collision, decoration, items and the bot navigation graph from it.
- **One place for balance numbers.** Weapons, projectiles, status effects and traps each have a single table (`weapons.gd`, `status.gd`, `traps.gd`).

## Performance

All numbers are from Chrome on the target laptop: Intel i3-1215U, integrated Intel UHD graphics, 1080p at 125% scaling, display at about 68 Hz. Each test is a 20-second all-bot match with 8 fighters and the HUD on.

| | Before | After |
|---|---|---|
| Average FPS (Deck-17 / Foundry / Cryo Station) | 17.7 / 19.9 / 17.0 | **68 / 68 / 68** (display refresh) |
| 99th-percentile frame time | 80-112 ms | **14.8 ms** |
| Draw calls per frame | 516-1294 | **about 40** |

What made the difference:
- **Batching.** In Godot's GL Compatibility 2D renderer, every `draw_circle`, `draw_polygon`, `draw_polyline` and `draw_arc` is its own draw call and creates new GPU buffers on every redraw. All dynamic drawing (fighters, particles, pickups, projectiles) now uses quads from one shared texture atlas (`DrawUtil`), which Godot batches into a handful of instanced draw calls.
- **Static layers baked once.** Level tiles, decoration and parallax backgrounds are baked into one mesh per layer (`StaticDraw`). On Cryo Station that cut level drawing from 1000 draw calls to 8.
- **Less work each frame.** Pickups and traps only redraw when their state changes, particles are pooled with no per-frame allocation, the living-players list is cached, and nav graphs are built once per map and reused. Sounds are preloaded and registered as web samples so the first shot doesn't stall the frame.
- **Engine settings.** `allow_hidpi=false`, a cap on physics catch-up steps, and the background match behind the menu freezes on sub-screens.

The web build has a benchmark mode built in: open `index.html?bench=20&map=2&bots=7` (add `&xray=1` to include the overlay), and the results are published as `window.__bench`.

## Tests

The dev tools live in `src/dev/` and are left out of exported builds.

```bash
godot --headless --path . -- --test=combat                # rules and mechanics
godot --headless --path . -- --test=menu                  # menus and match flow
godot --headless --path . -- --test=nav                   # bot navigation on every map
godot --headless --fixed-fps 60 --path . -- --test=bot    # bots play every arena (fast-forwarded)
godot --headless --path . -- --test=regress               # regression checks for recent fixes and features
godot --headless --fixed-fps 60 --path . -- --test=mode   # Gun Game / Instagib / Rocket Arena
godot --headless --path . -- --test=touch                 # touch controls and the QR code
godot --headless --path . -- --test=announcer             # announcer lines and priorities
godot --headless --path . -- --test=stats                 # match stats, awards, results screen
godot --headless --path . -- --test=audio                 # every sound loads; loops loop
godot --headless --path . -- --test=sfx_hooks             # gameplay sound triggers
godot --path . --rendering-driver opengl3 -- --shots=/tmp/fragline-shots   # screenshot every map
```

## Deploying

The web build is a plain static site. It works on itch.io, GitHub Pages, Cloudflare Pages, Vercel or any other static host. Turn on gzip or brotli on the host: it shrinks the engine's `.wasm` file from about 39 MB to about 10 MB. Joining LAN matches needs the web build, because desktop builds would need Godot's `webrtc-native` extension.

## Project layout

```
src/
  autoload/   settings (preferences, audio, input rebinding), sfx (pooled audio), music, net (rooms + WebRTC)
  data/       weapons, characters, maps (ASCII arenas), status effects
  game/       world (rules + events), player, level building, projectiles, pickups, traps,
              fx, hud, bots (nav_graph, bot_brain), training room, shaders
  ui/         menus, settings, theme, character and map previews
  dev/        headless tests and the screenshot tool (not exported)
assets/       audio (Kenney CC0, LMGLolo CC BY-ND, SnakeF8), music (The Cynic Project, CC0),
              sprites (SnoopethDuckDuck guns, CC0), fonts (Chakra Petch, OFL)
addons/       qr_code (Kenyoni, MIT; encoder only)
tools/        build_web.sh, serve.py, web/ (loading page, icons, social card)
```

## Credits

Built with [Godot Engine](https://godotengine.org). Sound effects are by Kenney, LMGLolo (FREE FPS SFX Pack, CC BY-ND 4.0, unmodified) and SnakeF8 (Snake's Authentic Gun Sounds). Weapon sprites are by SnoopethDuckDuck (CC0). Music is by The Cynic Project, and the font is Chakra Petch. See [CREDITS.md](CREDITS.md) for full attribution and licences.

*FRAGLINE is an independent tribute. It shares no code or assets with Unreal Flash or Unreal Tournament.*
