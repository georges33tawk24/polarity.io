class_name BotBrain
extends RefCounted
## Bot AI. Writes `move_dir` / `holding` on its magnet and nothing else — bots
## fire repel by releasing the hold on the same falling edge the player does,
## so they cannot do anything a human cannot.

enum State { SEEK, HUNT, FLEE, RETURN }

var magnet: Magnet
var t: Tuning
## 0 = clumsy, 1 = sharp. Drives reaction time, aim error and aggression.
var skill := 0.5

var state := State.SEEK
var _think_timer := 0.0
var _think_interval := 0.25
var _waypoint := Vector3.ZERO
var _waypoint_timer := 0.0
var _aim_offset := Vector2.ZERO
var _release_timer := 0.0
var _target: Magnet = null


func _init(m: Magnet, tuning: Tuning, skill_level: float) -> void:
	magnet = m
	t = tuning
	skill = clampf(skill_level, 0.0, 1.0)
	# Stagger first thinks so 14 bots never re-plan on the same frame.
	_think_timer = randf() * 0.25
	_think_interval = lerpf(0.4, 0.12, skill)


func think(delta: float, magnets: Array, ring_radius: float) -> void:
	if not magnet.alive:
		return

	_release_timer = maxf(0.0, _release_timer - delta)
	_waypoint_timer -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = _think_interval
		_plan(magnets, ring_radius)
		# Aim error re-rolled each decision, not each frame, so bots drift
		# convincingly instead of jittering.
		var err := lerpf(0.45, 0.04, skill)
		_aim_offset = Vector2(randf_range(-err, err), randf_range(-err, err))

	_act(ring_radius)


func _plan(magnets: Array, ring_radius: float) -> void:
	var me := magnet.global_position
	var dist_to_centre := Vector2(me.x, me.z).length()

	# Getting caught outside the ring beats every other consideration.
	if dist_to_centre > ring_radius * 0.88:
		state = State.RETURN
		_target = null
		return

	var threat: Magnet = null
	var prey: Magnet = null
	var threat_d := INF
	var prey_d := INF
	var awareness := magnet.pull_radius() * lerpf(1.6, 3.2, skill)

	for other: Magnet in magnets:
		if other == magnet or not other.alive:
			continue
		var d := me.distance_to(other.global_position)
		if d > awareness:
			continue
		if other.mass > magnet.mass * t.absorb_mass_ratio:
			if d < threat_d:
				threat_d = d
				threat = other
		elif magnet.mass > other.mass * t.absorb_mass_ratio:
			if d < prey_d:
				prey_d = d
				prey = other

	# A confident bot will trade a nearby threat for a kill; a timid one runs.
	if threat != null and threat_d < magnet.pull_radius() * lerpf(2.0, 1.2, skill):
		state = State.FLEE
		_target = threat
	elif prey != null and randf() < 0.35 + skill * 0.6:
		state = State.HUNT
		_target = prey
	else:
		state = State.SEEK
		_target = null


func _act(ring_radius: float) -> void:
	var me := magnet.global_position
	var desired := Vector2.ZERO
	var want_hold := true

	match state:
		State.RETURN:
			desired = -Vector2(me.x, me.z).normalized()
			want_hold = true

		State.FLEE:
			if _target != null and _target.alive:
				var away := Vector2(me.x - _target.global_position.x, me.z - _target.global_position.z)
				desired = away.normalized()
				# Close enough to be bitten: release into their face to buy space.
				var d := me.distance_to(_target.global_position)
				if d < (magnet.radius() + _target.radius()) * 2.0 and _release_timer <= 0.0:
					want_hold = false
					_release_timer = t.repel_cooldown + 0.2
			else:
				state = State.SEEK

		State.HUNT:
			if _target != null and _target.alive:
				var to := Vector2(_target.global_position.x - me.x, _target.global_position.z - me.z)
				desired = to.normalized()
				# If the prey is already near the edge, launching them out is
				# worth more than the bite — this is the bot playing well.
				var prey_edge := Vector2(_target.global_position.x, _target.global_position.z).length()
				var close: bool = to.length() < magnet.pull_radius() * 0.6
				if close and prey_edge > ring_radius * 0.7 and magnet.charge > t.repel_charge_time * 0.7 \
						and _release_timer <= 0.0 and randf() < skill:
					want_hold = false
					_release_timer = t.repel_cooldown + 0.3
			else:
				state = State.SEEK

		_:
			if _waypoint_timer <= 0.0 or Vector2(me.x - _waypoint.x, me.z - _waypoint.z).length() < 3.0:
				_pick_waypoint(ring_radius)
			desired = Vector2(_waypoint.x - me.x, _waypoint.z - me.z).normalized()
			want_hold = true

	magnet.move_dir = (desired + _aim_offset).limit_length(1.0)
	magnet.holding = want_hold


func _pick_waypoint(ring_radius: float) -> void:
	# ponytail: bots roam to random points rather than hunting the densest
	# scrap. Attraction brings the scrap to them, so the behaviour reads the
	# same and it skips a 400-item search per bot per think. Revisit if bots
	# start looking aimless on camera.
	var r: float = ring_radius * 0.8 * sqrt(randf())
	var a := randf() * TAU
	_waypoint = Vector3(cos(a) * r, 0.0, sin(a) * r)
	_waypoint_timer = randf_range(2.5, 5.0)
