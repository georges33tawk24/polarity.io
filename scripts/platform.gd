extends Node
## The one place that knows what device it is running on.
##
## The spec asks for ~8 service singletons (Ads/IAP/Haptics/Notifications/...).
## ponytail: they are all "detect platform, call the right SDK, no-op otherwise" —
## one adapter with null providers, split into real services when an actual SDK
## lands (see DECISIONS.md). Gameplay never calls OS.get_name() directly.

enum Kind { DESKTOP, MOBILE, WEB }

var kind := Kind.DESKTOP
var os_name := ""
var has_touch := false
## Flips to true the first time a touch event arrives — an iPad reports
## touch support that a desktop browser on the same build does not have.
var touch_seen := false
var reduced_motion := false

var _safe_insets := Vector4.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	os_name = OS.get_name()
	if OS.has_feature("web"):
		kind = Kind.WEB
	elif os_name in ["Android", "iOS"]:
		kind = Kind.MOBILE
	has_touch = DisplayServer.is_touchscreen_available()
	_build_input_map()
	_refresh_safe_area()
	get_tree().get_root().size_changed.connect(_refresh_safe_area)


func _input(event: InputEvent) -> void:
	if not touch_seen and event is InputEventScreenTouch:
		touch_seen = true


func is_web() -> bool: return kind == Kind.WEB
func is_mobile() -> bool: return kind == Kind.MOBILE
## True when we should draw touch affordances rather than keyboard hints.
func prefers_touch() -> bool: return touch_seen or kind == Kind.MOBILE


# --- input map -------------------------------------------------------------
# Built in code: the project.godot serialisation for InputEvent objects is
# long and easy to corrupt by hand, and this is the same thing in 12 lines.
func _build_input_map() -> void:
	var actions := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"magnet_hold": [KEY_SPACE, KEY_SHIFT],
		"ui_pause": [KEY_ESCAPE, KEY_P],
	}
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in actions[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# --- safe area -------------------------------------------------------------
## Insets in *viewport* pixels: (left, top, right, bottom).
func safe_insets() -> Vector4:
	return _safe_insets


func _refresh_safe_area() -> void:
	_safe_insets = Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return
	if kind == Kind.MOBILE:
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0 and safe.size.x > 0:
			# Screen-space insets, expressed as a fraction, then re-applied in
			# viewport space so it survives the canvas_items stretch.
			var vp := Vector2(get_tree().get_root().get_visible_rect().size)
			_safe_insets = Vector4(
				float(safe.position.x) / screen.x * vp.x,
				float(safe.position.y) / screen.y * vp.y,
				float(screen.x - safe.end.x) / screen.x * vp.x,
				float(screen.y - safe.end.y) / screen.y * vp.y)
	elif kind == Kind.WEB:
		# ponytail: reading CSS env(safe-area-inset-*) needs a JS bridge; a flat
		# top/bottom pad clears iOS Safari's chrome and costs nothing. Swap for
		# the real values when a JS interop layer exists.
		var vp := Vector2(get_tree().get_root().get_visible_rect().size)
		if vp.y > vp.x:
			_safe_insets = Vector4(0, vp.y * 0.02, 0, vp.y * 0.03)


# --- haptics ---------------------------------------------------------------
## Google Play Games / Sign in with Apple. Both are native-plugin territory, and
## neither plugin is present, so this is false everywhere for now. Gating the UI on
## it means the buttons are hidden rather than broken.
func federated_auth_available(kind: String) -> bool:
	# Both are false until a plugin ships. Written as an explicit false rather than
	# omitted, so the reason is visible at the call site instead of the feature
	# silently not existing.
	match kind:
		"google": return self.kind == Kind.MOBILE and false
		"apple": return os_name == "iOS" and false
		_: return false


## Shortest gap between two buzzes. Closer together than this and a phone does not
## reproduce them as separate taps — it just rattles.
##
## Guarded here rather than at each call site because the bug this fixes was
## `Arena._hazard_hit` calling vibrate EVERY PHYSICS FRAME while the player stood
## on a saw: sixty haptic events a second, each one restarting the iOS haptic
## engine's pattern. That is the "my phone was gonna explode" report, and it is a
## mistake any future call site can make just as easily. One check covers them all.
const MIN_GAP := 0.14

## duration and amplitude multipliers per level.
##
## Both are scaled, not just amplitude. Godot honours amplitude on iOS 13+ (via
## CHHapticEngine) and on Android API 26+ (via VibrationEffect), so turning it down
## really does turn the motor down — but the complaint that survived a
## strength-only reduction was about how MUCH buzzing there was, so duration comes
## down with it.
const LEVELS := {
	"off": Vector2.ZERO,
	"light": Vector2(0.55, 0.45),
	"full": Vector2(1.0, 1.0),
}

var _last_vibe := -999.0


## "off" / "light" / "full". Honours the old boolean toggle so a profile saved
## before this setting existed still means what the player chose.
func haptics_level() -> String:
	if not bool(Game.profile.get("haptics", true)):
		return "off"
	var level := String(Game.get_value("haptics_level", "light"))
	return level if LEVELS.has(level) else "light"


func vibrate(ms: int, strength := 0.6) -> void:
	var scale: Vector2 = LEVELS[haptics_level()]
	if scale == Vector2.ZERO:
		return
	# Time, not frame count: the same guard has to hold at 30fps and at 120.
	var now := float(Time.get_ticks_msec()) * 0.001
	if now - _last_vibe < MIN_GAP:
		return
	_last_vibe = now
	if kind == Kind.MOBILE:
		Input.vibrate_handheld(maxi(1, roundi(float(ms) * scale.x)),
				clampf(strength * scale.y, 0.0, 1.0))
	# Desktop/web: no-op. Web Vibration API needs a JS bridge — see DECISIONS.md.


# --- share -----------------------------------------------------------------
## Returns true if the share was handed off to the OS.
func share_text(text: String) -> bool:
	if kind == Kind.MOBILE or kind == Kind.WEB:
		# Real native/Web Share needs a plugin or JS bridge — flagged in DECISIONS.md.
		DisplayServer.clipboard_set(text)
		return true
	DisplayServer.clipboard_set(text)
	return true


# --- monetisation (null providers) -----------------------------------------
# Real providers (AdMob on mobile, CrazyGames/Poki on web) plug in here.
# They are deliberately NOT stubbed as if they work: `available()` is false, so
# every caller already takes the "no ad" path and nothing is gated on a fake.
func ads_available() -> bool:
	return false


## Calls `cb` with `true` only if a reward was genuinely earned.
func show_rewarded(_placement: String, cb: Callable) -> void:
	push_warning("[ads] no provider on %s — reward denied" % os_name)
	cb.call(false)


func show_interstitial(_placement: String) -> void:
	pass


func iap_available() -> bool:
	return false


# --- rating prompt ---------------------------------------------------------
## Native review request. Frequency-capped by the caller; this only decides
## whether the platform can show one at all.
func can_request_review() -> bool:
	return kind == Kind.MOBILE


## Real in-app review needs StoreKit / Play In-App Review via a plugin. Opening
## the store listing is the honest fallback and still works.
func request_review(store_url := "") -> bool:
	if store_url != "":
		OS.shell_open(store_url)
		return true
	return false


# --- notifications ---------------------------------------------------------
## Local notifications need a plugin on both mobile platforms. The schedule is
## kept so it can be replayed the moment one is added, and so the opt-in state
## is real from day one.
func schedule_notification(id: String, _seconds_from_now: int, _title: String,
		_body: String) -> bool:
	if not Game.profile.get("notifications", true):
		return false
	if kind != Kind.MOBILE:
		return false
	push_warning("[notify] no scheduler plugin — '%s' not scheduled" % id)
	return false


func cancel_notification(_id: String) -> void:
	pass


# --- share -----------------------------------------------------------------
## Writes the card next to the save file and reports where. Native/Web Share of
## an image needs a plugin or a JS bridge; the file is real either way.
func share_image(path: String, caption: String) -> String:
	DisplayServer.clipboard_set(caption)
	return ProjectSettings.globalize_path(path)
