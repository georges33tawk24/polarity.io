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


## Locale-aware currency. Godot ships no ICU money formatter, so this is a small
## table rather than a pretend-general solution: symbol, whether it leads or
## trails, and whether a space sits between. Those three facts cover every locale
## this game ships in, and the honest failure for anything else is "$ in front",
## which is what an unformatted price already does.
##
## Prices from a real IAP provider arrive PRE-FORMATTED by the store — this is only
## for locally computed amounts (offers, bundle previews, "was $X.XX").
const CURRENCY := {
	"en": ["$", true, false], "es": ["\u20ac", false, true],
	"pt_BR": ["R$", true, true], "fr": ["\u20ac", false, true],
	"de": ["\u20ac", false, true], "ru": ["\u20bd", false, true],
	"tr": ["\u20ba", true, false], "id": ["Rp", true, true],
	"ja": ["\u00a5", true, false], "ko": ["\u20a9", true, false],
}


static func currency(amount: float, code := "") -> String:
	var c := code if code != "" else String(Game.get_value("locale", "en"))
	var rule: Array = CURRENCY.get(c, CURRENCY.get(c.split("_")[0], ["$", true, false]))
	var sym := String(rule[0])
	var leads := bool(rule[1])
	var space := bool(rule[2])
	# Yen and won have no minor unit; showing ".00" on them is a tell.
	var minor := 0 if c in ["ja", "ko"] else 2
	var body := number(int(round(amount))) if minor == 0 \
			else "%s%s%02d" % [number(int(amount)), decimal_sep(c),
					int(round(fmod(absf(amount), 1.0) * 100.0))]
	var gap := " " if space else ""
	return (sym + gap + body) if leads else (body + gap + sym)


static func decimal_sep(code := "") -> String:
	var c := code if code != "" else String(Game.get_value("locale", "en"))
	return "," if c.split("_")[0] in ["es", "fr", "de", "ru", "tr", "id", "pt"] else "."


## Short date, ordered the way the locale writes it. Used for season end dates and
## the GDPR export stamp — anywhere a bare ISO string would read as a machine value.
static func date(unix: int, code := "") -> String:
	var c := code if code != "" else String(Game.get_value("locale", "en"))
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var y: int = d["year"]
	var m: int = d["month"]
	var day: int = d["day"]
	match c.split("_")[0]:
		"ja", "ko":
			return "%d/%02d/%02d" % [y, m, day]
		"en":
			return "%02d/%02d/%d" % [m, day, y] if c == "en" else "%02d/%02d/%d" % [day, m, y]
		_:
			return "%02d/%02d/%d" % [day, m, y]
