shader_type spatial;
render_mode cull_back, diffuse_lambert, shadows_disabled;

// Riveted steel panels — large plates with recessed seams and rivets set in from
// each corner. Chosen over diamond plate because the tread pattern competed with
// the collectibles; a plate this size reads as structure, not as texture.
//
// Fully procedural: nothing to download, tiles perfectly, and plate size is a
// uniform. `grid_size` is the plate pitch and `grid_color` the rivet/edge metal,
// kept under those names so existing arena themes work without a data migration.

uniform vec3 base_color : source_color = vec3(0.161, 0.161, 0.169);
uniform vec3 grid_color : source_color = vec3(0.361, 0.365, 0.384);
uniform vec3 danger_color : source_color = vec3(0.360, 0.145, 0.125);
uniform float grid_size = 9.0;        // world units per plate
uniform float ring_radius = 40.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	vec2 cell = floor(w / grid_size);
	vec2 f = fract(w / grid_size);

	// Each plate gets its own tone so a large floor does not read as one sheet.
	vec3 c = base_color * (0.90 + hash(cell) * 0.26);

	// Recessed seam: dark trough with a lit lip on the near side, so the plate
	// edge reads as a real step rather than a drawn line.
	vec2 d = abs(f - 0.5);
	float edge = max(d.x, d.y);
	float trough = smoothstep(0.468, 0.5, edge);
	float lip = smoothstep(0.44, 0.468, edge) * (1.0 - trough);
	c *= 1.0 - trough * 0.55;
	c += grid_color * lip * 0.30;

	// Four rivets, inset from the plate corners.
	vec2 r = min(f, 1.0 - f);
	float rd = length(r - vec2(0.055));
	float rivet = 1.0 - smoothstep(0.012, 0.026, rd);
	float rivet_shadow = smoothstep(0.026, 0.040, rd) * (1.0 - smoothstep(0.040, 0.055, rd));
	c = mix(c, grid_color * 1.35, rivet * 0.9);
	c *= 1.0 - rivet_shadow * 0.25;

	// Grain, plus large-scale staining so the surface has history.
	c *= 0.96 + hash(floor(w * 6.0)) * 0.08;
	c *= 0.92 + hash(floor(w * 0.09)) * 0.14;

	// Outside the ring used to be flooded with red at 0.88 — a huge saturated slab
	// that dominated the frame and made the arena look like it was on fire. The
	// boundary still has to read, so it keeps a narrow painted edge and the ground
	// beyond it just goes darker, which says "off the plate" without shouting.
	float d_ring = length(w);
	float outside = smoothstep(ring_radius - 0.8, ring_radius + 0.8, d_ring);
	float boundary = smoothstep(ring_radius + 2.6, ring_radius + 0.2, d_ring) * outside;
	c = mix(c, c * 0.42, outside);
	c = mix(c, danger_color, boundary * 0.35);

	ALBEDO = c;
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
}
