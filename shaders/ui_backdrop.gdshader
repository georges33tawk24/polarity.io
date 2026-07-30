shader_type canvas_item;

// Riveted steel panels — the same surface as the arena floor, so the front end
// and the game are visibly one material and one world.
//
// Duplicated from floor.gdshader rather than shared: that one is a `spatial`
// shader and Godot cannot use it on a Control. Kept structurally identical so
// the two cannot drift apart.
//
// Plus the one thing the front end has that the floor does not: FIELD LINES.
// Iron filings converge on whatever the screen wants you to press — PLAY on the
// menu, the price column in the shop, the placement in results. It costs one
// uniform set per screen on a shader that already runs full-screen every frame,
// and it is the only decoration in this UI derived from the game's own subject.
// A magnet arena whose menus carry no field is a menu for any game at all.

// Defaults are the warm ramp, but UiKit.backdrop() sets these from the tokens.
// They were cool slate and nothing overrode them, so the palette never reached
// the largest surface in the game on any of six screens.
uniform vec4 base_color : source_color = vec4(0.149, 0.141, 0.122, 1.0);
uniform vec4 rivet_color : source_color = vec4(0.333, 0.306, 0.255, 1.0);
uniform float plate_px = 420.0;
uniform float dim : hint_range(0.0, 1.0) = 0.0;

// Field pole, NORMALISED 0..1 across the viewport. Not pixels: FRAGCOORD is in
// framebuffer pixels while Control.get_global_rect() is in canvas units, and with
// content scaling those differ by the scale factor — passing pixels aimed the
// field off-screen. Strength 0 skips the pass entirely, which is what a screen
// with no single call to action wants.
uniform vec2 pole = vec2(0.5, 0.62);
uniform float pole_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 field_color : source_color = vec4(0.910, 0.639, 0.239, 1.0);
uniform float field_reach = 0.42;   // as a fraction of viewport height

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 w = FRAGCOORD.xy;
	vec2 cell = floor(w / plate_px);
	vec2 f = fract(w / plate_px);

	vec3 c = base_color.rgb * (0.92 + hash(cell) * 0.20);

	vec2 d = abs(f - 0.5);
	float edge = max(d.x, d.y);
	float trough = smoothstep(0.468, 0.5, edge);
	float lip = smoothstep(0.44, 0.468, edge) * (1.0 - trough);
	c *= 1.0 - trough * 0.50;
	c += rivet_color.rgb * lip * 0.25;

	vec2 r = min(f, 1.0 - f);
	float rd = length(r - vec2(0.055));
	float rivet = 1.0 - smoothstep(0.012, 0.026, rd);
	float rivet_shadow = smoothstep(0.026, 0.040, rd) * (1.0 - smoothstep(0.040, 0.055, rd));
	c = mix(c, rivet_color.rgb * 1.30, rivet * 0.85);
	c *= 1.0 - rivet_shadow * 0.22;

	c *= 0.97 + hash(floor(w * 0.5)) * 0.06;

	// Filings: radial strokes bent by distance, so they curve into the pole the
	// way a field does rather than reading as a starburst.
	if (pole_strength > 0.001) {
		vec2 vp = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 pd = (w - pole * vp) / (vp.y * field_reach);
		float pr = length(pd);
		float pa = atan(pd.y, pd.x);
		// Curvature is what makes this iron rather than a sunburst. Straight
		// radial spokes — which is what a low `pr` coefficient gives — are a lens
		// flare, and a lens flare is the single most generated-looking thing you
		// can put behind a title. The strong pr term bends them into arcs.
		float lines = sin(pa * 30.0 + pr * 30.0);
		float fil = smoothstep(0.88, 1.0, lines) * exp(-pr * 2.4);
		// Broken into filings along their length, so they read as loose particles
		// aligned to a field instead of drawn rays.
		fil *= 0.35 + 0.65 * smoothstep(0.35, 0.95, sin(pr * 54.0) * 0.5 + 0.5);
		// Fade out close in, or the filings crawl across the button itself.
		fil *= smoothstep(0.05, 0.26, pr);
		c += field_color.rgb * fil * 0.17 * pole_strength;
	}

	// Multiply toward black so dim can actually reach dark. This was
	// mix(c, c * 0.55, dim), whose maximum was a 45% darken — so every
	// "dim the backdrop behind a modal" value in the codebase animated nothing.
	COLOR = vec4(c * (1.0 - dim * 0.88), 1.0);
}
