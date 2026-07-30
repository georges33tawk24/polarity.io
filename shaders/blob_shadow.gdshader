shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Blob shadow. §13A: "blob shadows, NOT realtime shadows on mobile/web".
//
// Without these every object floats — the single biggest readability problem in
// a top-down scene, and far cheaper to fix than with a real shadow map.

uniform float softness : hint_range(0.5, 4.0) = 1.8;
uniform float strength : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), softness);
	ALBEDO = vec3(0.0);
	ALPHA = a * strength;
}
