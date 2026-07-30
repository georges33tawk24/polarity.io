shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// A painted floor marking, stencilled onto the plate.
//
// Hazards and zones used to be additive rings on ring.gdshader, which is exactly
// wrong for paint: additive blending makes a surface EMIT light, so every hazard
// read as a flat glowing blob hovering over the floor. Paint absorbs light. This
// mixes instead, and adds the two things that make a marking look real —
// diagonal chevron hatching, and noise erosion so it reads as worn stencil on
// steel rather than a clean vector shape.
//
// `stripe_dir` flips the hatch angle, which is how one shader distinguishes a
// damage hazard from a polarity zone without a second set of colours to learn.

uniform vec3 paint : source_color = vec3(0.72, 0.24, 0.18);
uniform vec2 stripe_dir = vec2(1.0, 1.0);
uniform float stripe_scale = 7.0;
// 0 fills the disc (damage hazards — the whole footprint is dangerous). Above 0
// leaves a painted annulus, which is what a pickup pad wants: it marks a spot
// without claiming the area.
uniform float inner : hint_range(0.0, 0.95) = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	float disc = 1.0 - smoothstep(0.94, 1.0, d);
	disc *= smoothstep(inner, inner + 0.06, d);

	// sin rather than step: the soft crossing antialiases for free at the
	// distances this is viewed from, and step() shimmered badly when the camera
	// moved.
	float sw = sin(dot(UV, normalize(stripe_dir)) * stripe_scale * 6.28318);
	float stripes = smoothstep(-0.28, 0.28, sw);

	// A solid painted rim, so the boundary still reads where a stripe falls dark.
	float rim = smoothstep(0.78, 0.85, d) * (1.0 - smoothstep(0.94, 1.0, d));
	rim = max(rim, smoothstep(inner + 0.10, inner + 0.03, d) * step(0.01, inner));
	float cover = max(stripes * 0.82, rim);

	// Worn paint. Two octaves: fine speckle plus large patches scuffed away.
	float wear = noise(UV * 40.0) * 0.5 + noise(UV * 8.0) * 0.5;
	cover *= smoothstep(0.20, 0.60, wear);

	ALBEDO = paint * (0.88 + pulse * 0.28);
	ALPHA = cover * disc * strength;
}
