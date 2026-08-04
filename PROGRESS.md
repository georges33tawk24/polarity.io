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

### Endless mode — DONE 2026-08-01, one open failure

Timer removed, bots respawn at the edge, score is peak mass + survival time.
DECISIONS §12aw. 405 logic checks green; matches terminate on player death.

**OPEN:** `smoke --real` fails one assertion — "no daily mission progressed from a
full match". Sessions now end in ~10s rather than 100s, so far less scrap is
banked. Likely a fixture artifact (today's dailies may all be kill/win based), but
UNVERIFIED — check which dailies were active before dismissing it.

### Polish queue — agreed 2026-08-01, ordered by impact

1. **Audio.** 13 synthesised SFX, no music. Everything else has had an art pass;
   the sound has not, and absorbing something — the payoff of the whole game —
   currently reads as a synthesised blip. Highest-impact item left. Needs a
   licensed pack or authored samples; ASK BEFORE BUYING.
2. **Replay loop.** PARTLY DONE: revive auto-decline cut 8s -> 5s and a tap
   anywhere now declines. PLAY AGAIN on results already restarts in one tap.
   Remaining: consider skipping results entirely on a fast death.
3. **Endless needs a target.** PARTLY DONE: personal best mass now shows under
   the HUD readout and flips to NEW BEST in brass, with a sting, the moment it is
   beaten. Best survival time is now stored (`best_survived`) and shown under the
   clock, which turns brass once the run outlasts it. DONE.
   Original note: No finish line any more, so the player needs a
   number to beat: best survival time and best peak mass on screen DURING the run,
   with a marker when they are about to beat it. Without this an endless game is a
   drift rather than a chase.
4. **Absorbing another magnet should be felt.** Hitstop and a shockwave exist, but
   the mass gain reads as a ticking number. Camera pull-back, trail flare, heavier
   haptic.
5. **Threat telegraphy in the world**, not just the minimap. You should know
   something bigger is closing without looking down.
6. **First ten seconds.** Verify scrap density at the spawn ring guarantees an
   absorb within ~3s. That is the difference between "I get it" and "nothing
   happened".

### Also outstanding

- **Revert the mobile entity cut.** `Arena.MOBILE_BOTS` (0.33) / `MOBILE_SCRAP`
  (0.25) were added chasing a frame rate problem that turned out to be the VIBRATE
  permission (§12av). The player is getting 30 magnets instead of 91. Raise once a
  real FPS reading exists — Settings > Display > Show FPS.
- Godot 4.5+ upgrade before API 36 lands (Play raises the floor each August).
- Receipt validation and AdMob server-side reward verification are both still
  client-side.
- (2026-08-01) **FIXED, CONFIRMED ON DEVICE:** the dead-buttons / "2fps" bug was a
  missing VIBRATE permission. vibrate_handheld() requested it on every button
  press, launching Android's permission activity, pausing and resuming the game
  each tap. DECISIONS §12av. Settings toggles and dropdowns resized in the same
  build.
- **Consider reverting the mobile entity cut.** `Arena.MOBILE_BOTS` (0.33) and
  `MOBILE_SCRAP` (0.25) were added chasing a frame rate problem that did not
  exist. The player is currently getting 30 magnets instead of 91. Raise them once
  a real FPS reading exists — Settings > Display > Show FPS.
- (2026-08-01) ROOT CAUSE FOUND: no VIBRATE permission in the Android export.
  vibrate_handheld() requests it on call, launching Android's permission activity,
  pausing/resuming the app on EVERY button press. That is the dead buttons and the
  "2fps" both. Fixed + guarded by test_android_permissions. DECISIONS §12av.
  v0.1.2 (3) — needs a device confirmation.
- The four earlier perf changes (compat renderer, MSAA off, mobile entity scaling)
  were NOT the cause. Keep or revert on their own merits, not as fixes.
- (2026-08-01) FIRST DEVICE INSTALL: ~2fps, menu included. Addressed four ways —
  Android on the compatibility renderer, MSAA off, mobile entity scaling, FPS
  readout in Settings. NOT confirmed fixed; needs another device round trip.
  DECISIONS §12au.
- Also fixed: FTUE skip and out-of-ring warning overlapped the leaderboard; the
  magnet now turns to face travel.
- (2026-07-31) targetSdk 35 reached WITHOUT the engine upgrade — see §12at.
  Debug AAB builds clean at 54 MB with play-services-ads 24.9.0 linked and the
  test App ID in the debug manifest. `tools/prepare_android.sh` must be run on a
  fresh checkout before any Android export.
- Godot 4.5+ upgrade deferred, not cancelled: API 36 lands August and needs it.
- (2026-07-31) Upload keystore wired via GODOT_ANDROID_KEYSTORE_RELEASE_* env vars
  — nothing secret in export_presets.cfg. `tools/build_aab.sh` builds and verifies
  the signed AAB. Play feature graphic generated (`store/feature_graphic.png`).
- **BLOCKED: disk.** 198 GB used of 228, ~2.5 GB free. The Godot 4.5+ upgrade
  (needed for targetSdk 35, which gates every Play upload) wants ~6 GB.
- (2026-07-31) AdMob wired: rewarded + interstitial + UMP consent, test units in
  debug, real IDs in release, Gradle build + AAB export on. Debug AAB builds clean
  (50 MB, 0 script errors). DECISIONS §12as.
- **BLOCKED on the Play upload:** Godot 4.3's Android template targets SDK 34;
  Play requires targetSdk 35 for new apps. Needs a Godot 4.5+ upgrade, not a
  config change.
- **NEEDS THE USER:** generate an upload keystore (release AAB cannot be signed
  without it); real privacy-policy URL and support email; run the friends SQL;
  rotate the exposed service_role key.
- **STILL UNPLAYED ON A DEVICE.** Every device test so far has found a bug no
  headless suite caught. Four for four.
- (2026-07-31) Renamed to **Polarity.io** — display name, wordmark, web shell,
  credits. Bundle id deliberately unchanged (`io.polarity.arena`). Trademark
  position checked on USPTO: no live bare POLARITY mark in any class. DECISIONS
  §12ar. Store listing copy still says POLARITY in places — update before submission.
- (2026-07-31) Both owed features landed. Magnet body rebuilt as a true U with
  straight legs (was a 320-degree annulus); friends shipped end to end — schema
  with RLS, SECURITY DEFINER code lookup, provider methods, board scope, add-by-code
  modal. DECISIONS §12aq. 382 + 200 checks green.
- **ACTION REQUIRED FROM THE USER:** the friends tables do not exist in the live
  Supabase project yet. Run the new section at the bottom of `supabase/schema.sql`
  in the Supabase SQL editor. Until then the FRIENDS tab correctly reports that it
  needs a connection rather than failing.
- Still open: on-device profiling (desktop frame numbers are noise, §12ap);
  rotate the exposed service_role key.
- (2026-07-31) Perf + balance round: uniform-grid broad phase (checked against
  brute force), bot AI level-of-detail, bots 90 -> 60, pull reach decoupled from
  body growth, trail now emits off the body and scales with it, missions countdown
  ticks, daily pool 8 -> 16. Frame-time reporting added to smoke.
  DECISIONS §12ap. 374 + 196 checks green.
- NOT DONE, still owed to the player:
  - **Friends / add-a-friend.** Needs a Supabase table + RLS, a friend-code or
    handle lookup, and a screen. Real feature, not a tweak.
  - **The magnet does not look like a magnet** ("a circle cut in a place"). The
    body is a sphere with a two-tone split. Wants a horseshoe read like the app
    icon, which is mesh + shader + art iteration.
  - **On-device profiling.** The desktop frame numbers are noise (see §12ap).
- (2026-07-31) Feel round 2: shake cut to ~20% + capped, closing ring removed
  (mechanic, floor ring and HUD bar), buff pickups now report in the kill feed,
  arena x10 (r=185, 91 magnets, 7000 scrap), spawn placement rebuilt as concentric
  rings, settings regrouped into plated sections. DECISIONS §12ao.
  342 + 196 checks, smoke --real green.
  UNVERIFIED ON DEVICE: 90 bots + 7000 scrap has never been profiled on a phone.
  If it drops frames, `bot_count` in `data/default_tuning.tres` is the first knob.
  Median eliminations fell from 7-9 to ~4-5 as a direct result of the x10 arena.
- (2026-07-31) Fixed: claiming the daily reward left a full-screen black scrim
  over the menu (`_close_daily` freed the modal box instead of the wrapper, so the
  shade was orphaned). Modal scrims also now cover the full viewport instead of
  stopping at the safe-area inset. DECISIONS §12an. screens.tscn asserts a modal
  goes away, not just that it appears.
- (2026-07-31) Game feel round: touch steering rebuilt as a floating stick
  (`Intent`), optional semi-transparent on-screen joystick (`Ui.Stick`, settings
  toggle), haptics rate-limited in `Platform` + Off/Light/Full setting, minimap
  320 -> 460 with contents scaled, arena 44 -> 58 with bots 14 -> 22 and scrap
  420 -> 700. DECISIONS §12ak-§12am. 331 + 191 checks, smoke --real green.
  UNCONFIRMED ON DEVICE: the arena enlargement is a guess at what "make the map
  bigger" meant — if the player meant only the minimap, revert the three values in
  `data/default_tuning.tres`.
- (2026-07-31) Touch scrolling fixed on the shop / missions / pass / store /
  settings lists. Two bugs: a drag starting on a card never reached the
  ScrollContainer (Godot delivers touches to the topmost Control), and the panel
  restored a stale scroll position from the previously open tab. `UiKit.TouchScroll`
  + `_settle_scroll` restoring unconditionally. Dragged for real in
  `tests/screens.tscn` — a mouse wheel cannot reproduce this. DECISIONS §12aj.
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
- [~] Server-authoritative validation — PARTIAL, and now PROVEN: a lower submission does not overwrite a higher score, and direct writes to `scores` are refused (403). Full validation still needs server-side simulation.

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
- [x] **§10** Android: **signed debug APK BUILT** (`build/android/polarity-debug.apk`, 48 MB, io.polarity.arena, arm64 + armv7, signature verified). Never yet RUN — no emulator/device on this machine. · [x] iOS: **unsigned IPA BUILDS** via `tools/build_ipa.sh` (20 MB, arm64, universal). Installed on a real device. actool/ibtool need a simulator runtime even for device builds, so the asset catalog and launch storyboard are dropped and icons ship loose — same shape as a known-good IPA already on the machine.
- [x] **§10** Store listing scaffold + data-safety answers — DONE (`store/LISTING.md`)
- [x] **§10** App icons at 9 store sizes — DONE · [~] Store screenshots — PARTIAL: `tools/store_shots.sh` generates the set from the real game, but capture is the window framebuffer and macOS clamps it to the display, so 1290x2796 comes back 1290x1570. Composition is right, pixels are short. Needs a taller display or a SubViewport render pass. · [ ] promo video — TODO
- [x] **§11** Backend — **LIVE on Supabase.** Anonymous auth, cloud save round-trip, leaderboards all verified against the real project (`tools/backend_check.tscn`). RLS isolation proven: a second user cannot read or overwrite another's save (403), and cannot write the scores table directly (403).
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
