class_name Tuning
extends Resource
## Every gameplay constant. Gameplay scripts read these — they never hard-code a number.
## Edit res://data/default_tuning.tres in the inspector to retune without touching code.

@export_group("Magnet")
## Mass every magnet starts a match with.
@export var start_mass := 10.0
## Below this mass a magnet is eliminated. The gap to start_mass is the whole
## early-game survivability budget — keep it wide.
@export var min_mass := 3.0
## Visual/collision radius at start_mass.
@export var base_radius := 1.15
## radius = base_radius * (mass / start_mass) ^ this. Sub-linear, so growth stays readable.
@export var radius_exponent := 0.42
## Pull radius as a multiple of body radius.
@export var pull_radius_mult := 4.6
## Move speed at start_mass. Raised hard after the first device test — at 10.5 a
## magnet took two full seconds to cross the visible arena, which reads as slow
## motion on a phone where your thumb has already arrived.
@export var base_speed := 16.5
## speed = base_speed * (start_mass / mass) ^ this. Bigger = slower = the growth tradeoff.
@export var speed_mass_exponent := 0.17
@export var accel := 95.0
## Deceleration when not steering.
@export var drag := 9.0

@export_group("Magnetism")
## force = base_pull_force * puller_mass / distance ^ falloff_exponent
@export var base_pull_force := 30.0
@export var falloff_exponent := 1.35
## Distance clamp — stops the 1/d^2 singularity from launching things to infinity.
@export var min_distance := 1.4
@export var scrap_max_speed := 30.0
@export var scrap_drag := 1.4

@export_group("Repel")
## Base impulse strength of a release burst.
@export var repel_impulse := 30.0
## Hold this long (seconds) for a full-power release.
@export var repel_charge_time := 0.45
## Power floor, so a quick tap still does something.
@export var repel_min_power := 0.35
@export var repel_cooldown := 0.35
## Hard ceiling on how fast a magnet can be flung. Impulses stack — two bots
## releasing at once used to put a magnet at 4x its own top speed, which is
## unrecoverable and reads as being deleted rather than launched. Keep this
## well above base_speed so launches still look violent.
@export var max_launch_speed := 26.0

@export_group("Combat")
## You must out-mass a rival by this ratio to bite them on contact. Set this
## too low and eating two scrap pieces lets you delete a neighbour.
@export var absorb_mass_ratio := 1.25
## Fraction of their mass taken per contact bite. 0.12 gave ~3.5s of sustained
## contact to kill, which on a phone felt like nothing was happening. 0.26 fixed
## that and broke the other end — an idle player died in 1.9s, inside the 3s floor
## the smoke test enforces, which is about how long someone needs to notice they are
## being eaten and react. 0.19 lands near 1.9x faster than the original without
## taking the reaction window away.
@export var absorb_fraction := 0.19
## Awarded to the killer as a fraction of the victim's PEAK mass, not their
## remaining mass — victims always die at min_mass, so remaining-mass bounties
## are worthless and killing a giant has to pay more than killing a rookie.
@export var kill_bounty := 0.35
## Being launched outside the ring above this speed is lethal immediately,
## but only once this far past the boundary — see launch_kill_margin.
@export var launch_kill_speed := 17.0
## How far beyond the ring the victim must be flung for the instant kill.
@export var launch_kill_margin := 3.0
## Seconds of contact invulnerability after being bitten (stops instant chain-drain).
@export var bite_cooldown := 0.46

@export_group("Scrap")
@export var scrap_count := 420
@export var scrap_mass_min := 0.5
@export var scrap_mass_max := 1.7
@export var scrap_respawn_time := 3.0

@export_group("Hazards")
@export var saw_count := 2
@export var saw_radius := 2.1
@export var saw_orbit_speed := 0.5
## Mass drained per second of saw contact. Budget every drain against
## (start_mass - min_mass) = 7, NOT start_mass: 3.0/s is ~2.3s to kill a fresh
## magnet — a real threat you can still escape, not an instant delete.
@export var saw_drain := 3.0
@export var spike_count := 2
@export var spike_radius := 2.6
## ~3.9s to kill at rest, ~1.2s for someone launched in at speed.
@export var spike_drain := 1.8
## Impact-speed multiplier — launching a rival into spikes is the payoff.
@export var spike_impact_mult := 1.5

@export_group("Hazards II")
## Electric fence: a rotating bar that arcs between two posts.
## Zero on purpose. The fence was a white bar that blocked movement and did nothing
## visually when it caught someone — the least readable hazard in the set and the
## only one with no reaction. Kept as a tunable rather than deleted, like the
## conveyor, so it can come back if the arena ever feels empty.
@export var fence_count := 0
@export var fence_length := 9.0
@export var fence_spin := 0.35
@export var fence_drain := 4.5
## Conveyor: a directional strip that shoves anything standing on it.
## Disabled by default — it was the least readable hazard and the only one with
## no visual payoff when a rival hits it. Set above 0 to bring it back.
@export var conveyor_count := 0
@export var conveyor_length := 12.0
@export var conveyor_width := 4.0
@export var conveyor_push := 14.0
## Reverse-polarity zone: inverts attract/repel while you stand in it. The one
## hazard that is a puzzle rather than damage.
@export var reverse_zone_count := 1
@export var reverse_zone_radius := 6.0

@export_group("Power-ups")
@export var powerup_count := 3
@export var powerup_respawn := 12.0
@export var powerup_radius := 1.4
@export var powerup_duration := 6.0
## Multipliers applied while a power-up is active.
@export var surge_pull_mult := 2.2
@export var speed_mult := 1.55
@export var mega_repel_mult := 2.4
@export var freeze_seconds := 2.5

@export_group("Match")
@export var bot_count := 14
@export var match_duration := 100.0
@export var ring_start_radius := 44.0
@export var ring_end_radius := 8.0
## Seconds of grace before the ring starts closing.
@export var ring_shrink_delay := 12.0
## Magnets remaining that triggers sudden death.
@export var sudden_death_at := 3
@export var sudden_death_shrink_mult := 2.6
## Mass drained per second while outside the ring — ~2.8s of grace to get back.
@export var outside_drain := 2.5
@export var countdown_time := 2.5

@export_group("Camera")
@export var camera_angle_deg := 58.0
@export var camera_size_base := 21.0
## Orthographic size grows with mass so a bigger magnet sees more.
@export var camera_size_mass_exp := 0.34
@export var camera_lerp := 7.0

@export_group("Feel")
## Shake punctuates, it does not obscure. These were 3x higher and made a kill
## unreadable at this camera distance — see ART_DIRECTION.md.
@export var shake_launch := 0.12
@export var shake_kill := 0.22
@export var shake_hit := 0.08
## Seconds of slow-motion on a kill — the clip moment.
@export var hitstop_time := 0.12
@export var hitstop_scale := 0.25
## A launch above this power on a real target triggers the clip cam.
@export var clip_power_threshold := 0.8

@export_group("Economy")
@export var coins_per_kill := 12
@export var coins_per_mass := 0.35
@export var coins_win_bonus := 120
@export var xp_per_kill := 8
@export var xp_win_bonus := 60


## radius grows sub-linearly with mass.
func radius_for(mass: float) -> float:
	return base_radius * pow(maxf(mass, 0.01) / start_mass, radius_exponent)


## speed shrinks as mass grows — the risk/reward of snowballing.
func speed_for(mass: float) -> float:
	return base_speed * pow(start_mass / maxf(mass, 0.01), speed_mass_exponent)


func pull_radius_for(mass: float) -> float:
	return radius_for(mass) * pull_radius_mult


## Attraction force a magnet of `mass` exerts at `distance`.
func pull_force(mass: float, distance: float) -> float:
	return base_pull_force * mass / pow(maxf(distance, min_distance), falloff_exponent)
