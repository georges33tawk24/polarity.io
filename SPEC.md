# POLARITY — Ultra Build Prompt (MASTER SPEC — SOURCE OF TRUTH)

> **This file is the authoritative brief, saved verbatim from the user.**
> It outranks any summary, any assumption, and any earlier decision.
> Track delivery against it in [PROGRESS.md](PROGRESS.md).
> Record every deviation in [DECISIONS.md](DECISIONS.md). Do not silently drop features.

---

## 0. ROLE & MISSION

You are a senior Godot game engineer + technical designer shipping a production-ready, store-quality hyper/hybrid-casual arena game called POLARITY. You will deliver a complete, runnable, well-architected Godot 4.x project that builds and plays on Android, iOS, and the Web (HTML5), with a single responsive UI that adapts to desktop and mobile browsers.

Non-negotiables:

* No placeholder logic. Every system listed here must actually work (with mock/stub backends where a live service is required, clearly flagged).
* Data-driven & config-first. Tuning values live in `Resource`/JSON files, never hard-coded in gameplay scripts.
* Typed GDScript, clean architecture, no God-objects, no memory leaks, 60 FPS target on mid-range 2020 phones.
* Cross-platform from day one. Never assume a mouse, a keyboard, a fixed resolution, or a fixed aspect ratio.
* Ship with documentation, tests, export presets, and CI.

When requirements are ambiguous, prefer the most common hybrid-casual convention, implement it, and record the assumption. Ask the user only if a decision is irreversible or costs real money.

## 1. THE GAME — CONCEPT & PILLARS

Elevator pitch: A one-thumb magnet-combat arena. You are a magnet in a top-down arena full of opponents. Hold to attract, release to repel. Attract loose metal scrap to grow bigger and stronger; time a release to launch nearby enemies into hazards or out of the ring and absorb their mass. The arena shrinks. Last magnet standing wins. Rounds are 60–120 seconds.

Design pillars (every decision serves these):

1. Instantly readable — a new player understands the core verb in 3 seconds.
2. Snowball dopamine — you visibly, satisfyingly grow stronger within a run.
3. The clip moment — launching an enemy across the map must look spectacular (this is the marketing engine).
4. One-thumb, zero-friction — playable with a single finger or a single mouse button; no tutorials required to start.
5. Fair, deep, replayable — easy to play, high skill ceiling (release timing, positioning, polarity management).

Genre framing: hybrid-casual (simple core + light meta + cosmetics/IAP + rewarded ads). Single-player against bots styled as an ".io" arena ("fake multiplayer" — no netcode required for v1; see §7).

## 2. TARGET PLATFORMS & TECH BASELINE

* Engine: Godot 4.4+ (latest stable 4.x). Use the Forward+ / Mobile renderer appropriately: Mobile renderer as default for broad device + web compatibility; allow Forward+ on desktop.
* Language: GDScript (typed) as primary. C# only if a specific plugin requires it — keep it isolated.
* Rendering: 3D low-poly, top-down orthographic (or slightly perspective) camera — the "hole.io" look. Keep it stylized and cheap.
* Platforms:
  * Android (min SDK 24 / Android 7+), arm64-v8a + armeabi-v7a.
  * iOS (min iOS 14+), arm64.
  * Web HTML5, GL Compatibility (WebGL2) export for maximum reach; must run in Chrome, Safari (desktop + iOS), Firefox, Edge, and mobile browsers.
* Orientation: Portrait primary. Support landscape on web/desktop via responsive layout (see §8). Lock mobile to portrait unless the user later requests both.
* Frame rate: 60 FPS target; degrade gracefully to 30 with a quality-scaler on low-end/thermal-throttled devices.

## 2A. ONE CODEBASE FOR ALL PLATFORMS (read this first)

There is exactly ONE Godot project and ONE codebase (GDScript). It is NOT two projects, and there is no separate "web version" of the game. Godot compiles that single project into an Android build, an iOS build, and a Web build. You never fork, duplicate, or rewrite gameplay per platform.

The only platform-specific code is a thin adapter/provider layer behind service interfaces. At runtime the app detects the platform and injects the right provider:

* `OS.get_name()` → `"Android"`, `"iOS"`, `"Web"`, `"Windows"`, `"macOS"`, `"Linux"`.
* `OS.has_feature("web")` / `OS.has_feature("mobile")` for coarse branching.

Provider routing examples (all selected at runtime, all inside the same project):

* `AdsService` → `AdMobProvider` (Android/iOS) · `WebAdsProvider` = CrazyGames/Poki/WebBus (Web) · `NullAdsProvider` (editor/dev).
* `IAPService` → Play Billing (Android) · StoreKit (iOS) · portal-store or disabled (Web).
* `HapticsService` → OS vibrator (mobile) · Vibration API (web) · no-op (desktop).
* `PlatformService` → device safe-area (mobile) · CSS `env(safe-area-inset-*)` (web).
* `NotificationService`, `AuthService`, `LeaderboardService` → same pattern.

Everything else — gameplay, physics, controls, all UI, meta-progression, shop, economy, cosmetics, VFX, audio — is shared, identical code across all three platforms. Only the export presets differ (Android `.aab`, iOS Xcode, Web HTML5); the source does not.

Hard rule for the building agent: never create a per-platform copy of a scene or script. If a feature needs platform behavior, put it behind a service interface with per-platform providers chosen at runtime. One project, one source of truth.

## 3. CORE GAMEPLAY SPECIFICATION

### 3.1 The magnet (player)

* Represented by a magnet body with a mass value (starts ~10). Visual radius and pull radius scale with mass.
* Movement: auto-drift toward the input point, OR twin-mode: drag-to-steer (a virtual joystick on touch; mouse position / WASD on desktop). Implement an InputController abstraction so control scheme is swappable and tested on all inputs.
* Polarity states: `ATTRACT` (default while holding), `REPEL` (on release burst), `NEUTRAL` (idle). Optional toggle mode for accessibility.

### 3.2 The magnetism (core mechanic — must feel perfect)

* Every frame, for objects within `pull_radius`, apply a force ∝ `mass / distance²` (clamp min distance to avoid singularities). Expose constants in a `MagnetTuning` resource: `base_pull_force`, `pull_radius`, `repel_impulse`, `falloff_exponent`, `max_speed`, `mass_to_radius_curve`.
* Attract: scrap and lighter enemies are pulled toward you; on contact with scrap you absorb it (mass += scrap value). Contact with a smaller enemy magnet absorbs a fraction of their mass.
* Repel (the money move): releasing fires a radial impulse. Nearby enemies/objects are launched away with force scaled by your mass and their proximity. A launched enemy that hits a hazard/wall or leaves the ring is eliminated; you gain a mass bounty.
* Counterplay: a bigger enemy resists your pull and can out-repel you. Polarity is a resource — a short cooldown/charge on repel prevents spam (`repel_cooldown`, `repel_charge_time`).

### 3.3 Growth / snowball

* Absorbing scrap and eliminations increases mass → bigger radius, stronger pull, higher score, but slightly slower turn speed (risk/reward). Define the full curve in config.
* On-screen: a size/score meter and a "biggest magnet in arena" indicator.

### 3.4 Arena & match flow

* Procedurally themed arenas (grid of tiles + scattered scrap spawners + hazards: spike pits, saw blades, electric fences, conveyor belts, "reverse-polarity" zones).
* Shrinking ring (battle-royale pressure): safe zone contracts on a timeline; outside the ring = continuous mass drain then elimination.
* Match states (FSM): `LOADING → COUNTDOWN → PLAYING → SUDDEN_DEATH → RESULTS`. Sudden death shrinks the ring aggressively when 2–3 magnets remain.
* Win condition: last magnet standing or highest mass at timer end. Placement (1st…Nth) drives rewards.

### 3.5 Bots / opponents

* 8–30 bots per match (configurable), each a lightweight state machine: `SEEK_SCRAP`, `HUNT_SMALLER`, `FLEE_BIGGER`, `CONTEST_ZONE`, `PANIC`. Difficulty tiers scale reaction time, aim error, and aggression.
* Bots use the same physics and abilities as the player (no cheating). Give them believable ".io" usernames and cosmetic variety (see §7).

### 3.6 Game feel / juice (mandatory — this is what sells)

* Screen shake (Trauma-based, config-capped), hit-stop/time-freeze on big launches, squash-and-stretch on absorb, particle bursts (scrap sparks, magnetic field lines, launch shockwave), dynamic camera zoom that pulls out as you grow.
* Satisfying SFX for pull/absorb/launch/eliminate with pitch variance; layered music that intensifies during sudden death.
* Haptics on mobile (light on absorb, heavy on launch/eliminate). Web: use the Vibration API where available; degrade silently.
* A "clip cam": on a multi-eliminate or a huge launch, briefly trigger a slow-mo + framing suitable for screen recording, and surface a "Share this clip" prompt after the match (see §6.7).

## 4. FULL FEATURE SET ("every single feature")

Implement all of the following. Each bullet is a real, working system, config-driven, with UI.

### 4.1 Meta-progression

* Player level & XP (XP from matches, placement, missions).
* Two currencies: soft (`Coins`, earned freely) and hard (`Gems`, premium/earned rarely).
* Trophy/rank ladder (bronze → … → master) driving matchmaking bracket + seasonal rewards.
* Daily reward calendar (streak-based, escalating).
* Missions/quests: daily (3), weekly (5), and lifetime achievements; each with progress tracking and claim UI.
* Battle Pass / Season Pass: free + premium tracks, tiers, seasonal reset, remote-configurable.
* Achievements wired to platform (Google Play Games, Game Center) and internal.
* Collections/Codex of unlocked skins and cosmetics.

### 4.2 Cosmetics & customization (primary IAP driver)

* Unlockable magnet skins, trails, launch VFX, absorb VFX, emotes/taunts, victory poses, nameplate frames, arena themes.
* Rarity tiers, preview screen, equip/loadout system. Cosmetics are purely visual (no pay-to-win).
* Gacha/loot optional and clearly odds-disclosed (region-compliant); prefer direct-purchase + a rotating shop to avoid loot-box legal risk. Make it a config toggle.

### 4.3 Shop & economy

* Shop with tabs: Featured (rotating), Skins, Coins/Gems bundles, Remove Ads, Starter Pack, Season Pass, Special Offers (time-limited, triggered by liveops/segmentation).
* Full economy service: balances, transactions, sinks/sources, anti-negative, receipt validation hooks. Ledger all currency changes for analytics.

### 4.4 Monetization (platform-split — critical, see §9/§10)

* Rewarded video: revive, 2× coins, free daily gem, wheel spin, unlock-skin-trial, extra starting mass. Never block core play behind ads; always optional and value-positive.
* Interstitials: at natural breaks (post-results), frequency-capped (e.g., every 3rd match, min 60s apart, never during gameplay, never on first session).
* Banner: web only, non-intrusive placement; none during active gameplay.
* IAP: consumables (currency), non-consumables (Remove Ads, skins), subscriptions optional (VIP: no ads + daily gems). Include restore purchases, receipt validation, and graceful failure.
* Consent & compliance: GDPR/UMP consent flow, Apple ATT prompt, CCPA, COPPA age gate, and a "not personalized ads" path. Wire these before any ad SDK init.

### 4.5 Live-ops & configuration

* Remote Config service (interface + provider): tune drop rates, ad frequency, prices, event flags, feature flags, kill-switches — without a client update.
* A/B testing hooks (variant assignment, exposure logging).
* Timed events / seasons (themed arenas, limited skins, double-XP weekends), driven entirely by remote config + a local fallback.
* Segmentation: new user / payer / churn-risk cohorts drive offers and difficulty.

### 4.6 Social & virality

* Share result/clip to native share sheet (mobile) and Web Share API (web); fallback to copy-link + downloadable image/video.
* Referral / invite with reward attribution (deep links).
* Leaderboards: global, friends, weekly, country — via backend (§11). Show rank, delta, and rewards.
* Deep links / dynamic links to open specific offers, replays, or friend challenges.
* App rating prompt (native review request) triggered after a positive moment, frequency-capped.

### 4.7 Onboarding / FTUE

* Zero-text first match: guided by highlight + gentle nudges (attract this scrap → launch this dummy → win). Skippable, replayable from settings.
* Progressive feature unlock (don't dump all systems at once); "coach marks" for new UI as it unlocks.

### 4.8 Settings & accessibility

* Audio (master/music/sfx sliders, mute), haptics toggle, quality preset (auto/low/med/high), control scheme (joystick/tap/toggle-polarity), left/right-handed layout, reduced-motion / reduced-flashing mode (epilepsy-safe), colorblind-friendly palettes + shapes, UI scale, language selector.
* Account: sign-in (Google/Apple/guest), cloud-save link, delete-account & data-export (GDPR), restore purchases, support/contact, privacy policy + ToS links, credits, version/build info.

### 4.9 Localization

* Full i18n via Godot translation system (`.po`/CSV). Externalize all strings. Ship English + at least 8 languages scaffolded (EN, ES, PT-BR, FR, DE, RU, TR, ID, JA, KO — expandable). Support RTL layout switch. Number/currency/date formatting per locale.

### 4.10 Save, data & sync

* Local save: versioned, migratable, corruption-tolerant (atomic write + backup), encrypted-at-rest for sensitive fields.
* Cloud save with conflict resolution (last-write-wins + merge for currencies), tied to account.
* Clear separation of persistent player data vs run/session state.

### 4.11 Notifications

* Local notifications (energy refilled, daily reward ready, event ending) with scheduling + opt-in.
* Push notifications (interface + provider hook, e.g., FCM) for re-engagement, behind consent.

### 4.12 Telemetry & ops

* Analytics service (interface + provider): funnel events (install, FTUE steps, match start/end, placement, ad shown/clicked/rewarded, IAP, currency flows, retention pings). Batch + offline queue.
* Crash & error reporting (interface + provider, e.g., Sentry/Crashlytics-style). Global exception hook, breadcrumb log.
* Performance metrics (FPS, frame time, memory) sampled and reportable in a debug overlay.

### 4.13 Anti-abuse / integrity

* Client-side sanity clamps on currencies/score; server-authoritative validation hooks for leaderboards (reject impossible scores).
* Bot config kept server-tunable; obfuscate sensitive constants where reasonable (accept that a client game is not fully cheat-proof; protect the backend).

### 4.14 Optional online multiplayer (v2 — architect for it now)

* Design the netcode seam behind an interface so v1 bots can later be swapped for real players (Godot high-level multiplayer / Nakama / a relay). Do not build full netcode in v1, but do not paint yourself into a corner: keep simulation deterministic-friendly and input-abstracted.

## 5. ARCHITECTURE & PROJECT STRUCTURE

Use a clean, service-oriented architecture. Autoload singletons for cross-cutting services; scenes for content; `Resource` files for data.

```
res://
  addons/                 # third-party plugins
  autoload/               # singletons (registered in Project Settings)
    GameManager.gd        # top-level app FSM, scene routing
    EventBus.gd           # global signals (decoupled pub/sub)
    SaveService.gd
    ConfigService.gd      # local + remote config merge
    EconomyService.gd
    AdsService.gd         # platform-routed (mobile/web)
    IAPService.gd
    AnalyticsService.gd
    CrashService.gd
    AudioService.gd
    HapticsService.gd
    LocalizationService.gd
    NotificationService.gd
    LeaderboardService.gd
    AuthService.gd
    PlatformService.gd     # OS/browser/device detection, safe areas
    InputService.gd        # input abstraction (touch/mouse/keyboard/gamepad)
  data/                   # Resources: tuning, skins, missions, seasons, economy
    tuning/ skins/ missions/ arenas/ economy/ localization/
  scenes/
    boot/  menu/  game/  ui/  fx/  arena/  entities/
  entities/
    magnet_player.tscn/.gd  magnet_bot.tscn/.gd  scrap.tscn  hazard_*.tscn
  systems/
    match_fsm.gd  spawn_director.gd  bot_ai.gd  ring_controller.gd
    camera_rig.gd  object_pool.gd  quality_scaler.gd
  ui/
    hud/ shop/ battlepass/ settings/ results/ onboarding/ components/
  shaders/  audio/  fonts/  themes/
  tests/                  # GUT unit/integration tests
  tools/                  # editor tools, build scripts
  export_presets.cfg
  DECISIONS.md  README.md  ARCHITECTURE.md
```

Principles:

* EventBus for decoupling (UI never reaches into gameplay internals; it listens to signals).
* Services are interfaces with swappable providers (e.g., `AdsProvider_AdMob`, `AdsProvider_CrazyGames`, `AdsProvider_Null` for editor). `AdsService` picks the provider at runtime by platform.
* Object pooling for scrap, particles, projectiles, damage numbers — zero per-frame allocation in the hot loop.
* State machines for app flow, match flow, and each entity.
* No singleton spaghetti: services expose small APIs; gameplay depends on abstractions.
* Static typing everywhere, `class_name` for reusable types, doc-comments on public methods.

## 6. RESPONSIVE UI/UX SYSTEM (desktop + mobile, one codebase)

This is a hard requirement — the same build must look right on a phone in portrait and a desktop browser in landscape.

### 6.1 Scaling

* Project Settings → Stretch mode `canvas_items`, aspect `expand`, a base reference resolution (e.g., 1080×1920 portrait). Use `Control` anchors/containers everywhere — no absolute pixel positions.
* Build a `ResponsiveManager` that classifies the viewport into breakpoints (phone-portrait, phone-landscape, tablet, desktop-wide) and swaps layout containers / font scales / HUD density accordingly.

### 6.2 Safe areas & notches

* Query `DisplayServer.get_display_safe_area()` on mobile and CSS env(safe-area-inset-*) on web; inset a `SafeAreaContainer` so nothing hides under notches, home indicators, or browser chrome. Re-evaluate on resize/rotation.

### 6.3 Input abstraction

* `InputService` unifies: touch (tap, drag, virtual joystick, multi-touch guard), mouse (hover states, click, drag), keyboard (WASD/arrows + shortcuts), gamepad (optional). Gameplay reads intent (`move_dir`, `hold`, `release`), never raw device events.
* Show touch controls only on touch-capable devices; show keyboard hints on desktop. Detect at runtime (touch events / pointer type), not by OS guess alone.

### 6.4 Responsive HUD

* HUD reflows: portrait = thumb-reachable bottom cluster; landscape/desktop = spread corners. Buttons meet min 48×48 dp touch targets. Text remains legible at all sizes (dynamic font sizing + min clamp).

### 6.5 Menus & popups

* All screens (menu, shop, battle pass, settings, results) built with responsive containers, scroll where needed, and tested at 9:16, 3:4, 16:9, 21:9, and odd tablet ratios.

### 6.6 Web resize handling

* Listen for browser resize / orientation / DPR changes and re-layout live (no reload). Handle the browser being resized mid-match without breaking the camera or HUD.

### 6.7 Clip / share UX

* After notable matches, present a share card (auto-generated image with score + skin) and, where supported, a short captured clip. One-tap to native share / Web Share / download.

## 7. THE ".io" ARENA WITHOUT SERVERS (v1)

* v1 is single-player vs bots presented as multiplayer (industry-standard for hole.io/paper.io-style hits). No servers to run, infinite scalability, no cheaters, no matchmaking latency.
* Generate a fake roster: believable usernames (localized name pools), cosmetic variety, plausible skill spread. Optionally seed a few names from the real leaderboard to feel alive.
* Keep the door open for real multiplayer via the §4.14 interface. Be transparent in store copy per platform policies (avoid claiming live PvP if it's bots).

## 8. PERFORMANCE & OPTIMIZATION

* Target: 60 FPS on a 2020 mid-range Android (e.g., Snapdragon 6-series) and on mobile Safari. Never below 30.
* Object pooling for all frequently spawned nodes. Preallocate at match start.
* Physics: cap active magnetic-influence checks (spatial partition / Area3D query radius, not O(n²) over all objects). Use groups + a broad-phase grid.
* Draw calls: low-poly meshes, shared materials, texture atlases, MultiMesh for scrap fields where possible. Bake lighting; avoid real-time shadows on mobile/web (or use cheap blob shadows).
* Quality scaler: auto-detects device tier + watches frame time/thermal; scales particle counts, shadow quality, resolution scale, post-processing. Manual override in settings.
* Memory: no per-frame allocations in hot paths; reuse arrays; watch web memory ceiling.
* Load times: async loading with a branded loading screen + progress; keep initial web download small (see §9).

## 9. WEB (HTML5) — PRODUCTION REQUIREMENTS

* Export: GL Compatibility (WebGL2) for reach; provide a WebGPU-capable preset as optional. Test on Chrome, Firefox, Edge, desktop Safari, and iOS Safari (the strictest).
* Threads/SharedArrayBuffer: if using threads, the host must serve COOP/COEP headers (`Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`). Provide a single-threaded fallback export for hosts (and portals) that can't set headers. Document this clearly.
* Audio unlock: Web audio requires a user gesture — gate audio start behind the first tap/click; show a "tap to start" splash.
* Canvas & DPR: responsive canvas that fills the window, respects `devicePixelRatio`, and re-lays-out on resize/rotate (§6.6). Handle fullscreen request on user gesture.
* Focus/visibility: pause + mute on tab blur (`visibilitychange`); resume cleanly.
* Download size: keep the initial payload lean (compress textures, strip unused, split/lazy-load non-essential assets). Enable gzip/br on host.
* PWA: ship a web manifest + service worker for installability + offline shell + splash icons. Add-to-home-screen support.
* Web monetization SDKs (choose per host): CrazyGames SDK, Poki SDK, or a unifier like WebBus (CrazyGames/Poki/Yandex/VK) for rewarded + interstitial + banner on portals. `AdsService` must route to the web provider on web builds (AdMob is mobile-only). Implement gameplay pause + audio duck during web ads, and handle ad-unavailable gracefully.
* Loading UX: branded loader, no white flash, error screen with retry if WASM fails.

## 10. MOBILE (Android / iOS) — PRODUCTION REQUIREMENTS

* Android: Gradle build, arm64 + armv7, app bundle (`.aab`) for Play, adaptive icon, splash, proper `min/target SDK`, runtime permissions minimal (no unnecessary perms), Play Games Services (achievements/leaderboards/cloud save), Play Billing.
* iOS: Xcode project export, arm64, App Store icons/splash, `Info.plist` privacy strings, ATT prompt, Game Center, StoreKit IAP, background/interruption handling (calls, backgrounding), safe-area/notch/Dynamic Island support.
* Ads (mobile): Poing Studios AdMob plugin (Godot 4.2+, GDScript/C#, rewarded/interstitial/rewarded-interstitial/banner, UMP consent, editor mock ads) or the `godot-sdk-integrations/godot-admob` community plugin (mediation for 15+ networks). Initialize after consent. Mediation-ready.
* IAP (mobile): Google Play Billing + StoreKit via the relevant Godot plugins; server-side receipt validation hook; restore purchases; handle refunds/entitlement revocation.
* Haptics: native haptics (Android Vibrator / iOS Haptic Engine) via plugin or OS calls; respect the settings toggle.
* Lifecycle & thermal: pause on background, handle low-memory warnings, reduce quality on thermal pressure, respect battery-saver.
* Store readiness: localized store listings scaffold, screenshots per device class, age ratings (IARC), data-safety / privacy nutrition labels.

## 11. BACKEND (leaderboards, cloud save, config) — pluggable

* v1 can ship with a serverless/BaaS backend behind interfaces. Acceptable options: Nakama (self-host/managed), PlayFab, Firebase (Firestore + Remote Config + FCM + Auth), or SilentWolf (lightweight Godot leaderboards/auth). Pick one, wire it behind `LeaderboardService`/`AuthService`/`ConfigService`, and keep a Null/local provider so the game runs fully offline in dev.
* Requirements the backend must cover: auth (guest + Google/Apple), cloud save, global/friend/weekly/country leaderboards with anti-cheat validation, remote config + feature flags, event scheduling, and analytics ingestion (or forward to a dedicated analytics provider).
* Never trust the client for anything that awards real value or public rank.

## 12. CODE QUALITY, TESTING & CI/CD

* Style: typed GDScript, `snake_case` funcs/vars, `PascalCase` classes, `SCREAMING_SNAKE` consts; small functions; no magic numbers (pull from config); doc-comments on public API; `assert`s on invariants.
* Tests: use GUT (Godot Unit Test). Cover: magnetism math, economy transactions (no negative balances, correct sinks/sources), save migration + corruption recovery, config merge (remote overrides local), bot FSM transitions, reward/mission progress, ad-frequency capping, input abstraction mapping. Include integration tests for match FSM start→results.
* Debug tooling: in-game debug overlay (FPS/mem/entity counts), cheat/console panel (grant currency, force events, spawn bots) gated to dev builds, feature-flag inspector.
* CI/CD: GitHub Actions (or similar) — lint, run GUT headless, and produce Web + Android export artifacts on tag. Cache the export templates. Document signing steps (kept out of the repo/secrets).
* Definition of done per feature: works on all 3 platforms (or documented platform-split), config-driven, tested, localized, analytics-instrumented, no leaks, 60 FPS unaffected.

## 13. ASSET PIPELINE

* 3D: low-poly, stylized, shared PBR-lite materials, vertex-color friendly. Model magnet + variants, scrap chunks (several shapes), arena tiles/props, hazards, pickups in Blender; export glTF; consistent scale + origins; import presets that disable unneeded features for mobile/web.
* VFX: GPUParticles with mobile-safe settings; pooled; toggled by quality tier and reduced-motion.
* Audio: compressed (Ogg), normalized, pooled players, music stems for adaptive intensity; respect mute/focus.
* UI: vector-friendly, atlased, theme resource for consistent styling + easy reskin/seasonal theming; icon set for all currencies/rarities/buttons.
* Fonts: dynamic fonts with fallback for CJK/RTL; licensing-clean.

## 13A. ART DIRECTION & VISUAL SPEC (how everything should look)

Overall style: bold, clean, juicy low-poly 3D — flat/lightly-shaded, chunky rounded forms, strong readable silhouettes from a top-down camera. The polished hyper-casual look (hole.io / Voodoo / Supersonic): bright, saturated, high-contrast. Gameplay objects always pop against a calmer arena floor. Mobile-first legibility — every entity must read instantly at small size.

Camera: top-down with a slight tilt (~25–35°) or clean orthographic; dynamic zoom-out as the player grows; smooth follow; the "clip-cam" slow-mo + reframe on big launches/multi-eliminates.

Color & lighting:

* Player magnet uses hero colors — classic red (North) / blue (South) poles so polarity reads at a glance; skins retint but keep pole legibility.
* Scrap = metallic grey with a rim-light glint. Hazards = warning red/yellow. Safe-zone ring = a clear glowing translucent wall; the death zone outside reads darker / hazard-tinted.
* Baked or simple lighting; blob shadows, NOT realtime shadows on mobile/web; cheap bloom only on emissive VFX/accents. Reduced-flashing mode desaturates and slows flashes.

Assets to model (low-poly, glTF export, shared material library, consistent scale/origins):

* Magnet body (player + bots): readable horseshoe/bar magnet or two-pole puck, ~300–800 tris; two-tone poles; a magnetic-field aura shader that visualizes the pull radius; scales visually with mass. Skins = mesh/material swaps. Animations: idle bob, squash on absorb, stretch/pulse on repel, fast-move wobble, "charge-ready" glow pulse.
* Scrap set (the food): bolts, nuts, gears, screws, metal shards, cans, paperclips — ~50–200 tris each, MultiMesh-instanced for dense fields; gentle spin + glint; size/color encodes mass value; spark burst on absorb.
* Arena: circular or rounded-square field; themeable floors (junkyard / lab / factory / neon-grid) via arena-theme resources for seasons; a clearly visible contracting safe-zone ring.
* Hazards: spike pit, spinning saw blade, electric fence, conveyor belt, reverse-polarity zone — bold warning colors, animated, and telegraphed (flash/wind-up) before they activate.
* Power-ups (recommended): magnet surge (bigger pull), speed, shield, mega-repel, enemy-freeze — each with a distinct icon, color, and pickup VFX.
* UI art: chunky rounded high-contrast buttons; one consistent icon set; currency icons (coin / gem); rarity frames (common→legendary, color-coded); skin cards; animated fill bars; confetti/burst on rewards — all driven by a Theme resource for easy reskin + seasonal theming.

VFX look: field lines during attract; a bright radial shockwave ring on repel; absorb sparkles; elimination "pop" + debris; big-launch trail + slow-mo (the clip moment); level-up burst; juicy floating gain/loss numbers. Everything pooled, quality-tiered, and reduced-motion-aware.

Consistency rules: shared materials, uniform scale/origins, one silhouette language, colorblind-safe (shape + color redundancy). All art licensing-clean (original or CC0/licensed); flag any placeholder in `DECISIONS.md`.

Note for asset generation (Claude Code / Blender): produce each item above as a separate low-poly glTF with clean topology, centered origin, real-world-ish scale, vertex colors or a tiny shared atlas (avoid large textures for web payload), and material names matching the shared library. Deliver base meshes first; skins are variants.

## 13B. AUDIO & SFX SPEC (yes — full audio is in scope)

Philosophy: audio is half the game feel. Every action fires an immediate, satisfying sound with pitch variance to avoid fatigue; music adapts to tension.

Music (loopable Ogg, stems for adaptivity): menu loop; gameplay loop; a sudden-death intensity layer that fades in as magnets thin out; victory sting; defeat sting.

SFX — concrete list:

* Magnet: attract hum (loops while holding, pitch scales with pull strength); repel "whoomp" shockwave; charge-ready ping.
* Absorb: scrap clink/ching (pitch rises with combo); big-absorb "chomp."
* Combat: launch whoosh; enemy clang on wall/hazard; elimination pop/explosion; escalating chimes on multi-eliminates.
* Growth: size-up rising sweep; milestone fanfare.
* Ring / hazard: out-of-zone alarm; ring-contract rumble; saw whir; electric zap; spike shing.
* UI / shop / IAP: button tap; tab switch; purchase-success cha-ching; error buzz; reward "ta-da"; daily-chest open; gacha build-up + reveal; mission-complete ding.
* Ambient: subtle arena bed.

Audio systems (`AudioService`): buses (Master / Music / SFX / UI) with volume sliders + mute; pooled `AudioStreamPlayer`s; pitch randomization; duck the music during rewarded/interstitial ads and resume cleanly; mute on focus loss / web tab blur (`visibilitychange`); pair haptics with key SFX (absorb, launch, eliminate, purchase). Respect all settings toggles. Audio licensing-clean; placeholders flagged.

## 14. BUILD PLAN — PHASED MILESTONES

Deliver in vertical slices; each milestone is runnable on all target platforms.

* M0 — Skeleton: project scaffold, autoloads/services (Null providers), responsive shell, boot→menu→match→results loop, input abstraction, CI producing web+android artifacts.
* M1 — Core loop (the fun): magnetism, growth, repel/launch, bots, arena + shrinking ring, full juice (shake/hit-stop/particles/audio/haptics), 60 FPS on target devices. This must be genuinely fun before anything else.
* M2 — Meta: currencies, XP/levels, cosmetics + loadout, shop, daily reward, missions, save/load + migration, settings, localization scaffold, onboarding/FTUE.
* M3 — Monetization & liveops: AdsService (AdMob mobile + CrazyGames/Poki web), IAP, consent/ATT, remote config + feature flags + A/B, battle pass, offers/segmentation, analytics + crash reporting.
* M4 — Social & backend: auth, cloud save, leaderboards, share/clip, referral/deep links, push/local notifications, rating prompt.
* M5 — Polish & ship: performance pass + quality scaler, accessibility pass, store assets, privacy/data-safety, PWA, device-matrix QA, soft-launch build.

For each milestone output: working code, updated `README`/`ARCHITECTURE`/`DECISIONS`, tests, and a short changelog.

## 15. ACCEPTANCE CRITERIA (Definition of Done for the whole project)

1. Runs and is fun on Android, iOS, and Web (desktop + mobile browsers) from one codebase.
2. Responsive at every common aspect ratio with correct safe-area handling; works with touch, mouse, and keyboard.
3. Every feature in §4 is implemented, config-driven, localized, and analytics-instrumented (live services stubbed with clearly-flagged Null providers where credentials are absent).
4. Monetization is correctly platform-split (AdMob mobile / web-portal SDK on web), consent-gated, and never pay-to-win or ad-blocking-of-core-play.
5. 60 FPS on target mid-range hardware; graceful degradation; no leaks; fast load.
6. Tests pass in CI; web + android artifacts build on tag.
7. Documentation complete: `README` (setup/build/export), `ARCHITECTURE`, `DECISIONS`, config reference, and a "how to reskin / add a cosmetic / add a language / change ad frequency" guide.
8. No hard-coded secrets; no copyrighted assets; store-listing + privacy scaffolding present.

## 16. GUARDRAILS FOR THE BUILDING AGENT

* Implement, don't stub, unless a live credential is required — then provide a working Null/mock provider and flag it in `DECISIONS.md`.
* Prefer boring, proven patterns over cleverness. Keep gameplay code readable.
* Keep everything data-driven; adding a skin, mission, arena, or price must not require touching gameplay logic.
* Never block the first play session with sign-in, ads, or IAP.
* Respect platform policies (Apple/Google/portals), privacy law (GDPR/CCPA/COPPA/ATT), and accessibility (reduced motion, colorblind, min touch targets, epilepsy-safe flashing).
* Ask the user before: spending money, publishing, choosing the paid backend/analytics vendor, or any irreversible store action. Otherwise proceed and document.
* Optimize for the clip moment and retention in every design tradeoff — those drive the game's success.

---

**End of Ultra Build Prompt.** Build POLARITY to this spec. Where you must deviate, deviate toward "simpler, more fun, more shippable" and record why.
