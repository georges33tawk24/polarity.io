# Store listing scaffold

Everything a submission needs that is **not** code. Nothing here is submitted
automatically — publishing is an irreversible action and is the owner's call
(spec §16).

---

## Identity

| Field | Value |
|---|---|
| Title | POLARITY |
| Subtitle / short description | One-thumb magnet combat. Hold to attract, release to repel. |
| Bundle / package id | `com.example.polarity` — **change before submission** |
| Category | Games › Action / Arcade |
| Content rating | Expect IARC "Everyone" / PEGI 3 — no violence against characters, no gambling, no user-generated content |

## Full description (EN)

> You are a magnet in a shrinking arena full of rivals.
>
> **Hold to attract.** Pull loose scrap in to grow bigger and stronger.
> **Release to repel.** Time the burst to launch rivals into saw blades, spike
> pits — or clean out of the ring.
>
> The same thumb does both, so every second you spend growing is a second you
> are not armed. The arena closes in. Last magnet standing wins.
>
> • 15-magnet arenas, 100-second matches
> • Saw blades, spike pits, electric fences, conveyors and reverse-polarity zones
> • Power-ups: surge, speed, shield, mega-repel, freeze
> • 35 cosmetics — skins, trails, launch effects, nameplates, arena themes
> • Daily rewards, missions, a 30-tier season pass and a six-rank ladder
> • Ten languages
>
> No sign-in. No wait timers. Cosmetics are cosmetic — nothing you buy makes
> your magnet stronger.

**Do not claim live PvP.** Opponents are bots (spec §7); several store policies
treat "multiplayer" claims about bot lobbies as misleading.

## Keywords

`magnet, arena, io, battle royale, one thumb, casual, physics, shrinking ring`

---

## Required assets — NOT YET PRODUCED

| Asset | Spec | Status |
|---|---|---|
| App icon | 1024×1024 PNG, no alpha, no rounded corners | **TODO** — `icon.svg` is a placeholder |
| Adaptive icon (Android) | 432×432 foreground + background | **TODO** |
| Feature graphic (Play) | 1024×500 | **TODO** |
| Phone screenshots | ≥3, 1080×1920 | Capturable via `tests/menu_shot.tscn` and `tests/smoke.tscn --shot=` |
| Tablet screenshots | ≥1, 1536×2048 | **TODO** |
| iPhone 6.7" / 6.5" | 1290×2796 / 1242×2688 | **TODO** |
| Promo video | 15-30s | **TODO** — the clip-cam moment is the hook |

Screenshots can be produced today:

```bash
/Applications/Godot.app/Contents/MacOS/Godot res://tests/smoke.tscn -- --real --shot=/tmp/shot1.png
```

---

## Data safety / privacy nutrition labels

Answer these from what the code **actually** does today, not from what it might
do once a vendor is wired in.

| Question | Answer today |
|---|---|
| Collects personal info? | **No** |
| Collects device identifiers? | **No** — `install_id` is generated locally and never transmitted (all providers are Null) |
| Collects analytics? | **Not transmitted.** Events are queued and written to a local file only |
| Shares data with third parties? | **No** |
| Data encrypted in transit? | N/A — nothing is transmitted |
| Can users request deletion? | **Yes** — Settings › Account › Delete My Data wipes every local file |
| Ads? | **No** — no ad SDK is integrated |
| In-app purchases? | **No** — no billing provider is integrated |

**These answers change the moment a real provider is wired in.** Ads, analytics
and IAP all become "yes", and identifiers/purchase history become collected
categories. Re-answer before any submission that includes a live SDK.

## Legal

- Privacy policy URL — **TODO**, currently `https://example.com/polarity/privacy` in Settings
- Terms of service URL — **TODO**
- Support / contact email — **TODO**
- COPPA: an age gate ships and under-13 disables personalised ads and IAP entirely

## Pre-submission checklist

- [ ] Bundle id changed from `com.example.polarity`
- [ ] App icons produced at every required size
- [ ] Privacy policy and ToS hosted, URLs updated in `ui.gd`
- [ ] Data-safety answers re-checked against wired providers
- [ ] Android keystore configured (never committed — see README "Signing")
- [ ] iOS team id set in `export_presets.cfg`
- [ ] Store copy does not claim live multiplayer
- [ ] Tested on a real low-end device, not only the simulator
