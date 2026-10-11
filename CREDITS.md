# Credits

## Engine
- **Godot Engine 4.7** — MIT License — https://godotengine.org/license

## Code
- **QR Code addon** by Kenyoni Software (Iceflower S), from https://github.com/kenyoni-software/godot-addons
  — MIT License. Used for the lobby's "scan to join" QR code. `addons/qr_code/` holds the encoder
  scripts only (no editor plugin), with the large Shift JIS table swapped for a small ASCII stub since
  Kanji mode isn't used. The licence is in `addons/qr_code/LICENSE.md`.

## Audio
- **Kenney** — *Sci-fi Sounds*, *Impact Sounds*, *Interface Sounds* — Creative Commons Zero (CC0)
  — https://kenney.nl/assets
  (The `.ogg` files in `assets/audio/` are renamed copies of a subset of these packs.)
- **FREE FPS SFX Pack** by LMGLolo — https://lmglolo.itch.io/free-fps-sfx — CC BY-ND 4.0
  (https://creativecommons.org/licenses/by-nd/4.0/) — used unmodified (format-converted for web playback only).
  Files: `flak1-4`, `flak_pump`, `rocket1-4`, `rocket_loop`, `sniper1-3`, `explode1-4`, `death1-6`,
  `step1-6`, `land`, `jump`, `low_ammo`, `fall_loop`, `equip_5` (`.wav`, byte-identical copies of the originals).
- **Snake's Authentic Gun Sounds And More** by SnakeF8 (F8 Studios) — https://f8studios.itch.io/snakes-authentic-gun-sounds
  — free for commercial use, credit not required (per the itch.io page, 2026-10-11); credited with thanks;
  some sounds trimmed/edited. Files: `pistol1-3`, `minigun1-3`, `grenade`, `flak_alt`, `equip_0-4`, `equip_6-8`,
  `pickup_weapon`, `kill_confirm`, `headshot` (`.wav`; trimmed, faded, pitch-shifted, saturated or layered).

## Music (all CC0 — public domain; credited with thanks)
All tracks by **The Cynic Project / cynicmusic.com** (OpenGameArt):
- **"Calm Relax 1 (Synthwave 421k)"** — menu theme — https://opengameart.org/content/calm-relax-1-synthwave-421k
- **"Hyper Ultra-Racing"** — https://opengameart.org/content/hyper-ultra-racing
- **"Hyperflight Racing"** — https://opengameart.org/content/hyperflight-racing
- **"Awake! (Megawall-10)"** — https://opengameart.org/content/awake-megawall-10

(Files in `assets/music/` are trimmed, loudness-normalised, re-encoded copies.)

## Art
- **"Guns"** pixel-art weapon sprites by **SnoopethDuckDuck** — https://snoopethduckduck.itch.io/guns
  (also on OpenGameArt, https://opengameart.org/user/88671) — Creative Commons Zero (CC0 1.0,
  https://creativecommons.org/publicdomain/zero/1.0/); credited with thanks, not required.
  `assets/sprites/guns.png` is an atlas of nine sprites from the pack (2px-outline variant,
  upscaled 4x nearest-neighbour): Enforcer = Pack 1 #26, Flak Cannon = Pack 1 #51,
  Minigun = Pack 1 #48, Shock Rifle = Pack 2 #33, Pulse Gun = Pack 1 #32,
  Rocket Launcher = Pack 1 #50, Grenade Launcher = Pack 1 #42, Sniper Rifle = Pack 1 #56,
  Redeemer = Pack 2 #15.

## Fonts
- **Chakra Petch** by Cadson Demak — SIL Open Font License 1.1 — https://github.com/m4rc1e/Chakra-Petch
  (`assets/fonts/title.ttf` = Chakra Petch Bold, `assets/fonts/ui.ttf` = Chakra Petch SemiBold;
  the full licence is in `assets/fonts/OFL.txt` and is packaged with every build.)

## Inspiration
- *Unreal Flash* (2006), a Newgrounds Flash game by Erik S, itself a tribute to *Unreal Tournament*.
  FRAGLINE shares no code or assets with either.

All characters, levels, effects and UI art (everything except the weapon sprites above) are drawn procedurally in code for this project.
