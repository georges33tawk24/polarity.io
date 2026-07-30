class_name Magnet
extends CharacterBody3D
## A magnet — player or bot. Identical physics and abilities either way; the
## only difference is who writes `move_dir` / `holding` each frame.

const BODY_Y := 0.4

signal repelled(origin: Vector3, radius: float, strength: float, power: float)
signal eliminated(magnet: Magnet, killer: Magnet)

var t: Tuning
var display_name := "MAGNET"
var tint_a := Color(1.0, 0.23, 0.34)
var tint_b := Color(0.25, 0.49, 1.0)
var is_player := false
var brain: BotBrain = null
var alive := true

## Intent, written every frame by input or by the bot brain.
var move_dir := Vector2.ZERO
var holding := false

var mass := 10.0: set = _set_mass
## Highest mass ever reached. Kill bounties pay off this, not `mass` — a victim
## is always at min_mass when they die, so remaining mass is a useless measure
## of what they were worth.
var peak_mass := 10.0
var charge := 0.0
var cooldown := 0.0
var bite_timer := 0.0
var kills := 0
var outside_ring := false
## The arena's current biggest. Spec §3.3 asked for this and it was never built —
## in a game whose whole tension is "who can eat me", the answer was only ever
## available by reading a leaderboard in the corner.
var is_leader := false
## Who last hit us, and for how long they still get the credit. Without this,
## launching someone into the death zone would award the kill to nobody.
var last_attacker: Magnet = null
var attacker_timer := 0.0
var placement := 0

var _radius := 1.0
var _pull_radius := 5.0
var _was_holding := false
var _squash := 0.0
var _hurt := 0.0
var _charge_pinged := false
var _skin_emission := 0.0
var _trail: GPUParticles3D = null
## kind -> seconds remaining. Bots use these too; a pickup a bot cannot use is
## set dressing rather than a mechanic.
var buffs: Dictionary = {}
var frozen := 0.0
## Set by a reverse-polarity zone: attract becomes repel and vice versa.
var inverted := false

var _shape: CollisionShape3D
var _sphere: SphereShape3D
var _body: MeshInstance3D
var _aura: MeshInstance3D
var _body_mat: ShaderMaterial
var _aura_mat: ShaderMaterial
var _field_strength := 0.0
var _field_sweep := 0.0
var _label: Label3D
var _shadow: MeshInstance3D


func configure(tuning: Tuning, n: String, a: Color, b: Color, player := false) -> void:
	t = tuning
	display_name = n
	tint_a = a
	tint_b = b
	is_player = player
	_build()
	_set_mass(t.start_mass)


func _build() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 1

	_sphere = SphereShape3D.new()
	_shape = CollisionShape3D.new()
	_shape.shape = _sphere
	add_child(_shape)

	# Authored magnet.glb if tools/blender_export.py has been run, generated
	# horseshoe otherwise. Either way the silhouette says "magnet" from overhead,
	# which the original cylinder never did (spec §13A).
	var cyl := AssetLibrary.mesh("magnet", func() -> Mesh: return Meshes.horseshoe())
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = load("res://shaders/magnet.gdshader")
	if is_player:
		# The equipped skin only ever retints; pole legibility is preserved
		# because the shader always splits on model-space X (spec §13A).
		var colors := Cosmetics.skin_colors()
		tint_a = colors[0]
		tint_b = colors[1]
		_skin_emission = colors[2]
	_body_mat.set_shader_parameter("pole_a", tint_a)
	_body_mat.set_shader_parameter("pole_b", tint_b)
	_body = MeshInstance3D.new()
	_body.mesh = cyl
	_body.material_override = _body_mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)

	# Only the player gets a field. Every magnet used to draw a hard ring at its
	# pull radius; with fifteen of them the floor was a mess of overlapping circles
	# and the rings read as selection gizmos rather than as anything physical.
	# Rivals are read by body size and by the minimap, which is enough.
	if is_player:
		var plane := PlaneMesh.new()
		plane.size = Vector2(2.0, 2.0)
		_aura_mat = ShaderMaterial.new()
		_aura_mat.shader = load("res://shaders/field.gdshader")
		_aura_mat.set_shader_parameter("tint", Color(0.98, 0.86, 0.52))
		_aura = MeshInstance3D.new()
		_aura.mesh = plane
		_aura.material_override = _aura_mat
		_aura.position.y = -BODY_Y + 0.03
		_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_aura)

	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	# fixed_size keeps labels at a constant screen size, so these are effectively
	# UI pixels — big enough to read over the arena, small enough not to own it.
	_label.pixel_size = 0.0005
	_label.font_size = 68 if is_player else 52
	_label.outline_size = 20
	if is_player:
		var plate := Cosmetics.nameplate_colors()
		_label.modulate = plate[0]
		_label.outline_modulate = plate[1]
	else:
		_label.modulate = Color(1, 1, 1, 0.45)
	add_child(_label)

	# Blob shadow. Everything floated without one.
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = load("res://shaders/blob_shadow.gdshader")
	shadow_mat.set_shader_parameter("strength", 0.22)
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(2.0, 2.0)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = shadow_plane
	_shadow.material_override = shadow_mat
	_shadow.position.y = -BODY_Y + 0.02
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	position.y = BODY_Y
	if is_player:
		_build_trail()


## Equipped trail. Emission rate is driven by speed in _update_visuals so a
## stationary magnet does not sit in a puddle of its own particles.
func _build_trail() -> void:
	var cfg := Cosmetics.trail_config()
	if not bool(cfg.get("enabled", false)):
		return
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0, 1.2, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.damping_min = 1.0
	mat.damping_max = 2.0

	var mesh := QuadMesh.new()
	var size := float(cfg.get("size", 0.2))
	mesh.size = Vector2(size, size)
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mmat.albedo_color = Color(String(cfg.get("color", "#ffffff")))
	mesh.material = mmat

	_trail = GPUParticles3D.new()
	_trail.amount = int(cfg.get("amount", 24))
	_trail.lifetime = 0.7
	_trail.local_coords = false
	_trail.process_material = mat
	_trail.draw_pass_1 = mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.emitting = false
	add_child(_trail)


func _set_mass(v: float) -> void:
	mass = maxf(v, 0.0)
	peak_mass = maxf(peak_mass, mass)
	if t == null:
		return
	_radius = t.radius_for(mass)
	_pull_radius = t.pull_radius_for(mass)
	_sphere.radius = _radius
	if _aura != null:
		_aura.scale = Vector3(_pull_radius, 1.0, _pull_radius)
	_label.position.y = _radius * 0.5 + 1.5
	if is_player:
		Bus.player_mass_changed.emit(mass)


func radius() -> float: return _radius


## Reach, including the surge buff. Every magnetism call site uses this rather
## than the raw field so buffs apply consistently.
func pull_radius() -> float:
	return _pull_radius * (1.35 if has_buff(Powerups.Kind.SURGE) else 1.0)


func pull_strength_mult() -> float:
	return t.surge_pull_mult if has_buff(Powerups.Kind.SURGE) else 1.0


func has_buff(kind: int) -> bool:
	return buffs.has(kind)


func grant_buff(kind: int, seconds: float) -> void:
	buffs[kind] = maxf(float(buffs.get(kind, 0.0)), seconds)


func freeze(seconds: float) -> void:
	if has_buff(Powerups.Kind.SHIELD):
		return
	frozen = maxf(frozen, seconds)
	_hurt = maxf(_hurt, 0.4)


func _physics_process(delta: float) -> void:
	if not alive:
		return

	cooldown = maxf(0.0, cooldown - delta)
	bite_timer = maxf(0.0, bite_timer - delta)
	frozen = maxf(0.0, frozen - delta)
	for kind: int in buffs.keys():
		buffs[kind] -= delta
		if buffs[kind] <= 0.0:
			buffs.erase(kind)
	attacker_timer = maxf(0.0, attacker_timer - delta)
	if attacker_timer <= 0.0:
		last_attacker = null
	_squash = move_toward(_squash, 0.0, delta * 4.0)
	_hurt = move_toward(_hurt, 0.0, delta * 9.0)

	# --- charge / release ---------------------------------------------------
	# A reverse-polarity zone swaps the verb: holding pushes, releasing pulls.
	var effective_hold := (not holding) if inverted else holding
	if effective_hold and cooldown <= 0.0:
		charge = minf(charge + delta, t.repel_charge_time)
		if not _charge_pinged and charge >= t.repel_charge_time:
			_charge_pinged = true
			if is_player:
				Audio.play("charge_ready", 1.0, -8.0)
	elif not effective_hold:
		if _was_holding and cooldown <= 0.0:
			fire_repel()
		charge = 0.0
		_charge_pinged = false
	_was_holding = effective_hold

	# --- movement -----------------------------------------------------------
	var speed := t.speed_for(mass) * (t.speed_mult if has_buff(Powerups.Kind.SPEED) else 1.0)
	if frozen > 0.0:
		speed = 0.0
	var target := Vector3(move_dir.x, 0.0, move_dir.y) * speed
	if move_dir.length_squared() > 0.001:
		velocity = velocity.move_toward(target, t.accel * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, t.drag * delta * 2.0)
	velocity.y = 0.0
	# Clamped here rather than in apply_impulse: several repels can land in one
	# frame, and each is individually reasonable.
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > t.max_launch_speed:
		flat = flat.normalized() * t.max_launch_speed
		velocity.x = flat.x
		velocity.z = flat.y
	move_and_slide()
	position.y = BODY_Y

	_update_visuals(delta)


## Marks the arena's biggest magnet. The nameplate turns brass and gains a crown,
## which is readable in the corner of your eye — the leaderboard is not.
func set_leader(v: bool) -> void:
	if v == is_leader:
		return
	is_leader = v
	if _label == null or not is_instance_valid(_label):
		return
	if v:
		_label.text = "\u2654 " + display_name
		_label.modulate = Color(0.851, 0.631, 0.235)
		_label.outline_modulate = Color(0.055, 0.051, 0.043, 0.95)
	else:
		_label.text = display_name
		if is_player:
			var plate := Cosmetics.nameplate_colors()
			_label.modulate = plate[0]
			_label.outline_modulate = plate[1]
		else:
			_label.modulate = Color(1, 1, 1, 0.45)


func _update_visuals(delta: float) -> void:
	var charge01 := charge / t.repel_charge_time if t.repel_charge_time > 0.0 else 0.0
	var ready := cooldown <= 0.0
	_body_mat.set_shader_parameter("charge", charge01 if ready else 0.0)
	_body_mat.set_shader_parameter("hurt", _hurt)
	_body_mat.set_shader_parameter("skin_glow", _skin_emission)
	if _trail != null:
		_trail.emitting = speed() > 2.5
	if _aura_mat != null:
		# Visible only while you are actually pulling, and it tightens as you charge.
		# A field that is always on is furniture; one that appears on input is
		# feedback.
		# Halved. Between this and the elimination ring the player was surrounded by
		# soft light whenever anything happened.
		var want: float = (0.16 + charge01 * 0.18) if (holding and ready) else 0.0
		_field_strength = lerpf(_field_strength, want, delta * 9.0)
		_field_sweep += delta * (2.4 + charge01 * 7.0)
		_aura_mat.set_shader_parameter("strength", _field_strength)
		_aura_mat.set_shader_parameter("sweep", _field_sweep)

	# Squash on absorb, stretch along travel when moving fast.
	var stretch := 1.0 + _squash
	_body.scale = Vector3(_radius * stretch, _radius * (1.0 - _squash * 0.6), _radius * stretch)
	if _shadow != null:
		# Slightly wider than the body and offset along the light direction, so
		# it reads as cast rather than painted on.
		_shadow.scale = Vector3(_radius * 1.35, 1.0, _radius * 1.35)
		_shadow.position.x = _radius * 0.12
		_shadow.position.z = _radius * 0.18
	# Lean into the direction of travel — cheap, and it sells the weight.
	var lean := Vector3(velocity.z, 0.0, -velocity.x) * 0.012
	_body.rotation.x = lerpf(_body.rotation.x, lean.x, delta * 8.0)
	_body.rotation.z = lerpf(_body.rotation.z, lean.z, delta * 8.0)

	if is_player:
		Bus.player_charge_changed.emit(charge01, ready)


## Release burst. Strength scales with mass and how long you held.
func fire_repel() -> void:
	var power: float = clampf(charge / maxf(t.repel_charge_time, 0.01), t.repel_min_power, 1.0)
	var strength := t.repel_impulse * power * sqrt(mass / t.start_mass)
	if has_buff(Powerups.Kind.MEGA_REPEL):
		strength *= t.mega_repel_mult
	cooldown = t.repel_cooldown
	charge = 0.0
	_squash = -0.28
	repelled.emit(global_position, _pull_radius, strength, power)
	if is_player:
		Audio.play("launch", 1.0 + (1.0 - power) * 0.25, -3.0)
		Platform.vibrate(28, 0.5 + power * 0.5)
		Bus.repel_fired.emit(global_position, _pull_radius, power)
		Bus.shake.emit(t.shake_launch * power)


func gain_mass(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	var before := mass
	_set_mass(mass + amount)
	_squash = minf(0.34, _squash + amount * 0.05)
	if is_player:
		Bus.player_absorbed.emit(global_position, amount)
		Audio.play("absorb" if amount < 4.0 else "absorb_big",
				1.0 + clampf(amount * 0.04, 0.0, 0.4), -12.0 if amount < 4.0 else -4.0)
		Platform.vibrate(10, 0.25)
		# Milestone every doubling — the snowball needs a drumbeat.
		if floori(log(before / t.start_mass) / log(2.0)) < floori(log(mass / t.start_mass) / log(2.0)):
			Audio.play("size_up", 1.0, -4.0)


## Returns true if this killed them.
## `flash` is the hurt-tint strength, NOT a boolean: continuous drains call this
## every frame, and a full flash per frame pinned _hurt at 1.0 forever, turning
## every magnet in a melee into an unreadable white blob.
func lose_mass(amount: float, killer: Magnet = null, flash := 1.0) -> bool:
	if not alive or amount <= 0.0:
		return false
	# Shield absorbs damage outright — the defensive pickup has to actually
	# defend, or nobody picks it up.
	if has_buff(Powerups.Kind.SHIELD):
		_hurt = maxf(_hurt, 0.25)
		return false
	_hurt = maxf(_hurt, flash)
	_set_mass(mass - amount)
	if mass <= t.min_mass:
		kill(killer)
		return true
	return false


func kill(killer: Magnet = null) -> void:
	if not alive:
		return
	alive = false
	visible = false
	set_physics_process(false)
	# Stop colliding immediately — a corpse must not block the fight.
	collision_layer = 0
	collision_mask = 0
	eliminated.emit(self, killer)


## Brings a dead magnet back. Only the player is ever revived (§4.4 rewarded
## placement) — bots die for good, because a bot that came back would make the
## leaderboard lie about what happened.
func revive(at: Vector3, with_mass: float) -> void:
	if alive:
		return
	alive = true
	visible = true
	set_physics_process(true)
	collision_layer = 1
	collision_mask = 1
	global_position = at
	velocity = Vector3.ZERO
	charge = 0.0
	cooldown = 0.0
	frozen = 0.0
	_hurt = 0.0
	outside_ring = false
	placement = 0
	_set_mass(with_mass)
	# Brief invulnerability is not modelled; instead the caller places the magnet in
	# open space, which is cheaper and cannot be gamed by standing in a saw.


func apply_impulse(dir: Vector3, strength: float, source: Magnet = null) -> void:
	# Divide by mass: a heavy magnet shrugs off a hit that would launch a light one.
	velocity += dir * strength / maxf(mass / t.start_mass, 0.35)
	_hurt = maxf(_hurt, 0.45)
	if source != null and source != self:
		last_attacker = source
		attacker_timer = 3.5


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## What the arena's magnetism pass should treat as "attracting".
func is_attracting() -> bool:
	return alive and ((not holding) if inverted else holding) and frozen <= 0.0
