shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Flat ground ring. Used for both the magnet's pull-radius aura and the
// arena's shrinking safe zone — same geometry, different uniforms.

uniform vec3 tint : source_color = vec3(0.4, 0.7, 1.0);
uniform float inner : hint_range(0.0, 1.0) = 0.86;
uniform float thickness : hint_range(0.0, 0.5) = 0.05;
uniform float strength : hint_range(0.0, 2.0) = 1.0;
uniform float fill : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float outer = inner + thickness;
	float band = smoothstep(inner - 0.02, inner, d) * (1.0 - smoothstep(outer, outer + 0.02, d));
	float inside = (1.0 - smoothstep(inner - 0.02, inner, d)) * fill;
	ALBEDO = tint;
	ALPHA = clamp((band + inside) * strength, 0.0, 1.0);
}
