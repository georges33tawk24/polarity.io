class_name CameraRig
extends Node3D
## Top-down orthographic follow cam. Zooms out as the player grows, shakes on
## impact, and punches in for the clip moment.

var t: Tuning
var target: Node3D = null
var camera: Camera3D

var _trauma := 0.0
var _size := 21.0
var _clip_punch := 0.0


func setup(tuning: Tuning) -> void:
	t = tuning
	rotation = Vector3(-deg_to_rad(t.camera_angle_deg), 0.0, 0.0)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0, 0, 60)
	camera.near = 0.5
	camera.far = 220.0
	_size = t.camera_size_base
	camera.size = _size
	camera.current = true
	add_child(camera)
	Bus.shake.connect(add_trauma)
	Bus.clip_moment.connect(_on_clip)


func _process(delta: float) -> void:
	# The rig is added to the tree before setup() builds the camera — staged
	# arena construction puts real frames in that gap.
	if camera == null:
		return
	if target != null and is_instance_valid(target):
		var goal: Vector3 = target.global_position
		goal.y = 0.0
		global_position = global_position.lerp(goal, clampf(t.camera_lerp * delta, 0.0, 1.0))

		var mass: float = target.mass if target is Magnet else t.start_mass
		var want: float = t.camera_size_base * pow(maxf(mass, 1.0) / t.start_mass, t.camera_size_mass_exp)
		_size = lerpf(_size, want, clampf(2.5 * delta, 0.0, 1.0))

	_clip_punch = move_toward(_clip_punch, 0.0, delta * 1.6)
	# Orthographic `size` applies to ONE axis, so a fixed axis makes the other
	# shrink with the aspect: on a 420x860 phone, KEEP_HEIGHT showed barely ten
	# world units across — narrower than the player's own pull diameter.
	# Fixing the minor axis keeps the visible play area equal on every device,
	# which is also the fair choice: an ultrawide must not grant more vision.
	var vp := get_viewport().get_visible_rect().size
	camera.keep_aspect = Camera3D.KEEP_WIDTH if vp.y >= vp.x else Camera3D.KEEP_HEIGHT
	camera.size = maxf(4.0, _size * (1.0 - _clip_punch * 0.22))

	_trauma = maxf(0.0, _trauma - delta * 2.6)
	if _trauma > 0.0:
		# Linear-ish (pow 1.5) rather than squared: squaring made small hits
		# vanish and big ones wreck the screen. Amplitude is also capped as a
		# fraction of the view so it never obscures the fight.
		var amp: float = minf(pow(_trauma, 1.5) * _size * 0.05, _size * 0.03)
		camera.h_offset = randf_range(-amp, amp)
		camera.v_offset = randf_range(-amp, amp)
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func add_trauma(amount: float) -> void:
	if Game.profile.get("reduced_motion", false):
		amount *= 0.25
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _on_clip(_pos: Vector3) -> void:
	if Game.profile.get("reduced_motion", false):
		return
	_clip_punch = 1.0


## Where a world point lands on screen — used to anchor input steering.
func screen_point(world: Vector3) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world)
