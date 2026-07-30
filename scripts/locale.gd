class_name Locale
extends RefCounted
## Language list, locale switching and locale-aware formatting.
##
## Static-only: switching a locale is three TranslationServer calls, which does
## not justify a fifteenth autoload. `Game` owns the saved preference and calls
## `apply()`; everything else just uses `tr()`.

## Order matters — this is the order shown in the settings picker.
const LANGUAGES := [
	{"code": "en", "name": "English"},
	{"code": "es", "name": "Español"},
	{"code": "pt_BR", "name": "Português (BR)"},
	{"code": "fr", "name": "Français"},
	{"code": "de", "name": "Deutsch"},
	{"code": "ru", "name": "Русский"},
	{"code": "tr", "name": "Türkçe"},
	{"code": "id", "name": "Indonesia"},
	{"code": "ja", "name": "日本語"},
	{"code": "ko", "name": "한국어"},
]

## Languages written right-to-left. None shipped yet, but the layout switch is
## wired so adding Arabic or Hebrew is a CSV column plus one entry here.
const RTL_CODES := ["ar", "he", "fa", "ur"]


static func codes() -> Array:
	var out: Array = []
	for l: Dictionary in LANGUAGES:
		out.append(l["code"])
	return out


static func names() -> Array:
	var out: Array = []
	for l: Dictionary in LANGUAGES:
		out.append(l["name"])
	return out


## Best supported match for the device's own language, for first launch.
static func detect() -> String:
	var os_locale := OS.get_locale()
	var supported := codes()
	if supported.has(os_locale):
		return os_locale
	# "pt_BR_something" -> "pt_BR", then "pt" -> first pt_* we ship.
	var lang := os_locale.split("_")[0]
	for code: String in supported:
		if code == lang or code.begins_with(lang + "_"):
			return code
	return "en"


static func is_rtl(code: String) -> bool:
	return RTL_CODES.has(code.split("_")[0])


static func apply(code: String) -> void:
	if not codes().has(code):
		code = "en"
	TranslationServer.set_locale(code)


## Digit grouping, e.g. 1234567 -> "1,234,567". Godot has no locale-aware
## number formatter, and unseparated six-figure coin balances are unreadable.
static func number(value: int, code := "") -> String:
	if code == "":
		code = TranslationServer.get_locale()
	var sep := " " if code.begins_with("ru") or code.begins_with("fr") else ","
	if code.begins_with("de") or code.begins_with("pt") or code.begins_with("id"):
		sep = "."
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = sep + out
	return ("-" if value < 0 else "") + out


## Seconds -> "m:ss", or "h:mm:ss" past an hour. Used by mission reset timers.
static func duration(seconds: int) -> String:
	seconds = maxi(0, seconds)
	# Past a day, hours stop being meaningful — a weekly reset should read "6d",
	# not "143:59:12".
	if seconds >= 86400:
		var days := seconds / 86400
		var rem_h := (seconds % 86400) / 3600
		return "%dd" % days if rem_h == 0 else "%dd %dh" % [days, rem_h]
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]
