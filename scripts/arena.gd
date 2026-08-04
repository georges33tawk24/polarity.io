class_name Arena
extends Node3D
## The match: world, entities, interactions and the match state machine.
##
## All cross-entity interaction lives here rather than inside the entities, so
## every rule (attraction, bites, repel, hazards, the ring) is in one readable
## pass instead of scattered across N objects reaching into each other.

## AWAITING_REVIVE holds the match open after the player dies while the revive offer
## is on screen. Everything that gates on PLAYING therefore stops, which is what we
## want: the arena freezes rather than running on without you.
enum State { COUNTDOWN, PLAYING, SUDDEN_DEATH, AWAITING_REVIVE, FINISHED }

## Fallback pool. The localised pools live in data/bot_names.json — see
## _bot_name_pool(). A lobby of English handles in a Japanese build was the one
## remaining place the game did not speak the player's language (§7).
const BOT_NAMES := [
	"Ferro", "Gauss", "Tesla", "NoobSlayer", "Polaris", "xX_Iron_Xx", "Bolt",
	"Rust", "Magneto", "Anvil", "Cobalt", "Zap", "Slag", "Nickel", "Coil",
	"Hexnut", "Flux", "Ampere", "Scrapz", "Lodestone", "Weber", "Oersted",
	"Pigiron", "Solder", "Dynamo", "Sparky", "Ingot", "Cathode",
]

## Bot colours. De-neoned to the same degree as the shop skins — this table was
## missed by that pass entirely, so every rival stayed fluorescent while the
## player's own skins were toned down.
const PALETTE := [
	[Color(0.90, 0.44, 0.30), Color(0.89, 0.73, 0.34)],
	[Color(0.39, 0.78, 0.60), Color(0.27, 0.53, 0.76)],
	[Color(0.78, 0.39, 0.78), Color(0.46, 0.35, 0.83)],
	[Color(0.88, 0.35, 0.47), Color(0.36, 0.36, 0.44)],
	[Color(0.35, 0.74, 0.83), Color(0.22, 0.37, 0.59)],
	[Color(0.86, 0.78, 0.39), Color(0.51, 0.41, 0.20)],
	[Color(0.67, 0.83, 0.35), Color(0.31, 0.53, 0.27)],
]

var t: Tuning
var state := State.COUNTDOWN
var magnets: Array[Magnet] = []
var player: Magnet = null
var ring_radius := 44.0
var time_left := 100.0
var elapsed := 0.0

var scrap: ScrapField
var fx: Fx
var rig: CameraRig
var intent := Intent.new()
## Last time a hazard buzzed. See _hazard_hit.
var _hazard_vibe_at := 0.0

var _floor_mat: ShaderMaterial
var _saws: Array[Dictionary] = []
var _spikes: Array[Dictionary] = []
var _hazard_nodes: Array[Node3D] = []
var _fences: Array[Dictionary] = []
var _conveyors: Array[Dictionary] = []
var _reverse_zones: Array[Dictionary] = []
var powerups: Powerups
var _countdown := 0.0
var _last_countdown_call := -1
var _placement_counter := 0
var _board_timer := 0.0
var _revive_used := false
var _pending_boost := 0.0

## §4.14 determinism. Every random the ARENA uses goes through this, so the same
## seed produces the same layout — spawn ring, hazard placement, scrap field.
##
## What this buys and what it does NOT: a reproducible starting state, which is the
## prerequisite for replays, for a server validating a client's match, and for
## reproducing a bug report. It is NOT lockstep determinism — physics runs on
## floats through Godot's solver, bots hold their own RNG, and delta varies with
## frame rate. Claiming more than this would be the kind of thing that looks true
## until two machines disagree.
var rng := RandomNumberGenerator.new()
var seed_used := 0
var _alarm_timer := 0.0
var _fps_accum := 0.0
var _fps_frames := 0
var _quality := 1.0
var _finished_emitted := false
var _hitstop_until := 0


func setup(tuning: Tuning, camera_rig: CameraRig, match_seed := 0) -> void:
	for step in setup_staged(tuning, camera_rig, match_seed):
		step.call()


## Same work, yielded in stages so a loading screen can report honest progress.
## Each stage is one frame's worth of construction; the caller drives it.
## Entity budget for the device actually running this.
##
## The shipped tuning is authored on a desktop. On a real phone, 91
## CharacterBody3D magnets plus 7000 MultiMesh scrap pieces measured about two
## frames per second — the game was not slow, it was unplayable, and every button
## looked broken because the UI was updating twice a second too.
##
## The arena keeps its size: the player asked for a big map and a big map is
## cheap. What is expensive is what is IN it, so density comes down on mobile
## instead. Scaled from the shipped values rather than hardcoded so tuning still
## has one source of truth.
func _fit_to_device(tuning: Tuning) -> Tuning:
	if not Platform.is_mobile():
		return tuning
	var t2: Tuning = tuning.duplicate()
	t2.bot_count = maxi(8, int(round(float(tuning.bot_count) * MOBILE_BOTS)))
	t2.scrap_count = maxi(120, int(round(float(tuning.scrap_count) * MOBILE_SCRAP)))
	return t2


## Fractions of the desktop counts. Deliberately aggressive: an unplayable frame
## rate costs more than a thinner lobby, and these are the two numbers to raise
## once there is a real measurement from a device.
const MOBILE_BOTS := 0.33
const MOBILE_SCRAP := 0.25


func setup_staged(tuning: Tuning, camera_rig: CameraRig,
		match_seed := 0) -> Array[Callable]:
	t = _fit_to_device(tuning)
	rig = camera_rig
	# 0 means "pick one" — a real match should differ every time. A caller that
	# passes a seed gets that exact layout back, which is what makes a bug report
	# reproducible.
	seed_used = match_seed if match_seed != 0 else randi()
	rng.seed = seed_used
	ring_radius = t.ring_start_radius
	time_left = t.match_duration
	_countdown = t.countdown_time
	return [
		func() -> void: _build_world(),
		func() -> void: _spawn_magnets(),
		# After spawning, so hazards can be kept clear of everyone's start point.
		func() -> void: _build_hazards(),
		func() -> void:
			# A headless caller (the determinism test, and any future replay
			# re-simulation) has no camera. The arena is fully playable without one.
			if rig != null:
				rig.setup(t)
				rig.target = player
			_placement_counter = magnets.size()
			Bus.alive_count_changed.emit(magnets.size())
			Bus.ring_changed.emit(ring_radius),
	]


# --- world -----------------------------------------------------------------
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.145, 0.145, 0.152)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.88, 0.94)
	e.ambient_light_energy = 0.85
	# Glow OFF. When everything blooms, nothing is emphasised — and bloom over a
	# dark background is the core of the neon look we are removing.
	e.glow_enabled = false
	# Grading + vignette: the polish layer that separates "prototype" from
	# "shipped" in this genre, and costs nothing on the mobile renderer.
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.08
	# Below 1.0 on purpose: matte and chalky, not fluorescent.
	e.adjustment_saturation = 0.95
	env.environment = e
	add_child(env)

	# Key light, warm, from over the player's shoulder.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-deg_to_rad(58), deg_to_rad(35), 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = false  # blob shadows instead — §13A, and free on mobile
	add_child(sun)

	# Cool fill from the opposite side. One light gives a flat, half-black read
	# on a curved body; the fill is what makes the horseshoe legible.
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-deg_to_rad(28), deg_to_rad(-135), 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.72, 0.76, 0.84)
	fill.shadow_enabled = false
	add_child(fill)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(t.ring_start_radius * 3.0, t.ring_start_radius * 3.0)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = load("res://shaders/floor.gdshader")
	_floor_mat.set_shader_parameter("ring_radius", ring_radius)
	var theme := Cosmetics.arena_theme()
	_floor_mat.set_shader_parameter("base_color", Color(String(theme.get("base", "#292a2c"))))
	_floor_mat.set_shader_parameter("grid_color", Color(String(theme.get("grid", "#5c6068"))))
	_floor_mat.set_shader_parameter("danger_color", Color(String(theme.get("danger", "#5c2520"))))
	ground.mesh = pm
	ground.material_override = _floor_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# No closing ring. The arena boundary is now fixed and shown only by the floor
	# shader's edge falloff — the brass ring that used to be drawn here, and the
	# shrink that drove it, were both removed at the player's request. The boundary
	# ITSELF stays (see _boundary_pressure): without a wall a launched magnet flies
	# into empty space forever.

	scrap = ScrapField.new()
	add_child(scrap)
	scrap.setup(t, t.ring_start_radius * 0.95)

	fx = Fx.new()
	add_child(fx)

	powerups = Powerups.new()
	add_child(powerups)
	powerups.setup(t, t.ring_start_radius * 0.85)


func _build_hazards() -> void:
	# Hazards are kept outside the final ring: once the arena has closed to
	# ring_end_radius there has to be somewhere left to actually fight.
	var inner: float = t.ring_end_radius * 1.15
	for i in t.saw_count:
		var orbit: float = maxf(inner, t.ring_start_radius * rng.randf_range(0.22, 0.66))
		var angle := _clear_angle(orbit, t.saw_radius)
		_saws.append({
			"angle": angle,
			"orbit": orbit,
			"speed": t.saw_orbit_speed * rng.randf_range(0.6, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0),
			"pos": Vector3(cos(angle) * orbit, 0.0, sin(angle) * orbit),
		})
		_hazard_nodes.append(_hazard_node(t.saw_radius, Color(0.82, 0.65, 0.28), true))

	for i in t.spike_count:
		var r: float = lerpf(inner, t.ring_start_radius * 0.72, sqrt(rng.randf()))
		var a := _clear_angle(r, t.spike_radius)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		_spikes.append({"pos": p})
		var n := _hazard_node(t.spike_radius, Color(0.72, 0.33, 0.25), false)
		n.position = p
		_hazard_nodes.append(n)


	_build_fences(inner)
	_build_conveyors(inner)
	_build_reverse_zones(inner)


## Electric fence: a bar that sweeps between two posts. Lethal along its whole
## length, so it threatens a corridor rather than a point.
func _build_fences(inner: float) -> void:
	for i in t.fence_count:
		var orbit: float = maxf(inner + t.fence_length * 0.5,
				t.ring_start_radius * rng.randf_range(0.3, 0.55))
		var angle := _clear_angle(orbit, t.fence_length * 0.5)
		_fences.append({
			"centre": Vector3(cos(angle) * orbit, 0.0, sin(angle) * orbit),
			"angle": rng.randf() * TAU,
			"speed": t.fence_spin * (1.0 if rng.randf() < 0.5 else -1.0),
		})
		var root := Node3D.new()
		add_child(root)
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(t.fence_length, 0.22, 0.22)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.albedo_color = Color("#c9d6dd")
		mat.emission = Color("#7f9aa8")
		bm.material = mat
		bar.mesh = bm
		bar.position.y = 0.6
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bar)
		root.set_meta("bar", bar)
		_hazard_nodes.append(root)
		_fences[i]["node"] = root


## Conveyor: a strip that shoves whatever stands on it. Not damaging — it is a
## positioning hazard, and shoving a rival onto one is the point.
func _build_conveyors(inner: float) -> void:
	for i in t.conveyor_count:
		var r: float = lerpf(inner, t.ring_start_radius * 0.6, rng.randf())
		var a := rng.randf() * TAU
		var dir_angle := rng.randf() * TAU
		_conveyors.append({
			"centre": Vector3(cos(a) * r, 0.0, sin(a) * r),
			"dir": Vector3(cos(dir_angle), 0.0, sin(dir_angle)),
			"angle": dir_angle,
		})
		var strip := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(t.conveyor_length, t.conveyor_width)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#5a5f66")
		mat.emission_enabled = true
		mat.emission = Color("#000000")
		mat.emission_enabled = false
		pm.material = mat
		strip.mesh = pm
		strip.position = _conveyors[i]["centre"] + Vector3(0, 0.03, 0)
		strip.rotation.y = -dir_angle
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)
		_hazard_nodes.append(strip)


## Reverse-polarity zone: inverts attract/repel while you stand in it. The only
## hazard that changes the verb rather than the health bar.
func _build_reverse_zones(inner: float) -> void:
	for i in t.reverse_zone_count:
		var r: float = lerpf(inner, t.ring_start_radius * 0.65, rng.randf())
		var a := _clear_angle(r, t.reverse_zone_radius)
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		_reverse_zones.append({"pos": pos})
		var marker := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/hazard_decal.gdshader")
		mat.set_shader_parameter("paint", Color("#6f6478"))
		# Hatch runs the other way to the damage hazards. Same marking language,
		# opposite angle — you learn "this one changes the rules" in one look.
		mat.set_shader_parameter("stripe_dir", Vector2(1.0, -1.0))
		mat.set_shader_parameter("stripe_scale", 5.0)
		mat.set_shader_parameter("strength", 0.85)
		marker.mesh = pm
		marker.material_override = mat
		marker.scale = Vector3(t.reverse_zone_radius, 1.0, t.reverse_zone_radius)
		marker.position = pos + Vector3(0, 0.06, 0)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
		_hazard_nodes.append(marker)


## An angle at `orbit` distance that is not sitting on anyone's spawn point.
## Spawning inside a saw is an instant unearned death and feels like a bug.
func _clear_angle(orbit: float, hazard_radius: float) -> float:
	var clearance := hazard_radius + 5.0
	for attempt in 12:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * orbit, 0.0, sin(a) * orbit)
		var clear := true
		for m in magnets:
			if p.distance_to(m.global_position) < clearance + m.radius():
				clear = false
				break
		if clear:
			return a
	return rng.randf() * TAU


func _hazard_node(radius: float, tint: Color, saw: bool) -> Node3D:
	var root := Node3D.new()
	add_child(root)

	var marker := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/hazard_decal.gdshader")
	mat.set_shader_parameter("paint", tint)
	mat.set_shader_parameter("stripe_scale", 6.5)
	mat.set_shader_parameter("strength", 0.9)
	marker.mesh = pm
	marker.material_override = mat
	marker.scale = Vector3(radius, 1.0, radius)
	marker.position.y = 0.05
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marker)

	var body := MeshInstance3D.new()
	var bm: Mesh
	if saw:
		# Built at unit scale and scaled by the node, so the cached mesh stays
		# valid if saw_radius is retuned between matches.
		bm = AssetLibrary.mesh("hazard_saw", func() -> Mesh: return Meshes.saw_blade())
		body.scale = Vector3(radius * 0.86, 1.0, radius * 0.86)
	else:
		bm = AssetLibrary.mesh("hazard_spike", func() -> Mesh: return Meshes.shard(1.0, 1.0))
		body.scale = Vector3(radius * 0.34, radius * 0.7, radius * 0.34)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = tint.lerp(Color(0.15, 0.15, 0.2), 0.45)
	bmat.metallic = 0.8
	bmat.roughness = 0.3
	bmat.emission_enabled = true
	bmat.emission = tint
	bmat.emission_energy_multiplier = 0.0
	bmat.emission_enabled = false
	body.mesh = bm
	body.material_override = bmat
	body.position.y = 0.3
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	root.set_meta("body", body)

	if not saw:
		# One wedge read as a dark blob with no scale cue. Four of them at mixed
		# sizes read as a spike cluster, which is what the hazard actually is.
		for i in 4:
			var extra := MeshInstance3D.new()
			extra.mesh = bm
			extra.material_override = bmat
			var a := TAU * (float(i) + 0.5) / 4.0
			var k: float = 0.5 + float(i % 2) * 0.28
			extra.scale = Vector3(radius * 0.24 * k, radius * 0.44 * k, radius * 0.24 * k)
			extra.position = Vector3(cos(a) * radius * 0.46, 0.22, sin(a) * radius * 0.46)
			extra.rotation.y = a
			extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(extra)
	return root


# --- spawning --------------------------------------------------------------
## How far a spawn may wander from its slot, as a fraction of the slot. Shared by
## the placement and by _spawn_ring, which has to size the ring around it.
const SPAWN_JITTER := 0.12


## Spawn positions: concentric rings, filled outward, everyone outside everyone
## else's pull radius at the whistle.
##
## Spawn radii used to be randomised per magnet across a third of the arena, with
## an angular jitter of +/-0.12rad against a 0.27rad slot — so two magnets could
## start about one unit apart while the pull radius was 5.3. That is the player
## report of dying the instant they spawned in, and nothing tested spawn geometry.
##
## One ring is not enough for a big lobby: at 91 magnets the ring needed to be
## wider than the arena, so it clamped and everyone bunched up again. Rings are
## separated by the same gap they enforce along their own circumference, so the
## guarantee holds radially as well as tangentially.
func _spawn_slots(total: int) -> Array:
	var inner: float = t.ring_start_radius * 0.35
	var limit: float = t.ring_start_radius * 0.82
	var gap: float = t.pull_radius_for(t.start_mass) * 2.4
	# Only if the arena genuinely cannot seat the lobby at a comfortable gap do we
	# tighten it — far better than the old behaviour of stacking magnets together,
	# and it still terminates.
	for attempt in 8:
		var slots := _slots_at(total, inner, limit, gap)
		if slots.size() >= total:
			return slots
		gap *= 0.8
	return _slots_at(total, inner, limit, gap)


func _slots_at(total: int, inner: float, limit: float, gap: float) -> Array:
	# Jitter can close up to 2*SPAWN_JITTER of a slot, so each magnet is given
	# that much more room along the circumference than the bare gap.
	var per: float = gap / (1.0 - 2.0 * SPAWN_JITTER)
	var out: Array = []
	var ring_i := 0
	while out.size() < total:
		var r: float = inner + float(ring_i) * gap
		if r > limit:
			break
		var cap: int = maxi(1, int(floor(TAU * r / per)))
		var take: int = mini(cap, total - out.size())
		var step: float = TAU / float(take)
		# Rotated per ring so neighbouring rings do not line up into spokes.
		var phase: float = rng.randf() * TAU
		for k in take:
			var a: float = phase + step * float(k) \
					+ rng.randf_range(-step * SPAWN_JITTER, step * SPAWN_JITTER)
			out.append(Vector3(cos(a) * r, Magnet.BODY_Y, sin(a) * r))
		ring_i += 1
	return out


func _spawn_magnets() -> void:
	var total: int = t.bot_count + 1
	var names := _bot_names(total)
	var slots := _spawn_slots(total)
	# Fisher-Yates through the seeded rng: rings fill inward-out, so without this
	# the player is always the magnet nearest the centre.
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap: Variant = slots[i]
		slots[i] = slots[j]
		slots[j] = swap
	for i in total:
		var m := Magnet.new()
		var is_player := i == 0
		var pal: Array = PALETTE[i % PALETTE.size()]
		if is_player:
			pal = [Color(1.0, 0.25, 0.36), Color(0.28, 0.52, 1.0)]
		add_child(m)
		if is_player and bool(Game.get_value("boost_mass", false)):
			# Consumed here, not when the ad completed: the grant survives a crash
			# between watching and playing, and cannot be spent twice.
			Game.set_value("boost_mass", false)
			_pending_boost = t.start_mass * Config.num("boost.mass_fraction", 0.5)
		m.configure(t, Game.player_name() if is_player else names[i % names.size()],
				pal[0], pal[1], is_player)
		if is_player and _pending_boost > 0.0:
			m.gain_mass(_pending_boost)
			_pending_boost = 0.0

		m.position = slots[i] if i < slots.size() else Vector3(0, Magnet.BODY_Y, 0)

		if not is_player:
			# Skill spread so the lobby feels like real players of mixed ability.
			# Bracketed by rank: climbing the ladder has to mean tougher lobbies.
			var bias := Meta.bot_skill_bias()
			m.brain = BotBrain.new(m, t, clampf(rng.randfn(0.35 + bias * 0.4, 0.22), 0.05, 0.98))
		else:
			player = m

		m.repelled.connect(_on_repelled.bind(m))
		m.eliminated.connect(_on_eliminated)
		magnets.append(m)


# --- input -----------------------------------------------------------------

	# Once, outside the loop: this is a Bus signal, not a per-magnet one.
	if not Bus.player_absorbed.is_connected(_on_player_absorbed):
		Bus.player_absorbed.connect(_on_player_absorbed)

func _unhandled_input(event: InputEvent) -> void:
	if state == State.FINISHED:
		return
	intent.handle_event(event)


func _process(delta: float) -> void:
	if t == null:
		return
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0
	_update_quality(delta)
	# The stick is anchored where the thumb landed, so it no longer depends on the
	# camera having moved — but it still runs here, once per frame, so `dir` is one
	# consistent value for the whole physics step.
	if player != null and player.alive and rig != null:
		intent.update(get_viewport().get_visible_rect().size)

	for i in _saws.size():
		var node := _hazard_nodes[i]
		node.position = _saws[i]["pos"]
		var body: Node3D = node.get_meta("body")
		body.rotation.y += delta * 9.0


func _physics_process(delta: float) -> void:
	if t == null:
		return
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING, State.SUDDEN_DEATH:
			_tick_match(delta)
		State.FINISHED:
			pass


func _tick_countdown(delta: float) -> void:
	_countdown -= delta
	var secs := ceili(_countdown)
	if secs != _last_countdown_call:
		_last_countdown_call = secs
		Bus.countdown_tick.emit(maxi(secs, 0))
		if secs > 0:
			Audio.play("ui_tap", 0.9, -6.0)
	if _countdown <= 0.0:
		state = State.PLAYING
		Bus.match_started.emit()
		Audio.play("reward", 1.0, -6.0)


func _tick_match(delta: float) -> void:
	elapsed += delta
	# Counts UP. There is no round any more: the session ends when the PLAYER
	# dies, which is the only end condition left now the ring and the timer are
	# both gone. What the clock shows is how long you have survived, which is
	# also half the score.
	Bus.clock_changed.emit(elapsed)

	_apply_intent()
	_think_bots(delta)
	_magnet_interactions(delta)
	_step_scrap(delta)
	powerups.step(delta, magnets, ring_radius)
	_hazards(delta)
	_boundary_pressure(delta)
	_update_board(delta)

	# The attract hum rises as you charge — the audio tells you when to release.
	if player != null and player.alive and player.holding and player.cooldown <= 0.0:
		Audio.set_hum(0.5 + 0.5 * player.charge / t.repel_charge_time,
				0.85 + player.charge / t.repel_charge_time * 0.55)
	else:
		Audio.set_hum(0.0)

	_respawn_bots(delta)


## Refills the lobby from the arena edge.
##
## Without this the arena empties: bots eat each other, nobody replaces them, and
## a cautious player ends up alone in a 370-unit arena with nothing to do and no
## way to finish. agar.io works without a round timer because the lobby is always
## full; this is that.
##
## Always at the OUTER edge, never on the spawn rings. A bot appearing next to the
## player mid-match is the spawn-death bug (§12ao) with worse consequences, since
## both are at full mass by then.
func _respawn_bots(delta: float) -> void:
	if state != State.PLAYING:
		return
	var alive := 0
	for m in magnets:
		if m.alive:
			alive += 1
	if alive >= t.bot_count + 1:
		return
	_respawn_timer -= delta
	if _respawn_timer > 0.0:
		return
	_respawn_timer = RESPAWN_EVERY
	_add_bot()


## One replacement bot on the boundary, at an angle well clear of the player.
func _add_bot() -> void:
	var names := _bot_names(8)
	var m := Magnet.new()
	var pal: Array = PALETTE[rng.randi() % PALETTE.size()]
	add_child(m)
	m.configure(t, String(names[rng.randi() % names.size()]), pal[0], pal[1], false)

	# Pick an angle away from the player, so nobody arrives on top of them.
	var away := 0.0
	if player != null and player.alive:
		away = atan2(player.global_position.z, player.global_position.x) + PI
	var a := away + rng.randf_range(-1.1, 1.1)
	var r: float = ring_radius * 0.88
	m.position = Vector3(cos(a) * r, Magnet.BODY_Y, sin(a) * r)

	var bias := Meta.bot_skill_bias()
	m.brain = BotBrain.new(m, t, clampf(rng.randfn(0.35 + bias * 0.4, 0.22), 0.05, 0.98))
	magnets.append(m)
	Bus.alive_count_changed.emit(_alive_count())


## Gap between replacements. Instant refill would make eliminations feel weightless.
const RESPAWN_EVERY := 2.5

var _respawn_timer := 0.0


func _apply_intent() -> void:
	if player == null or not player.alive:
		return
	player.move_dir = intent.dir
	player.holding = intent.held


func _think_bots(delta: float) -> void:
	# Level of detail, the way an .io server does it: what the player can see gets
	# full attention, the rest of the world runs coarser. A bot on the far side of
	# a 370-unit arena is invisible and nobody can tell it is deciding four times a
	# second instead of sixty — but at 90 bots that is most of the AI budget.
	#
	# Staggered by index so the cheap bots do not all think on the same frame and
	# produce a stutter every fourth one.
	_ai_tick += 1
	var focus := player.global_position if player != null and player.alive \
			else Vector3.ZERO
	var near: float = t.ring_start_radius * 0.32
	var near_sq := near * near
	for i in magnets.size():
		var m := magnets[i]
		if not m.alive or m.brain == null:
			continue
		if m.global_position.distance_squared_to(focus) > near_sq:
			if (_ai_tick + i) % AI_SKIP != 0:
				continue
			m.brain.think(delta * float(AI_SKIP), magnets, ring_radius)
		else:
			m.brain.think(delta, magnets, ring_radius)


## How many frames a distant bot skips between decisions.
const AI_SKIP := 4

var _ai_tick := 0


## Attraction and contact bites between magnets. O(n^2) over ~15 bodies.
func _magnet_interactions(delta: float) -> void:
	_rebuild_grid()
	for i in magnets.size():
		var a := magnets[i]
		if not a.alive:
			continue
		# One directional pass: `a` pulls everyone in ITS reach. The old loop tested
		# every ordered pair and applied both directions at once — the same result
		# for n(n-1)/2 length() calls in GDScript every frame, whether or not
		# anything was anywhere near anything.
		for j: int in neighbours(i):
			var b := magnets[j]
			if not b.alive:
				continue
			var to := b.global_position - a.global_position
			to.y = 0.0
			var d := to.length()
			if d < 0.001:
				continue
			var dir := to / d
			if a.is_attracting() and d < a.pull_radius():
				b.velocity -= dir * t.pull_force(a.mass, d) \
						* a.pull_strength_mult() / _resist(b) * delta
			# Contact is symmetric, so resolve it once per pair.
			if j > i and d < a.radius() + b.radius():
				_contact(a, b, dir)


## Uniform grid over the arena, rebuilt each frame.
##
## Cell size is a compromise: too small and a big magnet scans hundreds of cells,
## too large and every cell holds everyone. Reach is dominated by pull radius,
## which after the pull_radius_exponent change tops out near 19 units even for a
## huge magnet, so cells a little wider than that keep the usual scan to 3x3.
const CELL := 28.0

var _grid: Dictionary = {}
var _max_radius := 0.0


func _rebuild_grid() -> void:
	# Buckets are emptied and refilled, never reallocated. Rebuilding the whole
	# Dictionary allocated ~40 Arrays every frame, and per-frame garbage in
	# GDScript shows up as p99 hitches rather than a lower average — which is the
	# half of "keep the fps high" that an average frame time hides.
	for key: Vector2i in _grid:
		(_grid[key] as Array).clear()
	_max_radius = 0.0
	for i in magnets.size():
		var m := magnets[i]
		if not m.alive:
			continue
		_max_radius = maxf(_max_radius, m.radius())
		var key := _cell_key(m.global_position)
		var bucket: Variant = _grid.get(key)
		if bucket == null:
			_grid[key] = [i]
		else:
			(bucket as Array).append(i)


func _cell_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


## Indices of every magnet that could possibly interact with `i`.
##
## Separate from the loop that uses it so it can be checked against brute force —
## a broad phase that quietly misses a pair does not crash, it just stops magnets
## attracting each other sometimes, which is indistinguishable from bad tuning.
func neighbours(i: int) -> Array:
	var a := magnets[i]
	var reach: float = maxf(a.pull_radius(), a.radius() + _max_radius)
	var span := int(ceil(reach / CELL))
	var base := _cell_key(a.global_position)
	var out: Array = []
	for cx in range(base.x - span, base.x + span + 1):
		for cy in range(base.y - span, base.y + span + 1):
			var bucket: Variant = _grid.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			for j: int in bucket:
				if j != i:
					out.append(j)
	return out


## Heavier magnets are dragged around less. Never below 1 or light magnets
## would be flung uncontrollably.
func _resist(m: Magnet) -> float:
	return maxf(1.0, m.mass / t.start_mass)


func _contact(a: Magnet, b: Magnet, dir: Vector3) -> void:
	var big := a
	var small := b
	var sign := 1.0
	if b.mass > a.mass:
		big = b
		small = a
		sign = -1.0
	if big.mass < small.mass * t.absorb_mass_ratio or small.bite_timer > 0.0:
		return

	var take: float = small.mass * t.absorb_fraction
	small.bite_timer = t.bite_cooldown
	small.last_attacker = big
	small.attacker_timer = 3.5
	small.apply_impulse(dir * sign, t.repel_impulse * 0.35, big)
	# Some mass is destroyed rather than transferred — without the sink, two
	# magnets trading bites would inflate the arena's total mass.
	var died := small.lose_mass(take, big)
	if not died:
		big.gain_mass(take * 0.75)
		if big.is_player or small.is_player:
			Audio.play("hit", 1.0, -10.0)
			Bus.shake.emit(t.shake_hit)
			fx.floater(small.global_position, "-%d" % roundi(take), Color(1, 0.5, 0.45))


func _step_scrap(delta: float) -> void:
	var n := magnets.size()
	var mpos := PackedVector3Array()
	var mmass := PackedFloat32Array()
	var mrad := PackedFloat32Array()
	var mpull := PackedFloat32Array()
	var mhold := PackedByteArray()
	mpos.resize(n); mmass.resize(n); mrad.resize(n); mpull.resize(n); mhold.resize(n)
	for i in n:
		var m := magnets[i]
		mpos[i] = m.global_position
		mmass[i] = (m.mass * m.pull_strength_mult()) if m.alive else 0.0
		mrad[i] = (m.radius() + 0.25) if m.alive else -1.0
		mpull[i] = m.pull_radius() if m.alive else 0.0
		mhold[i] = 1 if m.is_attracting() else 0

	var gained := scrap.step(delta, mpos, mmass, mrad, mpull, mhold, ring_radius)
	for i in n:
		if gained[i] > 0.0:
			magnets[i].gain_mass(gained[i])
			if magnets[i].is_player:
				Bus.scrap_absorbed.emit(gained[i])


func _hazards(delta: float) -> void:
	for s in _saws:
		s["angle"] += s["speed"] * delta
		s["pos"] = Vector3(cos(s["angle"]) * s["orbit"], 0.0, sin(s["angle"]) * s["orbit"])

	for f in _fences:
		f["angle"] += f["speed"] * delta
		var node: Node3D = f["node"]
		node.position = f["centre"]
		node.rotation.y = f["angle"]

	for m in magnets:
		if not m.alive:
			continue
		var p := m.global_position

		# Fence: distance to the bar segment, not to its centre.
		for f in _fences:
			var half: Vector3 = Vector3(cos(f["angle"]), 0.0, -sin(f["angle"])) \
					* t.fence_length * 0.5
			var a: Vector3 = f["centre"] - half
			var b: Vector3 = f["centre"] + half
			var ab: Vector3 = b - a
			var tt: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if p.distance_to(a + ab * tt) < 0.5 + m.radius():
				_hazard_hit(m, t.fence_drain * delta, a + ab * tt)

		# Conveyor: push anything standing inside the strip.
		for c in _conveyors:
			var local: Vector3 = p - c["centre"]
			var along: float = local.dot(c["dir"])
			var across: float = local.dot(Vector3(-c["dir"].z, 0.0, c["dir"].x))
			if absf(along) < t.conveyor_length * 0.5 and absf(across) < t.conveyor_width * 0.5:
				m.velocity += c["dir"] * t.conveyor_push * delta

		# Reverse-polarity zone: flips the verb while inside.
		var in_zone := false
		for z in _reverse_zones:
			if p.distance_to(z["pos"]) < t.reverse_zone_radius:
				in_zone = true
				break
		if in_zone != m.inverted:
			m.inverted = in_zone
			if m.is_player:
				Bus.polarity_inverted.emit(in_zone)
				Audio.play("charge_ready", 0.7, -10.0)

		for s in _saws:
			var d: float = Vector2(p.x - s["pos"].x, p.z - s["pos"].z).length()
			if d < t.saw_radius + m.radius():
				_hazard_hit(m, t.saw_drain * delta, s["pos"])
		for sp in _spikes:
			var pos: Vector3 = sp["pos"]
			var d: float = Vector2(p.x - pos.x, p.z - pos.z).length()
			if d < t.spike_radius + m.radius():
				# Impact speed matters — launching a rival in is the payoff.
				var mult: float = 1.0 + m.speed() * 0.08 * t.spike_impact_mult
				_hazard_hit(m, t.spike_drain * mult * delta, pos)


func _hazard_hit(m: Magnet, amount: float, at: Vector3) -> void:
	# Credit stays with whoever launched them in, if it was recent.
	var killer: Magnet = m.last_attacker
	# Low, steady tint rather than a per-frame full flash — you are standing in
	# a hazard, not being hit anew 60 times a second.
	if m.lose_mass(amount, killer, 0.35):
		return
	if m.is_player:
		Bus.shake.emit(t.shake_hit * 0.6)
		# Hazard damage is dealt per frame (the callers pass `amount * delta`), so an
		# unguarded buzz here fired sixty times a second for as long as the player
		# touched a saw. Platform.vibrate now rate-limits as a backstop, but standing
		# in a hazard should read as a slow grind rather than the fastest rattle that
		# backstop permits — and a haptic every 0.14s would also crowd out the
		# elimination thump, which is the one that actually means something.
		var now := float(Time.get_ticks_msec()) * 0.001
		if now - _hazard_vibe_at >= 0.5:
			_hazard_vibe_at = now
			Platform.vibrate(7, 0.18)
	if rng.randf() < 0.25:
		fx.floater(at + Vector3(0, 0.5, 0), "!", Color(1, 0.5, 0.2))


## The arena wall. Kept after the closing ring was removed: `ring_radius` is now a
## constant boundary, and something still has to stop a magnet that gets launched
## past the edge from travelling forever.
func _boundary_pressure(delta: float) -> void:
	for m in magnets:
		if not m.alive:
			continue
		var p := m.global_position
		var d := Vector2(p.x, p.z).length()
		var outside := d > ring_radius
		if m.is_player and outside != m.outside_ring:
			Bus.player_outside_ring.emit(outside)
		m.outside_ring = outside
		if not outside:
			continue
		# Launched clear of the ring at speed = eliminated on the spot. This is
		# the clip moment, so it needs a margin: triggering the instant kill the
		# frame you clip the boundary killed magnets who had every chance to
		# steer back, and read as arbitrary rather than spectacular.
		if d > ring_radius + t.launch_kill_margin and m.speed() > t.launch_kill_speed \
				and m.last_attacker != null:
			m.kill(m.last_attacker)
			continue
		m.lose_mass(t.outside_drain * delta, m.last_attacker, 0.0)

	if player != null and player.alive and player.outside_ring:
		_alarm_timer -= delta
		if _alarm_timer <= 0.0:
			_alarm_timer = 0.7
			Audio.play("alarm", 1.0, -14.0)


func _update_board(delta: float) -> void:
	_board_timer -= delta
	if _board_timer > 0.0:
		return
	_board_timer = 0.35
	var live: Array[Magnet] = []
	for m in magnets:
		if m.alive:
			live.append(m)
	live.sort_custom(func(a: Magnet, b: Magnet) -> bool: return a.mass > b.mass)
	var rows: Array = []
	for i in mini(10, live.size()):
		rows.append({
			"name": live[i].display_name,
			"mass": live[i].mass,
			"is_player": live[i].is_player,
			"rank": i + 1,
		})
	# One leader, recomputed on the same 0.35s tick as the board.
	for m in magnets:
		m.set_leader(not live.is_empty() and m == live[0])

	if player != null and player.alive:
		var rank := live.find(player) + 1
		if rank > 10:
			rows.append({"name": player.display_name, "mass": player.mass,
					"is_player": true, "rank": rank})
	Bus.leaderboard_changed.emit(rows)


# --- events ----------------------------------------------------------------
func _on_player_absorbed(pos: Vector3, amount: float) -> void:
	# Only worthwhile pickups spark. A sparkle on every 0.2-mass nut is noise.
	if fx == null or amount < 0.9:
		return
	fx.spark(pos + Vector3(0, 0.6, 0), Cosmetics.launch_color())


func _on_repelled(origin: Vector3, radius: float, strength: float, power: float, source: Magnet) -> void:
	scrap.repel(origin, radius, strength * 0.7)
	var launched := 0
	for m in magnets:
		if m == source or not m.alive:
			continue
		var to := m.global_position - origin
		to.y = 0.0
		var d := to.length()
		if d > radius or d < 0.001:
			continue
		var falloff := 1.0 - d / radius
		m.apply_impulse(to / d, strength * falloff, source)
		launched += 1

	if source.is_player:
		fx.shockwave(origin, radius * Cosmetics.launch_scale(), Cosmetics.launch_color(), power)
	else:
		fx.shockwave(origin, radius, source.tint_a.lerp(Color.WHITE, 0.4), power, 0.40)
	if source.is_player and launched > 0 and power >= t.clip_power_threshold:
		Bus.clip_moment.emit(origin)


func _on_eliminated(victim: Magnet, killer: Magnet) -> void:
	victim.placement = _placement_counter
	_placement_counter -= 1

	fx.burst(victim.global_position, victim.tint_a)
	# Was radius * 6.0 — a ring six times the width of the thing that died, which is
	# what "the halo is too much" is describing. An elimination should read as an
	# impact at the body, not as a shockwave across the arena.
	fx.shockwave(victim.global_position, victim.radius() * 2.6, victim.tint_a, 0.6)

	if killer != null and killer.alive:
		killer.kills += 1
		var bounty: float = maxf(victim.peak_mass, t.start_mass) * t.kill_bounty
		killer.gain_mass(bounty)
		if killer.is_player:
			fx.floater(victim.global_position, "+%d" % roundi(bounty), Color(0.5, 1.0, 0.6))

	var by_player := killer != null and killer.is_player
	if by_player:
		Bus.player_eliminated_rival.emit()
	Bus.magnet_eliminated.emit(victim.display_name,
			killer.display_name if killer != null else "", by_player)

	if by_player or victim.is_player:
		Audio.play("eliminate", 1.0, -4.0)
		Bus.shake.emit(t.shake_kill)
		# An elimination is the one moment that earns a real thump, but 45ms at 0.9
		# was a jolt rather than a beat.
		Platform.vibrate(22, 0.45)
		_hitstop()

	var alive := _alive_count()
	Bus.alive_count_changed.emit(alive)
	# Music tension tracks how empty the arena is, so it builds rather than
	# switching on all at once when sudden death triggers.
	Audio.set_intensity(clampf(1.0 - float(alive - 1) / maxf(1.0, magnets.size() - 1), 0.0, 1.0))

	if victim.is_player:
		# One revive per match, and only when an ad is genuinely available — the
		# offer must never appear and then fail to deliver.
		if not _revive_used and Config.flag("revive_enabled") and Ads.rewarded_available():
			state = State.AWAITING_REVIVE
			Bus.player_down.emit()
			return
		_finish()
		return
	if alive <= 1:
		_finish()
		return
	if alive <= t.sudden_death_at and state == State.PLAYING:
		state = State.SUDDEN_DEATH
		Bus.sudden_death_started.emit()


func _hitstop() -> void:
	if Game.profile.get("reduced_motion", false):
		return
	Engine.time_scale = t.hitstop_scale
	# Wall-clock deadline rather than `await` on a timer: an awaited coroutine
	# outlives the arena if the match ends mid-freeze, and leaks.
	_hitstop_until = Time.get_ticks_msec() + int(t.hitstop_time * 1000.0)


func _alive_count() -> int:
	var n := 0
	for m in magnets:
		if m.alive:
			n += 1
	return n


func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	state = State.FINISHED
	Engine.time_scale = 1.0
	Audio.set_hum(0.0)

	# Placement is meaningless once bots respawn — there is no fixed lobby to
	# place within. Rank among the living at the moment of death is still a useful
	# thing to show, so it is kept, but the SCORE is peak mass and survival time.
	var live: Array[Magnet] = []
	for m in magnets:
		if m.alive:
			live.append(m)
	live.sort_custom(func(a: Magnet, b: Magnet) -> bool: return a.mass > b.mass)
	for i in live.size():
		live[i].placement = i + 1

	var peak: float = player.peak_mass if player != null else 0.0
	var result := {
		"placement": player.placement if player != null else 99,
		# Peak, not final: you are at your smallest the instant you die, and
		# scoring that punishes the player for the last second of a good run.
		"mass": peak,
		"peak_mass": peak,
		"kills": player.kills if player != null else 0,
		"survived": elapsed,
		"total": magnets.size(),
		# No round to win. "Won" now means outlasting the clock's own par.
		"won": elapsed >= t.match_duration,
	}
	Audio.play("win" if result["won"] else "lose", 1.0, -3.0)
	Bus.match_ended.emit(Game.record_match(result))


# --- quality scaler --------------------------------------------------------
func _update_quality(delta: float) -> void:
	if Game.profile.get("quality", "auto") != "auto":
		return
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum < 2.0:
		return
	var fps := _fps_frames / _fps_accum
	_fps_accum = 0.0
	_fps_frames = 0
	# ponytail: one dial, moved slowly. Real per-feature tiers only pay off once
	# there is a device matrix to tune against.
	if fps < 45.0:
		_quality = maxf(0.25, _quality - 0.25)
	elif fps > 57.0 and _quality < 1.0:
		_quality = minf(1.0, _quality + 0.25)
	fx.quality = _quality
	get_viewport().scaling_3d_scale = lerpf(0.7, 1.0, _quality)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Bot names for the active language, falling back to English. Loaded per match
## rather than cached: a locale change rebuilds the UI and the next match should
## follow it.
func _bot_name_pool() -> Array:
	var f := FileAccess.get_file_as_string("res://data/bot_names.json")
	if f != "":
		var parsed: Variant = JSON.parse_string(f)
		if parsed is Dictionary:
			var pools: Dictionary = (parsed as Dictionary).get("pools", {})
			var code := String(Game.get_value("locale", "en"))
			for key in [code, code.split("_")[0]]:
				if pools.has(key) and (pools[key] as Array).size() >= 8:
					return (pools[key] as Array).duplicate()
	return BOT_NAMES.duplicate()


## Turns a base pool into `count` distinct handles that look like a real lobby.
##
## A fixed list gives itself away in two matches — the same fourteen names in a
## different order. Roughly half the names get gamertag decoration and half stay
## plain, because an all-decorated lobby reads as fake exactly as fast as an
## all-plain one. Decoration is language-neutral on purpose: xX_ and 1337 look the
## same in every locale a real player would use them in.
func _bot_names(count: int) -> Array:
	var base := _bot_name_pool()
	# Fisher-Yates through THIS arena's rng. Array.shuffle() draws from Godot's
	# global RNG, so the same seed produced a different name order, a different
	# number of dedupe retries below, and therefore a different spawn layout —
	# §4.14 determinism silently broken. Latent until the lobby grew: at 23 names
	# out of a 60-name pool collisions were rare enough that the retry count
	# usually matched by luck.
	for i in range(base.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap: Variant = base[i]
		base[i] = base[j]
		base[j] = swap
	var decor := _bot_decor()
	var prefixes: Array = decor.get("prefixes", [])
	var suffixes: Array = decor.get("suffixes", [])
	var numbers: Array = decor.get("numbers", [])
	var leet: Dictionary = decor.get("leet", {})

	var out: Array = []
	var used := {}
	var guard := 0
	while out.size() < count and guard < count * 40:
		guard += 1
		var name := String(base[rng.randi() % base.size()])
		var roll := rng.randf()
		if roll < 0.22 and not numbers.is_empty():
			name += String(numbers[rng.randi() % numbers.size()])
		elif roll < 0.36 and not prefixes.is_empty():
			name = String(prefixes[rng.randi() % prefixes.size()]) + name
		elif roll < 0.46 and not suffixes.is_empty():
			name += String(suffixes[rng.randi() % suffixes.size()])
		elif roll < 0.54 and not leet.is_empty():
			var swapped := ""
			for ch in name:
				var lower := ch.to_lower()
				swapped += String(leet[lower]) if leet.has(lower) and rng.randf() < 0.6 else ch
			name = swapped
		if used.has(name):
			continue
		used[name] = true
		out.append(name)
	# Guard exhausted (a tiny pool): fall back to numbering so a match still starts.
	while out.size() < count:
		out.append("Magnet%d" % (out.size() + 1))
	return out


func _bot_decor() -> Dictionary:
	var f := FileAccess.get_file_as_string("res://data/bot_names.json")
	if f != "":
		var parsed: Variant = JSON.parse_string(f)
		if parsed is Dictionary:
			return (parsed as Dictionary).get("decor", {})
	return {}


## Accepted the revive. Placed at the ring centre with a fraction of peak mass:
## far enough from anything to be survivable, small enough that dying was still a
## real loss.
func revive_player() -> void:
	if player == null or state != State.AWAITING_REVIVE:
		return
	_revive_used = true
	var give: float = maxf(t.start_mass, player.peak_mass * Config.num("revive.mass_fraction", 0.45))
	player.revive(_open_spot(), give)
	state = State.PLAYING
	Bus.alive_count_changed.emit(_alive_count())
	Audio.play("size_up", 1.0, -4.0)
	fx.shockwave(player.global_position, player.radius() * 2.2,
			player.tint_a, 0.6)
	Analytics.track("revive_used", {"mass": give})


## Declined, or the offer timed out. The match ends exactly as it would have.
func decline_revive() -> void:
	if state != State.AWAITING_REVIVE:
		return
	_finish()


## Somewhere inside the ring that is not on top of a hazard or another magnet.
func _open_spot() -> Vector3:
	var best := Vector3.ZERO
	var best_clear := -1.0
	for attempt in 24:
		var a := rng.randf() * TAU
		var r: float = ring_radius * 0.55 * sqrt(rng.randf())
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var clear := INF
		# Distance to the nearest live magnet AND the nearest hazard.
		for m in magnets:
			if m.alive:
				clear = minf(clear, p.distance_to(m.global_position))
		for h in _hazard_nodes:
			if is_instance_valid(h) and h is Node3D:
				clear = minf(clear, p.distance_to((h as Node3D).global_position))
		if clear > best_clear:
			best_clear = clear
			best = p
		if clear > 14.0:
			break
	return best
