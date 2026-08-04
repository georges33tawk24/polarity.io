extends Node
## Buses, a player pool, and every sound effect synthesised at boot.
##
## ponytail: the spec wants ~25 named SFX. Sourcing, licensing and shipping 25
## .ogg files is more work and more payload than generating them — these are
## blips, sweeps and noise bursts, which is exactly what synthesis is good at.
## They are deliberately placeholder-grade; see DECISIONS.md.

const MIX_RATE := 22050.0
const POOL_SIZE := 14

var _sfx: Dictionary = {}          # name -> AudioStreamWAV
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _hum: AudioStreamPlayer
## Browsers refuse to start audio before a user gesture.
var _unlocked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	_build_sfx()
	_apply_authored()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)
	_hum = AudioStreamPlayer.new()
	_hum.bus = "SFX"
	_hum.stream = _sfx["hum"]
	_hum.volume_db = -80.0
	_hum.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hum)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	_intensity_player = AudioStreamPlayer.new()
	_intensity_player.bus = "Music"
	_intensity_player.volume_db = -80.0
	_intensity_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_intensity_player)


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		_unlocked = true


func _make_buses() -> void:
	for name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")


func set_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))


func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not _unlocked or not _sfx.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _sfx[name]
	# Pitch variance stops repetition fatigue on the sounds that fire constantly.
	p.pitch_scale = clampf(pitch * randf_range(0.94, 1.06), 0.2, 4.0)
	p.volume_db = volume_db
	p.play()


## Continuous attract hum. `strength` 0..1, 0 silences it.
func set_hum(strength: float, pitch := 1.0) -> void:
	if not _unlocked:
		return
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.01:
		if _hum.playing:
			_hum.stop()
		return
	if not _hum.playing:
		_hum.play()
	_hum.pitch_scale = clampf(pitch, 0.5, 2.5)
	_hum.volume_db = linear_to_db(strength * 0.35)


# --- music -----------------------------------------------------------------
## Adaptive music (spec §13B): a base loop plus an intensity layer that fades in
## as the lobby thins out.
##
## Synthesised like the SFX, but generated LAZILY rather than at boot — a 4-bar
## stereo-less loop is ~200k samples and building three of them up front is a
## visible hitch. The arena loading screen is the natural place to hide it.
##
## Written in A minor pentatonic over Am-F-C-G. Pentatonic because there is no
## wrong note in it: procedural melody cannot land on a semitone clash, which is
## what makes generated music sound broken rather than merely simple.
const MUSIC_BPM := 100.0
const MUSIC_BARS := 4
const SCALE := [0, 3, 5, 7, 10]              # minor pentatonic, semitones
const PROGRESSION := [0, -4, 3, -2]          # Am, F, C, G as root offsets

var _music: Dictionary = {}
var _music_player: AudioStreamPlayer
var _intensity_player: AudioStreamPlayer
var _current_track := ""
var _intensity := 0.0
var _intensity_target := 0.0


## Builds a track if it does not exist yet. Safe to call repeatedly.
func ensure_music(track: String) -> void:
	if _music.has(track):
		return
	match track:
		"menu": _music["menu"] = _wav_loop(_music_bed(0.45, false))
		"game": _music["game"] = _wav_loop(_music_bed(0.8, false))
		"intensity": _music["intensity"] = _wav_loop(_music_bed(1.0, true))


func play_music(track: String) -> void:
	if not _unlocked or _current_track == track:
		return
	ensure_music(track)
	if not _music.has(track):
		return
	_current_track = track
	_music_player.stream = _music[track]
	_music_player.play()
	# The intensity layer runs in lockstep with the bed so they stay phase-aligned
	# — starting it later would put the two loops out of sync permanently.
	if _music.has("intensity"):
		_intensity_player.stream = _music["intensity"]
		_intensity_player.play()


func stop_music() -> void:
	_current_track = ""
	_music_player.stop()
	_intensity_player.stop()


## 0 = calm, 1 = sudden death. Ramped in _process so it never snaps.
func set_intensity(value: float) -> void:
	_intensity_target = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	_intensity = move_toward(_intensity, _intensity_target, delta * 0.6)
	if _intensity_player != null:
		_intensity_player.volume_db = linear_to_db(maxf(0.0001, _intensity * 0.5))


## One loopable bar-aligned bed. `drive` adds the sudden-death layer.
func _music_bed(level: float, drive: bool) -> PackedFloat32Array:
	var beats := MUSIC_BARS * 4
	var seconds := beats * 60.0 / MUSIC_BPM
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)

	var beat_samples := int(MIX_RATE * 60.0 / MUSIC_BPM)
	var lp := 0.0

	for i in n:
		var beat := i / beat_samples
		# Bar index drives the chord; beat-in-bar drives the arp step.
		var bar: int = (beat / 4) % PROGRESSION.size()
		var root: float = 110.0 * pow(2.0, PROGRESSION[bar] / 12.0)
		var t := float(i) / MIX_RATE
		var v := 0.0

		# Bass: root, held for the bar, with a soft attack each bar.
		var bar_pos: float = fmod(t, seconds / MUSIC_BARS) / (seconds / MUSIC_BARS)
		v += sin(TAU * root * t) * 0.5 * (0.35 + 0.65 * exp(-bar_pos * 2.0))

		# Pad: a fifth above, very quiet, to stop the bass sounding bare.
		v += sin(TAU * root * 1.5 * t) * 0.12

		# Arp: eighth notes walking the pentatonic.
		var step: int = int(t / (30.0 / MUSIC_BPM)) % SCALE.size()
		var arp: float = root * 4.0 * pow(2.0, SCALE[step] / 12.0)
		var env: float = 1.0 - fmod(t, 30.0 / MUSIC_BPM) / (30.0 / MUSIC_BPM)
		v += asin(sin(TAU * arp * t)) * (2.0 / PI) * 0.10 * env * env

		# --- percussion ---------------------------------------------------
		# The bed had bass, pad and arp but no rhythm, which is why it read as a
		# drone rather than a loop. Everything here is struck metal and a low
		# thump, because the game is set in a scrapyard — a synth drum kit would
		# belong to a different product.
		var beat_len := 60.0 / MUSIC_BPM
		var beat_pos: float = fmod(t, beat_len) / beat_len
		var beat_in_bar: int = beat % 4

		# Kick on 1 and 3: a pitch-dropping sine, which is the whole trick.
		if beat_in_bar == 0 or beat_in_bar == 2:
			var kd: float = exp(-beat_pos * 11.0)
			var kf: float = 92.0 * (1.0 + 2.2 * exp(-beat_pos * 26.0))
			v += sin(TAU * kf * fmod(t, beat_len)) * 0.42 * kd

		# Anvil on 2 and 4 — inharmonic partials, the same trick as _metal(),
		# so the backbeat is a struck object rather than a snare.
		if beat_in_bar == 1 or beat_in_bar == 3:
			var ad: float = exp(-beat_pos * 15.0)
			var hit := 0.0
			for k in [1.0, 2.76, 5.4]:
				hit += sin(TAU * 620.0 * k * fmod(t, beat_len))
			v += hit * 0.055 * ad

		# Offbeat tick: eighth notes between the beats, quiet, to carry the pulse
		# through the long bass notes.
		var eighth: float = fmod(t + beat_len * 0.5, beat_len) / beat_len
		v += sin(TAU * 2400.0 * t) * 0.02 * exp(-eighth * 30.0)

		if drive:
			# Sudden death: a pulse on every beat and an octave-up arp.
			var pulse: float = 1.0 - fmod(t, 60.0 / MUSIC_BPM) / (60.0 / MUSIC_BPM)
			v += sin(TAU * root * 0.5 * t) * 0.35 * pulse * pulse
			v += (1.0 if sin(TAU * arp * 2.0 * t) > 0.0 else -1.0) * 0.05 * env

		# One-pole lowpass: takes the edge off the square/tri harmonics so the
		# bed sits under the SFX instead of fighting them.
		lp += 0.22 * (v - lp)
		out[i] = clampf(lp * level * 0.55, -1.0, 1.0)

	# Fade the seam. Even bar-aligned loops click if the waveform is not near
	# zero at the join.
	var fade := int(MIX_RATE * 0.02)
	for i in fade:
		var k := float(i) / fade
		out[i] *= k
		out[n - 1 - i] *= k
	return out


## Duck everything under an ad or an interruption, and restore afterwards.
## Ads play their own audio; leaving the game mixing over them is the single
## most common ad-integration complaint.
func duck(on: bool) -> void:
	var master := AudioServer.get_bus_index("Master")
	if master == -1:
		return
	AudioServer.set_bus_volume_db(master, -24.0 if on else 0.0)
	if on:
		set_hum(0.0)


# --- synthesis -------------------------------------------------------------
## Prefers a real recorded sound over the synthesised one, per name.
##
## I cannot license or download audio, so the deliverable here is the SEAM, not the
## pack: drop `foo.wav`/`foo.ogg` into `assets/sfx/` and it replaces the generated
## `foo` with no code change. Same shape as AssetLibrary does for meshes. Until a
## pack exists every name falls through to synthesis, and the boot line says how
## many of each were used so a half-installed pack is visible rather than silent.
const SFX_DIR := "res://assets/sfx"


func _load_authored(name: String) -> AudioStream:
	for ext in [".wav", ".ogg", ".mp3"]:
		var path := "%s/%s%s" % [SFX_DIR, name, ext]
		if ResourceLoader.exists(path):
			var res := ResourceLoader.load(path)
			if res is AudioStream:
				return res
	return null


## Swaps in anything authored, and reports the split.
func _apply_authored() -> void:
	var authored := 0
	for name: String in _sfx.keys():
		var real := _load_authored(name)
		if real != null:
			_sfx[name] = real
			authored += 1
	print("[polarity] sfx: %d authored, %d synthesised"
			% [authored, _sfx.size() - authored])


func _build_sfx() -> void:
	# Every impact is struck metal now. The pitch tells you the size of the thing
	# that was hit, which a sweep never did.
	_sfx["absorb"] = _wav(_mix(_metal(1240.0, 0.09, 3.4, 3),
			_noise(0.02, 9.0, 0.5), 0.25))
	_sfx["absorb_big"] = _wav(_mix(_sweep(420.0, 1180.0, 0.20, "sine", 2.2),
			_sweep(210.0, 590.0, 0.20, "square", 2.2), 0.35))
	_sfx["launch"] = _wav(_mix(_sweep(560.0, 70.0, 0.34, "sine", 1.6),
			_noise(0.34, 4.5, 0.28), 0.55))
	# A heavy clang with a low body under it — the one sound that should feel like
	# mass leaving the arena.
	_sfx["eliminate"] = _wav(_mix(_mix(_metal(196.0, 0.55, 1.15, 5),
			_noise(0.05, 7.0, 0.35), 0.35), _sweep(150.0, 48.0, 0.40, "sine", 2.2), 0.5))
	_sfx["hit"] = _wav(_mix(_metal(330.0, 0.18, 2.6, 4), _noise(0.03, 8.0, 0.4), 0.3))
	_sfx["charge_ready"] = _wav(_metal(1560.0, 0.07, 4.5, 2))
	_sfx["ui_tap"] = _wav(_sweep(680.0, 680.0, 0.04, "sine", 6.0))
	# Growth is a bright ring, not a rising beep.
	_sfx["size_up"] = _wav(_mix(_metal(660.0, 0.30, 1.8, 4),
			_sweep(440.0, 990.0, 0.22, "sine", 2.0), 0.35))
	_sfx["alarm"] = _wav(_alternating(820.0, 540.0, 0.44, 0.07))
	_sfx["reward"] = _wav(_arp([523.0, 659.0, 784.0, 1046.0], 0.09))
	_sfx["win"] = _wav(_arp([523.0, 659.0, 784.0, 1046.0, 1318.0], 0.12))
	_sfx["lose"] = _wav(_arp([440.0, 349.0, 262.0], 0.16))
	_sfx["hum"] = _wav_loop(_hum_wave(0.5, 118.0))


func _wav(frames: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		bytes.encode_s16(i * 2, int(clampf(frames[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = int(MIX_RATE)
	s.stereo = false
	s.data = bytes
	return s


func _wav_loop(frames: PackedFloat32Array) -> AudioStreamWAV:
	var s := _wav(frames)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = frames.size() - 1
	return s


## Frequency sweep f0 -> f1 with an exponential decay envelope.
func _sweep(f0: float, f1: float, dur: float, wave: String, decay: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq: float = lerpf(f0, f1, t * t if f1 < f0 else t)
		phase += TAU * freq / MIX_RATE
		var v := 0.0
		match wave:
			"square": v = 1.0 if sin(phase) > 0.0 else -1.0
			"tri": v = asin(sin(phase)) * (2.0 / PI)
			_: v = sin(phase)
		# Short attack removes the click on note-on.
		var atk: float = minf(1.0, float(i) / maxf(1.0, MIX_RATE * 0.004))
		out[i] = v * atk * exp(-decay * t * 3.0)
	return out


## Ideal-bar mode ratios. Not small integers on purpose: a harmonic series sounds
## like a musical note, an INHARMONIC one sounds like something metal was struck.
## These are the classic transverse modes of a free bar.
const BAR_MODES := [1.0, 2.756, 5.404, 8.933, 13.34]


## Struck metal. Every impact in this game was a sine or square sweep, which is a
## beep — the single change that separates "synthesised" from "something hit a steel
## nut" is inharmonic partials with independent decay rates, high ones dying first.
## That gives the bright tick-then-hum a real fastener makes.
func _metal(freq: float, dur: float, decay: float, modes := 4) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var count: int = mini(modes, BAR_MODES.size())
	var phases := PackedFloat32Array()
	phases.resize(count)
	var norm := 0.0
	for k in count:
		norm += 1.0 / (1.0 + float(BAR_MODES[k]) * 0.6)
	for i in n:
		var t := float(i) / n
		var v := 0.0
		for k in count:
			var r: float = BAR_MODES[k]
			phases[k] += TAU * freq * r / MIX_RATE
			v += sin(phases[k]) * exp(-decay * (1.0 + r * 0.5) * t * 3.0) \
					/ (1.0 + r * 0.6)
		# 1.5ms attack: fast enough to read as a strike, long enough not to click.
		var atk: float = minf(1.0, float(i) / maxf(1.0, MIX_RATE * 0.0015))
		out[i] = (v / maxf(0.001, norm)) * atk
	return out


func _noise(dur: float, decay: float, lowpass: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y += lowpass * (randf_range(-1.0, 1.0) - y)  # one-pole lowpass
		out[i] = y * exp(-decay * t * 3.0)
	return out


func _alternating(fa: float, fb: float, dur: float, step: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var freq := fa if fmod(t, step * 2.0) < step else fb
		phase += TAU * freq / MIX_RATE
		out[i] = (1.0 if sin(phase) > 0.0 else -1.0) * 0.5
	return out


func _arp(notes: Array, note_dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f: float in notes:
		out.append_array(_sweep(f, f, note_dur, "sine", 1.8))
	return out


func _hum_wave(dur: float, freq: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# Frequency chosen so exactly `cycles` fit the buffer — otherwise the loop clicks.
	var cycles := roundf(dur * freq)
	for i in n:
		var p := TAU * cycles * float(i) / n
		out[i] = (sin(p) * 0.6 + sin(p * 2.0) * 0.25 + sin(p * 3.01) * 0.1) * 0.7
	return out


## Adds `b` into `a` at `gain`, matching lengths.
func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var va := a[i] if i < a.size() else 0.0
		var vb := b[i] if i < b.size() else 0.0
		out[i] = clampf(va + vb * gain, -1.0, 1.0)
	return out
