# POLARITY

A one-thumb magnet-combat arena. Hold to attract, release to repel. Absorb
scrap to grow, launch rivals into hazards or out of the shrinking ring, be the
last magnet standing.

Godot 4.3 · GDScript · one codebase → Android, iOS, Web.

> **Read [DECISIONS.md](DECISIONS.md) first.** It states exactly which systems
> exist and which do not. This is the core loop plus save/economy/settings —
> not the full commercial feature set in the build spec.

---

## Run it

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . 
```

Or open the folder in the Godot editor and press F5.

**Controls** — hold anywhere (touch or left mouse) to attract and steer toward
your finger; release to fire a repel burst. Keyboard: WASD/arrows to steer,
space/shift to attract. Esc returns to the menu.

The single gesture is the whole game: holding is how you farm *and* how you
charge your weapon, so every second you spend growing is a second you are not
armed.

## Test

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/tests.tscn
```

49 assertions, exits non-zero on failure. Covers magnetism maths, save
migration, economy clamps, reward calculation, input intent, the scrap field,
and an arena start/teardown leak check.

```bash
/Applications/Godot.app/Contents/MacOS/Godot res://tests/smoke.tscn
```

Plays a real match end-to-end through real physics and real bots. Needs a
renderer (drop `--headless` or it skips the visual assertions). Add
`-- --real` for a full-length match, `-- --shot=/tmp/x.png` to capture a frame.

Headless runs print `mesh_get_surface_count: Parameter "m" is null` — that is
the dummy renderer, not a game error. Filter with
`grep -v mesh_get_surface_count`.

## Export

Presets for Web, Android and iOS are in `export_presets.cfg`.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --export-release "Web" build/web/index.html
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --export-release "Android" build/android/polarity.aab
```

Serve the web build over HTTP (not `file://`):

```bash
python3 -m http.server 8777 --directory build/web
```

The web export is single-threaded so it runs on hosts that cannot set
COOP/COEP headers. PWA manifest, service worker and offline page are enabled.

**Signing** — no keystore or team ID is in this repo, and `.gitignore` keeps it
that way. Set the Android keystore in the editor's export dialog (or
`export_credentials.cfg`, untracked) and the iOS team ID in the preset before
a release build.

---

## Architecture

```
main.tscn ─ main.gd            root; owns the UI, swaps the arena in/out
  ui.gd                        every screen, built in code, responsive
  camera_rig.gd                ortho follow cam, trauma shake, clip punch
  arena.gd                     match FSM + ALL cross-entity interaction
    magnet.gd                  player and bots — identical physics
    bot_brain.gd               5-state FSM writing move_dir/holding
    scrap_field.gd             MultiMesh scrap sim over flat arrays
    fx.gd                      pooled shockwaves, bursts, floating numbers
autoload/  Bus  Platform  Audio  Game
data/default_tuning.tres       every gameplay constant
shaders/   magnet  ring  floor
```

Two rules hold the design together:

**Interaction lives in `arena.gd`, not in the entities.** Attraction, contact
bites, repel, hazards and ring pressure are one readable pass per frame rather
than N objects reaching into each other. Entities own only themselves.

**UI never touches gameplay.** It listens to `Bus` signals. Gameplay emits and
never knows the UI exists.

`Platform` is the only file that branches on operating system. Ads, IAP,
haptics, share and safe areas all route through it, so adding a real SDK
touches one file and no gameplay code (spec §2A).

---

## Tuning the game

**Every gameplay number lives in `data/default_tuning.tres`.** Open it in the
inspector; nothing in `scripts/` hard-codes a constant. `scripts/tuning.gd`
documents each field and holds the derived curves (`radius_for`, `speed_for`,
`pull_force`).

Balance rules that are easy to get wrong — all learned the hard way, see
DECISIONS §9–10:

- **Budget drains against `start_mass - min_mass`, not `start_mass`.** With
  `start_mass 10` and `min_mass 3`, a magnet has 7 mass of survivability. A
  drain of 10/s kills in 0.7s, not 2.5s.
- Keep `absorb_mass_ratio` well above 1.0. At 1.12, eating two scrap pieces let
  you delete a neighbour.
- `kill_bounty` multiplies the victim's **peak** mass, not their remaining mass.
- Keep `max_launch_speed` above `base_speed` but finite. Uncapped, stacked
  repels put a magnet at 4x its own top speed.

### Change match length / lobby size
`match_duration`, `bot_count`, `ring_start_radius`, `ring_end_radius`,
`ring_shrink_delay`.

### Make launches more spectacular
Raise `repel_impulse` and `max_launch_speed` together, and raise
`shake_launch` / `hitstop_time`. Lower `clip_power_threshold` to trigger the
slow-motion clip cam more often.

### Add a hazard
`arena.gd` → `_build_hazards()` for placement (keep it outside
`ring_end_radius * 1.15` or the endgame has nowhere to fight), `_hazards()` for
the per-frame effect, `_hazard_node()` for the visual. Everything is a distance
check against a small list.

### Reskin
Colours and button styles: `ui.gd` → `_build_theme()` and the `BG`/`ACCENT`/
`HOT` constants. Magnet look: `shaders/magnet.gdshader` and the `PALETTE` table
in `arena.gd`. Arena floor: `shaders/floor.gdshader`.

### Swap in real art / audio
Meshes are built in `magnet.gd` (`_build`) and `scrap_field.gd` (`setup`) —
replace the primitives with loaded `.glb` resources. Sounds are registered in
one dictionary in `audio.gd` → `_build_sfx()`; replace synthesised
`AudioStreamWAV`s with loaded `.ogg` files. `Audio.play_music()` is an empty
hook waiting for stems.

### Add a language
Strings are **not** externalised yet (DECISIONS §0). They are literals in
`ui.gd`. Wrap them in `tr()` and add a translation CSV before shipping outside
English.

---

## Performance

Targets 60fps on mid-range 2020 hardware. What keeps it there:

- One draw call for all scrap (MultiMesh), no per-frame allocation in the sim.
- No real-time shadows; glow only on emissive accents.
- All FX pooled and preallocated.
- Auto quality scaler watches frame time and drops particle work and 3D
  render scale together. Override in Settings.

The known ceiling is the naive scrap↔magnet loop — fine to ~2000 scrap or ~40
bots, then it needs a spatial hash. Marked in `scrap_field.gd`.
