# DECISIONS

Every deviation from the build spec, and why. Read this before assuming a
feature exists.

---

## 0. Scope: what actually got built

The spec describes a full commercial hybrid-casual title (§4 alone lists ~60
systems across meta-progression, battle pass, IAP, liveops, backend,
localization and social). **This delivery is M0 + M1 + almost all of M2.**
Live state is tracked in [PROGRESS.md](PROGRESS.md), which is authoritative —
this section is a summary and can lag.

The spec's own build plan says M1 "must be genuinely fun before anything else",
and §16 says to deviate toward "simpler, more fun, more shippable". That is the
tradeoff taken: one complete, verified, playable vertical slice rather than
sixty half-wired systems.

**Built and verified:**

| Area | State |
|---|---|
| Magnetism, growth, repel/launch, mass economy | Complete, tuned, unit-tested |
| Bots (5-state FSM, skill spread, no cheating) | Complete |
| Arena, shrinking ring, sudden death, hazards | Complete |
| Match FSM `COUNTDOWN→PLAYING→SUDDEN_DEATH→FINISHED` | Complete, integration-tested |
| Juice: shake, hitstop, shockwaves, bursts, floaters, squash | Complete |
| Audio: 13 synthesised SFX, buses, volume, focus-mute | Complete (placeholder quality) |
| Input abstraction (touch / mouse / keyboard) | Complete, unit-tested |
| Responsive UI, safe areas, landscape clamp | Complete |
| Save/load, versioned migration, corruption recovery | Complete, unit-tested |
| Coins / XP / levels / match rewards | Complete, unit-tested |
| Settings (audio, haptics, reduced motion, quality) | Complete |
| Menu / HUD / results / share | Complete |
| Quality scaler | Complete (single dial) |
| Web + Android + iOS export presets | Written; Web export verified end-to-end in-browser |
| Localization: 75 keys x 10 languages, runtime switch, RTL wiring | Complete, CJK verified |
| Cosmetics: 35 items across 5 kinds, rarity, loadout, all visually wired | Complete |
| Shop / missions / battle pass / daily reward / rank ladder | Complete, unit + integration tested |
| Currency ledger (sources and sinks auditable) | Complete |

**Not built** (no code, not stubbed, do not assume): FTUE/onboarding, ads,
IAP, consent/ATT flows, remote config, A/B testing, liveops events,
segmentation, analytics, crash reporting, leaderboards, cloud save, auth,
notifications, referral/deep links, rating prompt, gacha, emotes/victory poses,
online multiplayer, CI.

Where the spec demanded a system that needs a live credential or vendor
account, see §7 below — it is deliberately *not* faked.

---

## 1. Godot 4.3, not 4.4+

4.3.stable is what is installed on this machine. Nothing used here needs 4.4.
Bump `config/features` in `project.godot` when upgrading.

## 2. Four autoloads, not seventeen

Spec §5 lists 17 singletons. Fourteen of them would have been empty shells
around a `match OS.get_name()`. Shipped: `Bus` (signals), `Platform` (all
platform branching + null providers), `Audio`, `Game` (config + save + economy).

`Platform` is the single seam the spec's §2A demands — gameplay never calls
`OS.get_name()`. Split it into real services when a real SDK lands; the call
sites do not change.

## 3. No `.tscn` scenes except three trivial roots

UI and entities are built in code. The layout is driven entirely by runtime
breakpoints and safe-area insets, so a scene file would be a second place to
keep the same anchors in sync — and hand-authored `.tscn` anchor blocks are
exactly what broke twice during this build (see §9).

## 4. Scrap is a MultiMesh over flat arrays, not nodes

400+ `RigidBody3D`s will not hold 60fps on a mid-range phone, and scrap needs no
collision against anything except a magnet — which is one distance check. So:
`PackedVector3Array` position/velocity, one `MultiMesh`, one draw call, no scene,
no object pool.

Cost: the scrap↔magnet loop is naive O(n·m), ~6.3k squared-distance tests per
frame at 420 scrap × 15 magnets. That is free. Marked in
`scrap_field.gd` with the upgrade path (spatial hash) if scrap exceeds ~2000 or
bots exceed ~40.

**Consequence accepted:** one mesh means one shape. Variety comes from
per-instance scale and colour, not from the bolts/nuts/gears/shards set in
spec §13A.

## 5. Magnets are `CharacterBody3D`, not `RigidBody3D`

Rigid bodies give launch physics for free but make direct control mushy, and
fighting a rigid body for crisp steering is more code than integrating velocity
by hand. `CharacterBody3D` in `MOTION_MODE_FLOATING` gives crisp control,
free collision/sliding, and launching is just `velocity +=`.

## 6. Procedural meshes and procedural audio — no asset pipeline

Spec §13/§13A/§13B want a Blender→glTF pipeline and ~25 licensed SFX plus music
stems. Shipped instead: Godot primitives with three custom shaders, and 13 SFX
synthesised at boot from sweeps, noise bursts and envelopes.

Rationale: zero licensing risk, near-zero web payload (the whole game `.pck` is
93 KB), and no binary assets to manage. **These are placeholder-grade.** The
magnet is a two-tone cylinder, not a horseshoe; scrap is a box. Real art and
real audio are a straight swap — meshes are built in `magnet.gd`/`scrap_field.gd`
and sounds are registered in one dictionary in `audio.gd`.

**No music.** Procedurally generated loops sound worse than silence.
`Audio.play_music()` exists and no-ops; drop in `.ogg` stems and fill it in.

## 7. Ads and IAP are null providers that report themselves unavailable

`Platform.ads_available()` returns `false` and `show_rewarded()` calls back with
`false`. This is deliberate and is **not** the same as a stub that pretends to
work: every caller already takes the "no ad" path, so nothing is gated behind a
fake success that would silently grant currency in production.

AdMob (mobile) and CrazyGames/Poki (web) need vendor accounts and app IDs — per
spec §16, money and vendor choice are the user's call. Wire them into
`Platform`; no gameplay code changes.

Consent/ATT/GDPR flows are **not** implemented, because they gate ad SDK init
and there is no ad SDK. Do not ship ads without them.

## 8. Web: single-threaded, PWA on

`variant/thread_support=false`. Threads require the host to serve
`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`, which most game
portals and static hosts will not do. Single-threaded runs everywhere; flip the
flag and add the headers if you need threads.

PWA (manifest, service worker, offline page, icons) is enabled and verified in
the export output. Web haptics and Web Share need a JS bridge and currently
fall back to clipboard — flagged in `platform.gd`.

Web safe-area insets use a flat proportional pad rather than reading CSS
`env(safe-area-inset-*)`, which needs JS interop. Clears iOS Safari chrome; not
pixel-exact.

## 9. Bugs found by testing during this build

Recorded because each one was invisible without the check that caught it:

1. **All 420 scrap invisible until the countdown ended.** Initial spawn skipped
   writing the MultiMesh instance transform, so every piece sat on the identity
   transform stacked at the world origin. Caught by a screenshot, now asserted
   in `smoke.gd`.
2. **Test suite reported 47/47 green with the UI completely broken.** A parse
   error in `ui.gd` made `Ui.new()` return null; nothing asserted the UI existed.
   Now asserted, including that the menu has a non-collapsed rect.
3. **Safe-area container silently discarded the landscape layout.** It was a
   `MarginContainer`, and containers overwrite child anchors every layout pass.
4. **Hidden Controls skip layout**, so a screen hidden during a viewport resize
   came back with a zero rect. `show_screen()` now re-asserts the preset.
5. **Hurt flash pinned at full white.** Continuous drains call `lose_mass` every
   frame, re-setting the flash before it could decay, so every magnet in a melee
   became an unreadable white blob. `flash` is now a strength, not a boolean.
6. **Damage budgeted against the wrong number.** Drains were sized against
   `start_mass` (10) instead of the real survivability budget
   `start_mass - min_mass` (7), making saws ~4x too lethal — 0.7s to kill.
7. **Repel impulses stacked without a ceiling**, putting a magnet at 4x its own
   top speed. Unrecoverable, and it read as deletion rather than launch. Capped
   by `max_launch_speed`.
8. **Hazards and spawns could overlap**, and magnets spawned close enough to the
   boundary that one enemy repel was an instant unearned kill.
9. **`await`-based hitstop leaked coroutines** when a match ended mid-freeze.
   Replaced with a wall-clock deadline.

## 10. Balance rules worth keeping

- **Budget every drain against `start_mass - min_mass`, not `start_mass`.**
- **Kill bounty pays off the victim's *peak* mass.** Victims always die at
  `min_mass`, so a remaining-mass bounty is worthless and killing a giant would
  pay the same as killing a rookie.
- **Contact bites destroy ~25% of the mass they move.** Without that sink, two
  magnets trading bites inflate the arena's total mass.
- **The camera fixes the minor axis.** Orthographic `size` applies to one axis;
  fixing height showed ~10 world units across on a portrait phone, narrower than
  the player's own pull diameter. Fixing the minor axis also means an ultrawide
  monitor grants no extra vision.

## 11. Bots roam to random waypoints

They do not search for the densest scrap. Attraction brings scrap to them, so
the behaviour reads identically and it skips a 400-item search per bot per
think. Revisit if bots look aimless on camera.

## 12. `.io` lobby is bots, single-player

Per spec §7. Bots use the same physics, the same abilities and the same
release-edge repel as the player — they cannot do anything a human cannot.
Do not claim live PvP in store copy.

## 12a. Localization: CSV, static helper, rebuild-on-switch

Strings live in `data/i18n/strings.csv` (70 keys × 10 languages), which Godot
imports to `.translation` resources. `Locale` is a **static helper, not an
autoload** — switching language is three `TranslationServer` calls, which does
not justify a fifteenth singleton. `Game` owns the saved preference.

`tr()` resolves when a Control is *constructed*, so changing language rebuilds
the UI (`Ui.rebuild()`) rather than refreshing text in place. It preserves which
screen is showing.

Two things this caught that would otherwise have shipped:

- **A format-arg mismatch blanks a label in every language at once.**
  `UI_WALLET` declared `%d` for the coin count while the code passed
  `Locale.number()` (a String); the whole line silently rendered empty, with no
  error at build time. There is now a test that formats every parameterised key
  with the exact argument types the UI passes.
- **CJK glyph coverage** was verified by screenshot, not assumed — Godot 4.3's
  default theme font does render Japanese and Korean. A custom font would need
  an explicit CJK fallback.

RTL is wired (`Locale.is_rtl` drives `Control.layout_direction`) but no RTL
language ships yet, so it is untested against real content.

## 12b. Meta layer: JSON catalogues, one autoload, static lookups

`data/cosmetics.json` and `data/meta.json` hold every skin, mission, battle-pass
tier and rank. Adding content is a data edit (spec §16). `Cosmetics` is a static
lookup over `Game.profile`; `Meta` is the fifth and last autoload, because
missions genuinely need to listen to signals over time.

Decisions worth knowing:

- **Gameplay never knows missions exist.** The arena emits "scrap absorbed" and
  "player eliminated a rival"; `Meta` counts them. No gameplay file imports the
  mission system.
- **All periods are UTC day indices.** Local-time rollover lets a player
  re-claim a daily by changing timezone.
- **Missions are picked deterministically** from `hash(scope:period)` with a
  local RNG. `Array.shuffle()` uses the global RNG, so the player would have
  been handed different missions on every launch.
- **Kill bounty, mission targets and prices are all data.** No gameplay script
  contains a number that a designer would want to tune.
- **Cosmetic names are not translated.** They are proper nouns ("Gold Rush",
  "Singularity"), which is standard for the genre and avoids 10 columns × 35
  items of low-value translation.
- **Seasons count from a launch epoch** (`epoch_day` in meta.json). Without it
  `season = unix_day / 28` and the game shipped showing "SEASON 737".

Bugs this round, all caught by running rather than compiling:

1. A daily-reward popup at 0.97 alpha **ghosted through** the shop panel on top
   of it. Opaque now, and opening the shop closes the popup.
2. Five cosmetic-category buttons in one row **overflowed a portrait phone** and
   pushed the whole panel off the right edge. Now a 3-column grid, with
   `clip_text` on tab buttons so long translations shrink instead of expanding.
3. `"Finish top 3" % target` — a mission name with no `%d` **corrupted its own
   label**. Names are only formatted when they contain a placeholder.
4. Weekly reset timers rendered as `143:59:12`. Durations past a day read as days.

## 12c. M3 services: real policy, Null transport

Four new autoloads — `Config`, `Analytics`, `Ads` (plus `Meta` from M2) — for
nine total. Each has genuine state and lifecycle; the fourteen the spec lists
that would still be empty shells remain folded into `Platform` / `Locale`.

**The policy is real even though the transport is not.** No vendor is chosen, so
`Platform.ads_available()` is false and analytics drains to a local JSONL file.
But the frequency caps, the daily rewarded cap, the consent gate, the COPPA
branch, the kill switch, the bounded offline queue and the batch-retry are all
implemented and unit-tested — those are exactly the parts that get bolted on
badly when a vendor is wired in late.

- **A reward is granted only on a genuine completion callback.** With no
  provider the callback fires `false`, the player keeps what they already
  earned, and nothing is gated.
- **The monetisation kill switch beats every individual ad flag.** Tested,
  because a kill switch that any flag can override is not a kill switch.
- **Under-13 is never asked about personalisation** and sees no ads at all.
- **`clear_remote()` exists** because `apply_remote()` writes to disk and
  reloads on launch: a bad payload — say one that sets the kill switch — would
  otherwise persist across every restart with no way back short of reinstalling.
  This was found when a test payload poisoned the next test run.
- **A/B buckets hash the install id**, so assignment is stable without a server.

Bugs found by running it:

1. The **daily reward popup drew over the age gate** — a legal precondition
   covered by a monetisation prompt. Consent now suppresses everything until
   resolved.
2. The test suite was **mutating the real save file**. It only looked harmless
   because runs finished faster than the one-second save debounce; once the
   suite grew past a second, purchases persisted and the next run failed on
   state left by the previous one. The suite now snapshots and restores.

## 12d. IAP: swappable provider, one grant path

`Store.Provider` is an object you replace to plug in Play Billing / StoreKit /
a portal store. The shipped one reports unavailable and grants nothing.

The important structural choice: **every grant goes through one `_grant()`**,
whether it came from a purchase or a restore. The tests inject a fake billing
provider and drive the real grant, restore and revoke paths — otherwise none of
that logic would be exercised until the day an SDK is wired in, which is exactly
when it is most expensive to find out it is wrong.

- **`no_ads` suppresses interstitials and banners but NOT rewarded video.**
  Rewarded is opt-in and value-positive; taking it from the player who paid
  would be a downgrade.
- **Offers are never shown to someone who has not played yet** — the "new"
  segment is gated behind `offers.starter_pack_after_matches`.

**Known gap:** there is no server, so a receipt is not validated before granting.
That is marked at the call site. Do not ship real IAP without server-side
validation.

Bugs found by the injected-provider tests:

1. **`revoke()` could never clear the no-ads entitlement.** It asked
   `has_no_ads()` to decide whether to clear the flag that `has_no_ads()` reads,
   so the answer was always "still entitled" and a refunded purchase kept
   working forever. Now recomputed from the remaining entitlements.
2. **"engaged" — the largest segment — had no offer configured at all.** Every
   other cohort had one.
3. A test-harness bug worth recording: **GDScript lambdas capture locals by
   value**, so `res = r` inside a purchase callback never reached the assertion.
   Result-carrying tests use a single-element Array.

## 12e. M4/M5: backend seam, power-ups, accessibility

`Backend` is one autoload for auth + cloud save + leaderboards + referral,
because in practice they are one vendor account. The conflict merge is
deliberately *outside* the provider — it is the piece that loses player money
when it is wrong, so it is pure, static and unit-tested.

Merge rules, ordered by how much damage getting them wrong does: currencies take
the **max** (summing double-credits every sync, last-write-wins deletes money
earned on another device), entitlements **union**, best placement takes the
**min**, everything else is last-write-wins. Verified symmetric and idempotent.

**Power-ups apply to bots identically.** A pickup only the player can use is set
dressing, and bots would ignore a third of the arena.

**The colourblind palette changes the poles to blue/yellow.** Red/blue is the
worst possible pair for the two most common types of colour blindness, and the
shader's hard model-space split already provides the shape redundancy the spec
asks for.

**Reverse-polarity zones invert the verb, not the damage.** They are the one
hazard that is a puzzle rather than a health bar.

Bugs found this round:

1. **The share card hung forever headless.** It awaited
   `RenderingServer.frame_post_draw`, which never fires without a renderer — the
   test suite deadlocked. It now declines before the await. The same bug would
   hang CI.
2. **`revoke()` could never clear the no-ads entitlement** (see §12d).
3. **The leaderboard sampled names with replacement**, putting "Gauss" on the
   board three times — which reads as fake immediately.
4. **Tab rows clipped labels** at four and five tabs ("MISSIO", "LEADERB"), and
   worse in German. Tabs now wrap in a grid rather than shrinking.
5. A test asserted the share card *must* render, which would have failed in
   exactly the headless environment where declining is correct.

## 12f. Art pass: generated geometry, not a DCC pipeline

`meshes.gd` builds an ArrayMesh horseshoe magnet and four scrap shapes (hex nut,
bolt, gear, shard) procedurally. Still not a Blender pipeline — the reasoning in
§6 stands — but these are real modelled shapes inside the spec's §13A tri
budget, not primitives, and a shape is a parameter change rather than a round
trip through a DCC tool.

Scrap is now one MultiMesh **per shape** — four draw calls instead of one, which
is still nothing, and the field stops reading as a box factory.

Two bugs the screenshots caught:

1. **Every solid prism shipped with a wedge missing from both caps.** The cap
   fan ran inside the wall loop, so its first triangle was degenerate
   (centre, next, centre) and the last was never emitted. Bolts and shards were
   visibly open.
2. **Scrap rendered near-black.** Metallic 0.75 with no reflection probe or sky
   has nothing to reflect, so high metallic just darkens — the opposite of the
   "gameplay objects always pop" rule. Low metallic plus faint emission gives
   the intended rim-lit metal.

Still placeholder-grade: no icon set (colour swatches stand in), no music, and
the magnet is a generated horseshoe rather than an authored asset with skinned
variants.

## 12g. Loading screen is fire-and-forget

Arena construction is staged into four steps with a frame between each, so the
loader reports real progress instead of animating a lie.

The loader **dismisses itself** and nothing awaits it. An earlier version had
`start_match()` await a `finished` signal that the loader emitted immediately
before `queue_free()` — which could strand the awaiting coroutine and hang match
start entirely. Decoupling removed the whole class of failure.

Making `start_match()` async had a second consequence worth recording: the
camera rig is now in the tree for several frames before `setup()` builds its
camera, so `_process` had to tolerate a null camera. Every caller must `await`
it or inspect a half-built arena.

## 12h. Blender pipeline: written, not run

The spec's §13A asks for assets authored in Blender and exported as glTF. That
has **not** happened, for a checkable reason: there is no Blender MCP connected
to this session, none in the connector registry, and Blender is not installed on
this machine.

What exists instead:

- **`tools/blender_export.py`** — a complete `bpy` script producing all ten
  gameplay meshes as separate `.glb` files with clean topology, centred origins,
  vertex colours (no textures, per §13A's web-payload note) and material names
  matching a shared library. It exits non-zero if any asset breaks the §13A tri
  budget, so blowing the budget cannot pass silently.
- **`scripts/asset_library.gd`** — resolves each mesh by name: authored `.glb`
  when present, generated geometry otherwise. The project builds and plays
  either way, and the boot log prints exactly which assets came from files
  ("0 authored, 5 generated" today) so this is never a guess.

Running `blender --background --python tools/blender_export.py` populates
`assets/` and the game picks the files up on the next launch with no code change.

**Update — the Blender MCP is connected**, and its bundled API reference works
offline even with no Blender running. That turned out to matter: validating the
export script against it caught two calls that would have failed on the first
asset.

- `export_colors=True` is **not a parameter** of `bpy.ops.export_scene.gltf`.
  The real ones are `export_vertex_color` (enum) and `export_all_vertex_colors`.
  Instant `TypeError`.
- `mesh.vertex_colors` is documented as *"Legacy vertex color layers.
  Deprecated, use color attributes instead"* and is read-only, so writing
  through it fails on Blender 4.x. Now uses
  `mesh.color_attributes.new(type="FLOAT_COLOR", domain="CORNER")` with a 3.x
  fallback.

The MCP still cannot build geometry: it is a remote control for a *running*
Blender at localhost:9876, the extension bundles docs and no binary, and
`~/Applications/Blender.app` is an orphaned **Steam launcher stub** from 2022
whose `Contents/MacOS/` holds only a `run.sh` calling `open steam://run/365670`.
There is no Steam on the machine.

Honest state: pipeline real, API-validated against the user's own Blender
version, assets not yet authored, nothing pretending otherwise.

## 12i. Icon set: drawn, not shipped

`icons.gd` rasterises coin, gem, trophy, star, lock and check into ImageTextures
at first use — supersampled 4x and downscaled for clean edges. Same reasoning as
the synthesised audio: no binary assets, no licensing, no import step, a few KB
of RAM.

Rarity now carries a **star as well as a colour**, because colour alone is not
readable for a colourblind player — the shape-redundancy rule §13A asks for.

## 12j. Visual quality pass

Biggest wins in a stylised top-down game are not mesh density — they are
grounding, shading and silhouette. What landed:

- **Blob shadows** on every magnet and on all 420 scrap pieces (one extra
  MultiMesh for the whole field). §13A asks for these explicitly. Without them
  everything floated, which was the single worst readability problem.
- **Toon diffuse + specular and a fresnel rim** on magnet bodies, plus a faked
  contact-AO band at the base.
- **Two-light rig** — warm key, cool fill. One light left a curved horseshoe
  half-black and illegible.
- **Colour grading**: contrast 1.12, saturation 1.18, brightness 1.02.

**The bug underneath all of it: every generated mesh had wrong normals.** The
hand-written horseshoe shared one horizontal normal across wall *and* cap
vertices, so top faces were lit as vertical walls. That is why the meshes looked
flat and dark from the first art pass — and when a fresnel rim was added it
fired across the whole surface and rendered every magnet solid white. Rewritten
with `SurfaceTool` + flat smooth groups so Godot derives per-face normals.
**Never hand-author normals for generated geometry.**

Two things tried and reverted, recorded so they are not re-attempted:

1. **Inverted-hull outlines.** They assume closed, thick geometry. The horseshoe
   is a thin ring, so pushing along normals closed it from the inner and outer
   wall at once and the hull ate the body. Rim light plus blob shadow give the
   separation instead; `outline.gdshader` was deleted rather than left dead.
2. **Toon shading on scrap.** A 0.5-unit object at this camera distance has no
   room for a band, so the ramp just clips — every piece went flat white.
   Scrap stays lambert with a faint rim, which preserves the grey-to-brass
   gradient that encodes mass value.

## 12k. Music: synthesised, pentatonic, lazily built

§13B asks for adaptive music. Shipped: a 4-bar loop over Am-F-C-G with bass,
pad and arp layers, plus a separate intensity layer that fades in as the lobby
thins — not only at sudden death, so the tension builds rather than switching on.

Two decisions that make generated music survivable:

- **A minor pentatonic.** There is no wrong note in it, so a procedural melody
  cannot land on a semitone clash. That is the difference between "simple" and
  "broken", and it is why I previously said generated music would sound worse
  than silence — that was true of an unconstrained note choice, not this one.
- **Built lazily during the loading screen.** Both tracks cost ~300ms of
  synthesis, measured; doing it at boot is a visible hitch, doing it behind the
  loader is free.

I cannot judge whether it sounds *good*. What is asserted instead are the
failure modes that make generated audio unusable: silence, clipping, DC offset,
wrong length against the bar grid, and a click at the loop seam. All measured.

Still placeholder-grade against §13B, which wants licensed stems.

## 13. Testing approach

No GUT. Two plain suites, no framework:

- `tests/tests.tscn` — headless. Growth curves, pull force, repel power, save
  migration, economy clamps, match rewards, input intent, scrap field, arena
  lifecycle/leak check. 49 assertions.
- `tests/smoke.tscn` — real renderer. Plays a full match through real physics
  and real bots, asserts placements are unique and valid, that the ring produces
  eliminations, that the lobby is not wiped on spawn, and that an idle player is
  not deleted instantly. Seeded, because unseeded runs swing idle survival from
  1.7s to 4.6s and made the balance assertions flaky.

Headless cannot read back MultiMesh transforms (dummy renderer), so the scrap
positioning assertion lives in the smoke test.

## 14. No CI

Spec §12 wants GitHub Actions. This is not a git repository, and CI config that
has never run is decoration. The two commands CI needs are in the README.


## §12l — arena legibility pass (2026-07-30)

- `shaders/field.gdshader` (new) replaces the magnet pull-radius ring. Player only.
- `shaders/hazard_decal.gdshader` (new) replaces additive hazard/zone rings with
  mix-blended worn paint. `inner > 0` gives an annulus for pickup pads; filled discs
  made five overlapping powerups merge into one unreadable smear.
- `ring.gdshader` kept: still correct for the safe-zone boundary and shockwaves,
  which genuinely are emissive.
- `Meshes.saw_blade()` / `_star_prism()` (new). Saw was an 8-segment cylinder.
- Powerup palette de-neoned; it had been missed by the Part 1 sweep.
- `tests/smoke.gd --shot-at=N` (new). The old fixed 4s capture always landed during
  or just after the countdown, so anything driven by player input — the charge field,
  repel feedback — was idle and could not be verified from a screenshot. Every
  in-match visual bug found in this pass was invisible at 4s.


## §12m — UI identity pass (2026-07-30)

- `scripts/stencil.gd` (new). Drawn glyph set: POLARITY, 0-9, S/N/D, and the marks
  that appear beside a number. Deliberately partial — an unknown character advances
  the pen and draws nothing, so a missing glyph can never become a mystery box.
- `UiKit` rewritten: warm steel ramp, POLE_POS/POLE_NEG as semantic colour, `plate()`
  as the single surface primitive, four button tiers, `state_tag()`, `chip_row()`,
  `swatch()`, `snap()`, `weight_dur()`, proportional HUD halo.
- Old tokens (BG/PANEL/DIM/HOT/GOOD) kept as aliases pointing at the new warm values
  for ONE step, so the palette landed on every screen without a 99-site rename in the
  same commit. They must be deleted; two colour systems coexisting is how the next
  screen picks the wrong one.
- Rejected from the synthesised spec, on the adversarial pass's advice: Material
  elevation tokens (wrong light model for bolted steel), a 4-cell bottom nav bar
  (violates ART_DIRECTION:110, which outranks the spec), a 10-step neutral ramp, and
  `FontVariation` synthetic weight.
- Emission on paid skins CLAMPED to 0.08, not zeroed. Zeroing all eight would have
  removed the only thing the legendary tier looks like it is selling — a palette pass
  should not devalue the paid content as a side effect.
- `rarities` in cosmetics.json is a dict of dicts (`{"common": {"color": ...}}`).
  Flattening it to bare strings parses fine and then throws 30 runtime errors from
  `rarity_color`. JSON shape changes need a runtime check, not just a valid-JSON check.

### Still open after this pass

- Workstream 7 (HUD) not started: the board still rebuilds 11 rows + 33 labels three
  times a second (~130 node allocations/sec on the mid-range Android target), which is
  also the mechanical reason a rank change cannot animate. Charge meter is still a 4px
  strip at the extreme bottom edge. Minimap is a gauge but threat is hue-only.
- Results choreography (cascade, count-up) and screen transitions not implemented.
- Token alias deletion + the ~99-site rename.
- i18n rank keys and the `.translation` re-import step.


## §12n — HUD pass (2026-07-30)

- Leaderboard rows are built once, keyed by magnet name, hand-positioned in a plain
  Control (NOT a container — a container rewrites child positions every layout pass
  and would silently discard the rank tween).
- `UiKit.hud_lbl` halo is proportional to font size.
- `Bus.ring_changed` and `Bus.player_absorbed` now have consumers; both they and
  `clock_changed` are emitted every frame, so all three handlers early-out on
  no-change.
- Mission in-progress rows have NO action control. An in-progress mission has no
  action, so it gets no button.
- `MISSION_TOP_THREE_N` added for the weekly variant, 10 locales.
- `UI_LEFT_SHORT` added, 10 locales.
- `tests/smoke.gd`: `--shot-at=N`, plus a guaranteed capture at match end.

### Still open

- Deprecated `UiKit` aliases (BG/PANEL/DIM/HOT/GOOD) still exist and ~99 sites still
  name them. They must go; two colour systems coexisting is how the next screen
  picks the wrong one.
- Results choreography (stat cascade, reward count-up) and screen-to-screen
  transitions are not implemented. `UiKit.snap` and `weight_dur` exist for them.
- Battle-pass scroll-to-current-tier; store offer countdown is still frozen at build
  time; scroll position is lost on `_rebuild`.
- App icons at store sizes.


## §12o — token migration, results choreography, store/pass (2026-07-30)

- Deprecated UiKit tokens deleted; `ui.gd`'s local `const BG/HOT/DIM` deleted too.
  Role-based mapping, not a sed. `grep -rE 'UiKit\.(BG|PANEL|DIM|HOT|GOOD|RADIUS)'`
  returns zero, as does the bare-name grep.
- `Ui._choreograph` / `_count_up`: placement arrest, row cascade with a rising blip
  ladder, mass-weighted count-up on the two reward rows only.
- Removed the duplicated post-match `Audio.play("reward")`.
- `MetaPanel._buy_control`: one purchase affordance shared by the offer card and the
  product rows, so they cannot drift.
- Store offer countdown: one 1s Timer re-texting one Label, `_rebuild()` once on
  expiry. NOT a periodic rebuild — that would fight the scroll position.
- `MetaPanel._settle_scroll`: deferred, own function, `is_instance_valid` after the
  await. `_rebuild()` must stay synchronous because `open_tab()` depends on it.
- Terminal states are `state_tag`, never disabled buttons: pass rewards, store
  products without a provider, OWNED, CLAIMED, EQUIPPED, mission progress.
- `tests/menu_shot.gd`: `--settle=N` (default 1.9s) and `--reduced`. Six frames
  photographed the results cascade mid-flight and reported success.

### Still open

- Screen-to-screen transitions (`show_screen` is still six boolean assignments).
  `UiKit.snap` and `dur` exist for it.
- The daily-reward calendar and the two remaining hand-rolled modals are not on a
  shared `modal()` builder.
- App icons at store sizes; `floor_options.gdshader` style 2 (hex) still renders flat.


## §12p — modals, transitions, app icon (2026-07-30)

- `UiKit.modal` / `dismiss` / `enter`. Four hand-rolled modals collapsed into one.
  Scrim is 0.97 (opaque only for the age gate).
- Screen transitions are alpha-only and skip the HUD.
- Daily calendar: staggered cells, breathing today-cell (guarded against a
  zero-duration looping tween), centred grid, equal cell widths, tokenised colours.
- `tools/make_icons.gd` + `tools/make_icons.tscn`: nine sizes into `store/icons/`.
  Re-run it if the palette or the mark changes; the PNGs are build outputs.
- `config/icon` AND the five icon entries in `export_presets.cfg` now point at the
  generated set. The preset entries were empty strings, which Godot fills with its
  own default at export time — so setting only `config/icon` would have left the
  Android and PWA builds shipping the engine icon.
- `tests/menu_shot.gd --daily`: `--noconsent` marks today claimed, so the calendar
  could not be captured at all and the one screen whose job is to feel like a prize
  had never actually been looked at.

### Still open

- `floor_options.gdshader` style 2 (hex) renders flat; only worth fixing if asked.
- iOS/Android store builds have never been produced on this machine (no signing set
  up); only the Web export is verified end to end.
- No authored meshes or licensed audio — everything is generated in-engine, which is
  a deliberate call, not an omission (DECISIONS §6).


## §12q — affordance pass, age gate removal (2026-07-30)

- **Age gate removed at the user's request.** `Ads.personalised_allowed()` is now
  hardcoded false, because the game can no longer establish age. `is_child()` and
  `age_bracket` are retained so a publisher can reinstate the gate. The
  run_tests assertion is deliberately inverted with the reason in a comment.
- Consent strings rewritten in all 10 locales: the old copy offered a
  personalisation choice that no longer exists.
- `UiKit.icon_btn` / `icon_nav` / `nav_bar` / `new_dot` / `cap_width`.
- `Icons`: `bag`, `target`, `bars`, `gear`, `card`. `_poly(..., erase := true)` added
  because `_px` blends, so an alpha-0 fill silently does nothing.
- `card` rather than `gem` for the store tab: coin and gem are colour-locked so they
  read as currency anywhere, which means they cannot dim or highlight with a nav cell.
- `tools/icon_sheet.gd` + `.tscn`: renders every glyph and one invalid name.
- Reversal noted: Part 6 removed the slab tab bar on the advice of the adversarial
  design pass (ART_DIRECTION:110, "menus secondary and small"). That was right about
  the amber budget and wrong about affordance. Icons + captions + full width satisfy
  both.


## §12r — affordance follow-ups (2026-07-30)

- `Button.icon_alignment` defaults to LEFT and that applies even with no text, so
  every icon-only round button drew its glyph against the left edge of the circle.
  `icon_btn` now sets both icon alignments to centre explicitly.
- Card padding equalised to 24/24 (was 24/16), list separation 14 -> 24, and every
  list card has a 150px floor height. Switching terminal states from buttons to state
  tags had made the rows collapse to thin strips.
- Card text blocks are `SIZE_SHRINK_CENTER` vertically. With a floor height they were
  hanging at the top of the card while the action beside them was centred.
- `tests/menu_shot.gd` resets the locale to `en` unless `--locale` is passed. The flag
  writes into the profile, so one `--locale=ja` capture left every subsequent capture
  rendering in Japanese — a store screenshot came out fully localised with no
  indication anything was wrong. Same class of leak as the save-file mutation in §12.


## §12s — consent removal, horizontal poles, hardware nuts (2026-07-30)

- **Consent screen removed at the user's request.** `Ads.needs_consent()` is now
  hardcoded false and `_build_consent` is deleted. Ads were already contextual-only
  (§12q), and a contextual ad needs no permission — the ADS toggle in Settings is the
  player's control. `show_consent_if_needed` survives as a guard that pushes a warning
  if `needs_consent()` is ever flipped back on, because **AdMob's UMP and several EEA
  partners require their own consent flow before the first ad request**. Whoever wires
  a real network must reinstate one.
- Magnet pole split moved from model X to model Z. The camera looks straight down, so
  X is the screen horizontal — splitting on X drew a vertical divide. `UiKit.Swatch`
  was flipped to match, since a preview that divides the other way to the thing it
  previews is worse than no preview.
- Scrap colour: three fastener finishes plus a mass-driven brass shift.
  **Values were measured, not guessed.** Sun 1.0 + fill 0.45 + ambient 0.85 is ~2.3x,
  so the old 0.46 albedo clipped to white on any upward face — a clipped face has no
  shading and no hue left, which is what made the nuts look like plastic. A lit face
  measured 209/255 before, 173 after the first correction, 93 (p95) now.
- Elimination shockwave: `victim.radius() * 6.0` -> `* 2.6`, power 0.8 -> 0.6.
  Player field wash halved.
- Cosmetic kind filter uses `nav_bar` with five new glyphs (skin/trail/effect/plate/
  arena) at 118px, one step down from the 148px top-level bar.

### Object counts, as of this pass

Hazards (10 objects, 4 active kinds): 3 saws, 3 spikes, 2 fences, 2 reverse-polarity
zones. Conveyors exist but are tuned to 0 — the least readable hazard, kept as a
tunable rather than deleted.
Power-ups: 4 live on the field at a time, drawn from 5 kinds — Surge, Speed, Shield,
Mega Repel, Freeze.
Total non-scrap objects in an arena: **14**.


## §12t — charge wash, bot palette, object counts (2026-07-30)

- `magnet.gdshader` charge cue is `c *= 1.0 + charge * 0.20` — a multiply, chosen
  specifically because it cannot desaturate. Two prior attempts keyed off `edge`
  both washed the largest magnet to near-white. **Do not reintroduce a mix-to-white
  charge term.**
- `edge` (the view-facing keyline term) is not small on these bodies and varies per
  magnet. Unverified why; the keyline itself still looks right, so it is logged
  rather than chased.
- `arena.gd PALETTE` de-neoned (~26% saturation pull). It had been missed by every
  previous de-neon pass.
- Counts now: 2 saws, 2 spikes, 1 fence, 1 reverse zone, 3 power-ups = **9**
  non-scrap objects. Script defaults and `data/default_tuning.tres` kept in sync.


## §12u — CI that can actually fail, and the sensory pass (2026-07-30)

**`tests/screens.tscn` (new).** Structural check on every screen plus the icon set
and every sound. It exists because four times in this project a green check sat on a
broken screen, and every one was invisible for the same reason: `tests.tscn` never
builds a screen and `smoke.tscn` never looks at the one it builds.

Deliberately structural, not pixel-based: CI runners have no rendering device. A
screen that failed to build has no children, a screen that lost its layout has a zero
rect, a glyph that fell through to the fallback is byte-identical to every other
fallback, and a dead sound has zero peak. All four are checkable headless, and all
four are what actually went wrong.

**Both new checks were verified by breaking the code on purpose** — a commented-out
glyph case, an emptied `_build_hud`, and a sound decayed to silence. Each produced a
precise failure. A check that has never failed proves nothing.

**`tools/verify.sh` (new).** Everything CI runs, runnable locally — there is still no
git remote, so this is the only way any of it executes today. Fails on `SCRIPT ERROR`
as well as on assertions.

**CI was red and nobody knew.** `smoke.tscn` headless asserted scrap positions from
MultiMesh transforms, which the dummy renderer does not store — a guaranteed false
failure. The check now skips headless and says so out loud, and still runs under a
real renderer.

**Audio.** `_metal()` synthesises struck metal from inharmonic bar modes
(1 : 2.756 : 5.404 : 8.933 : 13.34) with per-partial decay. Impacts were sine and
square sweeps, i.e. beeps. absorb / hit / eliminate / size_up / charge_ready rebuilt
on it.

**Removed:** fences (`fence_count = 0`) — a white bar with the least readable
silhouette of any hazard and no reaction when it caught someone. Non-scrap objects
per arena: 9 -> 8.

**Results screen:** stats on a bolted plate, rewards separated by a rule and coloured
as gains, and a trophy delta with the current rank — the number that decides how hard
the next lobby is had appeared nowhere.

**Cosmetics:** 35 -> 56 items, and `UiKit.cosmetic_preview` draws per kind, so trails,
effects, nameplates and arenas stopped previewing as the same two-pole chip.


## §12v — repo, encryption, localisation, web shell (2026-07-30)

- **Repository created and pushed** to github.com/georges33tawk24/polarity.io. CI has
  never been able to run before this; it runs on every push now.
- **Save encryption at rest.** Device-derived key (`OS.get_unique_id()` + a build
  constant, SHA-256), XOR, base64, magic prefix. Named as obfuscation rather than
  security in the code, because a key on a device the player owns is not a secret —
  the threat model is a text editor, not an attacker. Deliberately NOT
  `open_encrypted_with_pass`, which throws on a wrong key and would turn one
  corrupted byte into an unrecoverable save; this degrades to "unparseable, fall back
  to the backup", which the existing loader already handles. Unsealed saves from
  older builds still load, so no migration step is needed.
- **Localised bot names** in `data/bot_names.json`, 10 pools, falling back to English.
  Flavour text rather than UI strings, so not in strings.csv.
- **`web/shell.html`.** Godot's default shell shows a bare bar and, on failure, a
  line of grey text with no way forward — on a 35 MB download that is a dead end.
  The new one is branded in the game's material, reports real progress, detects a
  stalled download separately from an error, and offers both a retry and a
  cache-clear (a stale service worker is the most common cause of a web build that
  will not start after an update).
  **Verified in a real browser**: the game boots, and the failure path was tested by
  hiding `index.wasm`.
- **Authored-audio seam.** I cannot license or download audio, so what shipped is the
  swap-in path, not the pack: `assets/sfx/<name>.{wav,ogg,mp3}` wins over the
  synthesised sound with no code change, and boot prints `sfx: N authored, M
  synthesised` so a half-installed pack is visible.


## §12w — rewarded revive (2026-07-30)

The first rewarded placement beyond double-coins (§4.4). Design constraints that
shaped it:

- **The arena HOLDS rather than finishing.** A new `AWAITING_REVIVE` state freezes
  the match while the offer is up. Everything that gates on `PLAYING` therefore
  stops, so the fight does not continue without the player watching it.
- **The offer only appears when an ad genuinely exists** (`Ads.rewarded_available()`),
  because an offer that then fails to deliver is worse than no offer.
- **Every exit answers.** Accept, decline, ad-failed, and an 8-second auto-decline all
  end in `revive_player()` or `decline_revive()`. The failure mode here is a match
  that never ends, so this is the one thing the test suite proves exhaustively.
- Revived at 45% of PEAK mass (remote-configurable) at the most open spot inside the
  ring — survivable, but dying is still a real loss.
- Bots are never revived. A bot that came back would make the leaderboard lie.

**The test caught itself corrupting the run, twice.** First it was called during
`_ready()`, so `decline_revive()` ended the match before it had played (0 eliminations).
Then it ran inside `_on_ended` before the result assertions, and `revive()` resets
`placement`, so the suite reported "bad placement 0 for YOU". It now snapshots and
restores the player state it touches. Worth recording: a test that mutates live game
state has to be as careful as the code it checks.
