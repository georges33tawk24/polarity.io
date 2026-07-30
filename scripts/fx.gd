class_name Fx
extends Node3D
## Pooled feedback: shockwave rings, floating numbers, elimination bursts.
## Everything is preallocated — the hot loop never instantiates a node.

const WAVES := 10
const LABELS := 14
const BURSTS := 6

class Wave:
	var node: MeshInstance3D
	var mat: ShaderMaterial
	var life := 0.0
	var dur := 0.4
	var weight := 1.0
	var from := 1.0
	var to := 6.0

class Floater:
	var node: Label3D
	var life := 0.0
	var dur := 0.9
	var origin := Vector3.ZERO

var _waves: Array[Wave] = []
var _labels: Array[Floater] = []
var _bursts: Array[GPUParticles3D] = []
var _burst_next := 0
var quality := 1.0


func _ready() -> void:
	var shader: Shader = load("res://shaders/ring.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)

	for i in WAVES:
		var w := Wave.new()
		w.mat = ShaderMaterial.new()
		w.mat.shader = shader
		w.mat.set_shader_parameter("inner", 0.88)
		w.mat.set_shader_parameter("thickness", 0.07)
		w.node = MeshInstance3D.new()
		w.node.mesh = plane
		w.node.material_override = w.mat
		w.node.visible = false
		w.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w.node)
		_waves.append(w)

	for i in LABELS:
		var f := Floater.new()
		f.node = Label3D.new()
		f.node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		f.node.no_depth_test = true
		f.node.fixed_size = true
		f.node.pixel_size = 0.0011
		f.node.font_size = 96
		f.node.outline_size = 30
		f.node.visible = false
		add_child(f.node)
		_labels.append(f)

	for i in BURSTS:
		_bursts.append(_make_burst())


func _make_burst() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.35, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 13.0
	mat.gravity = Vector3(0, -14.0, 0)
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	p.process_material = mat

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.3)
	var mmat := StandardMaterial3D.new()
	mmat.vertex_color_use_as_albedo = false
	mmat.emission_enabled = true
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mmat
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _process(delta: float) -> void:
	for w in _waves:
		if not w.node.visible:
			continue
		w.life += delta
		var k := w.life / w.dur
		if k >= 1.0:
			w.node.visible = false
			continue
		var s: float = lerpf(w.from, w.to, ease(k, 0.32))
		w.node.scale = Vector3(s, 1.0, s)
		# Squared falloff, and the band thins as it expands. A wave that holds its
		# width and fades linearly reads as a slow soft circle — which is exactly
		# the pull-radius ring this game just got rid of. Sharpening it as it goes
		# makes the same geometry read as an impact instead.
		var fade := (1.0 - k) * (1.0 - k)
		w.mat.set_shader_parameter("strength", fade * 1.5 * w.weight)
		w.mat.set_shader_parameter("thickness", lerpf(0.09, 0.02, k))

	for f in _labels:
		if not f.node.visible:
			continue
		f.life += delta
		var k := f.life / f.dur
		if k >= 1.0:
			f.node.visible = false
			continue
		f.node.position = f.origin + Vector3(0, 1.0 + k * 2.6, 0)
		f.node.modulate.a = 1.0 - k * k


## `weight` scales visibility, not size. Fourteen rivals firing repels put several
## waves on screen at all times; at full strength they collectively read as
## ambient decoration rather than as anything you caused.
func shockwave(pos: Vector3, radius: float, tint: Color, power := 1.0,
		weight := 1.0) -> void:
	if quality < 0.35:
		return
	var w := _free_wave()
	if w == null:
		return
	w.life = 0.0
	w.weight = weight
	w.dur = 0.18 + power * 0.12
	w.from = radius * 0.16
	w.to = radius * (0.72 + power * 0.24)
	w.node.position = Vector3(pos.x, 0.06, pos.z)
	w.node.scale = Vector3(w.from, 1.0, w.from)
	w.mat.set_shader_parameter("tint", tint)
	w.mat.set_shader_parameter("strength", 1.5 * weight)
	w.node.visible = true


func floater(pos: Vector3, text: String, color: Color) -> void:
	if quality < 0.35:
		return
	for f in _labels:
		if f.node.visible:
			continue
		f.life = 0.0
		f.origin = pos
		f.node.text = text
		f.node.modulate = color
		f.node.position = pos + Vector3(0, 1.0, 0)
		f.node.visible = true
		return


func burst(pos: Vector3, color: Color) -> void:
	if quality < 0.5:
		return
	var p := _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % BURSTS
	p.global_position = pos
	var mesh := p.draw_pass_1 as BoxMesh
	var mat := mesh.material as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = color
	p.restart()
	p.emitting = true


func _free_wave() -> Wave:
	for w in _waves:
		if not w.node.visible:
			return w
	return null
