extends Node
## In-app purchases: catalogue, purchase flow, entitlements, restore and offers.
##
## The billing provider is swappable. The shipped one is Null — it reports
## unavailable and grants nothing, because no store account exists (spec §16).
## Everything above the provider is real: entitlement grants, restore, the
## no-ads entitlement, and segment-driven time-limited offers.
##
## Grants are applied in ONE place (`_grant`), so a real provider and a restore
## both go through the same code that the tests exercise.

const PATH := "res://data/store.json"

enum Result { SUCCESS, CANCELLED, UNAVAILABLE, ALREADY_OWNED, FAILED }

signal purchase_finished(product_id: String, result: Result)
signal entitlements_changed

## Billing seam — see StoreProvider. Lifted out of this file rather than left as
## an inner class: a GDScript inner class CANNOT be extended from another file, so
## the seam could never have had a real implementation. Backend hit this exact
## wall (§12) and the fix is the same.
var provider: StoreProvider = StoreProvider.new()
var _catalogue: Dictionary = {}
var _offers: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_select_provider()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	for p: Dictionary in data.get("products", []):
		_catalogue[String(p.get("id", ""))] = p
	_offers = data.get("offers", [])
	if _catalogue.is_empty():
		push_error("store.json missing or malformed — IAP disabled")


## Google Play Billing on Android when the plugin is present; the null provider
## everywhere else, which reports unavailable and grants nothing rather than
## faking a purchase.
func _select_provider() -> void:
	if Platform.os_name != "Android":
		return
	if not ResourceLoader.exists("res://addons/GodotGooglePlayBilling/plugin.cfg"):
		push_warning("[iap] billing addon missing — purchases unavailable")
		return
	var p := PlayBillingProvider.new()
	add_child(p)
	provider = p


# --- catalogue -------------------------------------------------------------
func products(include_offer_only := false) -> Array:
	var out: Array = []
	for id: String in _catalogue:
		var p: Dictionary = _catalogue[id]
		if bool(p.get("offer_only", false)) and not include_offer_only:
			continue
		out.append(p)
	return out


func product(id: String) -> Dictionary:
	return _catalogue.get(id, {})


func available() -> bool:
	return Config.flag("iap_enabled") and provider.available() and not Ads.is_child()


## Live localised price when the store gives us one, otherwise the config
## fallback. Never claim a currency we have not been told about.
func price_text(id: String) -> String:
	var live := provider.price_string(id)
	if live != "":
		return live
	var usd := float(product(id).get("price_usd", 0.0))
	return "$%.2f" % usd if usd > 0.0 else "—"


# --- entitlements ----------------------------------------------------------
func owned_products() -> Array:
	var list: Variant = Game.get_value("iap_owned", [])
	return list if list is Array else []


func owns(id: String) -> bool:
	return owned_products().has(id)


## The one entitlement that changes behaviour rather than just granting goods.
func has_no_ads() -> bool:
	if bool(Game.get_value("no_ads", false)):
		return true
	for id: String in owned_products():
		if bool(product(id).get("grants", {}).get("no_ads", false)):
			return true
	return false


# --- purchase --------------------------------------------------------------
func purchase(id: String, cb := Callable()) -> void:
	var p := product(id)
	if p.is_empty():
		_finish(id, Result.FAILED, cb)
		return
	if String(p.get("type", "")) != "consumable" and owns(id):
		_finish(id, Result.ALREADY_OWNED, cb)
		return
	if not available():
		Analytics.track("iap_unavailable", {"product": id})
		_finish(id, Result.UNAVAILABLE, cb)
		return

	Analytics.track("iap_start", {"product": id, "segment": Config.segment()})
	provider.purchase(id, func(ok: bool, receipt: String) -> void:
		if not ok:
			_finish(id, Result.CANCELLED, cb)
			return
		# A real build validates `receipt` server-side BEFORE granting. There is
		# no server, so this is the documented gap — see DECISIONS.
		_grant(id, receipt)
		_finish(id, Result.SUCCESS, cb))


## Applies a product's grants. Idempotent for non-consumables.
func _grant(id: String, receipt := "") -> void:
	var p := product(id)
	var grants: Dictionary = p.get("grants", {})
	var consumable := String(p.get("type", "")) == "consumable"

	if not consumable:
		if owns(id):
			return
		var list := owned_products()
		list.append(id)
		Game.set_value("iap_owned", list)

	for key: String in grants:
		match key:
			"coins", "gems":
				Game.add_currency(key, int(grants[key]), "iap_" + id)
			"no_ads":
				Game.set_value("no_ads", true)
			"cosmetic":
				Cosmetics.grant(String(grants[key]))
			"daily_gems":
				pass  # subscription drip, applied by the daily reward path

	Game.set_value("iap_count", int(Game.get_value("iap_count", 0)) + 1)
	Analytics.track("iap_success", {"product": id, "usd": product(id).get("price_usd", 0.0),
			"receipt": receipt.substr(0, 16)})
	entitlements_changed.emit()
	Bus.profile_changed.emit()
	Audio.play("reward", 1.0, -4.0)


func _finish(id: String, result: Result, cb: Callable) -> void:
	if result != Result.SUCCESS:
		Analytics.track("iap_end", {"product": id, "result": int(result)})
	purchase_finished.emit(id, result)
	if cb.is_valid():
		cb.call(result)


## Re-grants every non-consumable the store says this account owns. Required by
## both app stores, and the only recovery path after a reinstall.
func restore(cb := Callable()) -> void:
	if not available():
		if cb.is_valid():
			cb.call(0)
		return
	provider.restore(func(ids: Array) -> void:
		var restored := 0
		for id: Variant in ids:
			var pid := String(id)
			if not _catalogue.has(pid) or owns(pid):
				continue
			_grant(pid, "restored")
			restored += 1
		Analytics.track("iap_restore", {"count": restored})
		if cb.is_valid():
			cb.call(restored))


## Entitlement revocation (refund / chargeback / lapsed subscription). Called by
## a real provider; exposed so the path exists and is tested.
func revoke(id: String) -> void:
	var list := owned_products()
	if not list.has(id):
		return
	list.erase(id)
	Game.set_value("iap_owned", list)
	# Recompute from the remaining entitlements. Asking has_no_ads() here would
	# read the very flag being cleared and always answer "still entitled", so a
	# refunded remove_ads was never actually revoked.
	var still_entitled := false
	for pid: String in list:
		if bool(product(pid).get("grants", {}).get("no_ads", false)):
			still_entitled = true
			break
	Game.set_value("no_ads", still_entitled)
	Analytics.track("iap_revoked", {"product": id})
	entitlements_changed.emit()


# --- offers ----------------------------------------------------------------
## Time-limited offer for the player's current segment. Returns {} when there is
## none, or when the active one has expired.
func active_offer() -> Dictionary:
	var stored: Variant = Game.get_value("offer", {})
	var offer: Dictionary = stored if stored is Dictionary else {}
	var now := int(Time.get_unix_time_from_system())

	if not offer.is_empty():
		if now < int(offer.get("expires", 0)) and not owns(String(offer.get("product", ""))):
			return offer
		Game.set_value("offer", {})

	var segment := Config.segment()
	if segment == "new" and int(Game.get_value("matches", 0)) \
			< Config.int_val("offers.starter_pack_after_matches", 3):
		return {}   # do not sell to someone who has not played yet

	for candidate: Dictionary in _offers:
		var segments: Array = candidate.get("segments", [])
		if not segments.has(segment):
			continue
		var pid := String(candidate.get("product", ""))
		if owns(pid):
			continue
		var fresh := {
			"id": String(candidate.get("id", "")),
			"product": pid,
			"discount_pct": int(candidate.get("discount_pct", 0)),
			"expires": now + int(candidate.get("hours", 24)) * 3600,
		}
		Game.set_value("offer", fresh)
		Analytics.track("offer_shown", {"offer": fresh["id"], "segment": segment})
		return fresh
	return {}


func offer_seconds_left() -> int:
	var offer := active_offer()
	if offer.is_empty():
		return 0
	return maxi(0, int(offer.get("expires", 0)) - int(Time.get_unix_time_from_system()))
