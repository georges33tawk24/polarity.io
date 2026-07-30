shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The player's pull, drawn as force rather than as a boundary.
//
// This replaced a hard-edged additive ring on ring.gdshader. A crisp circle on the
// ground reads as a debug gizmo or a selection marker: it told you where your reach
// ended, but it looked like editor furniture, and fifteen of them — one per magnet —
// turned the floor into a Venn diagram. Rivals draw nothing now; the player gets a
// soft wash with no edge anywhere for the eye to lock onto.
//
// What sells the pull is the MOTION, not the shape: faint spokes drift inward, so
// the eye infers force without a circle ever being drawn.

uniform vec3 tint : source_color = vec3(0.98, 0.86, 0.52);
uniform float strength : hint_range(0.0, 2.0) = 0.0;
uniform float sweep = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;

	// Nothing at the centre — the body is already there. Peaks around 0.6 and is
	// fully gone by the rim, so there is no boundary to read.
	float wash = smoothstep(0.16, 0.52, d) * (1.0 - smoothstep(0.52, 1.0, d));

	float ang = atan(p.y, p.x);
	float spokes = 0.5 + 0.5 * sin(ang * 10.0 - d * 11.0 + sweep);
	wash *= 0.52 + spokes * 0.48;

	ALBEDO = tint;
	ALPHA = clamp(wash * strength, 0.0, 1.0);
}
