extends Node
## Global pub/sub. Gameplay emits, UI/FX/audio listen.
## Nothing here holds state and nothing reaches back into gameplay internals.

# --- match lifecycle ---
signal match_started
signal countdown_tick(seconds_left: int)
signal match_ended(result: Dictionary)
signal sudden_death_started

# --- gameplay ---
signal player_mass_changed(mass: float)
signal player_absorbed(world_pos: Vector3, amount: float)
signal player_charge_changed(charge01: float, ready: bool)
signal magnet_eliminated(victim_name: String, killer_name: String, by_player: bool)
signal alive_count_changed(count: int)
signal leaderboard_changed(rows: Array)
signal ring_changed(radius: float)
signal clock_changed(seconds_left: float)
signal player_outside_ring(outside: bool)
## The player died and a revive is genuinely available. The arena is HELD — it does
## not finish — until Arena.revive_player() or Arena.decline_revive() is called, so
## the offer can never be silently dropped and leave the match hanging.
signal player_down

# --- feel ---
signal shake(amount: float)
signal repel_fired(world_pos: Vector3, radius: float, power: float)
signal clip_moment(world_pos: Vector3)

# --- meta ---
signal profile_changed
## Every screen caches its strings at build time, so a locale change means a
## UI rebuild rather than a refresh.
signal locale_changed
## Every currency movement, for the ledger and analytics.
signal currency_changed(currency: String, delta: int, source: String)
signal cosmetic_equipped(kind: String, id: String)
signal mission_progress(id: String, current: int, target: int)
signal mission_completed(id: String)
signal reward_claimed(kind: String, amount: int)
## Gameplay facts the meta layer counts. Emitted by the arena, consumed by
## missions/achievements — gameplay never knows missions exist.
signal scrap_absorbed(amount: float)
signal player_eliminated_rival
signal powerup_taken(kind: int, seconds: float, color: Color)
signal polarity_inverted(inverted: bool)
