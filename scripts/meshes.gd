class_name Meshes
extends RefCounted
## Procedurally generated low-poly meshes.
##
## Generated rather than authored in Blender: the whole game ships as a ~100 KB
## .pck, there is no import step, and a shape is a parameter change instead of a
## round trip through a DCC tool. Tri counts stay inside the spec's §13A budget
## (magnet 300-800, scrap 50-200).
##
## Built with SurfaceTool and flat smooth groups so Godot derives per-face
## normals. An earlier hand-written version shared one horizontal normal across
## wall AND cap vertices, so every top face was lit as if it were a vertical
## wall — which read as flat and dark, and later made a fresnel rim fire across
## the entire surface. Never hand-author normals for generated geometry.
##
## Everything is centred on its origin and built at unit scale, per §13A's
## consistency rule.

## Horseshoe magnet. Reads as a magnet from directly overhead, which a cylinder
## never did.
static func horseshoe(segments := 14, thickness := 0.44, height := 0.52,
		leg := 0.78) -> ArrayMesh:
	## A real U: a semicircular bend with two straight parallel legs.
	##
	## This used to be a 320-degree annulus — a band with a 40-degree notch cut in
	## it — which the player described exactly as "a circle cut in a place". The
	## silhouette is the whole identity of this game, and an almost-closed ring
	## reads as a ring no matter what colours are on it. Straight legs and a gap as
	## wide as the arms are what make the shape say magnet at a glance, and at the
	## size a magnet occupies on a phone the silhouette is all there is.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # -1 = flat shading, one normal per face

	var half := height * 0.5
	var half_t := thickness * 0.5
	# Centreline radius, so the OUTER edge still lands at 1.0 and the mesh keeps
	# the same footprint every caller already scales by.
	var rc := 1.0 - half_t

	# Centreline path with an outward normal per point: up one leg, over the bend,
	# down the other. Legs run along -Z so the two poles separate along X, which is
	# the axis magnet.gdshader splits on.
	var path: Array[Vector3] = []
	var out_n: Array[Vector3] = []
	path.append(Vector3(-rc, 0.0, -leg))
	out_n.append(Vector3(-1.0, 0.0, 0.0))
	for i in segments + 1:
		var a: float = PI - PI * float(i) / float(segments)
		var n := Vector3(cos(a), 0.0, sin(a))
		path.append(n * rc)
		out_n.append(n)
	path.append(Vector3(rc, 0.0, -leg))
	out_n.append(Vector3(1.0, 0.0, 0.0))

	var rings: Array = []
	for i in path.size():
		var p: Vector3 = path[i]
		var n: Vector3 = out_n[i]
		rings.append([
			p - n * half_t + Vector3(0, -half, 0),   # 0 inner bottom
			p + n * half_t + Vector3(0, -half, 0),   # 1 outer bottom
			p + n * half_t + Vector3(0, half, 0),    # 2 outer top
			p - n * half_t + Vector3(0, half, 0),    # 3 inner top
		])

	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		_quad(st, a[0], b[0], b[3], a[3])   # inner wall
		_quad(st, a[1], a[2], b[2], b[1])   # outer wall
		_quad(st, a[3], b[3], b[2], a[2])   # top
		_quad(st, a[0], a[1], b[1], b[0])   # bottom

	# Flat pole faces at the tips of both legs.
	var first: Array = rings[0]
	var last: Array = rings[rings.size() - 1]
	_quad(st, first[0], first[3], first[2], first[1])
	_quad(st, last[1], last[2], last[3], last[0])

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Hex nut — the most recognisable piece of scrap at a glance.
static func nut(radius := 0.55, height := 0.34, hole := 0.34) -> ArrayMesh:
	return _prism(6, radius, height, hole)


static func bolt(radius := 0.34, height := 0.7) -> ArrayMesh:
	return _prism(6, radius, height, 0.0)


## Gear: tooth count IS the silhouette at this camera distance, so 10 reads as a
## gear and 20 reads as a circle.
static func gear(radius := 0.55, height := 0.2) -> ArrayMesh:
	return _prism(10, radius, height, 0.4)


static func shard(radius := 0.45, height := 0.34) -> ArrayMesh:
	return _prism(3, radius, height, 0.0)


## Saw blade. The hazard used to be an 8-segment CylinderMesh with a comment
## claiming the low segment count would "read as saw teeth" — it does not. At this
## camera distance an octagon is an octagon. Alternating radii are the only thing
## that reads as a blade from overhead.
static func saw_blade(teeth := 12) -> ArrayMesh:
	return _star_prism(teeth, 1.0, 0.76, 0.2, 0.26)


## Prism whose outline alternates between two radii, giving `points` teeth.
static func _star_prism(points: int, r_out: float, r_in: float, height: float,
		hole: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	var half := height * 0.5
	var n := points * 2
	var rim: Array = []
	var bore: Array = []
	for i in n:
		var a: float = TAU * float(i) / n
		var r: float = r_out if i % 2 == 0 else r_in
		var c := cos(a)
		var sn := sin(a)
		rim.append([Vector3(c * r, -half, sn * r), Vector3(c * r, half, sn * r)])
		bore.append([Vector3(c * hole, -half, sn * hole),
				Vector3(c * hole, half, sn * hole)])

	for i in n:
		var j := (i + 1) % n
		_quad(st, rim[i][0], rim[j][0], rim[j][1], rim[i][1])       # tooth wall
		_quad(st, bore[i][1], bore[j][1], bore[j][0], bore[i][0])   # bore
		_quad(st, rim[i][1], rim[j][1], bore[j][1], bore[i][1])     # top
		_quad(st, rim[i][0], bore[i][0], bore[j][0], rim[j][0])     # bottom

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## N-sided prism, optionally hollow. One generator covers nut, bolt, gear and
## shard — the shapes differ only in side count and bore.
static func _prism(sides: int, radius: float, height: float, hole: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	var half := height * 0.5
	var hollow := hole > 0.001
	var outer: Array = []
	var bore: Array = []
	for i in sides:
		var a: float = TAU * float(i) / sides
		var c := cos(a)
		var s := sin(a)
		outer.append([Vector3(c * radius, -half, s * radius),
				Vector3(c * radius, half, s * radius)])
		if hollow:
			bore.append([Vector3(c * hole, -half, s * hole),
					Vector3(c * hole, half, s * hole)])

	for i in sides:
		var j := (i + 1) % sides
		_quad(st, outer[i][0], outer[j][0], outer[j][1], outer[i][1])
		if hollow:
			_quad(st, bore[i][1], bore[j][1], bore[j][0], bore[i][0])
			_quad(st, outer[i][1], outer[j][1], bore[j][1], bore[i][1])
			_quad(st, outer[i][0], bore[i][0], bore[j][0], outer[j][0])

	if not hollow:
		# Fan both caps. Triangles 1..sides-2, so no degenerate first face and
		# no missing last one — an earlier version fanned inside the wall loop
		# and every solid piece shipped with a wedge cut out of both caps.
		for i in range(1, sides - 1):
			_tri(st, outer[0][1], outer[i][1], outer[i + 1][1])
			_tri(st, outer[0][0], outer[i + 1][0], outer[i][0])

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# UVs are flat-projected; nothing here is textured, but glTF and several
	# Godot materials expect the channel to exist.
	st.set_uv(Vector2(a.x, a.z))
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z))
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z))
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)
