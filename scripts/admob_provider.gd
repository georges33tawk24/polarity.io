class_name AdMobProvider
extends RefCounted
## AdMob, behind the Ads/Platform seam.
##
## Nothing above this file knows AdMob exists: `Ads` decides WHETHER an ad may
## show (caps, cooldowns, consent, no-ads entitlement) and this decides how to
## show one. That split is why the null provider can keep reporting honest
## failures on desktop and web while this handles mobile.
##
## ## Test ad units
##
## Non-release builds always use Google's public test units, never the real ones.
## Clicking your own live ad — which is trivially easy while testing a rewarded
## flow — is invalid traffic, and it gets AdMob accounts suspended. `OS.is_debug_build()`
## is the switch, so an exported release build is the only thing that can ever
## request a real ad.

const APP_ID_KEY := "ads.android_app_id"

var _rewarded_ad: RewardedAd = null
var _rewarded_loading := false
var _interstitial_ad: InterstitialAd = null
var _interstitial_loading := false
var _ready := false

## Set while an ad is on screen, so a second placement cannot fire into the
## first one's callback.
var _pending: Callable = Callable()


func _init() -> void:
	# UMP first, SDK second. Google requires a certified consent flow before ads
	# are served in the EEA and UK, and the SDK must not initialise ahead of the
	# player's answer. Outside those regions UMP reports NOT_REQUIRED and this
	# costs one callback.
	_request_consent()


func available() -> bool:
	return _ready


# --- consent (UMP) ----------------------------------------------------------

var _consent := ConsentInformation.new()


## Asks UMP whether a form is needed, shows it if so, then starts the SDK.
##
## The game removed its own hand-rolled consent screen a while back, with a note
## that `Ads.needs_consent()` was the switch to bring one back "if an ad network
## demands its own". AdMob does, and this is that form — Google's, not ours,
## because only a certified CMP satisfies the requirement.
func _request_consent() -> void:
	var params := ConsentRequestParameters.new()
	_consent.update(params,
			func() -> void:
				if _consent.get_is_consent_form_available() \
						and _consent.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
					_show_form()
				else:
					_start_sdk(),
			func(err: FormError) -> void:
				# Consent lookup failed (usually no network). Start the SDK anyway:
				# it will serve non-personalised ads or none at all, which is the
				# safe side of the line.
				push_warning("[admob] consent update failed: %s" % err.message)
				_start_sdk())


func _show_form() -> void:
	UserMessagingPlatform.load_consent_form(
			func(form: ConsentForm) -> void:
				form.show(func(_e: FormError) -> void: _start_sdk()),
			func(err: FormError) -> void:
				push_warning("[admob] consent form failed: %s" % err.message)
				_start_sdk())


func _start_sdk() -> void:
	MobileAds.initialize()
	_ready = true
	# Pre-load both. A rewarded ad requested at the moment the player taps is an
	# ad that arrives after they have stopped caring.
	preload_rewarded()
	preload_interstitial()


## Google's public test units in any non-release build. See the note at the top.
func _unit(kind: String) -> String:
	var key := "ads.android_" + kind
	if OS.is_debug_build():
		key = "ads.test_" + kind
	return String(Config.get_value(key, ""))


# --- rewarded ---------------------------------------------------------------

func rewarded_ready() -> bool:
	return _rewarded_ad != null


func preload_rewarded() -> void:
	if _rewarded_ad != null or _rewarded_loading:
		return
	var unit := _unit("rewarded")
	if unit == "":
		return
	_rewarded_loading = true
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded_loading = false
		_rewarded_ad = ad
	cb.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		_rewarded_loading = false
		_rewarded_ad = null
		push_warning("[admob] rewarded failed to load: %s" % err.message)
	RewardedAdLoader.new().load(unit, AdRequest.new(), cb)


## `cb` receives true ONLY when AdMob reports the reward was earned. Every other
## path — no fill, dismissed early, error — calls back false. A provider that
## granted on dismissal would mint currency for closing a dialog.
func show_rewarded(cb: Callable) -> void:
	if _rewarded_ad == null:
		preload_rewarded()
		cb.call(false)
		return
	if _pending.is_valid():
		cb.call(false)
		return

	var ad := _rewarded_ad
	_rewarded_ad = null
	_pending = cb
	var earned := [false]

	var content := FullScreenContentCallback.new()
	# Fires whether or not the reward was earned, so it is the one place that can
	# guarantee the caller always hears back exactly once.
	content.on_ad_dismissed_full_screen_content = func() -> void:
		ad.destroy()
		_finish(bool(earned[0]))
		preload_rewarded()
	content.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		ad.destroy()
		_finish(false)
		preload_rewarded()
	ad.full_screen_content_callback = content

	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_reward: RewardedItem) -> void:
		# The amount and item AdMob returns are deliberately ignored: what the
		# player gets depends on the PLACEMENT, which only the game knows.
		earned[0] = true
	ad.show(listener)


func _finish(earned: bool) -> void:
	var cb := _pending
	_pending = Callable()
	if cb.is_valid():
		cb.call(earned)


# --- interstitial -----------------------------------------------------------

func preload_interstitial() -> void:
	if _interstitial_ad != null or _interstitial_loading:
		return
	var unit := _unit("interstitial")
	if unit == "":
		return
	_interstitial_loading = true
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_interstitial_loading = false
		_interstitial_ad = ad
	cb.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		_interstitial_loading = false
		_interstitial_ad = null
		push_warning("[admob] interstitial failed to load: %s" % err.message)
	InterstitialAdLoader.new().load(unit, AdRequest.new(), cb)


func show_interstitial() -> void:
	if _interstitial_ad == null:
		preload_interstitial()
		return
	var ad := _interstitial_ad
	_interstitial_ad = null
	var content := FullScreenContentCallback.new()
	content.on_ad_dismissed_full_screen_content = func() -> void:
		ad.destroy()
		preload_interstitial()
	content.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		ad.destroy()
		preload_interstitial()
	ad.full_screen_content_callback = content
	ad.show()
