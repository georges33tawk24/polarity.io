# POLARITY — start here, every session

**Before doing anything else, read these two files:**

1. **[SPEC.md](SPEC.md)** — the user's full build brief, saved verbatim. This is
   the source of truth and it does not change. It outranks any summary in the
   conversation and any assumption you are tempted to make.
2. **[PROGRESS.md](PROGRESS.md)** — running delivery state, with a **NEXT UP**
   section at the top. Resume from there.

The spec is ~60 systems across 6 milestones and will not fit in one context
window. That is why it is on disk. The user asked explicitly that it stay the
standing priority across context resets.

## Rules of engagement

- **Never silently drop a feature.** If something is infeasible, build the
  closest viable version and log it in [DECISIONS.md](DECISIONS.md).
- **Update PROGRESS.md whenever a feature lands.** Never mark something DONE
  that you have not actually run.
- **Never mark a system complete because it compiles.** Run it. Nine real bugs
  in M1 were invisible until something was executed or screenshotted, including
  a test suite that reported 47/47 green while the UI was entirely broken
  (DECISIONS §9).
- **Settled architecture is in DECISIONS.md** — 4 autoloads not 17, UI in code,
  MultiMesh scrap, CharacterBody3D magnets. Don't drift back to the spec's
  literal structure by accident; change deliberately or not at all.
- **Null providers report unavailable, never fake success.** A stub that returns
  a granted reward would silently mint currency in production.
- Ask the user before spending money, publishing, or choosing a paid vendor
  (backend, analytics, ad network). Otherwise proceed and document.

## Verify with

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/tests.tscn
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot res://tests/smoke.tscn -- --real
```

Headless runs print `mesh_get_surface_count: Parameter "m" is null` — that is the
dummy renderer, not a game error. Do not filter output so aggressively that you
hide `SCRIPT ERROR` / `Parse Error` lines; that is how the broken-UI bug survived.
