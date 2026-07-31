extends Node
## Ads: consent state, placements, frequency capping and provider routing.
##
## No ad SDK is wired (no vendor account — spec §16). The provider is Null and
## `available()` reports false, so every caller already takes the no-ad path.
## What IS real and testable: the consent gate, the frequency caps, the daily
## rewarded cap, and the rule that a reward is only granted on a genuine
## completion callback.
##
## Nothing here may gate core play (spec §4.4).

enum Consent { UNKNOWN, GRANTED_PERSONALISED, GRANTED_NON_PERSONALISED, DENIED }

signal consent_resolved(state: Consent)

var consent := Consent.UNKNOWN
var _interstitial_last := 0
var _matches_since_interstitial := 0
var _rewarded_today := 0
var _rewarded_day := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved := int(Game.get_value("consent", Consent.UNKNOWN))
	consent = saved as Consent
	_rewarded_day = int(Game.get_value("rewarded_day", -1))
	_rewarded_today = int(Game.get_value("rewarded_count", 0))
	Bus.match_ended.connect(func(_r: Dictionary) -> void: _matches_since_interstitial += 1)


# --- consent ---------------------------------------------------------------
## True when we must show the consent flow before initialising any ad SDK.
## Always false. There is no consent screen any more: ads are contextual-only for
## everyone (see personalised_allowed), and a contextual ad needs no permission to
## show. The player's control is the ADS toggle in Settings, which is a better place
## for it than a modal on first launch.
##
## IMPORTANT for whoever wires a real ad network: AdMob's UMP and several EEA
## partners require their OWN consent flow before the first request. Turning this
## back on is how you reinstate it — the dialog builder is gone, but this is the
## switch that used to summon it.
func needs_consent() -> bool:
	return false


func set_consent(state: Consent) -> void:
	consent = state
	Game.set_value("consent", int(state))
	Analytics.track("consent_set", {"state": int(state)})
	consent_resolved.emit(state)
	# A real SDK initialises HERE and nowhere earlier (spec §4.4).
	if state != Consent.DENIED:
		_init_provider()


## Always false. The age gate was removed at the user's request, which means the
## game can no longer know whether a player is under 13 — so behavioural targeting
## is off for everyone rather than for the people who admitted their age. This is
## the standard "mixed audience, contextual ads only" position and it is what keeps
## the build COPPA-safe without a gate. Turning this back on REQUIRES restoring an
## age gate first.
func personalised_allowed() -> bool:
	return false


## Retained so a publisher requirement can reinstate a gate by writing this value,
## but nothing sets it any more — see personalised_allowed().
func is_child() -> bool:
	var age := int(Game.get_value("age_bracket", 0))
	return age == 1


## Nothing is ever UNKNOWN now, because no screen asks. Treat an unset record as
## "contextual ads allowed" rather than as a pending question.
func _default_consent() -> Consent:
	return Consent.GRANTED_NON_PERSONALISED


func _init_provider() -> void:
	# AdMob on mobile; web (CrazyGames / Poki) still has no vendor and stays null.
	# Called from set_consent as well as _ready, because the SDK must not be
	# initialised before the player has answered the consent prompt.
	Platform._init_ads()


# --- availability ----------------------------------------------------------
func available() -> bool:
	if not Config.flag("ads_enabled") or consent == Consent.DENIED:
		return false
	if is_child():
		return false
	# A paid no-ads entitlement removes interstitials and banners entirely.
	# Rewarded video deliberately survives it — it is opt-in and value-positive,
	# and removing it would punish the player who paid.
	if Store.has_no_ads():
		return false
	return Platform.ads_available()


## Rewarded is checked separately so `no_ads` does not take it away.
func _rewarded_base_available() -> bool:
	if not Config.flag("ads_enabled") or consent == Consent.DENIED:
		return false
	if is_child():
		return false
	return Platform.ads_available()


func rewarded_available() -> bool:
	return _rewarded_base_available() and Config.flag("rewarded_enabled") \
			and not _rewarded_capped()


func _rewarded_capped() -> bool:
	_roll_day()
	return _rewarded_today >= Config.int_val("ads.rewarded_daily_cap", 20)


func _roll_day() -> void:
	var day := Meta.today()
	if _rewarded_day != day:
		_rewarded_day = day
		_rewarded_today = 0
		Game.set_value("rewarded_day", day)
		Game.set_value("rewarded_count", 0)


# --- rewarded --------------------------------------------------------------
## `cb` receives true ONLY on a genuine completion. Callers must treat false as
## "no reward" and stay playable — rewarded video is always additive.
func show_rewarded(placement: String, cb: Callable) -> void:
	Analytics.track("ad_request", {"type": "rewarded", "placement": placement})
	if not rewarded_available():
		Analytics.track("ad_unavailable", {"type": "rewarded", "placement": placement})
		cb.call(false)
		return
	_roll_day()
	_rewarded_today += 1
	Game.set_value("rewarded_count", _rewarded_today)
	Audio.duck(true)
	Platform.show_rewarded(placement, func(earned: bool) -> void:
		Audio.duck(false)
		Analytics.track("ad_result", {"type": "rewarded", "placement": placement,
				"earned": earned})
		cb.call(earned))


# --- interstitial ----------------------------------------------------------
## Never during gameplay, never on a first session, never inside the cooldown.
func can_show_interstitial() -> bool:
	if not available() or not Config.flag("interstitials_enabled"):
		return false
	if int(Game.get_value("sessions", 0)) <= Config.int_val("ads.interstitial_skip_first_n_sessions", 1):
		return false
	if int(Game.get_value("matches", 0)) <= Config.int_val("ads.interstitial_skip_first_n_matches", 3):
		return false
	if _matches_since_interstitial < Config.int_val("ads.interstitial_every_n_matches", 3):
		return false
	var since := int(Time.get_unix_time_from_system()) - _interstitial_last
	return since >= Config.int_val("ads.interstitial_min_seconds", 60)


func try_show_interstitial(placement: String) -> bool:
	if not can_show_interstitial():
		return false
	_interstitial_last = int(Time.get_unix_time_from_system())
	_matches_since_interstitial = 0
	Analytics.track("ad_shown", {"type": "interstitial", "placement": placement})
	Audio.duck(true)
	Platform.show_interstitial(placement)
	Audio.duck(false)
	return true


# --- banner ----------------------------------------------------------------
## Web only, and never while a match is being played (spec §4.4).
func banner_allowed(in_match: bool) -> bool:
	return Platform.is_web() and Config.flag("banner_enabled_web") \
			and available() and not in_match
