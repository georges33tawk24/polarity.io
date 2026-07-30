class_name ScrapField
extends Node3D
## Every piece of scrap in the arena, as flat arrays driven into one MultiMesh.
##
## ponytail: no scrap scene, no RigidBody, no object pool. 400+ physics nodes
## would not hold 60fps on a mid-range phone, and none of them need collision
## against anything except a magnet — which is one distance check.

var t: Tuning

var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _mass: PackedFloat32Array
var _spin: PackedFloat32Array
var _spin_speed: PackedFloat32Array
var _respawn: PackedFloat32Array   # > 0 means dead and counting down
var _count := 0
var _field_radius := 40.0
var _meshes: Array[MultiMesh] = []
var _shape_of: PackedInt32Array
var _slot_of: PackedInt32Array
var _shadow_mm: MultiMesh
## Half the diagonal of the nut mesh (radius 0.55, height 0.34), so a tumbling
## piece never clips the ground at any rotation.
const NUT_HALF_DIAGONAL := 0.33

## Real fastener finishes, kept dark enough to sit under the magnets rather than
## competing with them. Nuts are the most numerous object on screen by an order of
## magnitude, so their value is what sets the whole scene's brightness.
## Sun 1.0 + fill 0.45 + ambient 0.85 is about 2.3x, so anything above ~0.43 albedo
## CLIPS TO WHITE on an upward face — and a clipped face has no shading and no hue
## left, which is exactly why these read as plastic rather than metal. Measured a
## sample at (209,201,192) before this change. Held under the clip point so the
## facets actually shade.
## Measured, not guessed: a lit nut face read 209/255 at the old value and 173 at
## the first correction. These land it near 140, which is where a nut reads as a
## piece of steel next to the plate floor instead of as a paper cutout on top of it.
const METALS: Array[Color] = [
	Color(0.24, 0.26, 0.28),   # galvanised zinc
	Color(0.17, 0.18, 0.19),   # blued steel
	Color(0.28, 0.27, 0.25),   # bright mild steel
]
const BRASS := Color(0.32, 0.24, 0.11)
## Broad-phase grid, rebuilt every frame. Cell is comfortably larger than a typical
## pull radius so a magnet touches only a handful of cells.
const CELL := 8.0
var _grid: Dictionary = {}
var _absorbed: PackedInt32Array


func setup(tuning: Tuning, field_radius: float) -> void:
	t = tuning
	_count = t.scrap_count
	_field_radius = field_radius

	# One MultiMesh per shape, and there is only one shape. Nuts only. A mixed bag of bolts/gears/shards read as generic debris; one
	# repeated, instantly recognisable object is both clearer and more .io — the
	# collectible should be a single icon you learn in one glance.
	var shapes: Array[Mesh] = [
		AssetLibrary.mesh("scrap_nut", func() -> Mesh: return Meshes.nut()),
	]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Low metallic on purpose. There is no reflection probe or sky, so a high
	# metallic value has nothing to reflect and just renders the scrap black —
	# the opposite of the "gameplay objects pop" rule in §13A. Rim-lit look comes
	# from a faint emission instead.
	mat.metallic = 0.0
	# Raised with the darker albedo: at 0.62 the specular lobe was tight enough to
	# blow out on its own, which put the white back on top faces.
	mat.roughness = 0.74
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.emission_enabled = true
	mat.emission_enabled = false
	# Deliberately NOT toon-shaded, unlike the magnets. Toon banding plus a rim
	# on a 0.5-unit piece blew every scrap to flat white — at this size there is
	# no room for a band, so the ramp just clips. Lambert keeps the metallic
	# grey-to-brass read that encodes mass value.

	_shape_of.resize(_count)
	var per_shape: Array[int] = []
	for i in shapes.size():
		per_shape.append(0)
	for i in _count:
		_shape_of[i] = i % shapes.size()
		per_shape[_shape_of[i]] += 1

	for si in shapes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		# Generated meshes need the shared material; an authored .glb brings its
		# own from the Blender material library, so leave it alone.
		if shapes[si].get_surface_count() > 0 and shapes[si].surface_get_material(0) == null:
			shapes[si].surface_set_material(0, mat)
		mm.mesh = shapes[si]
		mm.instance_count = per_shape[si]
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
		_meshes.append(mm)

	# One shared blob-shadow MultiMesh for the whole field: 420 pieces grounded
	# for a single extra draw call.
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(1.0, 1.0)
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = load("res://shaders/blob_shadow.gdshader")
	shadow_mat.set_shader_parameter("strength", 0.34)
	shadow_mesh.material = shadow_mat
	_shadow_mm = MultiMesh.new()
	_shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_shadow_mm.mesh = shadow_mesh
	_shadow_mm.instance_count = _count
	var shadow_inst := MultiMeshInstance3D.new()
	shadow_inst.multimesh = _shadow_mm
	shadow_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow_inst)

	# Per-scrap slot inside its own MultiMesh.
	var cursor: Array[int] = []
	for i in shapes.size():
		cursor.append(0)
	_slot_of.resize(_count)
	for i in _count:
		_slot_of[i] = cursor[_shape_of[i]]
		cursor[_shape_of[i]] += 1

	_pos.resize(_count)
	_vel.resize(_count)
	_mass.resize(_count)
	_spin.resize(_count)
	_spin_speed.resize(_count)
	_respawn.resize(_count)
	for i in _count:
		_spawn(i)


func _spawn(i: int) -> void:
	var r: float = _field_radius * sqrt(randf())      # sqrt = uniform over the disc
	var a := randf() * TAU
	# Y is set per-instance in _write_instance from the piece's own scale.
	_pos[i] = Vector3(cos(a) * r, 0.0, sin(a) * r)
	_vel[i] = Vector3.ZERO
	_mass[i] = randf_range(t.scrap_mass_min, t.scrap_mass_max)
	_spin[i] = randf() * TAU
	_spin_speed[i] = randf_range(-2.2, 2.2)
	_respawn[i] = 0.0
	# Always write the transform. Skipping it on the initial spawn left every
	# instance on MultiMesh's default identity transform — 420 pieces stacked at
	# the world origin, and an empty arena — until the first step() after the
	# countdown.
	_write_instance(i)


## Advance the whole field. Magnet state is passed in as flat arrays so the hot
## loop never touches a node property.
## Returns mass absorbed per magnet, indexed the same as the inputs.
##
## Broad-phase: live scrap is bucketed into a uniform grid each frame and each
## magnet only tests the cells its reach actually covers (spec §8). The previous
## version compared every piece against every magnet — 420 x 15 = 6.3k tests a
## frame, which was affordable but scaled as O(n*m) and capped how far scrap and
## bot counts could go.
func step(delta: float, mpos: PackedVector3Array, mmass: PackedFloat32Array,
		mrad: PackedFloat32Array, mpull: PackedFloat32Array,
		mhold: PackedByteArray, ring_radius: float) -> PackedFloat32Array:
	var gained := PackedFloat32Array()
	var mcount := mpos.size()
	gained.resize(mcount)

	# --- respawn timers ----------------------------------------------------
	for i in _count:
		if _respawn[i] > 0.0:
			_respawn[i] -= delta
			if _respawn[i] <= 0.0:
				_spawn(i)

	# --- broad phase: bucket live scrap ------------------------------------
	_grid.clear()
	for i in _count:
		if _respawn[i] > 0.0:
			continue
		var key := _cell_key(_pos[i].x, _pos[i].z)
		# Plain Array, NOT PackedInt32Array: packed arrays are value types, so
		# `_grid[key].append(i)` writes to a temporary copy and the cell keeps
		# only its first entry. Silent, and it would have made the broad phase
		# miss almost every piece.
		if _grid.has(key):
			var bucket: Array = _grid[key]
			bucket.append(i)
		else:
			_grid[key] = [i]

	if _absorbed.size() != _count:
		_absorbed.resize(_count)
	for i in _count:
		_absorbed[i] = -1

	# --- magnets pull and absorb nearby scrap ------------------------------
	for m in mcount:
		if mrad[m] < 0.0:
			continue                      # dead magnet
		var holding := mhold[m] != 0
		var touch := mrad[m]
		var pull := mpull[m] if holding else 0.0
		var reach: float = maxf(touch, pull)
		if reach <= 0.0:
			continue

		var mp := mpos[m]
		var cx0 := int(floor((mp.x - reach) / CELL))
		var cx1 := int(floor((mp.x + reach) / CELL))
		var cz0 := int(floor((mp.z - reach) / CELL))
		var cz1 := int(floor((mp.z + reach) / CELL))
		var touch_sq := touch * touch
		var pull_sq := pull * pull
		var force_mass := mmass[m]

		for cx in range(cx0, cx1 + 1):
			for cz in range(cz0, cz1 + 1):
				var key := (cx + 4096) * 8192 + (cz + 4096)
				if not _grid.has(key):
					continue
				var bucket: Array = _grid[key]
				for i: int in bucket:
					if _absorbed[i] >= 0:
						continue
					var p := _pos[i]
					var dx := mp.x - p.x
					var dz := mp.z - p.z
					var d_sq := dx * dx + dz * dz
					if d_sq < touch_sq:
						_absorbed[i] = m
						gained[m] += _mass[i]
						continue
					if not holding or d_sq > pull_sq:
						continue
					var d: float = sqrt(d_sq)
					var f := t.pull_force(force_mass, d) * delta
					var v := _vel[i]
					v.x += dx / d * f
					v.z += dz / d * f
					_vel[i] = v

	# --- integrate ---------------------------------------------------------
	var drag_mul: float = maxf(0.0, 1.0 - t.scrap_drag * delta)
	var max_speed := t.scrap_max_speed
	var ring_sq := ring_radius * ring_radius

	for i in _count:
		if _respawn[i] > 0.0:
			continue
		if _absorbed[i] >= 0:
			_respawn[i] = t.scrap_respawn_time
			_hide_instance(i)
			continue

		var p := _pos[i]
		var v := _vel[i]
		v.x *= drag_mul
		v.z *= drag_mul
		var speed_sq := v.x * v.x + v.z * v.z
		if speed_sq > max_speed * max_speed:
			var sc: float = max_speed / sqrt(speed_sq)
			v.x *= sc
			v.z *= sc
		p.x += v.x * delta
		p.z += v.z * delta

		# Scrap flung outside the ring is gone — keeps the food where the fight is.
		if p.x * p.x + p.z * p.z > ring_sq:
			_respawn[i] = t.scrap_respawn_time * 0.5
			_hide_instance(i)
			continue

		_pos[i] = p
		_vel[i] = v
		_spin[i] += _spin_speed[i] * delta
		_write_instance(i)

	return gained


## Grid cell key. Offset by 4096 cells so negative coordinates stay positive;
## at CELL = 8 that covers +/-32k units, far past any arena.
func _cell_key(x: float, z: float) -> int:
	return (int(floor(x / CELL)) + 4096) * 8192 + (int(floor(z / CELL)) + 4096)


func _write_instance(i: int) -> void:
	var s: float = 0.7 + _mass[i] * 0.55
	var basis := Basis(Vector3.UP, _spin[i]) * Basis(Vector3.RIGHT, _spin[i] * 0.6)
	var mm := _meshes[_shape_of[i]]
	# Lift by half the nut's own height. A fixed Y sank the larger pieces into
	# the floor — the mesh is 0.34 tall and scales up to ~1.6x, so a flat 0.13
	# put the bottom face below y=0. The tumble on X means the effective radius
	# is the diagonal, not the half-height.
	var lift: float = s * NUT_HALF_DIAGONAL
	var pos := Vector3(_pos[i].x, lift, _pos[i].z)
	mm.set_instance_transform(_slot_of[i], Transform3D(basis.scaled(Vector3(s, s, s)), pos))
	# Heavier scrap reads warmer, so value is visible before you commit to it.
	var warm: float = clampf((_mass[i] - t.scrap_mass_min)
			/ maxf(0.01, t.scrap_mass_max - t.scrap_mass_min), 0.0, 1.0)
	# Three metals rather than one grey-to-brass ramp: galvanised zinc, brass, and
	# blued steel, picked per piece from its index so a heap reads as a real box of
	# mixed hardware. The old single ramp sat too light and every nut came out the
	# same pale cream, which is what made them look like plastic.
	var metal: Color = METALS[i % METALS.size()]
	# `warm` still shifts a piece toward brass with its mass, so a big nut is
	# visibly a different piece of metal from a small one.
	mm.set_instance_color(_slot_of[i], metal.lerp(BRASS, warm * 0.55))
	if _shadow_mm != null:
		var sh := s * 1.5
		_shadow_mm.set_instance_transform(i, Transform3D(
			Basis().scaled(Vector3(sh, 1.0, sh)),
			Vector3(_pos[i].x + 0.06, 0.03, _pos[i].z + 0.09)))


func _hide_instance(i: int) -> void:
	_meshes[_shape_of[i]].set_instance_transform(_slot_of[i],
			Transform3D(Basis().scaled(Vector3.ZERO), _pos[i]))
	if _shadow_mm != null:
		_shadow_mm.set_instance_transform(i,
				Transform3D(Basis().scaled(Vector3.ZERO), _pos[i]))


## Radial impulse from a release burst.
func repel(origin: Vector3, radius: float, strength: float) -> void:
	var r_sq := radius * radius
	for i in _count:
		if _respawn[i] > 0.0:
			continue
		var dx := _pos[i].x - origin.x
		var dz := _pos[i].z - origin.z
		var d_sq := dx * dx + dz * dz
		if d_sq > r_sq or d_sq < 0.0001:
			continue
		var d: float = sqrt(d_sq)
		var falloff := 1.0 - d / radius
		var v := _vel[i]
		v.x += dx / d * strength * falloff
		v.z += dz / d * strength * falloff
		_vel[i] = v


func alive_count() -> int:
	var n := 0
	for i in _count:
		if _respawn[i] <= 0.0:
			n += 1
	return n
