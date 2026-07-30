class_name MetaPanel
extends Control
## Shop, collection, missions and battle pass — the meta screens.
##
## Kept out of `ui.gd` so neither file becomes the God-object the spec warns
## about. Reads catalogues through `Cosmetics` / `Meta`; owns no game state.

signal closed

const TABS := ["shop", "missions", "board", "pass", "store"]

var _tab := "shop"
var _shop_kind := "skin"
var _content: VBoxContainer
var _tab_row: Control
var _scroll: ScrollContainer
var _offer_clock: Label
var _offer_timer: Timer
var _focus_child: Control
var _chips: Array[Control] = []
var _toast_host: Control
var _title: Label
var _board_scope := Backend.Scope.GLOBAL


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Same riveted panels as the menu and the arena floor. This was a light beige
	# fill, which made every meta screen the one bright surface in a dark game and
	# left the text tokens — all tuned for dark — barely legible. The backdrop is
	# opaque, so the daily-reward popup underneath still cannot ghost through.
	add_child(UiKit.backdrop(0.35))

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 18)
	add_child(root)

	# Header: title + live currency chips
	_chips.clear()
	var coins := UiKit.currency_chip("coins")
	var gems := UiKit.currency_chip("gems")
	_chips.append(coins)
	_chips.append(gems)
	# The active nav cell already names the screen, so the title is the wordless
	# anchor rather than a second copy of the same word.
	_title = UiKit.lbl(tr("UI_SHOP"), UiKit.T_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _title
	var header := UiKit.row([title, coins, gems], 24)
	root.add_child(header)

	# A scrolling chip row, not a grid of slabs. Five tabs in a 3-column grid left
	# two ragged holes, and a filled amber slab for the ACTIVE tab spent the
	# accent that is supposed to mean money — nine amber hits on one screen.
	_tab_row = Control.new()
	_tab_row.custom_minimum_size = Vector2(0, 148)
	root.add_child(_tab_row)

	_scroll = ScrollContainer.new()
	var scroll := _scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", UiKit.S3)
	scroll.add_child(_content)

	# BACK was a full-width amber slab at the bottom — on r_shop.png it was the
	# loudest object on the screen, for the least important action. A ghost button
	# in the header is where an exit belongs.
	var back := UiKit.btn_ghost(tr("UI_BACK"), 92)
	back.custom_minimum_size.x = 150
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)
	header.move_child(back, 0)

	_toast_host = Control.new()
	_toast_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_host)

	Bus.profile_changed.connect(_refresh_chips)
	_rebuild()


func open_tab(tab: String) -> void:
	_tab = tab if TABS.has(tab) else "shop"
	_rebuild()


func _refresh_chips() -> void:
	for c in _chips:
		if is_instance_valid(c):
			UiKit.refresh_chip(c)


func _rebuild() -> void:
	var keep_scroll := _scroll.scroll_vertical if _scroll != null else 0
	# The offer clock is about to be freed with the rest of the content.
	_offer_clock = null
	_focus_child = null
	for c in _tab_row.get_children():
		c.queue_free()
	for c in _content.get_children():
		c.queue_free()

	# A full-width bar with a glyph and a caption per cell, not a row of five words.
	# Text-only tabs gave no affordance that they were tappable, and they occupied a
	# fraction of the width so the targets were small and unevenly spaced — swapping
	# between screens was the hardest thing to do on the hardest screen to read.
	var tab_keys := {"shop": "UI_SHOP", "missions": "UI_MISSIONS",
			"board": "UI_LEADERBOARD", "pass": "UI_PASS", "store": "UI_STORE"}
	var tab_glyphs := {"shop": "bag", "missions": "target", "board": "bars",
			"pass": "star", "store": "card"}
	var tab_labels: Array = []
	var glyphs: Array = []
	for tab: String in TABS:
		tab_labels.append(tr(String(tab_keys[tab])))
		glyphs.append(String(tab_glyphs[tab]))
	var bar := UiKit.nav_bar(tab_labels, TABS, glyphs, _tab,
			func(k: String) -> void:
				_tab = k
				_rebuild())
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_row.add_child(bar)

	if _title != null:
		_title.text = tr({"shop": "UI_SHOP", "missions": "UI_MISSIONS",
				"board": "UI_LEADERBOARD", "pass": "UI_PASS", "store": "UI_STORE"}[_tab])
	match _tab:
		"missions": _build_missions()
		"pass": _build_pass()
		"store": _build_store()
		"board": _build_board()
		_: _build_shop()
	_refresh_chips()
	# Deferred, and in its own function: _rebuild() must stay synchronous because
	# open_tab() calls it and depends on the content existing when it returns.
	_settle_scroll.call_deferred(keep_scroll)


## Restores the scroll position a rebuild would otherwise throw away, or jumps to
## the tier the player is actually on. Needs a real layout pass first, so it awaits
## a frame — and re-checks validity afterwards, because a locale change frees this
## whole panel and a resumed coroutine would touch a dead node.
func _settle_scroll(keep: int) -> void:
	await get_tree().process_frame
	if not is_instance_valid(self) or _scroll == null or not is_instance_valid(_scroll):
		return
	if _focus_child != null and is_instance_valid(_focus_child):
		_scroll.scroll_vertical = maxi(0, int(_focus_child.position.y) - 120)
	elif keep > 0:
		_scroll.scroll_vertical = keep


# --- shop / collection -----------------------------------------------------
func _build_shop() -> void:
	# A grid, not a row: five kind buttons side by side overflow a portrait phone
	# and push the whole panel off the right edge.
	var kind_keys := {"skin": "UI_SKINS", "trail": "UI_TRAILS",
			"launch_vfx": "UI_EFFECTS", "nameplate": "UI_NAMEPLATES",
			"arena_theme": "UI_ARENAS"}
	var kind_glyphs := {"skin": "skin", "trail": "trail", "launch_vfx": "effect",
			"nameplate": "plate", "arena_theme": "arena"}
	var kind_labels: Array = []
	var kind_icons: Array = []
	for kind: String in Cosmetics.KINDS:
		kind_labels.append(tr(String(kind_keys.get(kind, "UI_SKINS"))))
		kind_icons.append(String(kind_glyphs.get(kind, "skin")))
	# Same language as the nav bar above it, one step smaller — it is a filter
	# inside a screen rather than navigation between screens.
	_content.add_child(UiKit.nav_bar(kind_labels, Cosmetics.KINDS, kind_icons,
			_shop_kind,
			func(k: String) -> void:
				_shop_kind = k
				_rebuild(), 118))

	var done := Cosmetics.completion()
	_content.add_child(UiKit.lbl("%d / %d" % [done.x, done.y], 32, UiKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT))

	for item: Dictionary in Cosmetics.all_of(_shop_kind):
		_content.add_child(_item_card(item))


func _item_card(item: Dictionary) -> Control:
	var id := String(item["id"])
	var rarity := String(item.get("rarity", "common"))
	var color := Cosmetics.rarity_color(rarity)
	var owned := Cosmetics.is_owned(id)
	var equipped := Cosmetics.equipped(String(item["kind"])) == id

	var card := UiKit.panel(color if owned else Color(color, 0.35), equipped)
	var row := UiKit.row([], UiKit.S3)
	card.custom_minimum_size.y = 150
	card.add_child(row)

	row.add_child(UiKit.cosmetic_preview(item, 96))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 2)
	# Cosmetic names are proper nouns and stay untranslated (DECISIONS §12b).
	text.add_child(UiKit.lbl(String(item.get("name", id)), 40, UiKit.INK))
	# Rarity gets a star as well as a colour — colour alone is not readable for
	# a colourblind player (the shape-redundancy rule in §13A).
	var rarity_row := UiKit.row([
		UiKit.icon("star", 24, color),
		UiKit.lbl(tr(Cosmetics.rarity_key(rarity)), 28, color),
	], 8)
	text.add_child(rarity_row)
	row.add_child(text)

	if not owned:
		row.add_child(UiKit.icon("lock", 30, UiKit.INK_OFF))

	var action: Control
	if equipped:
		# Not a Button. As a dim button this was pixel-identical to the live tab
		# beside it, so a player could not tell what responds to a tap — which is
		# the most basic thing a UI has to communicate.
		action = UiKit.state_tag(tr("UI_EQUIPPED"))
	elif owned:
		var equip_btn := UiKit.btn(tr("UI_EQUIP"), UiKit.SIGNAL_GOOD, 110)
		action = equip_btn
		equip_btn.pressed.connect(func() -> void:
			Cosmetics.equip(String(item["kind"]), id)
			Bus.cosmetic_equipped.emit(String(item["kind"]), id)
			_rebuild())
	else:
		var cost := Cosmetics.price(id)
		var afford := int(Game.get_value("coins", 0)) >= cost
		var buy := UiKit.btn(Locale.number(cost), UiKit.ACCENT, 110) if afford \
				else UiKit.dim_btn(Locale.number(cost), 110)
		# The price carries its currency. "300" alone never said coins, and the
		# store's own gem prices were indistinguishable from coin prices.
		buy.icon = Icons.get_icon("coin")
		buy.expand_icon = false
		buy.add_theme_constant_override("h_separation", 10)
		action = buy
		# A rewarded trial on locked skins only. Nothing to try on a nameplate.
		if String(item.get("kind", "")) == "skin" and Config.flag("trial_enabled") \
				and Ads.rewarded_available() \
				and String(Game.get_value("trial_skin", "")) == "":
			var try_btn := UiKit.btn_ghost(tr("UI_TRY"), 110)
			try_btn.add_theme_font_size_override("font_size", UiKit.T_CAPTION)
			try_btn.custom_minimum_size.x = 130
			try_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			try_btn.pressed.connect(func() -> void:
				Ads.show_rewarded("skin_trial", func(granted: bool) -> void:
					if granted:
						Game.set_value("trial_skin", id)
						_toast(tr("UI_TRY_ACTIVE"))
					else:
						_toast(tr("UI_UNAVAILABLE"))
					_rebuild()))
			row.add_child(try_btn)
		buy.pressed.connect(func() -> void:
			if Cosmetics.purchase(id):
				Cosmetics.equip(String(item["kind"]), id)
				Audio.play("reward", 1.0, -8.0)
				_toast(tr("UI_EQUIPPED"))
				_rebuild()
			else:
				Audio.play("hit", 0.8, -14.0)
				_toast(tr("UI_NOT_ENOUGH")))
	action.custom_minimum_size.x = 260
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(action)
	return card


# --- leaderboard -----------------------------------------------------------
func _build_board() -> void:
	var scopes := GridContainer.new()
	scopes.columns = 4
	scopes.add_theme_constant_override("h_separation", 8)
	scopes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var labels := {
		Backend.Scope.GLOBAL: "UI_GLOBAL", Backend.Scope.FRIENDS: "UI_FRIENDS",
		Backend.Scope.WEEKLY: "UI_WEEKLY", Backend.Scope.COUNTRY: "UI_COUNTRY",
	}
	for scope: int in labels:
		var b := UiKit.btn(tr(String(labels[scope])),
				UiKit.ACCENT if scope == _board_scope else Color.TRANSPARENT, 84)
		b.add_theme_font_size_override("font_size", 26)
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_board_scope = scope
			_rebuild())
		scopes.add_child(b)
	_content.add_child(scopes)

	# The provider answers synchronously today; going through the signal keeps
	# the call site identical for a real async backend.
	var rows: Array = []
	var sink := func(_scope: String, r: Array) -> void: rows.assign(r)
	Backend.board_ready.connect(sink, CONNECT_ONE_SHOT)
	Backend.fetch(_board_scope)

	for row: Dictionary in rows:
		_content.add_child(_board_row(row))


func _board_row(row: Dictionary) -> Control:
	var mine := bool(row.get("is_player", false))
	var card := UiKit.panel(UiKit.ACCENT if mine else Color.TRANSPARENT)
	var h := UiKit.row([], 16)
	card.add_child(h)
	var rank := UiKit.lbl("%d" % int(row.get("rank", 0)), 32,
			UiKit.INK if mine else UiKit.INK_MUTE)
	rank.custom_minimum_size.x = 90
	h.add_child(rank)
	var name := UiKit.lbl(String(row.get("name", "?")), 32,
			UiKit.INK if mine else UiKit.INK_MUTE)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	if mine:
		h.add_child(UiKit.icon("trophy", 28, UiKit.ACCENT))
	h.add_child(UiKit.lbl(Locale.number(int(row.get("score", 0))), 32,
			UiKit.INK if mine else UiKit.INK_MUTE, HORIZONTAL_ALIGNMENT_RIGHT))
	return card


# --- store (real money) ----------------------------------------------------
func _build_store() -> void:
	# The offer goes first: it is time-limited and segment-targeted, so burying
	# it under the bundle list wastes it.
	var offer := Store.active_offer()
	if not offer.is_empty():
		_content.add_child(_offer_card(offer))

	if not Store.available():
		# Honest, not hidden: no billing provider is configured, so nothing here
		# can be bought. Saying so beats buttons that silently do nothing.
		var note := UiKit.lbl(tr("UI_UNAVAILABLE"), 34, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		_content.add_child(UiKit.spacer(10))
		_content.add_child(note)

	for p: Dictionary in Store.products():
		_content.add_child(_product_card(p))

	var restore := UiKit.btn_secondary(tr("UI_RESTORE"), 110)
	restore.add_theme_font_size_override("font_size", 32)
	UiKit.cap_width(restore, 620)
	restore.pressed.connect(func() -> void:
		Store.restore(func(n: int) -> void:
			_toast(tr("UI_RESTORE") + "  " + str(n))
			_rebuild()))
	_content.add_child(UiKit.spacer(12))
	_content.add_child(restore)


func _product_card(p: Dictionary) -> Control:
	var id := String(p["id"])
	var owned := Store.owns(id)
	var card := UiKit.panel(UiKit.SIGNAL_GOOD if owned else Color.TRANSPARENT)
	var row := UiKit.row([], UiKit.S3)
	card.custom_minimum_size.y = 150
	card.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 4)
	var title := _product_title(p)
	text.add_child(UiKit.lbl(title, 36))
	var summary := _grants_summary(p)
	# Currency bundles put the same string in both lines; only show the subtitle
	# when it actually adds something.
	if summary != "" and not summary.ends_with(title):
		text.add_child(UiKit.lbl(summary, 26, UiKit.INK_MUTE))
	row.add_child(text)

	var buy := _buy_control(id, owned)
	buy.custom_minimum_size.x = 230
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buy)
	return card


## The one purchase affordance, so the offer card and the product rows cannot drift
## apart. Owned is a terminal state, not a disabled button.
func _buy_control(id: String, owned: bool) -> Control:
	if owned:
		return UiKit.state_tag(tr("UI_OWNED"), "check", UiKit.SIGNAL_GOOD)
	if not Store.available():
		# Honest: no billing provider, so the price shows but nothing pretends to
		# be purchasable.
		return UiKit.state_tag(Store.price_text(id), "lock", UiKit.INK_OFF)
	var b := UiKit.btn(Store.price_text(id), UiKit.ACCENT, 100)
	b.pressed.connect(func() -> void:
		Store.purchase(id, func(result: int) -> void:
			_toast(tr("UI_OWNED") if result == Store.Result.SUCCESS
					else tr("UI_UNAVAILABLE"))
			_rebuild()))
	return b


func _product_title(p: Dictionary) -> String:
	var grants: Dictionary = p.get("grants", {})
	if bool(grants.get("no_ads", false)) and String(p["id"]) == "remove_ads":
		return tr("UI_REMOVE_ADS")
	if grants.has("coins"):
		return "%s %s" % [Locale.number(int(grants["coins"])), tr("UI_COINS")]
	if grants.has("gems"):
		return "%s %s" % [Locale.number(int(grants["gems"])), tr("UI_GEMS")]
	return String(p["id"]).replace("_", " ").to_upper()


func _grants_summary(p: Dictionary) -> String:
	var parts: Array[String] = []
	var grants: Dictionary = p.get("grants", {})
	if grants.has("coins"):
		parts.append("+%s %s" % [Locale.number(int(grants["coins"])), tr("UI_COINS")])
	if grants.has("gems"):
		parts.append("+%s %s" % [Locale.number(int(grants["gems"])), tr("UI_GEMS")])
	if bool(grants.get("no_ads", false)):
		parts.append(tr("UI_REMOVE_ADS"))
	if grants.has("cosmetic"):
		parts.append(String(Cosmetics.get_item(String(grants["cosmetic"])).get("name", "")))
	return "   ·   ".join(parts)


func _offer_card(offer: Dictionary) -> Control:
	var card := UiKit.panel(UiKit.ACCENT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(UiKit.lbl("%s  ·  -%d%%" % [tr("UI_OFFER"), int(offer.get("discount_pct", 0))],
			36, UiKit.ACCENT))
	var p := Store.product(String(offer.get("product", "")))
	var pid := String(offer.get("product", ""))
	if not p.is_empty():
		box.add_child(UiKit.lbl(_grants_summary(p), 28, UiKit.INK_MUTE))
	_offer_clock = UiKit.lbl(tr("UI_RESETS_IN") % Locale.duration(Store.offer_seconds_left()),
			26, UiKit.INK_MUTE)
	box.add_child(_offer_clock)
	# A time-limited offer with no way to accept it is a poster, not an offer.
	if pid != "":
		box.add_child(UiKit.spacer(UiKit.S1))
		box.add_child(_buy_control(pid, Store.owns(pid)))
	if _offer_timer == null:
		_offer_timer = Timer.new()
		_offer_timer.wait_time = 1.0
		_offer_timer.autostart = true
		_offer_timer.timeout.connect(_tick_offer)
		add_child(_offer_timer)
	_offer_timer.start()
	return card


## Re-texts one Label per second. A full _rebuild() every second would rebuild the
## whole catalogue and fight the player's scroll position.
func _tick_offer() -> void:
	if _offer_clock == null or not is_instance_valid(_offer_clock):
		_offer_timer.stop()
		return
	var left := Store.offer_seconds_left()
	if left <= 0:
		_offer_timer.stop()
		_rebuild()
		return
	_offer_clock.text = tr("UI_RESETS_IN") % Locale.duration(left)


# --- missions --------------------------------------------------------------
func _build_missions() -> void:
	for scope: String in ["daily", "weekly", "achievement"]:
		var key: String = {"daily": "UI_DAILY", "weekly": "UI_WEEKLY",
				"achievement": "UI_ACHIEVEMENTS"}[scope]
		var header := UiKit.row([], 12)
		var h := UiKit.lbl(tr(key), 46)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(h)
		if scope != "achievement":
			var secs := Meta.seconds_to_rollover()
			if scope == "weekly":
				secs += (6 - (Meta.today() % 7)) * Meta.DAY_SECONDS
			header.add_child(UiKit.lbl(tr("UI_RESETS_IN") % Locale.duration(secs),
					28, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		_content.add_child(UiKit.spacer(10))
		_content.add_child(header)

		var list := Meta.active(scope)
		if list.is_empty():
			# A blank panel reads as broken; say why it is empty.
			var empty := UiKit.lbl(tr("UI_EMPTY_MISSIONS"), 30, UiKit.INK_DIM,
					HORIZONTAL_ALIGNMENT_CENTER)
			empty.custom_minimum_size = Vector2(0, 120)
			_content.add_child(empty)
		for m: Dictionary in list:
			_content.add_child(_mission_card(scope, m))


func _mission_card(scope: String, m: Dictionary) -> Control:
	var card := UiKit.panel(UiKit.SIGNAL_GOOD if bool(m["complete"]) and not bool(m["claimed"])
			else Color.TRANSPARENT)
	var row := UiKit.row([], UiKit.S3)
	card.custom_minimum_size.y = 150
	card.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 8)
	text.add_child(UiKit.lbl(String(m["name"]), 34, UiKit.INK))
	text.add_child(UiKit.bar(float(m["current"]) / maxf(1.0, float(m["target"])),
			UiKit.SIGNAL_GOOD if bool(m["complete"]) else UiKit.ACCENT, 14))
	text.add_child(UiKit.lbl("%d / %d   ·   +%s" % [m["current"], m["target"],
			Locale.number(int(m["coins"]))], 26, UiKit.INK_MUTE))
	row.add_child(text)

	var action: Control
	if bool(m["claimed"]):
		action = UiKit.state_tag(tr("UI_CLAIMED"), "check", UiKit.INK_MUTE)
	elif bool(m["complete"]):
		var claim := UiKit.btn(tr("UI_CLAIM"), UiKit.SIGNAL_GOOD, 100)
		action = claim
		claim.pressed.connect(func() -> void:
			if Meta.claim_mission(scope, String(m["id"])):
				_toast("+%s" % Locale.number(int(m["coins"])))
				_rebuild())
	else:
		# Was a disabled button showing a percentage — a box that looks tappable,
		# is not, and repeats what the bar beside it already says. An in-progress
		# mission has no action, so it gets no control: that leaves the one filled
		# CLAIM button as the only thing on the screen pulling the eye.
		action = UiKit.spacer(0)
	action.custom_minimum_size.x = 220
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(action)
	return card


# --- battle pass -----------------------------------------------------------
func _build_pass() -> void:
	var state := Meta.bp_state()
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.lbl("SEASON %d   ·   TIER %d / %d"
			% [int(state["season"]), int(state["tier"]), int(state["tiers"])], 40))
	head.add_child(UiKit.bar(float(state["progress"]), UiKit.ACCENT, 18))
	head.add_child(UiKit.lbl(tr("UI_RESETS_IN") % ("%dd" % int(state["days_left"])),
			28, UiKit.INK_DIM))
	_content.add_child(head)

	if not bool(state["premium"]):
		var price := int(Meta.bp_config().get("premium_price_gems", 400))
		var unlock := UiKit.btn("%s  %s" % [tr("UI_BUY"), Locale.number(price)],
				UiKit.ACCENT)
		unlock.icon = Icons.get_icon("gem")
		unlock.add_theme_constant_override("h_separation", 10)
		unlock.pressed.connect(func() -> void:
			if Meta.unlock_premium():
				_toast(tr("UI_OWNED"))
			else:
				_toast(tr("UI_NOT_ENOUGH"))
			_rebuild())
		_content.add_child(unlock)

	for tier in range(1, int(state["tiers"]) + 1):
		var card := _pass_tier(tier, state)
		if card != null:
			_content.add_child(card)
			# A player at tier 12 used to open the pass at tier 1 and have to
			# hunt for where they actually are.
			if tier == int(state["tier"]):
				_focus_child = card


func _pass_tier(tier: int, state: Dictionary) -> Control:
	var free_reward := Meta.bp_reward(tier, false)
	var prem_reward := Meta.bp_reward(tier, true)
	if free_reward.is_empty() and prem_reward.is_empty():
		return null

	var unlocked := tier <= int(state["tier"])
	var card := UiKit.panel(UiKit.ACCENT if unlocked else Color.TRANSPARENT)
	var row := UiKit.row([], 14)
	card.add_child(row)

	var n := UiKit.lbl(str(tier), 40, Color.WHITE if unlocked else UiKit.INK_DIM)
	n.custom_minimum_size.x = 70
	row.add_child(n)
	row.add_child(_pass_slot(tier, free_reward, false, state, unlocked))
	row.add_child(_pass_slot(tier, prem_reward, true, state, unlocked))
	return card


func _pass_slot(tier: int, reward: Dictionary, premium: bool, state: Dictionary,
		unlocked: bool) -> Control:
	if reward.is_empty():
		var blank := Control.new()
		blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return blank

	var text := ""
	if String(reward.get("kind", "")) == "cosmetic":
		text = String(Cosmetics.get_item(String(reward["id"])).get("name", "?"))
	else:
		text = "+%s" % Locale.number(int(reward.get("amount", 0)))

	var claimed: Array = state["claimed_premium"] if premium else state["claimed_free"]
	var slot: Control
	if claimed.has(tier):
		slot = UiKit.state_tag(tr("UI_CLAIMED"), "check", UiKit.INK_MUTE)
	elif not unlocked or (premium and not bool(state["premium"])):
		# A tier you have not reached is not an action. As a disabled button it was
		# a tappable-looking box on 28 of 30 rows, and the two rows that ARE
		# claimable had to compete with all of them.
		slot = UiKit.state_tag(text, "lock", UiKit.INK_OFF)
	else:
		# Claims are SIGNAL_GOOD on both tracks. The premium one used to be amber,
		# which put money's colour on something that costs nothing to claim.
		var b := UiKit.btn(text, UiKit.SIGNAL_GOOD, 96)
		b.add_theme_font_size_override("font_size", 28)
		slot = b
		b.pressed.connect(func() -> void:
			if Meta.claim_bp(tier, premium):
				_toast(text)
				_rebuild())
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slot


# --- feedback --------------------------------------------------------------
func _toast(text: String) -> void:
	var l := UiKit.lbl(text, 40, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = -220
	_toast_host.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
