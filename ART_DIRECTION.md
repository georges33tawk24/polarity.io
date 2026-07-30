# ART DIRECTION — de-neon pass

Written after direct feedback: *"camera shake is way too brutal and it looks very
neon like and AI designed."* That is accurate. This file is the corrective brief
and the standard to hold every visual change against.

**Read this alongside [SPEC.md](SPEC.md).** Where §13A and this file disagree,
this file wins — it is later, and it is based on looking at the actual result.

---

## The diagnosis

What makes the current build read as machine-generated:

1. **Saturated cyan on near-black.** `#4FC7FF` on `#0E0F17` is the single most
   over-used palette in generated game art. It appears in the accent, the ring,
   the charge bar, the aura and the leaderboard highlight.
2. **Everything glows.** Bloom is on, skins carry an `emission` value, scrap
   emits, hazards emit, the safe ring is additive. When everything is emissive,
   nothing is emphasised.
3. **Additive translucent rings everywhere.** Pull auras, hazard markers,
   reverse-polarity zones, shockwaves. Fifteen overlapping glowing circles is
   the "AI slop" signature more than any single colour.
4. **A neon grid floor.** Tron-by-default. It says nothing about a magnet
   junkyard.
5. **Uniform UI rhythm.** Every button is the same width, height, weight and
   colour, stacked at equal spacing. No hierarchy, so nothing leads the eye.
6. **All-caps everything** at one weight. Reads as a wireframe, not a product.
7. **Camera shake far too strong.** Trauma 0.6 on a kill with a squared curve
   is a screen-wrecker at this camera distance.

## The target

**A junkyard in warm afternoon light, not a neon server room.**

Matte, chalky, saturated-but-not-glowing colours. Bright objects on a mid-tone
warm ground — not glowing objects on black. Think painted metal and dust, with
one accent colour used sparingly and meaningfully.

### Palette

| Role | Was | Becomes | Why |
|---|---|---|---|
| Ground | `#0E0F17` near-black | `#3A3630` warm dark taupe | Objects read against mid-tone; black forces glow to create contrast |
| Ground detail | `#2E3550` neon grid | `#443F37` subtle tonal panels | Texture without a Tron reference |
| Danger zone | `#57101C` | `#5C3327` rust | Reads as hazard without being a red LED |
| UI surface | `#0E0F17` | `#26241F` warm charcoal | Warmth is what stops it feeling synthetic |
| Accent | `#4FC7FF` cyan | `#E8A33D` amber | Warm, less common, ties to brass/metal |
| Positive | `#59D98C` | `#7FA05A` olive-green | Desaturated, sits in the same world |
| Danger | `#FF4D6B` | `#C4553D` terracotta | Muted, not an alarm LED |
| Player poles | `#FF4059` / `#477FFF` | `#D94F3D` / `#4A6FA5` | Keep the red/blue read, drop the fluorescence |

### Rules

1. **No emissive on anything that is not literally a light source.** Skins,
   scrap and magnet bodies are matte. Only charge-up, the clip moment and
   power-up pickups may emit, briefly.
2. **Glow/bloom off by default.** If a thing needs emphasis, use size, contrast
   or motion.
3. **At most one additive element on screen per magnet.** The player's own pull
   aura. Bot auras become a thin matte ring or nothing.
4. **Saturation grading down** from 1.18 to ~0.95. Contrast stays.
5. **Camera shake roughly a third of current.** Kill 0.6 → 0.22, launch
   0.35 → 0.12, hit 0.22 → 0.08. Shake should punctuate, not obscure.
6. **Hazards read by shape and colour, not by glow.** A saw is a saw because it
   has teeth and spins.

## UI/UX rules

1. **One accent, used once per screen.** The primary action. Everything else is
   surface or text.
2. **Type scale, not one size.** Display 96 / title 56 / body 34 / caption 26,
   with weight and opacity carrying hierarchy — not colour.
3. **Spacing scale of 8.** 8 / 16 / 24 / 40. No arbitrary values.
4. **Buttons are not all equal.** Primary is full-width and filled. Secondary is
   outline. Tertiary is text-only. Currently everything is a filled slab.
5. **Sentence case for prose, caps only for short labels.** All-caps body text
   is the single loudest "template" signal.
6. **Left-align lists and stats.** Centred columns of mixed-length text read as
   a placeholder.
7. **Real empty states.** "No missions yet" beats a blank panel.
8. **Touch targets stay ≥48dp** — this does not change.

---

# PART 2 — make it a true .io game

Second round of feedback: *"I want it to be a true IO game and focus on UI UX."*
The de-neon pass fixed the palette but the layout is still a generic mobile
game. The .io genre (agar / slither / hole / paper / diep) has a specific,
recognisable language and this build does not speak it.

## What actually defines an .io game

1. **The leaderboard is the game.** Top-right, ~10 rows, always visible, your
   row highlighted. It is the entire motivation loop — not a side panel.
2. **A minimap, bottom-right.** Small, square, shows the world bounds, your dot
   and the threats. Its absence is immediately noticeable to anyone who plays
   the genre.
3. **Almost no other HUD.** Your score bottom-left. That is it. No timer bar, no
   hint strip, no charge meter across the screen. The arena fills the screen.
4. **Names float on everything, always** — small, white, hard dark outline.
5. **Flat colour, not shaded 3D.** Entities are solid fills with a darker
   keyline. No rim light, no toon ramp, no specular. The read is instant and
   the same at any size.
6. **A light, calm, uniform ground** with a fine repeating grid. The world reads
   as huge and neutral; the entities carry all the colour.
7. **One screen to play.** Name field, PLAY, done. Menus are secondary and
   small. Nothing gates the first match.
8. **Death is instant and re-entry is one tap.** Stats, then PLAY AGAIN.

## What this build gets wrong

| | Now | Should be |
|---|---|---|
| Leaderboard | small, mid-right, 5 rows | top-right, 10 rows, prominent, rank + score columns |
| Minimap | **absent** | bottom-right, world bounds, player + rivals + ring |
| HUD | timer, alive count, charge bar, hint strip, kill feed | score bottom-left, leaderboard, minimap. Nothing else. |
| Ground | dark warm panels | light neutral, fine grid, uniform |
| Entities | toon + rim + specular | flat fill + dark keyline |
| Menu | title, name, 4 stacked buttons, wallet, rank | name + PLAY, everything else demoted |

## Non-negotiable

The arena must fill the screen. Every pixel of HUD is a pixel not showing the
game, and .io games are famously close to zero-chrome.

## Out of scope for this pass

Mesh silhouettes are fine and stay. This is a colour, light, motion and layout
pass, not a modelling pass. Authored meshes remain blocked on Blender.

---

# PART 3 — diamond plate

Third round of feedback, with a reference image: dark **diamond-plate steel**.
That supersedes both earlier ground treatments. It is the right surface for a
magnet junkyard in a way neither the neon grid nor the light uniform grid was —
industrial, tactile, and dense enough to give motion a reference without any
single feature competing with an entity.

- Ground and menu backdrop are the same procedural plate (`floor.gdshader` and
  `ui_backdrop.gdshader` — duplicated because one is `spatial` and the other
  `canvas_item`; the tread function is identical so they cannot drift).
- **World is dark again**, so the UI inverts back to light-on-dark. The type
  scale, spacing scale and button tiers from Part 1 all stay.
- **Collectibles are nuts only.** A mixed bag of bolts/gears/shards read as
  generic debris; one repeated, instantly recognisable object is clearer and
  more .io.
- **Buttons gained physical depth** — a darker bottom lip, and a pressed state
  that loses the lip and shifts down so the button visibly travels.

## Status

**Part 1 (de-neon) — done.** Shake cut ~3x with a saner curve, palette off
cyan-on-black, glow disabled, neon grid replaced, hazard LEDs removed, auras
calmed, type/spacing scale and button hierarchy in.

**Part 2 (.io) — done.** Minimap, 10-row leaderboard top-right, score
bottom-left, everything else stripped, light uniform ground, flat unshaded
entities with keylines, `name → PLAY` front end, results as headline + stats +
one action, prose sentence-cased, UI moved onto the same light surface as the
arena so entering a match is not a cut.

**Bugs this direction surfaced** — recorded because each was invisible in code
review and only showed in a screenshot:

1. Minimap collapsed to zero size: `PRESET_BOTTOM_RIGHT` pins all four anchors
   to 1 and zeroes the offsets.
2. All HUD text stayed light-on-dark after the arena went light.
3. The floor grid was mathematically present but invisible — the arena *theme*
   overrides the shader uniforms, and the theme values were near-identical.
4. Flipping `BG` to light turned every filled button label light-on-amber,
   because the label colour was defined as `BG`.
5. A hint label anchored to a zero-width centre point wrapped one glyph per line.
6. Rank colours from `meta.json` were chosen against a dark UI and vanished.

## Method note

Unasserted string replacement silently reported success at least twice this
session — once claiming the menu was restructured when nothing had changed.
Every scripted edit now carries `assert s != before`, and every visual change is
screenshotted before it is called done.

## How to check the work

Screenshot the menu, the shop and a live match after every change. The test is
not "does it look nice in isolation" but **"could this be mistaken for a
template?"** If the answer is yes, the change has not landed.


## PART 4 — one material, everywhere (2026-07-29)

The floor became riveted steel plates; the front end had not followed. Fixed so
the UI, the buttons and the HUD are the same object as the world.

- `ui_backdrop.gdshader` rewritten from diamond plate to the same plate/seam/
  rivet maths as `floor.gdshader`, at UI pixel scale (`plate_px = 420`).
- Corner radius went from 20-28px pills to a single `UiKit.RADIUS = 10`. Steel
  plates have small, consistent radii; the pills were the least industrial thing
  on screen. Progress bars squared off to 3px for the same reason.
- `UiKit.panel()` is now a plate: hairline border, heavier bottom edge, matching
  the floor's seam treatment.
- Minimap gained a bezel (heavy outer ring + hairline inner) so it reads as a
  mounted gauge rather than a hole cut in the screen.

### Two real bugs this surfaced

**Every meta screen was light beige.** `ui_meta.gd` painted an opaque
`Color(0.839, 0.827, 0.800)` behind shop, missions, leaderboard, pass and store
— the one bright surface in a dark game, with every text token tuned for dark
sitting on top of it. Shop copy was light-grey-on-light-grey and effectively
unreadable. Replaced with the shared backdrop at `dim = 0.35`.

**Cards were 5.5% white**, so backdrop rivets and seams printed straight through
the middle of every shop row. `PANEL` is now a near-opaque plate colour.

Both had been shipping. Neither showed up in 267 headless assertions, because
neither is a logic error — which is the whole argument for screenshotting every
screen after every visual change, not just the one being worked on.


## PART 5 — no more circles on the floor (2026-07-30)

User: *"i dont like the circles around the players"*. There were four separate
sources, and every one of them was a flat additive ring on `ring.gdshader`:

1. **Pull-radius auras.** Every magnet drew a hard ring at its reach. With fifteen
   magnets the floor was a Venn diagram, and a crisp circle under a character reads
   as an editor selection gizmo, not as anything physical. Rivals now draw nothing —
   body size and the minimap already carry threat. The player gets
   `shaders/field.gdshader`: a soft wash with no edge anywhere, plus spokes drifting
   inward. **The motion is what reads as pull; the shape never did.** It appears only
   while you are actually holding.
2. **Hazard footprints.** Saws and spikes marked their danger area with a thick
   additive band, i.e. a glowing blob. Additive blending is exactly wrong for a floor
   marking: paint absorbs light, it does not emit. Replaced with
   `shaders/hazard_decal.gdshader` — mix-blended chevron hatching inside a scuffed
   border, eroded by two octaves of noise so it reads as worn stencil on steel.
3. **Reverse-polarity zones.** Same decal, hatch running the opposite way. One
   marking language, one glance to tell a damage hazard from a rules change.
4. **Repel shockwaves.** These expanded to the *full repel reach* over half a second
   at constant width — which is to say they were the pull-radius ring, animated.
   Now 0.18-0.30s, squared falloff, and the band thins as it expands so the same
   geometry reads as an impact. Rival waves damped to 0.4 weight; fourteen bots
   firing repels at full strength was ambient decoration.

### Two things the same pass caught

**Powerup colours were still pure neon** — `#ff5ce0`, `#8dff5c`, `#5cd6ff`. They had
survived Part 1 entirely because the de-neon sweep went screen by screen and nothing
on a menu is a powerup. Now industrial signal colours: electrical teal, machine
green, safety yellow, hazard orange, cold steel.

**The saw was an octagon.** `radial_segments = 8` with a comment claiming the low
count would "read as saw teeth". It never did — at this camera distance an octagon is
an octagon. `Meshes.saw_blade()` builds a real alternating-radius blade with a bore.
Spikes went from one wedge to a four-piece cluster at mixed scales, because a single
prism gave no scale cue and just read as a dark blob.

Lesson worth keeping: **`blend_add` was the tell.** Almost everything that looked
"neon" or "AI-generated" in this project turned out to be an additive pass doing a
job that wanted mix blending. Additive means "this surface emits light" — true for a
charge glow, false for paint, floors, cards, and hazard markings.


## PART 6 — identity, not a design system (2026-07-30)

User: *"the UI seems very basic"*. Five independent critiques and a synthesis pass
produced a 9-workstream generic design system — a 10-step neutral ramp, Material
elevation, a 4-cell bottom nav bar, TRANSBACK everywhere. An adversarial art-director
pass returned **rework**, and it was right: grep that spec for *pole*, *field*,
*flux* and the words appear only where they already existed in the game code. Every
line of it would have applied unchanged to a banking app. The craft debt was real;
"install a design system" was the wrong conclusion, because a competent generic
design system is exactly what a machine generates.

What shipped instead, in priority order:

1. **The wordmark and the hero numbers are DRAWN** (`scripts/stencil.gd`). They were
   Godot's fallback font at 104-150px, and the proposed fix was
   `FontVariation.variation_embolden`, which thickens by dilating the outline and
   smears the stems at display size. Stencil lettering is what industrial lettering
   IS, stencils are rectangles, and rectangles are free — so this is the one place
   "100% procedural" beats shipping a font. Bridges (the gaps that stop a counter
   falling out of a real stencil plate) are why it looks fabricated; they are not
   decoration, they are the reason the shape is shaped that way. Diagonals were
   added after a rect-only first pass rendered POLAAITY — A and R both collapse to
   two stems and two bars. Open digits (2/3/5/7) use unbridged bars: a bridged 3
   reads as a square bracket.
2. **Field lines in the backdrop, poled to the call to action.** Iron filings
   converge on PLAY on the menu and on the placement in results. One uniform set per
   screen on a shader that already ran full-screen every frame. Two iterations were
   needed: at 11 spokes it was a lens flare, and straight radial spokes are a
   sunburst — the curvature term is what makes it read as iron.
3. **Warm steel replaces slate.** Every neutral was blue-dominant. ART_DIRECTION:48
   specified `#26241F` and it had never actually been applied to the tokens.
4. **Depth from fabrication, never from floating.** No drop shadows. `floor.gdshader`
   already established the language — recessed trough, lit lip, rivet contact shadow
   — and Material's paper metaphor would have fought it on every surface. `plate()`
   is the one surface primitive.
5. **Amber is money.** It was doing nine jobs on one screen. Selection is now an
   indicator (an underline), never a filled slab.
6. **`snap()`, not TRANS_BACK.** A rubber ball undershoots then overshoots; a magnet
   accelerates into contact and arrests. And `weight_dur()` — heavier numbers settle
   slower, because the whole scoring verb is accumulation.

### What this pass caught

**`dim` could not dim.** `mix(c, c * 0.55, dim)` maxes out at a 45% darken, so every
"dim the backdrop behind a modal" value in the codebase was animating nothing.

**The palette never reached the biggest surface.** `backdrop()` set only `dim`, so
the shader's hardcoded cool slate won on the menu, results, settings, all five meta
screens and the loader. A token pass with no shader in its file list is invisible.

**Field lines aimed off-screen.** `FRAGCOORD` is framebuffer pixels;
`get_global_rect()` is canvas units. With content scaling those differ by the scale
factor. The pole is normalised 0..1 now.

**The results screen had a dark picture frame.** It added its own backdrop as a
child, and the shared one is a sibling of the safe-area node — so the copy sat
inside the inset and the dim survived only as a ~24px border.

**Procedural preview textures cost 122ms each.** `icons.gd` rasterises per-pixel in
GDScript; fifteen 128px skin previews would have stalled the SKINS tab for most of
two seconds. Previews are drawn in a Control instead. The flat colour swatch was
also throwing `pole_b` away, so every two-tone skin previewed as one colour.

Standing rule, reinforced: **`blend_add` and `Color(1,1,1,alpha)` are the two tells.**
Additive means "this surface emits light"; a white wash over warm dark desaturates
the warmth straight back out. Between them they account for nearly everything that
read as neon or generic in this project.


## PART 7 — the HUD (2026-07-30)

The HUD was loose text floating over a game: a 12px halo on every glyph was doing
a surface's job, and the riveted material appeared in it zero times.

- **The board is bolted into the corner.** A plate with square outer corners and
  one rounded inner one, left and bottom borders only. Rows sit on it, so they use
  plain menu ink at `outline_size` 0 instead of a halo.
- **The halo is proportional** — `maxi(4, size * 0.13)`. A constant 12 was 46% of a
  26px glyph's height, which is why the MASS caption rendered as a grey smear.
- **The board is built ONCE.** It used to free every child and allocate 11 HBoxes
  plus 33 Labels with five theme overrides each on a 0.35s timer — roughly 130 node
  allocations a second on the mid-range Android target. That was also the mechanical
  reason climbing a rank could never animate: the row that moved up was a brand new
  node. Rows are now keyed by name and hand-positioned, so a rank change tweens and
  rows visibly slide past each other. Overtaking is the entire motivation loop of
  the genre and it had been a silent text swap.
- **The player's row is a different object** — amber left edge, amber wash, two
  points larger. That is the agar/slither read.
- **The mass readout is drawn** (stencil, with an explicit dark pass since drawn
  glyphs get no `outline_size`), climbs toward its target instead of teleporting,
  punches on absorb, and goes through `Locale.number` — it used to disagree with
  the leaderboard's own row for the same player, 1200 next to 1,200 on one screen.
  Heavier numbers settle slower.
- **The head row has units.** Two unlabelled size-30 numbers eight pixels apart read
  as one string. Now value + caption + divider + clock, and below the
  sudden-death threshold the alive count turns and pulses on every elimination —
  15 alive and 2 alive were visually identical.
- **The ring bar exists.** `Bus.ring_changed` was emitted every frame and had zero
  consumers; the ring closes for most of the match and the only cue was the clock
  going red under 15s, i.e. after you were already dying.
- **The charge meter moved** from a 4px strip pinned to the extreme bottom edge —
  not findable in any screenshot — to 260x14 beside the mass number. Cooldown fills
  in steel rather than emptying in amber, so the half second after a repel no longer
  looks identical to standing still.
- **The minimap is a gauge**: bezel, four rivets, background one step darker than the
  plate rather than five, and threat encoded by SHAPE (triangle) not hue — at the
  2.5-9px these dots occupy, colour alone is unreadable and colourblind-hostile.
  Dots size off RELATIVE mass, since absolute mass at match start says nothing. The
  safe ring was being drawn under the bezel hairline and was invisible for the first
  dozen seconds.
- **Per-frame signals gated.** `clock_changed` fires every frame and the handler
  called `add_theme_color_override`, invalidating the theme cache and forcing a font
  re-resolve and relayout 60x a second for a label that changes once a second.

### Two things found by screenshotting rather than by testing

**Nothing that isn't tappable may look tappable.** Mission rows showed progress in a
disabled button (`2%`, `0%`) — a box that looks pressable, isn't, and repeats what
the bar beside it already says. Deleted; the one filled CLAIM button is now the only
thing on the screen pulling the eye. Same fix retired `EQUIPPED`/`OWNED`/`CLAIMED`
in the shop.

**A weekly mission read as a lie.** "Finish top 3" beside "0 / 8" — the weekly reused
the daily's name key, which has no `%d`, so a target of 8 matches rendered as if the
goal were 8th place. New key, all ten locales.

### Harness

`smoke.gd` now takes the pending screenshot at match end if the deadline was missed.
The player is bot-driven and dies when it dies, so a capture timed from match start
was a race — a request for a shot at 6s silently produced no file on any run where
the player died at 4s, and five consecutive "failures" were nothing but that.


## PART 8 — finishing the pass (2026-07-30)

**The deprecated tokens are gone.** `BG`/`PANEL`/`DIM`/`HOT`/`GOOD`/`RADIUS` deleted
from UiKit, and the local aliases in `ui.gd` with them — those were the real problem,
because aliasing the deprecated names in a second file meant the deprecation could
never actually take effect. The rename was not a sed: `DIM` split by role into
`INK_DIM` (secondary body) and `INK_MUTE` (captions and metadata, every label at 28px
or below), the lock glyph went to `INK_OFF`, and `HOT` split into `DANGER` as a fill
versus `DANGER_LINE` as ink. Verified by grep returning zero.

**The theme Button is a real tier.** It was three white washes over a warm plate —
`Color(1,1,1,0.07/0.13/0.18)` — which is what fourteen call sites silently landed on.
Now steel. A white wash over warm dark desaturates the warmth straight back out,
which is how the whole kit drifted cool in the first place.

**Results are choreographed.** The placement lands with a scale arrest, the five stat
rows arrive in sequence against a rising ladder built from the one existing 680Hz
blip (no new asset), and only the two EARNED numbers count up — which is what points
the eye at the reward instead of at the recap. Bigger rewards take longer to land,
the same weight rule as the mass readout. Stat keys became tracked caps at a lighter
ink; both columns had been the same size and weight, so a 150/34 jump was faking the
entire hierarchy. Also removed a duplicated `Audio.play("reward")` that fired in the
same frame as the arena's win/lose arp, so a LOSS played an ascending reward
arpeggio over a descending lose arp.

**Nothing that isn't tappable looks tappable — everywhere now.** The rule that
started on mission rows finished the job: battle-pass rewards you have not reached
(28 of 30 rows), store products with no billing provider, `OWNED`, `CLAIMED`. Every
one was a disabled button. The screens got visibly shorter as a side effect — the
pass shows 18 tiers where it showed 13, the store fits all eight products — because a
state tag has no box.

**Two frozen things now move.** The store's "limited time" offer formatted
`offer_seconds_left()` once at build time and nothing rebuilt the panel, so the
countdown sat still for an entire session; it ticks one Label per second now, and
rebuilds once when it expires. And the offer had no CTA at all — a time-limited offer
with no way to accept it is a poster. The battle pass opens at the tier the player is
actually on rather than at tier 1.

**Scroll position survives a rebuild.** Buying an item at row 12 used to throw the
player back to the top. The restore is in its own deferred function, not inside
`_rebuild`, because `open_tab()` calls `_rebuild()` and depends on it being
synchronous — and it re-checks `is_instance_valid` after its await, since a locale
change frees the whole panel and a resumed coroutine would touch a dead node.

### The harness lied again, in a new way

Six frames was enough to photograph a screen back when nothing moved. Now the results
screen cascades over ~0.9s and counts up to ~1.4s, so a six-frame capture
photographed five invisible rows and printed `save=ok` — the harness reporting success
about exactly the thing it exists to check. `menu_shot` settles for 1.9s by default,
and `--reduced` captures the reduced-motion path, which is also the only way to
*test* that path: every value present and final on frame one.

That is the third distinct instance in this project of a green check over a broken
screen (DECISIONS §9, §12k, here). The pattern is always the same: the check measured
something adjacent to what mattered.


## PART 9 — transitions, one modal, and the app icon (2026-07-30)

**One modal builder.** Consent, the daily calendar, the delete confirm and the rating
prompt were four hand-rolled copies of the same twelve lines, with four different
scrim values — 0.93, 0.96, 0.97, 1.0 — and no rule behind the difference. `UiKit.modal`
now owns all four: shade fades, box is pulled in and arrested with `snap`, and
`dismiss` animates the exit instead of `queue_free()`-ing mid-frame. Opaque is
reserved for the age gate, which is a legal precondition rather than a dialog.

The scrim landed at **0.97**, twice revised upward: at 0.88 the menu's amber PLAY
button read as a lighter band straight through the dialog and the wordmark ghosted
behind the title. A modal has to be a different surface, not a tint over the previous
one — a number that is mathematically dark is not the same as a surface that reads as
covering.

**The daily calendar is choreographed.** Cells stagger in, and today's claimable cell
breathes — gated so a zero-duration looping tween can never be created under reduced
motion. Its grid was also left-aligned inside a full-width box, so a seven-cell
calendar sat in the left half of the screen under a centred title, with cells sized to
their content so `+5` was narrower than `+750`. Equal cells, centred.

Its two reward colours were the last raw hex in the UI, and one of them was
`#5ce1ff` — the saturated cyan the art direction bans by name. Brass and the repel
pole now.

**Screens transition.** `show_screen` was six boolean assignments. Menu and results
fade in; the HUD deliberately does not, because it appears with the match and fading
it would delay the one screen the player is trying to act on. Alpha only, never
position: `show_screen` re-asserts the full-rect preset on whatever became visible and
would fight an offset tween every frame.

**The app icon is real.** The project shipped Godot's `icon.svg` — the single most
recognisable "this is an engine demo" signal a store listing can carry, and it survived
every art pass because nothing on screen ever showed it. `tools/make_icons.gd` draws
the horseshoe with its two poles into a SubViewport and saves nine store sizes from
1024 down to 48. Drawn on the GPU, not rasterised: `Icons.get_icon` builds its 128px
glyphs pixel by pixel and one measures ~120ms, so a 1024² icon that way would cost most
of a second per size. The mark sits inside the inner 62% of the canvas so Android's
circular adaptive mask cannot clip the poles, and it carries no text — red and blue say
magnet on their own, at 48px.

Wiring `config/icon` was not enough: Android and PWA read their icons from
`export_presets.cfg`, where empty strings meant Godot substituted its own default at
export time. The store build would still have shipped the engine icon.


## PART 10 — affordance, on request (2026-07-30)

Four changes, all from the same user observation: *"the buttons that are just text
might not make sense to the users."* That is correct, and it was a real regression I
introduced — Part 6 replaced slab tabs with a text-only chip row on the strength of an
argument about amber budget, and traded away the one thing navigation cannot do
without, which is looking tappable.

- **Round icon buttons on the menu.** Four undifferentiated text links became
  circular buttons with a glyph and a small caption: shop, missions, leaderboard,
  settings. Icon alone is a guess; label alone is not obviously a control; navigation
  wants both. The gear is deliberately the most-drawn shape in software — settings is
  the wrong place to be original. The coach mark became an amber dot on the button
  instead of a `"  ·  NEW"` string suffix, which read as a typo and was never
  translated.
- **The meta nav bar spans the full width**, five equal cells, glyph over caption,
  active cell marked by an amber top inlay and an amber glyph. Swapping between shop,
  missions, leaderboard, pass and store was the hardest thing to do on the hardest
  screen to read.
- **No button spans the frame edge to edge.** PLAY, PLAY AGAIN, CLAIM, RESTORE and
  the consent buttons are capped at 620-700 and centred. A button the full width of
  the screen has no shape of its own — it reads as a coloured band, not a key.
- **The age gate is gone.** See below.

### Removing the age gate without removing what it was for

The 13+ screen existed for COPPA: an under-13 answer disabled personalised ads and
IAP. Deleting the screen and changing nothing else would have left the game serving
behaviourally targeted ads to an audience it can no longer age-check.

So `Ads.personalised_allowed()` now returns **false unconditionally**. The game does
not ask, therefore it does not know, therefore it does not target anyone — the standard
"mixed audience, contextual only" position. That is stricter than the gate produced,
not looser. The test that asserted "personalised consent is honoured" is now inverted
and carries the reason, so turning targeting back on requires restoring a gate first.

The consent dialog's copy had to change with it: it asked *"PERSONALISED ADS?"* about
a choice that no longer exists. Shipping that would have been a false statement to the
player in ten languages. It is now "SHOW ADS? — Ads are never personalised" with
OK / NO ADS.

### The trap this pass exposed

`Icons._px` does manual source-over blending, so filling a polygon with an alpha-0
colour is a **silent no-op**. Two glyphs had already shipped as solid blobs because of
it — a horseshoe whose gap never punched, and a card whose stripe never punched — with
no error anywhere. `_poly` now takes an explicit `erase` flag.

`tools/icon_sheet.gd` renders every named glyph plus one deliberately invalid name, so
the fallback-to-plain-disc path is visible. Five nav tabs rendering as five identical
circles was the default failure mode and it threw nothing.


### Part 10 follow-ups

The icons were left-aligned inside their circles, which is `Button.icon_alignment`
defaulting to LEFT — it applies even when there is no text for the icon to sit beside.
Worth knowing because an icon-only Button looks like it should centre by default and
does not.

Cards were cramped because retiring the fake-tappable buttons removed the very thing
that had been giving each row its height. Equal 24px padding, 24px separation, a 150px
floor per card, and text centred against it.

And the harness leaked again: `--locale` writes into the profile, so a single Japanese
capture left every later screenshot fully localised. A store screenshot came out in
Japanese with nothing to indicate a problem — the third time in this project that a
check has quietly reported on the wrong thing.


## PART 11 — measured, not eyeballed (2026-07-30)

The nuts had been called "too bright" three times across this project and adjusted by
eye each time, which never fixed it. Sampling the render found the actual cause: with
sun 1.0 + fill 0.45 + ambient 0.85, total light is about 2.3x, so **any albedo above
~0.43 clips to white on an upward-facing face**. A clipped face carries no shading and
no hue, so the whole piece reads as a flat paper cutout no matter what colour was
assigned to it. Every previous "make them less bright" edit had been moving a number
that the renderer then threw away.

Three fastener finishes now — galvanised zinc, blued steel, bright mild steel — picked
per piece from its index, with the existing mass-driven shift toward brass on top.
Roughness went 0.62 -> 0.74 so the specular lobe does not put the white back.

Lesson: **when a colour looks wrong, sample the frame before changing the value.**
Two of the three earlier attempts here were adjusting an input that was being clamped.

The pole split also moved from model X to model Z. Under a top-down camera, model X is
the screen horizontal, so splitting on X produced a vertical divide — the opposite of
what a bar magnet looks like. The shop swatch was flipped to match; a preview that
divides the other way to the object it previews is worse than no preview at all.


## PART 12 — the washed-out characters (2026-07-30)

User: *"sometimes the players becomes very light color"*. The palette was not the
cause. `magnet.gdshader` pushed the whole body up to 36% toward white while charging,
and bots hold almost continuously — so most magnets on screen were pastel for most of
the match.

Worth recording how this was found, because reasoning got it wrong twice:

1. First fix keyed the cue off `edge` (the view-facing keyline term) on the argument
   that `edge` is ~0 on a top-down face, so the wash would be harmless. Re-rendered:
   the biggest magnet was still white.
2. Removed the charge term **entirely** and re-rendered. Every magnet came back
   saturated — proving the term was the cause and that `edge` is NOT small on these
   bodies. It varies per magnet, and the derivation was simply wrong.
3. Second fix tightened the rim to `smoothstep(0.80, 1.0, edge)`. Still white on the
   biggest magnet, for the same reason.
4. Final fix stops using `edge` at all: `c *= 1.0 + charge * 0.20`. A multiply cannot
   desaturate, so a charging magnet gets brighter and stays its own colour regardless
   of what `edge` is doing.

The `edge` term evidently behaves inconsistently across bodies — that is a latent
issue in the keyline worth its own look, but it is now decoupled from the charge cue
rather than sitting underneath it.

**The bot palette had never been de-neoned.** Every rival was still fluorescent while
the player's own shop skins had been toned down two passes earlier — the sweep went
file by file and `arena.gd`'s `PALETTE` was not one of the files it visited.

Hazards cut again on request: saws 3->2, spikes 3->2, fences 2->1, reverse zones
2->1, power-ups 4->3. Non-scrap objects in an arena: 14 -> 9.
