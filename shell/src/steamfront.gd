extends Node

## ============================================================================
## THE STOREFRONT SEAM -- Valve's own front page, as data.
##
## The stores screen used to say, in its header and on the television, that it
## could not show you Steam's store: embedding a foreign client's window inside
## a Godot control is compositor work gamescope does not offer one of its
## clients. That is still true, and it is no longer the end of the sentence.
## Valve publishes the front page as JSON over a public endpoint, so the shell
## draws the STORE without embedding the CLIENT -- which is the better answer
## anyway, because a page drawn by this shell is a page at this shell's
## fidelity rather than a smaller television inside the television.
##
## THE SHELL STILL OPENS NO SOCKETS. This is the wifi seam's shape, a fourth
## time: write a one-line request into a player-owned directory, poll a state
## file and read result files that root wrote. marwanos-steamfront owns every
## curl, every URL and the whole of Valve's response shape; what crosses the
## boundary into this file is a normalised structure with no URL anywhere in
## it, and pictures that are already on disk.
##
## Requests are FIRE AND FORGET, like every other seam here. There is no
## correlation id: the answer to "did it work" is the state file changing,
## which the screen is already watching.
##
## PURCHASING IS THE CLIENT'S, DELIBERATELY. Nothing in this file or the screen
## it feeds can spend money; the panel browses at shell fidelity and the one
## action it offers hands the game's store page to Steam, where Valve's own UI
## owns the transaction. See stores_screen.gd, where a person could otherwise
## expect a Buy button.
## ============================================================================

## Emitted when the service's state word changes. States: "idle", "fetching",
## "done", "offline", "failed", "unknown" (nothing has been written yet -- a
## desk run, or too early in boot).
signal state_changed(state: String, detail: String)

## Emitted when the featured shelves change, including to and from empty.
signal featured_changed(categories: Array)

## Emitted when one application's detail page arrives.
signal app_changed(appid: int, details: Dictionary)

## Emitted when a search answer lands, including an empty one. The term comes
## back with the items because it has to: the results file has a fixed name, so
## the only way the screen can tell "no hits for what I asked" from "the previous
## term's hits are still on disk" is to compare what the service says it searched
## for against what was typed.
signal search_changed(term: String, items: Array)

## Emitted when the signed-in account changes, including to and from nobody.
## Carries the display name and never the SteamID: the shell has no use for the
## number and nothing on a television should be drawing it.
signal account_changed(signed_in: bool, persona: String)

## Emitted when the wishlist shelf changes, including to and from empty.
signal wishlist_changed(items: Array)

## Matches every other seam here. The service answers a cached request in one
## poll and a cold one in a second or two; two seconds is the latency of the
## screen noticing either.
const POLL_SECONDS := 2.0

const STATE_FILE := "/run/marwanos/steamfront.state"
const REQUEST_FILE := "/run/marwanos/steamfront/request"

## Where the results live. Shared with catalogue.gd's icon cache -- one
## directory is the whole of "artwork root writes and the shell reads".
const STORE_DIR := "/var/marwanos/store"

## Shared with the other seams so one fixture directory drives every file the
## shell reads. Nothing on the appliance sets either of these.
const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"
const STORE_DIR_ENV := "MARWANOS_SHELL_STORE_DIR"

## CURRENCY MARKS THE SHIPPED FONT ACTUALLY HAS. Godot's built-in UI font is a
## subset, and a mark it has no glyph for renders as a box -- which next to a
## number reads as a broken price rather than as a missing font. So the table
## is deliberately short: the four marks that are certainly there, plus the
## composed forms built from them, and every other currency renders as its
## three-letter code after the amount ("1049.00 SEK"). Ugly is fine; wrong is
## not, and a tofu box beside somebody's money is wrong.
const CURRENCY_SYMBOLS := {
	"USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥",
	"CAD": "CA$", "AUD": "A$", "NZD": "NZ$", "MXN": "MX$", "BRL": "R$",
	"HKD": "HK$", "SGD": "S$", "TWD": "NT$", "CNY": "CN¥",
}

## Currencies with no minor unit. Steam returns every price in hundredths --
## measured, not assumed: a game Valve itself prints as "8,778" comes back from
## the API as 877800 -- so the divide is universal and only the number of
## decimals differs. Showing "8778.00" for a yen price is the small kind of
## wrong that makes a whole screen look machine-translated.
const ZERO_DECIMAL_CURRENCIES := ["JPY", "KRW", "VND", "IDR", "CLP", "COP", "HUF"]

var state: String = "unknown"
var detail: String = ""

## The featured shelves, in the order the service published them. Each is
## {"id", "name", "items": [{"appid", "name", "discounted", "discount_percent",
## "original_price", "final_price", "currency"}]}.
var categories: Array = []

var _state_path := STATE_FILE
var _request_path := REQUEST_FILE
var _front_dir := STORE_DIR.path_join("front")

## The last search's results and the term the SERVICE says produced them --
## which is not necessarily the term last asked for. See search_changed.
var search_items: Array = []
var search_term: String = ""

## Who Steam is signed in as, from Steam's own loginusers.vdf by way of the
## service. THE SHELL NEVER SEES A CREDENTIAL and never asks for one: signing in
## happens inside Valve's client, which is the same boundary the missing Buy
## button draws. What crosses into this file is a name and a yes/no.
var account_signed_in := false
var account_persona := ""

## The wishlist, as appids in the order Valve returned them. The ITEMS are
## assembled from the per-app detail cache -- see wishlist_items -- because the
## wishlist endpoint returns appids and nothing else.
var wishlist_appids: Array = []

var _loaded := false
var _last_featured_raw := ""
var _last_search_raw := ""
var _last_account_raw := ""
var _last_wishlist_raw := ""

## Detail pages already read off disk, keyed by appid. A cache of file contents
## rather than of network answers -- the service owns freshness, and re-reading
## the same small file every time a person moved along a shelf would be the
## only reason this screen ever touched the disk in a loop.
var _apps: Dictionary = {}


func _ready() -> void:
	var status_override := OS.get_environment(STATUS_DIR_ENV)
	if not status_override.is_empty():
		_state_path = status_override.path_join(STATE_FILE.get_file())
		# The request keeps its own name but lands in the fixture directory, so
		# a desk run can show what the shell asked for with no service to
		# answer it.
		_request_path = status_override.path_join("steamfront.request")

	var store_override := OS.get_environment(STORE_DIR_ENV)
	if not store_override.is_empty():
		_front_dir = store_override.path_join("front")

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()
	# Read whatever is already on disk, whether or not a state file exists. A
	# machine that fetched a storefront last week and booted with no network
	# has a full store to draw and nothing to say about it yet, and that is the
	# case this line exists for.
	_load_featured()
	# AND THE LAST SEARCH, which is not symmetry -- it is the fix for a stall
	# that has a specific shape. The service answers a repeated term from disk by
	# writing the state file and nothing else, and if the state was ALREADY
	# `done search` that write changes no byte anywhere: no state transition, no
	# poll reaction, no signal. A screen waiting for one would wait forever. So
	# the results are on hand from startup and the screen renders them
	# synchronously when the term it just asked for is the term already loaded;
	# the signal is only ever the ASYNC arrival. See stores_screen's _open_search.
	_load_search()
	# The account and the wishlist, for _load_featured's reason: both survive a
	# reboot on purpose, and a machine that booted with no network still knows
	# whose Steam this is and what was on their list last time it looked.
	_load_account()
	_load_wishlist()


# ---------------------------------------------------------------------------
# Asking
# ---------------------------------------------------------------------------

## Ask for the front page. Cheap to call: the service answers from disk without
## touching the network while its copy is under an hour old, so a screen that
## asks every time it opens costs Valve one request an hour at most.
func request_featured() -> void:
	_write_request(["featured"])


## Ask who Steam is signed in as. Cheap by construction and safe offline: the
## service answers it by reading one local file, without the cache window, the
## failure cooldown or the network check the other requests go through.
func request_account() -> void:
	_write_request(["account"])


## Ask for the signed-in account's wishlist. Answered from disk for an hour like
## the front page, and answered with an empty shelf when nobody is signed in --
## which is a state, not a failure.
func request_wishlist() -> void:
	_write_request(["wishlist"])


## Search Valve's store for a term somebody typed on the keyboard.
##
## THE ONE REQUEST IN THIS SEAM THAT CARRIES FREE TEXT. _write_request already
## strips the tab, newline and carriage return that would restructure the file
## the service reads, and the service bounds the length and removes control
## characters before anything else happens to it. What makes it SAFE rather than
## merely tidy is on the root side: the term reaches a URL only through curl's
## own percent-encoder, and never reaches a filename at all. See do_search.
##
## An empty term is refused here rather than sent: the service would reject it
## anyway, and a request that exists only to be discarded is one more thing in
## the journal to explain.
func request_search(term: String) -> void:
	var trimmed := term.strip_edges()
	if trimmed.is_empty():
		return
	_write_request(["search", trimmed])


## Ask for one game's page. The appid is the number Valve uses; anything else
## is refused on the root side.
func request_app(appid: int) -> void:
	if appid <= 0:
		return
	# Warm the cache from disk before the request goes out, so the caller's own
	# render finds an already-fetched page waiting rather than an empty one --
	# which is what makes a page opened twice appear at once. Deliberately does
	# NOT emit: the caller is about to draw, and a signal here would make it
	# draw the same thing twice, once per journal line.
	app_details(appid)
	_write_request(["app", str(appid)])


## One line, `<verb>` or `<verb>TAB<appid>`. Temp-then-rename and 0600, for the
## wifi seam's reasons: the service polls twice a second and DELETES what it
## finds, so a poll landing inside an in-place write reads an empty file,
## discards it, and leaves the real write going to an unlinked inode -- a
## button that does nothing, with nothing anywhere to say why. Godot's
## FileAccess uses fopen() and does not chmod, so the mode is set before the
## rename rather than trusted to the umask.
func _write_request(fields: Array) -> void:
	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("steamfront: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return
	var line := ""
	for field in fields:
		if not line.is_empty():
			line += "\t"
		# Belt and braces, exactly as the wifi seam does it: this is the
		# function that turns values into a LINE, and a newline arriving in one
		# would restructure the file the service reads.
		line += str(field).replace("\n", "").replace("\r", "").replace("\t", "")
	file.store_line(line)
	file.close()
	# 384 is 0600. Decimal because GDSCRIPT HAS NO OCTAL LITERAL -- `0o600` is a
	# parse error that takes this whole autoload down and silently removes the
	# feature while the shell still starts and looks fine.
	FileAccess.set_unix_permissions(temp_path, 384)

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("steamfront: cannot place the request at %s (error %d)"
			% [_request_path, error])
		DirAccess.remove_absolute(temp_path)


# ---------------------------------------------------------------------------
# Listening
# ---------------------------------------------------------------------------

func _poll() -> void:
	var line := _read_line(_state_path)
	var word := line.get_slice("\t", 0).strip_edges()
	var rest := ""
	if line.contains("\t"):
		rest = line.substr(line.find("\t") + 1).strip_edges()
	if word.is_empty():
		word = "unknown"

	if _loaded and word == state and rest == detail:
		return
	_loaded = true
	state = word
	detail = rest
	ShellLog.info("steamfront state: %s%s"
		% [state, (" (%s)" % detail) if not detail.is_empty() else ""])

	# The results are re-read on any state change rather than only on "done",
	# because the service writes the file BEFORE the word: a poll that saw
	# `done` and then read would be reading a file that had already been there,
	# and one that only ever reacted to `done` would miss the boot where the
	# state file was already `done` from a previous request.
	if detail == "featured" or detail.is_empty():
		_load_featured()
	elif detail == "search":
		_load_search()
	elif detail == "account":
		_load_account()
	elif detail == "wishlist":
		_load_wishlist()
	elif detail.begins_with("app."):
		var appid := int(detail.substr(4))
		if appid > 0:
			_apps.erase(appid)
			var details := app_details(appid)
			if not details.is_empty():
				app_changed.emit(appid, details)

	state_changed.emit(state, detail)


## The shelves, from disk. Compared as raw text before parsing, for
## installed.gd's reason: an unchanged file must cost one string comparison
## rather than a re-parse and a rebuilt grid under somebody's thumb.
func _load_featured() -> void:
	var raw := _read_file(_front_dir.path_join("featured.json"))
	if raw == _last_featured_raw:
		return
	_last_featured_raw = raw

	var found: Array = []
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary and parsed.has("categories"):
		for category in parsed["categories"]:
			if not (category is Dictionary):
				continue
			var items: Array = []
			for item in category.get("items", []):
				if not (item is Dictionary):
					continue
				var appid := int(item.get("appid", 0))
				var name := str(item.get("name", ""))
				# An item with no appid cannot be opened and an item with no
				# name cannot be read. Either way there is nothing to draw, and
				# a blank tile a person can press is worse than a shorter row.
				if appid <= 0 or name.is_empty():
					continue
				items.append({
					"appid": appid,
					"name": name,
					"discounted": bool(item.get("discounted", false)),
					"discount_percent": int(item.get("discount_percent", 0)),
					"original_price": int(item.get("original_price", 0)),
					"final_price": int(item.get("final_price", 0)),
					"currency": str(item.get("currency", "")),
				})
			if items.is_empty():
				continue
			found.append({
				"id": str(category.get("id", "")),
				"name": str(category.get("name", "")),
				"items": items,
			})
	elif not raw.strip_edges().is_empty():
		# A file that exists and is not the shape this expects. Said once, on
		# change, rather than swallowed: it is the difference between "Valve
		# changed something" and "the network is down", and those lead
		# somewhere different.
		ShellLog.warn("steamfront: the stored storefront is not in a shape this shell knows")

	categories = found
	var total := 0
	for category in categories:
		total += (category["items"] as Array).size()
	ShellLog.info("steamfront: %d shelf/shelves, %d item(s)" % [categories.size(), total])
	featured_changed.emit(categories)


## The last search's results, from disk. Same raw-text comparison as the shelves
## for the same reason -- but with one difference that matters: an EMPTY result
## list is a real answer here and is emitted as one. "Nothing on Steam is called
## that" is a sentence the screen has to be able to say, and it is not the same
## sentence as "the search has not come back yet".
##
## Items are the same shape as a shelf's, deliberately, so the tile, the price
## formatter and the detail view are all the ones that already exist.
func _load_search() -> void:
	var raw := _read_file(_front_dir.path_join("search.json"))
	if raw == _last_search_raw:
		return
	_last_search_raw = raw

	var found: Array = []
	var term := ""
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		term = str(parsed.get("term", ""))
		for item in parsed.get("items", []):
			if not (item is Dictionary):
				continue
			var appid := int(item.get("appid", 0))
			var name := str(item.get("name", ""))
			# Same two-field floor as the shelves: an item with no appid cannot
			# be opened and one with no name cannot be read.
			if appid <= 0 or name.is_empty():
				continue
			found.append({
				"appid": appid,
				"name": name,
				"discounted": bool(item.get("discounted", false)),
				"discount_percent": int(item.get("discount_percent", 0)),
				"original_price": int(item.get("original_price", 0)),
				"final_price": int(item.get("final_price", 0)),
				"currency": str(item.get("currency", "")),
			})
	elif not raw.strip_edges().is_empty():
		ShellLog.warn("steamfront: the stored search is not in a shape this shell knows")

	search_items = found
	search_term = term
	# The COUNT and not the term, matching the service: the term is text somebody
	# typed and the journal is not where it belongs.
	ShellLog.info("steamfront: %d search result(s)" % search_items.size())
	search_changed.emit(search_term, search_items)


## Who is signed in, from disk.
func _load_account() -> void:
	var raw := _read_file(_front_dir.path_join("account.json"))
	if raw == _last_account_raw:
		return
	_last_account_raw = raw

	var signed_in := false
	var persona := ""
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		signed_in = bool(parsed.get("signed_in", false))
		persona = str(parsed.get("persona", ""))

	account_signed_in = signed_in
	account_persona = persona
	# WHETHER, never WHO, matching the service: a display name is somebody's and
	# the journal is not where it goes.
	ShellLog.info("steamfront: Steam is %s"
		% ("signed in" if account_signed_in else "not signed in"))
	account_changed.emit(account_signed_in, account_persona)


## The wishlist's appids, from disk.
func _load_wishlist() -> void:
	var raw := _read_file(_front_dir.path_join("wishlist.json"))
	if raw == _last_wishlist_raw:
		return
	_last_wishlist_raw = raw

	var found: Array = []
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		for value in parsed.get("appids", []):
			var appid := int(value)
			if appid > 0:
				found.append(appid)

	wishlist_appids = found
	var items := wishlist_items()
	ShellLog.info("steamfront: %d wishlist appid(s), %d with a page to draw"
		% [wishlist_appids.size(), items.size()])
	wishlist_changed.emit(items)


## The wishlist as drawable items, assembled from the per-app detail cache.
##
## ASSEMBLED RATHER THAN STORED, because the wishlist endpoint returns appids and
## nothing else -- no name, no price, no picture. The service fills the gap by
## fetching a detail page per appid (see do_wishlist for why that is the one
## request here that makes more than one call, and how it is bounded), and those
## pages already carry every field a tile draws in exactly the shape it wants.
## Keeping a second copy in wishlist.json would be one more thing to go stale
## against the file it was copied from.
##
## An appid whose page has not landed yet is SKIPPED rather than drawn blank: a
## tile with no name is not a game somebody can recognise, and the shelf simply
## fills in over the second or two the pages take on a cold machine.
func wishlist_items() -> Array:
	var items: Array = []
	for appid in wishlist_appids:
		var details := app_details(int(appid))
		if details.is_empty():
			continue
		items.append(details)
	return items


## The small picture for a search result -- the 231x87 capsule, which is what
## `storesearch` gives and what a list row is sized for. Deliberately its own
## name and its own slot: writing it into the grid's `<appid>.jpg` would replace
## a 616 px capsule with a third-width copy of itself the next time somebody
## searched for a game that was already on a shelf.
##
## Falls back to the large capsule, so a result for a game the front page has
## already fetched draws immediately rather than waiting for a second download.
func search_art_path(appid: int) -> String:
	if appid <= 0:
		return ""
	var art_dir := _front_dir.path_join("art")
	var small := art_dir.path_join("%d.small.jpg" % appid)
	if FileAccess.file_exists(small):
		return small
	var capsule := art_dir.path_join("%d.jpg" % appid)
	return capsule if FileAccess.file_exists(capsule) else ""


## One application's detail page, read from disk and remembered. Empty when
## nothing has been fetched for it yet -- which is a normal state, not an
## error: it is what every game looks like before somebody presses A on it.
func app_details(appid: int) -> Dictionary:
	if _apps.has(appid):
		return _apps[appid]
	var raw := _read_file(_front_dir.path_join("app.%d.json" % appid))
	if raw.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary) or str(parsed.get("name", "")).is_empty():
		return {}
	var details := {
		"appid": appid,
		"name": str(parsed.get("name", "")),
		"short_description": str(parsed.get("short_description", "")),
		"is_free": bool(parsed.get("is_free", false)),
		"discounted": bool(parsed.get("discounted", false)),
		"discount_percent": int(parsed.get("discount_percent", 0)),
		"original_price": int(parsed.get("original_price", 0)),
		"final_price": int(parsed.get("final_price", 0)),
		"currency": str(parsed.get("currency", "")),
	}
	_apps[appid] = details
	return details


## The picture for an appid, or empty. `large` asks for the full screenshot the
## detail view wants and falls back to the shelf capsule, which is the ordering
## that matters: a 616 px capsule blown up across most of a television is the
## soft, obviously-stretched art this whole change exists to stop drawing, so
## it is the floor rather than the choice.
##
## Resolved at draw time rather than cached: art lands minutes after the JSON
## on a cold machine, and a path resolved once at startup would be empty
## forever on exactly the boot where the store was first fetched.
func art_path(appid: int, large: bool = false) -> String:
	if appid <= 0:
		return ""
	var art_dir := _front_dir.path_join("art")
	if large:
		var shot := art_dir.path_join("%d.shot.jpg" % appid)
		if FileAccess.file_exists(shot):
			return shot
	var capsule := art_dir.path_join("%d.jpg" % appid)
	return capsule if FileAccess.file_exists(capsule) else ""


# ---------------------------------------------------------------------------
# Money, as text
# ---------------------------------------------------------------------------

## An amount in a currency's minor units, as something readable at three
## metres. Empty for "no price to show", which is a real answer: an unreleased
## game has no price, and rendering that as "0.00" or as "Free" would be the
## shell inventing a fact about somebody else's shop.
##
## THE SHELL FORMATS, not the service, and that is this project's own division
## of labour (installed.gd's PENDING_SUBTITLES says it for install states): the
## system reports numbers, the shell decides how they read on a television.
## Valve's endpoints do return pre-formatted strings -- but only one of the two
## does, so using them where they exist would render the same game's price two
## different ways on two halves of one panel.
func price_text(cents: int, currency: String) -> String:
	if cents <= 0:
		return ""
	var code := currency.to_upper()
	var amount := ""
	if ZERO_DECIMAL_CURRENCIES.has(code):
		amount = str(int(cents / 100.0))
	else:
		# Integer arithmetic rather than a float format: a price is an exact
		# number of minor units, and rounding one through a float is how a
		# 19.99 becomes a 19.98 on somebody's screen.
		amount = "%d.%02d" % [cents / 100, cents % 100]
	if CURRENCY_SYMBOLS.has(code):
		return "%s%s" % [CURRENCY_SYMBOLS[code], amount]
	if code.is_empty():
		return amount
	return "%s %s" % [amount, code]


## What a tile or a detail says under the name. Returns [main, secondary]:
## the price that is actually charged, and -- only when there is a discount --
## what it was, LABELLED rather than struck through.
##
## The strike-through was the first draft and it is not what shipped. Godot
## draws one only through a RichTextLabel's [s] tag, and a thin line across a
## number at three metres is a smudge rather than a statement; "was $59.99
## (-70%)" is unambiguous at any distance and needs no second kind of label.
func price_lines(item: Dictionary) -> Array:
	var final_price := int(item.get("final_price", 0))
	var currency := str(item.get("currency", ""))
	var main := price_text(final_price, currency)
	if main.is_empty():
		# A free game says so; anything else with no price is simply not
		# priced yet, and says nothing rather than guessing which it is.
		return ["Free" if bool(item.get("is_free", false)) else "", ""]

	if not bool(item.get("discounted", false)):
		return [main, ""]

	var was := price_text(int(item.get("original_price", 0)), currency)
	var percent := int(item.get("discount_percent", 0))
	if was.is_empty():
		return [main, ""]
	if percent > 0:
		return [main, "was %s  (-%d%%)" % [was, percent]]
	return [main, "was %s" % was]


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line()
