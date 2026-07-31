class_name Powerups
extends Node3D
## Pickups and the timed buffs they grant.
##
## Same shape as the scrap field: flat arrays, no per-pickup nodes, one visual
## per slot. Buffs live on the magnet as a small dictionary so bots benefit from
## them exactly as the player does — a pickup a bot cannot use is set dressing.

enum Kind { SURGE, SPEED, SHIELD, MEGA_REPEL, FREEZE }

const COLORS := {
	Kind.SURGE: Color("#4d90a8"),
	Kind.SPEED: Color("#7fa653"),
	Kind.SHIELD: Color("#c9a227"),
	Kind.MEGA_REPEL: Color("#b5543f"),
	Kind.FREEZE: Color("#8fa8bb"),
}

var t: Tuning

var _pos: PackedVector3Array
var _kind: PackedInt32Array
var _respawn: PackedFloat32Array
var _nodes: Array[Node3D] = []
var _field_radius := 40.0
var _spin := 0.0


func setup(tuning: Tuning, field_radius: float) -> void:
	t = tuning
	_field_radius = field_radius
	var count := t.powerup_count
	_pos.resize(count)
	_kind.resize(count)
	_respawn.resize(count)
	for i in count:
		_nodes.append(_make_node())
		_spawn(i)


func _make_node() -> Node3D:
	var root := Node3D.new()
	add_child(root)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	box.material = mat
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	root.set_meta("mesh", mesh)

	# Ground marker, so a pickup reads from a distance at a top-down angle.
	var marker := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	var mm := ShaderMaterial.new()
	mm.shader = load("res://shaders/hazard_decal.gdshader")
	mm.set_shader_parameter("stripe_scale", 9.0)
	# An annulus, not a filled disc. Filled, five of these overlapping near each
	# other merged into one unreadable smear of colour across a third of the
	# screen; a pad marks the spot without claiming the ground.
	mm.set_shader_parameter("inner", 0.60)
	mm.set_shader_parameter("strength", 0.7)
	marker.mesh = pm
	marker.material_override = mm
	marker.position.y = 0.04
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marker)
	root.set_meta("marker", mm)
	return root


func _spawn(i: int) -> void:
	var r: float = _field_radius * randf_range(0.15, 0.8) * sqrt(randf())
	var a := randf() * TAU
	_pos[i] = Vector3(cos(a) * r, 0.7, sin(a) * r)
	_kind[i] = randi() % Kind.size()
	_respawn[i] = 0.0
	_paint(i)


func _paint(i: int) -> void:
	var node := _nodes[i]
	var color: Color = COLORS[_kind[i]]
	var mesh: MeshInstance3D = node.get_meta("mesh")
	var mat := (mesh.mesh as BoxMesh).material as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = color
	var marker: ShaderMaterial = node.get_meta("marker")
	marker.set_shader_parameter("paint", color)
	node.scale = Vector3(t.powerup_radius, t.powerup_radius, t.powerup_radius)


## Pickup checks plus buff expiry, in one pass over a handful of items.
func step(delta: float, magnets: Array, ring_radius: float) -> void:
	_spin += delta * 1.8
	for i in _pos.size():
		var node := _nodes[i]
		if _respawn[i] > 0.0:
			_respawn[i] -= delta
			node.visible = false
			if _respawn[i] <= 0.0:
				_spawn(i)
				node.visible = true
			continue

		# A pickup stranded outside the shrinking ring is unreachable; move it.
		if Vector2(_pos[i].x, _pos[i].z).length() > ring_radius * 0.92:
			_spawn(i)

		node.position = _pos[i] + Vector3(0, sin(_spin + i) * 0.18, 0)
		node.rotation.y = _spin
		node.visible = true

		for m: Magnet in magnets:
			if not m.alive:
				continue
			var d := Vector2(m.global_position.x - _pos[i].x,
					m.global_position.z - _pos[i].z).length()
			if d > t.powerup_radius + m.radius():
				continue
			_apply(m, _kind[i], magnets)
			_respawn[i] = t.powerup_respawn
			node.visible = false
			break


func _apply(m: Magnet, kind: int, magnets: Array) -> void:
	var color: Color = COLORS[kind]
	if kind == Kind.FREEZE:
		# Freeze hits everyone ELSE in range — the only pickup that is offensive
		# rather than self-buffing, which is why it reads as the best one.
		for other: Magnet in magnets:
			if other == m or not other.alive:
				continue
			if other.global_position.distance_to(m.global_position) < m.pull_radius() * 1.6:
				other.freeze(t.freeze_seconds)
	else:
		m.grant_buff(kind, t.powerup_duration)

	if m.is_player:
		Audio.play("size_up", 1.2, -6.0)
		Platform.vibrate(10, 0.25)
		Bus.powerup_taken.emit(kind, t.powerup_duration, color)
