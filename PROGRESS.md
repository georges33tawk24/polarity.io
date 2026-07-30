# POLARITY — DELIVERY LEDGER

**Read this file and [SPEC.md](SPEC.md) at the start of every session.**
SPEC.md is the master brief and never changes. This file is the running state.
Update it whenever a feature lands. Never mark something DONE that has not been
run and verified.

Legend: **DONE** = built + verified · **PARTIAL** = usable, gaps noted ·
**TODO** = not started · **BLOCKED** = needs a credential/vendor/user decision.

---

## ART DIRECTION — read [ART_DIRECTION.md](ART_DIRECTION.md)

Direct feedback: the build read as "neon and AI designed", and camera shake was
brutal. A corrective brief exists and is being executed. **It outranks §13A
where they disagree.** Done so far: shake cut ~3x, palette warmed off
cyan-on-black, glow disabled, neon grid floor replaced, hazard LEDs removed,
auras calmed, UI given a type/spacing scale and button hierarchy.
Part 1 and Part 2 (.io conventions) are both complete: minimap, top-right
leaderboard, stripped HUD, light uniform ground, flat entities, `name -> PLAY`
front end, .io results screen, sentence-cased prose, unified light UI surface.

## NEXT UP

- (2026-07-30) UI identity pass landed: drawn stencil wordmark + hero numbers, field
  lines poled to the CTA, warm steel ramp, plate()-based depth, chip-row navigation,
  two-pole cosmetic previews, de-neoned rarity/skins/ranks. See ART_DIRECTION Part 6.
- (2026-07-30) HUD pass landed: board on a bolted plate with build-once rows and
  rank-slide motion, drawn stencil mass that climbs, ring-close bar, charge meter
  beside the score, minimap as a bezelled gauge with shape-encoded threat. Also
  retired every control that looked tappable but was not. See ART_DIRECTION Part 7.
- (2026-07-30) Token migration complete (aliases deleted, grep-verified), results
  choreographed, store offer countdown live with a CTA, pass opens at the player's
  tier, scroll survives rebuilds, and every fake-tappable control retired.
  See ART_DIRECTION Part 8.
- (2026-07-30) Screen transitions, one shared modal() builder for all four dialogs,
  daily calendar choreographed, and a real app icon generated at nine store sizes
  (project.godot AND export_presets.cfg wired). See ART_DIRECTION Part 9.
- (2026-07-30) Affordance pass: round icon buttons on the menu, full-width icon nav
  bar on the meta screens, no more edge-to-edge buttons, and the 13+ age gate removed
  (ads are now contextual-only for everyone, which is stricter). See ART_DIRECTION
  Part 10.
- (2026-07-30) Consent screen removed (ads contextual-only; UMP note in DECISIONS
  §12s), magnet poles split horizontally, scrap recoloured to real fastener finishes
  after measuring the render, elimination/field halos reduced, shop kind filter now
  matches the nav bar. See ART_DIRECTION Part 11.
- The UI/UX pass is complete. Remaining known gaps are in DECISIONS §12p "Still open":
  the hex floor candidate, and iOS/Android store builds (no signing on this machine).

- (2026-07-29) Riveted-panel pass complete across floor, backdrop, panels, buttons,
  HUD and minimap. Arena objects cut 22 -> 14, nuts lifted clear of the floor.
  Remaining: app icons at store sizes; hex-tile floor candidate still renders
  flat (`floor_options.gdshader` style 2) — only worth fixing if asked. (resume here)

Working through **M2 — Meta** in this order. Localization goes first so every
new screen is built with `tr()` from the start instead of being retrofitted.

1. ~~Localization~~ · ~~Cosmetics~~ · ~~Shop~~ · ~~Daily reward~~ · ~~Missions~~ ·
   ~~Battle pass~~ · ~~Rank ladder~~ — **all DONE**
2. ~~FTUE / onboarding~~ — **DONE**. M2 complete.
3. ~~M3: remote config, analytics + crash, ads + consent/COPPA + caps,
   rewarded, interstitial policy, IAP/Store + offers~~ — **DONE**
4. ~~M4: auth, cloud save + merge, leaderboards, share card, rating prompt,
   GDPR export/delete, notifications, referral + deep links~~ — **DONE**
5. M5 in progress: ~~3 remaining hazards~~, ~~power-ups~~, ~~accessibility
   (colourblind / UI scale / control scheme / left-handed)~~, ~~debug overlay +
   cheats~~, ~~CI~~, ~~ARCHITECTURE.md~~.
   ~~async loading screen~~, ~~art pass part 1: real generated meshes~~.
   ~~icon set~~, ~~music (§13B)~~, ~~store listing scaffold~~.
   **NEXT: spatial partition, then remaining polish.**
   Original M4: auth, cloud save, leaderboards, share card, referral, notifications,
   rating prompt
5. Then M5: debug overlay, accessibility (colorblind/control scheme/UI scale),
   remaining hazards, power-ups, CI, ARCHITECTURE.md, store scaffolding
6. Then the §13A art pass and §13B audio pass.

---

## Milestones

| | Milestone | State |
|---|---|---|
| M0 | Skeleton, autoloads, responsive shell, boot→menu→match→results, input abstraction | **DONE** |
| M1 | Core loop, magnetism, growth, repel, bots, ring, juice, 60fps | **DONE** |
| M2 | Meta: currencies, XP, cosmetics, shop, daily, missions, save, settings, i18n, FTUE | **DONE** |
| M3 | Monetization + liveops: ads, IAP, consent, remote config, A/B, battle pass, analytics | **DONE** (Null providers) |
| M4 | Social + backend: auth, cloud save, leaderboards, share, referral, notifications, rating | **DONE** (Null providers) |
| M5 | Polish + ship: perf, accessibility, store assets, privacy, PWA, QA | **PARTIAL** (art/audio + store listing left) |

---

## §3 Core gameplay

- [x] **3.1** Magnet body, mass, radius/pull scaling — DONE
- [x] **3.1** Drag-to-steer + WASD + touch, InputController abstraction — DONE (`intent.gd`)
- [x] **3.1** ATTRACT / REPEL / NEUTRAL states — DONE
- [x] **3.1** Toggle-polarity mode for accessibility — DONE
- [x] **3.2** Inverse-distance pull with clamped min distance, tuning resource — DONE
- [x] **3.2** Absorb scrap, absorb lighter magnets — DONE
- [x] **3.2** Repel radial impulse scaled by mass + proximity — DONE
- [x] **3.2** Launch into hazard / out of ring = elimination + bounty — DONE
- [x] **3.2** Counterplay: heavier resists, repel charge + cooldown — DONE
- [x] **3.3** Snowball: bigger = stronger pull, slower — DONE
- [x] **3.3** Size/score meter — DONE (HUD mass + leaderboard)
- [x] **3.3** "Biggest magnet in arena" indicator — DONE (crown nameplate + minimap diamond)
- [x] **3.4** Arena, scrap spawners, shrinking ring, mass drain outside — DONE
- [x] **3.4** Hazards: spike pit, saw blade — DONE
- [x] **3.4** Hazards: electric fence, conveyor belt, reverse-polarity zone — DONE
- [x] **3.4** Procedurally *themed* arenas — DONE (8 themes, each previewing its own colours)
- [x] **3.4** Match FSM incl. SUDDEN_DEATH, placement drives rewards — DONE
- [x] **3.5** Bots: 5-state FSM, difficulty tiers, no cheating, .io names — DONE
- [x] **3.5** Bot cosmetic variety (7-colour palette) — DONE
- [x] **3.6** Trauma shake, hitstop, squash/stretch, shockwave, bursts, dynamic zoom — DONE
- [x] **3.6** SFX with pitch variance, attract hum — DONE (synthesised; impacts rebuilt on inharmonic bar modes, §12u)
- [x] **3.6** Adaptive music: base loop + intensity layer that ramps as the lobby thins — DONE (synthesised)
- [x] **3.6** Haptics on mobile — DONE (web Vibration API: TODO, needs JS bridge)
- [x] **3.6** Clip cam slow-mo — DONE
- [ ] **3.6** "Share this clip" prompt with generated card — PARTIAL (text share only)

## §4 Feature set

### 4.1 Meta-progression
- [x] Player level & XP — DONE
- [x] Coins + Gems — DONE
- [x] Trophy/rank ladder (6 ranks) driving bot difficulty — DONE
- [x] Daily reward calendar, streak, UTC rollover — DONE
- [x] Missions: daily 3 / weekly 5 / 5 achievements, progress + claim — DONE
- [x] Battle Pass: 30 tiers, free + premium, seasonal reset — DONE
- [ ] Platform achievements (Play Games / Game Center) — BLOCKED (vendor)
- [x] Collection completion counter + dedicated codex screen — DONE (per-kind completion bars, locked items shown dimmed)

### 4.2 Cosmetics
- [x] Skins (23), trails (10), launch VFX (8), nameplates (7), arena themes (8) = 56 — DONE, all visually wired
- [x] Rarity tiers, equip/loadout, stale-id fallback — DONE
- [x] Emotes, absorb VFX, victory pose — DONE
- [x] Kind-aware previews in-card (skin poles, trail, burst, nameplate, arena plate) — DONE · [ ] dedicated preview screen — TODO
- [ ] Gacha behind a config toggle — TODO (direct purchase only, deliberate)

### 4.3 Shop & economy
- [x] Shop with tabs (shop / missions / pass / store) + 5 cosmetic categories — DONE
- [x] Currency bundles, remove-ads, starter pack, VIP, limited offer card — DONE
- [x] Balances, anti-negative clamps — DONE, unit-tested
- [x] Transaction ledger (`Game.ledger`, capped, emits `Bus.currency_changed`) — DONE
- [ ] Server-side receipt validation — BLOCKED until the Supabase project exists; then it is one Edge Function (see supabase/README.md)

### 4.4 Monetization
- [x] Rewarded service + double-coins placement, daily cap, honest grant — DONE
- [x] Rewarded placements: **revive**, **daily wheel**, **skin trial**, **+50% start mass** — DONE, all four consume-once and unit-tested. All hidden unless an ad can actually be delivered.
- [x] Interstitial policy: every-N-matches + cooldown + first-session/first-match skip — DONE, unit-tested
- [x] Web banner policy (web-only, never in-match) — DONE (no provider)
- [x] IAP: consumables / non-consumables / VIP, purchase, restore, revoke — DONE, unit-tested with an injected fake provider
- [x] no-ads entitlement suppresses interstitials/banners but keeps rewarded — DONE
- [x] COPPA/GDPR handled by REMOVING both gates: ads are contextual-only for everyone, which is stricter than the gate was (DECISIONS §12q, §12s). NOTE: a real ad network (AdMob UMP, EEA partners) will require its own consent flow.
- [ ] Apple ATT prompt — BLOCKED (needs iOS plugin)
- [x] Monetisation kill switch overriding every ad flag — DONE, unit-tested
- [x] Audio ducking during ads — DONE
- [x] Null providers that honestly report unavailable — DONE

### 4.5 Liveops & config
- [x] Remote config: shipped defaults <- disk cache <- live, plus `clear_remote()` — DONE
- [x] Feature flags + monetisation kill switch — DONE, unit-tested
- [x] A/B variant assignment (stable per install) + exposure logging — DONE
- [x] Seasons (battle pass, epoch-based) — DONE · [ ] themed timed events — TODO
- [x] Segmentation cohorts (new / engaged / payer / churn_risk) — DONE
- [x] Time-limited offers driven by segment, never shown before the player has played — DONE

### 4.6 Social & virality
- [x] Share card rendered to a real 1080x1080 PNG — DONE, verified
- [x] Share text + clipboard fallback — DONE (native/Web Share sheet needs a bridge)
- [x] Referral codes + invite link, self-referral and double-claim guards — DONE, unit-tested
- [x] Leaderboards: global / friends / weekly / country with a local provider — DONE
- [x] Deep-link parsing (native argv + `polarity://ref/`) — DONE (web needs a JS bridge)
- [x] Rating prompt: wins + matches thresholds, cooldown, once only, win-only — DONE, unit-tested

### 4.7 Onboarding / FTUE
- [x] Guided first match (hold -> release -> launch) inside a real arena, skippable, replayable — DONE
- [x] Per-step timeouts so it can never soft-lock — DONE
- [x] Progressive feature unlock (shop at 1 match, missions at 2) + NEW coach mark — DONE

### 4.8 Settings & accessibility
- [x] Music/SFX sliders, mute, haptics toggle, quality preset — DONE
- [x] Reduced motion — DONE (damps shake, disables hitstop/clip punch)
- [x] Control scheme selector (drag / joystick / toggle-polarity) — DONE
- [x] Left-handed toggle — DONE
- [x] Colourblind palette (blue/yellow poles + existing shape split) — DONE
- [x] UI scale slider — DONE
- [x] Language selector — DONE
- [x] Account section: guest sign-in, restore purchases, GDPR export + delete, privacy link — DONE
- [x] Support/contact (mailto) + credits — DONE · [x] Google/Apple sign-in seam — DONE, hidden until a native plugin exists (`Platform.federated_auth_available`)
- [x] Version/build info — DONE

### 4.9 Localization
- [x] Externalize all strings — DONE (`data/i18n/strings.csv`, 119 keys)
- [x] EN + 9 languages (es pt_BR fr de ru tr id ja ko) — DONE, all rows complete
- [x] Runtime language switch + UI rebuild — DONE
- [x] RTL layout switch wired (`Locale.is_rtl` → `layout_direction`) — DONE (no RTL language shipped yet)
- [x] Locale-aware number grouping + duration formatting — DONE
- [x] CJK glyph coverage verified (ja/ko render on the default font) — DONE
- [x] Localized bot-name pools — DONE (`data/bot_names.json`, 10 locales)
- [x] Currency + date formatting per locale — DONE, unit-tested (no minor unit on ja/ko, comma decimals, date order)

### 4.10 Save & sync
- [x] Versioned, migratable, corruption-tolerant local save + backup — DONE, unit-tested
- [x] Encryption at rest — DONE (device-derived XOR + base64; obfuscation, named honestly as such — DECISIONS §12v)
- [x] Cloud save + conflict merge (currency max, entitlement union, idempotent) — DONE, unit-tested
- [x] Persistent profile vs run state separated — DONE

### 4.11 Notifications
- [x] Opt-in setting + schedule/cancel API — DONE (scheduler needs a mobile plugin)
- [ ] Push provider hook (FCM) — BLOCKED (vendor)

### 4.12 Telemetry
- [x] Analytics: funnel events, batching, bounded queue, offline persistence, retry — DONE, unit-tested
- [x] Crash/error reporting with breadcrumb trail + fps/memory context — DONE
- [x] Opt-out that stops all collection — DONE
- [x] Debug overlay (FPS / mem / entity counts) — DONE (`debug_overlay.gd`, dev builds only)

### 4.13 Anti-abuse
- [x] Client-side currency clamps — DONE, unit-tested
- [x] Client-side score sanity clamp — DONE, unit-tested
- [~] Server-authoritative validation — PARTIAL: `submit_score()` is SECURITY DEFINER and keeps the best score, so a replayed or lowered submission cannot land. Full validation still needs a server-side simulation.

### 4.14 Netcode seam
- [x] Bots write the same `move_dir`/`holding` intent a network peer would — DONE
- [x] Explicit interface audit + seeded-RNG determinism — DONE. Narrow claim on purpose: same seed = same arena LAYOUT (enough for replays and reproducible bug reports). Lockstep is NOT claimed — physics is float-based at variable delta.

## §5–§16 Cross-cutting

- [x] **§5** Service architecture, EventBus, data-driven tuning — DONE (4 autoloads, see DECISIONS §2)
- [x] **§5** ARCHITECTURE.md — DONE
- [x] **§6** Responsive scaling, safe areas, input abstraction, HUD reflow, web resize — DONE
- [x] **§6.5** Verified at 9:16 / 3:4 / 16:9 / 21:9 / tablet — DONE (`menu_shot --size=WxH`)
- [x] **§7** Bot lobby with .io names, localized pools — DONE
- [x] **§8** MultiMesh scrap, pooled FX, no realtime shadows, quality scaler — DONE
- [x] **§8** Spatial partition for magnetic influence — DONE (uniform grid, `scrap_field.gd` CELL = 8.0)
- [x] **§8** Staged arena construction behind a branded loader — DONE
- [x] **§9** WebGL2 single-threaded export, PWA, focus mute, audio gesture unlock — DONE
- [x] **§9** Branded loader + WASM error/retry screen — DONE (`web/shell.html`), **verified in a real browser**: boots, and the failure path was tested by hiding the wasm
- [ ] **§9** Web portal ad SDK — BLOCKED (vendor)
- [x] **§10** Android/iOS export presets, portrait lock, min SDK/iOS — DONE (unbuilt: no signing)
- [x] **§10** Store listing scaffold + data-safety answers — DONE (`store/LISTING.md`)
- [x] **§10** App icons at 9 store sizes — DONE · [~] Store screenshots — PARTIAL: `tools/store_shots.sh` generates the set from the real game, but capture is the window framebuffer and macOS clamps it to the display, so 1290x2796 comes back 1290x1570. Composition is right, pixels are short. Needs a taller display or a SubViewport render pass. · [ ] promo video — TODO
- [~] **§11** Backend — Supabase provider WRITTEN and unit-tested (`scripts/supabase_provider.gd`, `supabase/schema.sql`). Needs the user to create the project and drop in `supabase.cfg`. Degrades to the local provider until then.
- [x] **§12** Typed GDScript, doc comments, no magic numbers — DONE
- [x] **§12** Tests: 269 headless assertions + 145 screen/icon/audio checks + real-renderer smoke — DONE (no GUT, see DECISIONS §13)
- [x] **§12** Debug overlay + cheat console, `OS.is_debug_build()` gated — DONE
- [x] **§12** CI: lint + three suites + banned-identifier gate + tagged artifacts, fails on SCRIPT ERROR — DONE. **Still unrun: there is no git repo.** `tools/verify.sh` runs the same checks locally.
- [x] **§13A** Generated meshes: horseshoe magnet, hex nut / bolt / gear / shard scrap — DONE
- [x] **§13A** Arena themes (5) and power-ups (5) — DONE
- [x] **§13A** Blob shadows (magnets + scrap), toon shading, fresnel rim, two-light
      rig, colour grading — DONE
- [x] **§13A** Icon set (coin, gem, trophy, star, lock, check), drawn procedurally, with rarity stars for colourblind shape-redundancy — DONE
- [x] **§13** Blender glTF pipeline written (`tools/blender_export.py`) + runtime
      loader with fallback — DONE
- [ ] **§13** Pipeline RUN — BLOCKED: Blender is not installed. The Blender MCP
      IS connected and its bundled API docs work offline (used to validate the
      export script), but it drives a *running* Blender and there is no binary.
      `~/Applications/Blender.app` is an orphaned Steam launcher stub from 2022.
      One command once Blender exists: see assets/README.md
- [x] **§13B** Music (menu/game/intensity) — DONE, synthesised
- [ ] **§13B** Licensed/authored SFX and music — BLOCKED (I cannot license or download audio). Drop-in seam built: `assets/sfx/<name>.wav` overrides synthesis with no code change, and the boot log reports the split.
- [x] **§15.8** No secrets, no copyrighted assets — DONE

---

## Verified-working commands

```bash
tools/verify.sh                                                                       # everything CI runs
/Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/tests.tscn        # 269 checks
/Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/screens.tscn      # 145 screen/icon/audio checks
/Applications/Godot.app/Contents/MacOS/Godot res://tests/smoke.tscn -- --real         # full match
/Applications/Godot.app/Contents/MacOS/Godot --headless --export-release "Web" build/web/index.html
```

## Standing decisions (do not re-litigate)

- Godot **4.3** (installed version), Mobile renderer, GL Compatibility on web.
- **4 autoloads**, not 17 — `Bus` / `Platform` / `Audio` / `Game`. All platform
  branching lives in `Platform`.
- UI built **in code**, not `.tscn`.
- Scrap is a **MultiMesh over flat arrays**, no nodes.
- Magnets are **CharacterBody3D**, not RigidBody3D.
- Null providers **report unavailable** rather than faking success.
- Budget every damage drain against `start_mass - min_mass`, not `start_mass`.

Full reasoning and the nine bugs found during M1 are in [DECISIONS.md](DECISIONS.md).
