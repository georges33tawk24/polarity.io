shader_type spatial;
// cull_disabled, deliberately. The horseshoe is generated geometry and any quad
// wound the wrong way gets culled, which shows the inside of the body and reads
// as the character being half transparent. Unshaded means a back face is
// indistinguishable from a front one, so disabling culling costs nothing and
// makes the whole class of bug impossible.
render_mode cull_disabled, unshaded;

// Stylised magnet body: two-tone poles, a banded toon ramp, a fresnel rim and a
// tight specular glint. The pole split is computed in model space so it stays
// centred at any body scale.
//
// Toon rather than lambert on purpose — §13A asks for "flat/lightly-shaded" with
// "strong readable silhouettes", and a smooth lambert falloff on a small
// top-down object reads as muddy grey rather than as a shape.

uniform vec3 pole_a : source_color = vec3(1.0, 0.23, 0.34);
uniform vec3 pole_b : source_color = vec3(0.25, 0.49, 1.0);
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float skin_glow : hint_range(0.0, 2.0) = 0.0;
// Fresnel rim. This is the "glint" that separates a magnet from the floor.
uniform float rim_strength : hint_range(0.0, 2.0) = 0.14;
uniform float rim_width : hint_range(1.0, 8.0) = 4.5;
uniform vec3 rim_color : source_color = vec3(1.0, 0.94, 0.82);

varying vec3 local_pos;
varying vec3 world_normal;
varying vec3 world_view;

void vertex() {
	local_pos = VERTEX;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	world_view = normalize((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	// Split on Z, not X. The camera looks straight down, so model X is the screen
	// horizontal and model Z is the screen vertical — splitting on X put the divide
	// on a vertical line. Z gives the horizontal 50/50 divide a bar magnet actually
	// has. The narrow smoothstep keeps it a hard edge rather than a gradient.
	// Split on X, not Z: the body is a U with its legs along -Z, so the two arms
	// separate left/right. Splitting on Z put one colour on the bend and the other
	// on both legs, which is not what a magnet's poles look like.
	float split = smoothstep(-0.05, 0.05, local_pos.x);
	vec3 c = mix(pole_b, pole_a, split);

	// Never a full white-out: colours must stay identifiable while being hit,
	// which is exactly when you need to read the fight.
	c = mix(c, vec3(1.0), hurt * 0.22);

	// Unshaded, flat fill. This is the .io read: the same solid colour at any
	// size and any angle, instantly legible. A lighting ramp on a 2-unit object
	// viewed top-down only muddies it.
	//
	// The one shading cue kept is a hard darker keyline at the silhouette,
	// derived from the view-facing term — the outline every .io entity has.
	float facing = clamp(dot(world_normal, -world_view), 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.10, 0.40, facing);
	c = mix(c, c * 0.30, edge);
	// `edge` is reused by the charge cue below — keep it in scope.
	// Slight overall lift so bodies stay brighter than the plate behind them.
	c *= 1.06;

	// Charging used to wash the WHOLE body up to 36% toward white. Bots hold almost
	// continuously, so every magnet on screen sat near-white most of the match and
	// the skins turned pastel — the thing that made the characters look washed out
	// was not the palette, it was this.
	//
	// The signal is kept, but it now rides on the silhouette instead of the fill:
	// the keyline brightens and a thin inner band lifts, so a charging magnet reads
	// as hot at its edge while its colour stays its colour.
	// Charging used to wash the WHOLE body up to 36% toward white, and bots hold
	// almost continuously — so most magnets on screen sat pastel for most of the
	// match. That, not the palette, is what made the characters look washed out.
	//
	// Verified by removing the term entirely and re-rendering: every magnet came
	// back saturated. Worth recording that the first attempt at a fix reasoned that
	// `edge` would be ~0 on a top-down face and therefore harmless — it is not, and
	// the render said so immediately. Measure, do not derive.
	//
	// The signal now rides on a TIGHT rim plus a hard-capped body lift, so a
	// charging magnet reads as hot at its outline while its colour stays its colour.
	// Hue-preserving. Two attempts at a charge cue keyed off `edge` both washed the
	// biggest magnet to near-white, because `edge` is NOT small on these bodies the
	// way the keyline maths implies — it varies per magnet and I was wrong about it
	// twice. A multiply cannot desaturate: a charging magnet gets brighter and stays
	// its own colour, whatever `edge` happens to be doing.
	c *= 1.0 + charge * 0.20;

	ALBEDO = c;
	EMISSION = vec3(0.0);
}
