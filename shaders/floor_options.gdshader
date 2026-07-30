shader_type spatial;
render_mode cull_back, diffuse_lambert, shadows_disabled;

// Background candidates, switchable by `style`, so they can be compared
// side-by-side in the same scene rather than described in prose.
//   0 = diamond plate (current)
//   1 = worn concrete
//   2 = hex tile
//   3 = magnetic field lines
//   4 = riveted panels

uniform int style : hint_range(0, 4) = 0;
uniform vec3 base_color : source_color = vec3(0.145, 0.145, 0.152);
uniform vec3 grid_color : source_color = vec3(0.404, 0.404, 0.420);
uniform vec3 danger_color : source_color = vec3(0.360, 0.145, 0.125);
uniform float grid_size = 3.2;
uniform float ring_radius = 40.0;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.17;
}

float lozenge(vec2 p, float a) {
	float c = cos(a); float s = sin(a);
	vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	return smoothstep(1.0, 0.55, length(q / vec2(0.40, 0.115)));
}

float treads(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float lean = mod(cell.y, 2.0) < 1.0 ? 0.7 : -0.7;
	return max(lozenge(f - vec2(0.0, 0.16), lean), lozenge(f + vec2(0.0, 0.16), lean));
}

// Distance to the nearest hex edge, for the honeycomb style.
float hex_edge(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.73))), p.x);
}

void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 w = world_pos.xz;
	vec3 c = base_color;

	if (style == 0) {
		vec2 uv = w / grid_size;
		float h = treads(uv);
		float e = 0.06;
		float hx = treads(uv + vec2(e, 0.0)) - treads(uv - vec2(e, 0.0));
		float hy = treads(uv + vec2(0.0, e)) - treads(uv - vec2(0.0, e));
		vec3 n = normalize(vec3(-hx, 0.55, -hy));
		float lit = clamp(dot(n, normalize(vec3(-0.45, 0.75, -0.48))), 0.0, 1.0);
		c = mix(base_color, grid_color, h * (0.30 + lit * 0.70));
		c *= 1.0 - clamp(-hy, 0.0, 1.0) * 0.40 * h;

	} else if (style == 1) {
		// Worn concrete: broad mottling, a few darker pours, fine aggregate.
		// Deliberately featureless — it gets out of the way entirely.
		float m = fbm(w * 0.09);
		c = mix(base_color * 0.85, base_color * 1.35, m);
		c *= 0.93 + hash(floor(w * 8.0)) * 0.14;
		float pour = smoothstep(0.45, 0.5, fbm(w * 0.022));
		c *= 1.0 - pour * 0.10;

	} else if (style == 2) {
		// Hex tile: echoes the nut silhouette, so ground and collectible share a
		// visual language without the ground competing.
		vec2 hs = vec2(grid_size * 0.95, grid_size * 0.82);
		vec2 a = mod(w, hs) - hs * 0.5;
		vec2 b = mod(w + hs * 0.5, hs) - hs * 0.5;
		vec2 g = dot(a, a) < dot(b, b) ? a : b;
		float d = hex_edge(g / (grid_size * 0.5));
		float line = smoothstep(0.82, 0.98, d);
		c = mix(base_color, base_color * 1.30, 1.0 - line);
		c = mix(c, grid_color * 0.75, line * 0.75);
		c *= 0.95 + hash(floor(w * 5.0)) * 0.10;

	} else if (style == 3) {
		// Magnetic field lines: slow flowing curves radiating from the arena
		// centre. The most thematic option and the most likely to distract.
		float r = length(w);
		float ang = atan(w.y, w.x);
		float flow = sin(ang * 8.0 + r * 0.22) * 0.5 + 0.5;
		float band = smoothstep(0.42, 0.5, flow) * (1.0 - smoothstep(0.5, 0.58, flow));
		c = base_color * (0.92 + fbm(w * 0.06) * 0.25);
		c = mix(c, grid_color * 0.8, band * 0.55);

	} else {
		// Riveted panels: large plates, recessed seams, rivets at the corners.
		// The junkyard read, closest to the reference in spirit but calmer.
		vec2 cell = floor(w / grid_size);
		vec2 f = fract(w / grid_size);
		float plate = 0.88 + hash(cell) * 0.24;
		c = base_color * plate;
		vec2 seam = abs(f - 0.5);
		float s = smoothstep(0.47, 0.5, max(seam.x, seam.y));
		c *= 1.0 - s * 0.45;
		float rivet = 1.0 - smoothstep(0.03, 0.055, length(f - clamp(f, 0.09, 0.91)) + length(min(f, 1.0 - f) - 0.09));
		vec2 rp = min(f, 1.0 - f);
		float rd = length(rp - vec2(0.085));
		float riv = 1.0 - smoothstep(0.028, 0.05, rd);
		c = mix(c, grid_color * 1.05, riv * 0.85);
		c *= 0.96 + hash(floor(w * 7.0)) * 0.08;
	}

	float outside = smoothstep(ring_radius - 0.8, ring_radius + 0.8, length(w));
	c = mix(c, danger_color, outside * 0.88);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
