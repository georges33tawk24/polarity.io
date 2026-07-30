# ARCHITECTURE

How POLARITY is put together and why. For *what exists*, see
[PROGRESS.md](PROGRESS.md); for *why it deviates from the brief*, see
[DECISIONS.md](DECISIONS.md).

---

## The three rules that hold it together

**1. Interaction lives in `arena.gd`, not in the entities.**
Attraction, contact bites, repel, hazards, conveyors, polarity zones, power-up
pickups and ring pressure are one readable pass per frame. Entities own only
themselves. The alternative — N objects reaching into each other — is how a
top-down arena game becomes unmaintainable by the third hazard type.

**2. UI never touches gameplay.** It listens to `Bus` signals. Gameplay emits
and does not know the UI exists. The same rule extends to the meta layer: the
arena emits `scrap_absorbed`, and `Meta` decides that means mission progress.

**3. Every platform difference sits behind a provider seam.** Gameplay never
calls `OS.get_name()`. Swapping in an ad network, a billing SDK or a backend
means replacing one object, not editing call sites.

---

## Layers

```
main.tscn ─ main.gd                 root; owns the UI, swaps the arena in/out
│
├── ui.gd ───────────────────────── menu, HUD, results, settings, consent,
│   ├── ui_kit.gd                   shared widget builders
│   ├── ui_meta.gd                  shop / missions / leaderboard / pass / store
│   └── ftue.gd                     guided first match
│
├── camera_rig.gd ───────────────── ortho follow, trauma shake, clip punch
│
└── arena.gd ────────────────────── match FSM + ALL cross-entity interaction
    ├── magnet.gd                   player and bots — identical physics
    ├── bot_brain.gd                5-state FSM writing move_dir/holding
    ├── scrap_field.gd              MultiMesh scrap sim over flat arrays
    ├── powerups.gd                 pickups and timed buffs
    └── fx.gd                       pooled shockwaves, bursts, floating numbers
```

### Autoloads (9)

| Autoload | Owns |
|---|---|
| `Bus` | Every cross-cutting signal. No state. |
| `Platform` | OS detection, safe areas, haptics, share, notifications, ad/IAP null providers |
| `Audio` | Buses, pooled players, synthesised SFX, ad ducking |
| `Game` | Tuning resource, profile, save/load/migration, currency + ledger |
| `Meta` | Daily rewards, missions, battle pass, rank ladder |
| `Config` | Remote config, feature flags, A/B assignment, segmentation |
| `Analytics` | Event queue, batching, offline persistence, crash breadcrumbs |
| `Ads` | Consent state, frequency caps, rewarded/interstitial/banner policy |
| `Store` | IAP catalogue, purchase/restore/revoke, entitlements, offers |
| `Backend` | Auth, cloud save + merge, leaderboards, referral |

The spec asks for 17. The seven that are missing would have been empty shells:
haptics, notifications, input and localization are static helpers or live in
`Platform`, and auth/leaderboard/cloud-save are one vendor account, so they are
one object.

### Static helpers (no autoload)

`Cosmetics`, `Locale`, `Intent`, `UiKit`, `Tuning` — lookup tables and pure
functions with no lifecycle. Making these singletons would add nine more
globals for zero behaviour.

---

## Data flow

```
input ──> Intent ──> magnet.move_dir / .holding ──┐
                                                   ├──> arena interaction pass
bot_brain ──> magnet.move_dir / .holding ─────────┘         │
                                                             ├──> Bus signals
                                                             │
                          ui.gd / Meta / Analytics <─────────┘
```

Bots write the *same two fields* a network peer would. That is the netcode seam
from spec §4.14: v1 bots can be replaced by remote input without touching the
simulation.

---

## Where the data lives

Everything a designer would want to change is a file, not a line of code:

| File | Controls |
|---|---|
| `data/default_tuning.tres` | Every gameplay constant (~90 values) |
| `data/cosmetics.json` | 35 cosmetics across 5 kinds |
| `data/meta.json` | Daily calendar, missions, battle pass, ranks |
| `data/store.json` | IAP products and offers |
| `data/remote_config.json` | Feature flags, ad caps, experiments — the schema of record |
| `data/i18n/strings.csv` | ~100 keys × 10 languages |

## Provider seams

| Seam | Shipped | Swap to |
|---|---|---|
| `Platform.ads_available()` | reports false | AdMob (mobile), CrazyGames/Poki (web) |
| `Store.Provider` | reports unavailable | Play Billing, StoreKit |
| `Backend.Provider` | local guest + on-disk board | Nakama, PlayFab, Firebase, SilentWolf |
| `Config.refresh()` | serves cached/default layers | Firebase Remote Config, PlayFab |
| `Analytics._send()` | appends to a local JSONL | any batch HTTP endpoint |

Each is one object or one function body. No gameplay code changes.

---

## Performance model

- **One draw call for all scrap.** A `MultiMesh` over flat `Packed*Array`s —
  400 `RigidBody3D`s would not hold 60fps on a mid-range phone, and scrap needs
  no collision with anything except a magnet, which is one distance check.
- **No real-time shadows.** Glow only on emissive accents.
- **Everything pooled.** FX preallocate; the hot loop never instantiates.
- **Auto quality scaler** watches frame time and drops particle work and 3D
  render scale together.

Known ceiling: the scrap↔magnet loop is naive O(n·m), fine to ~2000 scrap or
~40 bots. Marked in `scrap_field.gd` with the upgrade path.

---

## Testing

Two suites, no framework:

- **`tests/tests.tscn`** — headless, ~240 assertions. Maths, economy, save
  migration, cloud merge, ads policy, IAP grants, localization completeness,
  power-up buffs, referral guards, arena lifecycle/leak check.
- **`tests/smoke.tscn`** — real renderer. Plays a full match through real
  physics and real bots, asserting placements, ring pressure, meta-layer wiring
  and that scrap is visible before the first physics frame.

Both are seeded. The suite snapshots and restores the real profile, because it
buys things and claims rewards on it.

**Providers are injectable specifically so their consumers are testable.** The
IAP tests drive a fake billing provider through purchase, restore and revoke —
the shipped Null provider always fails, so without the fake, none of that logic
would be exercised until an SDK was wired in.
