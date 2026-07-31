class_name PlayBillingProvider
extends StoreProvider
## Google Play Billing, behind the Store seam.
##
## `Store` owns the catalogue, the grants and the ledger; this owns talking to
## Play. That split is what lets the null provider keep reporting honest failures
## on every other platform.
##
## ## Consumables vs entitlements
##
## Coin and gem packs are consumables: they must be CONSUMED after granting or
## Play considers them still owned and the player can never buy that pack again.
## `remove_ads`, `starter_pack` and `vip` are entitlements: they must be
## ACKNOWLEDGED within three days or Play automatically refunds them. Getting
## these two backwards is the classic billing bug — it either blocks repeat
## purchases or silently refunds real money — so the product type drives it,
## read from store.json rather than hardcoded here.
##
## ## Receipt validation
##
## Still client-side. The purchase token is passed up as the receipt so a future
## server can verify it, but nothing verifies it today — a modified client can
## grant itself entitlements. Documented rather than papered over; the fix is an
## Edge Function against Play's Developer API, and it is the same outstanding
## item as AdMob's server-side reward verification.

var _client: BillingClient
var _connected := false
## product_id -> localised price string from Play.
var _prices: Dictionary = {}
## product_id -> Callable, for the purchase currently in flight.
var _pending: Dictionary = {}


func _ready() -> void:
	_client = BillingClient.new()
	add_child(_client)
	_client.connected.connect(_on_connected)
	_client.disconnected.connect(func() -> void: _connected = false)
	_client.connect_error.connect(func(code: int, msg: String) -> void:
		_connected = false
		push_warning("[iap] billing connect failed %d: %s" % [code, msg]))
	_client.query_product_details_response.connect(_on_details)
	_client.on_purchase_updated.connect(_on_purchase_updated)
	_client.query_purchases_response.connect(_on_purchases_queried)
	_client.start_connection()


func available() -> bool:
	return _connected and _client != null and _client.is_ready()


func _on_connected() -> void:
	_connected = true
	# Tie purchases to the player's account id so a support request can be traced
	# without asking them for anything personal.
	if Backend.account_id != "":
		_client.set_obfuscated_account_id(Backend.account_id)
	var ids := PackedStringArray()
	for p: Dictionary in Store.products(true):
		ids.append(String(p.get("id", "")))
	if not ids.is_empty():
		_client.query_product_details(ids, BillingClient.ProductType.INAPP)
	# Anything owned but never granted — a purchase that completed while the app
	# was being killed, which is exactly when players lose what they paid for.
	_client.query_purchases(BillingClient.ProductType.INAPP)


func _on_details(response: Dictionary) -> void:
	for d: Variant in response.get("product_details_list", []):
		if not (d is Dictionary):
			continue
		var det: Dictionary = d
		var id := String(det.get("product_id", ""))
		# Play nests the formatted price; fall back through the shapes rather
		# than assuming one, since an empty price shows the catalogue default.
		var offer: Variant = det.get("one_time_purchase_offer_details", {})
		if offer is Dictionary:
			var price := String((offer as Dictionary).get("formatted_price", ""))
			if id != "" and price != "":
				_prices[id] = price


func price_string(product_id: String) -> String:
	return String(_prices.get(product_id, ""))


func purchase(product_id: String, cb: Callable) -> void:
	if not available():
		cb.call(false, "")
		return
	_pending[product_id] = cb
	var res := _client.purchase(product_id)
	# A non-OK response means the flow never opened, so no signal is coming and
	# the caller would wait forever.
	var code := int(res.get("response_code", BillingClient.BillingResponseCode.OK))
	if code != BillingClient.BillingResponseCode.OK:
		_pending.erase(product_id)
		push_warning("[iap] purchase %s refused: %d" % [product_id, code])
		cb.call(false, "")


func _on_purchase_updated(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	var list: Array = response.get("purchases", [])

	if code != BillingClient.BillingResponseCode.OK:
		# User cancelled, or the flow failed. Fail every purchase in flight —
		# leaving one pending would hang the shop's spinner forever.
		for id: String in _pending.keys():
			var cb: Callable = _pending[id]
			if cb.is_valid():
				cb.call(false, "")
		_pending.clear()
		return

	for entry: Variant in list:
		if entry is Dictionary:
			_settle(entry as Dictionary)


## Purchases found by query_purchases at startup. Same settlement path: one of
## these is a purchase the player already paid for that never got granted.
func _on_purchases_queried(response: Dictionary) -> void:
	for entry: Variant in response.get("purchases", []):
		if entry is Dictionary:
			_settle(entry as Dictionary)


func _settle(purchase_data: Dictionary) -> void:
	if int(purchase_data.get("purchase_state", 0)) != BillingClient.PurchaseState.PURCHASED:
		return   # PENDING — the player has not actually paid yet.
	var token := String(purchase_data.get("purchase_token", ""))
	var ids: Array = purchase_data.get("products", [])
	for raw: Variant in ids:
		var id := String(raw)
		var product := Store.product(id)
		if product.is_empty():
			continue

		var cb: Callable = _pending.get(id, Callable())
		_pending.erase(id)
		if cb.is_valid():
			cb.call(true, token)
		elif not Store.owns(id):
			# Arrived without anyone waiting — a purchase completed while the app
			# was closed. Grant it anyway; the player paid.
			Store.purchase_finished.emit(id, Store.Result.SUCCESS)
			Store._grant(id, token)

		# Consume or acknowledge, driven by the catalogue. See the note at the top.
		if String(product.get("type", "")) == "consumable":
			_client.consume_purchase(token)
		elif not bool(purchase_data.get("is_acknowledged", false)):
			_client.acknowledge_purchase(token)


func restore(cb: Callable) -> void:
	if not available():
		cb.call([])
		return
	# query_purchases settles through the same path, so restoring is a re-query;
	# what it returns here is what Play already told us is owned.
	_client.query_purchases(BillingClient.ProductType.INAPP)
	var owned: Array = []
	for p: Dictionary in Store.products(true):
		var id := String(p.get("id", ""))
		if Store.owns(id):
			owned.append(id)
	cb.call(owned)
