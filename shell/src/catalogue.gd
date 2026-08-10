extends RefCounted

## The stores the shell knows about.
##
## THIS FILE USED TO HOLD TWELVE PLACEHOLDER LIBRARY ENTRIES. They were honest
## scaffolding -- they made the rail wider than the screen, so the slide, the
## clipping at both edges and hold-to-repeat traversal were all exercised
## before there was anything real to put there -- and they are gone now that
## the rail lists what is actually installed (see installed.gd and
## marwanos-appscan). A shipped appliance showing "Placeholder Seven" is a lie
## about what the machine has on it, and an empty rail is not: it says
## "nothing is installed", which on a fresh stick is true.
##
## What remains is the store list, and it is still hand-written because there
## is exactly one store and no mechanism that could discover a second. Phase 1
## deletes this file too: marwand serves both the store list and the installed
## list over JSON-RPC.

## The one real entry, and the only one carrying an "exec". It lives in the
## STORES list rather than on the rail since the third amendment (ADR 0006):
## the rail is the library, and a store is somewhere you go on purpose --
## through the bag icon in the top bar, PS5-fashion. The stores screen renders
## a page for it (title, wash, description, live install state) and pressing A
## there launches this exec.
##
## `flatpak run` rather than a path: the app is a system flatpak installed by
## marwanos-flatpak-install, and `flatpak run` is the entry point that sets up the
## sandbox, the runtime and the environment. DISPLAY is inherited from the shell,
## which is how it lands on gamescope (see Launcher._spawn).
##
## -gamepadui, NOT the bare desktop client, and the difference is the whole
## bug this line used to be. The desktop UI is a tray-centric spread of CEF
## windows, and under gamescope it frequently never maps a window the
## compositor adopts -- while the flatpak wrapper pid stays alive. The launch
## seam watches that pid, so the shell said Steam was open and offered Close
## over a TV showing nothing, which is the worst state this machine has: a
## system that claims a thing the screen contradicts. Big Picture is the one
## Steam UI that reliably maps a single fullscreen window gamescope can seat,
## and the only one a controller can drive at all -- it is what the Deck
## itself runs under this same compositor. -gamepadui is the flag every
## community gamescope session starts the client with -- it is the Deck UI's
## own name for itself. -bigpicture is the older documented alias that lands
## in the same UI on current clients, and the first thing to try if a client
## update ever changes what -gamepadui does.
##
## steam://store rides along after the flag so Big Picture lands on the
## storefront -- the page the person asked for by pressing A on a STORE tab.
## If a client update ever stops honouring the pairing, the failure mode is
## Big Picture's home screen instead of the store: wrong page, still a
## drivable UI, which is the direction this line is allowed to fail in.
##
## Phase 1 deletes this alongside the rest of the file: marwand enumerates real
## installs and stores stop being a hand-written list.
const STEAM_STORE := {
	"id": "store.steam",
	"title": "Steam",
	"tagline": "Valve's storefront and library, installed from Flathub",
	"description": "Browse and buy on the Steam store, and pull your library"
		+ " down to this machine. A opens Big Picture on the storefront;"
		+ " X opens the desktop client with the stick as a mouse. Quitting"
		+ " Steam lands back on this page.",
	"accent": "#2A3F5A",
	# DIRECTLY UNDER THE SESSION'S OWN GAMESCOPE -- the nested-gamescope
	# detour is over, and the bench journal is why. The nesting shipped as a
	# flicker fix and lasted one evening: gamescope 3.16.23 as an inner
	# compositor on NVIDIA 610.43.03 died of `terminate called without an
	# active exception` three minutes into Hollow Knight (2026-08-10 10:33,
	# coredump on the bench), taking the game with it and leaving the sandbox
	# running behind a returned rail. The flicker it was chasing has a fix
	# that does not stack compositors: the SESSION's gamescope now runs
	# --force-composition, which closes the direct-scanout path the blinking
	# came from. One compositor, half the crash surface; the nested shape can
	# come back if a future gamescope survives it, and Launcher._spawn still
	# fills {W}/{H} tokens for whatever needs them next.
	"exec": ["flatpak", "run", "com.valvesoftware.Steam", "-gamepadui", "steam://store"],
	# The desktop-entry id, which is how the tab finds the application's REAL
	# icon: marwanos-appscan resolves an absolute path for everything installed,
	# and store_tab.gd matches on this rather than on the "id" above. The two are
	# deliberately different strings -- "store.steam" is the shell's name for a
	# tab, and this is what the file on disk is called. Empty or absent means the
	# tab draws its fallback glyph, which is also what happens until Steam is
	# actually installed.
	"app_id": "com.valvesoftware.Steam",
}


## Steam's OTHER face: the desktop client, launched deliberately from the
## shell rather than reached through Big Picture's own "Switch to Desktop".
## The in-client switch can never work here and is not a bug in this shell's
## power to fix: it restarts the client into the tray-centric multi-window
## desktop UI mid-session, under a compositor built to seat one fullscreen
## window -- the exact shape that ran invisibly for days. Launching desktop
## mode FROM THE SHELL is different in the two ways that matter: gamescope's
## --force-windows-fullscreen manages the windows from their first map, and
## the launch seam attaches the pad bridge in pointer mode (see pad_keys.gd)
## from the first frame -- because the desktop client is a mouse UI and this
## machine's only mouse is the right stick.
##
## A separate id, not a flag on STEAM_STORE: the launch seam, the splash and
## the bridge all key on the entry id, and "Steam as a storefront" and "Steam
## as a desktop program" want different treatment from every one of them.
static func steam_desktop_entry() -> Dictionary:
	return {
		"id": "store.steam.desktop",
		"title": "Steam",
		"accent": str(STEAM_STORE["accent"]),
		"exec": ["flatpak", "run", "com.valvesoftware.Steam"],
		"app_id": str(STEAM_STORE["app_id"]),
		"icon": store_icon_path(str(STEAM_STORE["app_id"])),
	}


## THE APPS SHELF IS GONE FROM THE STORES SCREEN, on the owner's word, and
## APPS_TAB with it. It was a tab whose page was a grid of every application
## the image ships -- which is the same set the RAIL already draws, installed
## cards and "press A to download it" cards side by side. Two screens listing
## the same applications is the thing ADR 0006 keeps calling one-thing-two-homes,
## and the store is the wrong one of the two to keep it in: a store is where you
## go to reach somebody else's catalogue, and the shelf was this machine's own.
## The rail is the library and stays the whole answer for what is on the
## machine; store_tab.gd's drawn "mark" fallback went out with this, since Steam
## and every store after it names a real application icon.
##
## THE FILES CARD IS GONE FROM THE RAIL for the mirror reason -- the file
## manager is a top-bar icon next to the gear and the power button now (see
## shell_root._build_topbar), so FILES_APP and builtin_apps() went with it.
## Nothing replaced the "surface" field they were the only user of: a shell
## surface is reached from the bar, and the bar's icons call their seam
## directly, which is one fewer indirection than a card that named a seam in a
## string.


static func stores() -> Array:
	return [STEAM_STORE]


## The desktop-entry ids of every store's application.
##
## This is how "one thing, one home" is enforced now: marwanos-appscan reports
## a store's application like any other install -- the stores screen needs
## that record to answer "is it actually here" and to find its real icon --
## and the RAIL is what filters these ids out (shell_root._populate), because
## the rail is the one place deciding what becomes a rail card. The scanner
## used to make this call by omitting Steam from apps.tsv, which turned the
## installed list into a lie the stores screen then believed.
static func store_app_ids() -> Array:
	var ids: Array = []
	for store in stores():
		var app_id := str(store.get("app_id", ""))
		if not app_id.is_empty():
			ids.append(app_id)
	return ids


## THE APPLICATIONS THIS IMAGE SHIPS, whether or not they are on the machine.
##
## The rail draws what is installed, and that was a complete answer right up
## until an application could be REMOVED. After that, "not installed" stopped
## meaning "never heard of it" and started meaning "gone, and gettable back" --
## with nowhere on the rail to say so. The stores screen offers Steam back
## because Steam is a store; nothing offered Kodi back, so removing it was a
## one-way door on a machine with no terminal.
##
## So an entry here that is not in the installed list becomes a card in the
## `available` state: it looks like an application, says it is not installed,
## and downloads itself when pressed (see tile.gd's _on_pressed).
##
## THE IDS MUST MATCH appctl's SHIPPED_APPS. That list is the privilege
## boundary and this one is only what gets drawn -- a name here that is not
## there produces a card whose press is refused by root, which is the safe
## direction for the two to disagree in. Phase 1 deletes both: marwand serves
## the shipped set and the installed set from one place.
## The tagline is one sentence of what the thing IS, for the store grid's
## focused-card line -- the same job the stores' "tagline" field does on a
## store page. The rail never shows it: there the subtitle is the state.
const AVAILABLE_APPS := [
	# Steam is listed because the ids here mirror appctl's SHIPPED_APPS, but
	# its card never reaches the rail in any state: _populate filters store
	# apps (see store_app_ids), and the stores screen is what offers it back.
	{
		"id": "com.valvesoftware.Steam",
		"title": "Steam",
		"accent": "#2A3F5A",
		"tagline": "Valve's storefront and library",
	},
	{
		"id": "app.zen_browser.zen",
		"title": "Zen Browser",
		"accent": "#3B2F5A",
		"tagline": "A browser, on the TV",
	},
	{
		"id": "tv.kodi.Kodi",
		"title": "Kodi",
		"accent": "#1F4E63",
		"tagline": "Your media library, ten feet tall",
	},
	# The 2026-08-08 curation (RetroArch, VLC, Moonlight, Spotify, Dolphin) is
	# gone on the owner's word: apps nobody asked for made the shelf read as
	# filler, and the file manager the Dolphin flatpak stood in for is the
	# shell's own screen now. The mechanism stays -- adding a shipped app is
	# still one entry here and one id in shipped-apps.
]

## What an available card says under its title. One sentence, and it is the
## instruction rather than the state: "Not installed" alone tells someone what
## is wrong without telling them that the thing they are looking at fixes it.
const AVAILABLE_SUBTITLE := "Not installed -- press A to download it"


## Rail entries for every shipped application that the installed seam does not
## already know about, in whatever state.
##
## Matched against EVERY installed record rather than only the installed ones:
## an application part-way through its first download is already on the rail as
## a pending card with a live progress line, and a second card next to it
## offering to start the same download would be both wrong and pressable.
static func available(known_ids: Array) -> Array:
	var result: Array = []
	for app in AVAILABLE_APPS:
		if known_ids.has(str(app["id"])):
			continue
		result.append({
			"id": str(app["id"]),
			"title": str(app["title"]),
			"subtitle": AVAILABLE_SUBTITLE,
			# The prefetched Flathub icon, where storeart has landed one. An
			# available application has nothing else on the machine to draw --
			# no flatpak, no export, nothing appscan could find -- and this is
			# exactly the gap the artwork cache exists to fill: the logo shows
			# BEFORE the multi-gigabyte install it is advertising, not after.
			"icon": store_icon_path(str(app["id"])),
			"exec": [],
			"state": "available",
			"accent": str(app["accent"]),
			"tagline": str(app.get("tagline", "")),
		})
	return result


## ---------------------------------------------------------------------------
## THE ARTWORK CACHE, read side.
##
## marwanos-storeart (see os/files/usr/lib/marwanos/storeart) prefetches each
## shipped application's Flathub icon into /var/marwanos/store/icons, root-
## written and player-read like every other seam in this project. The shell
## never fetches: it renders whatever file is there, and a machine that has
## been online once renders a full store forever after, offline included --
## which is what makes the store screen instant rather than a loading spinner.
##
## Resolved at entry-build time rather than draw time, so a consumer holding
## an entry can treat "icon" as settled the way it already does for appscan's
## paths. A missing file resolves to empty and the card draws its accent wash,
## which is the same fallback every icon in the shell already has.

## Where the cache lives on the appliance.
const STORE_DIR := "/var/marwanos/store"

## The desk and harness override, in the spirit of MARWANOS_SHELL_STATUS_DIR:
## point it at a directory holding icons/<app-id>.png and the store renders
## art on a machine that has no /var/marwanos at all.
const STORE_DIR_ENV := "MARWANOS_SHELL_STORE_DIR"


## THE APPLICATIONS THE PAD BRIDGE COVERS, and how each is driven: desktop
## programs with no gamepad support of their own, which the shell drives by
## injecting X events while they run (see pad_keys.gd). "keys" walks a
## keyboard-navigable UI with arrows and Return -- right for a file manager.
## "pointer" moves a real cursor with the stick and clicks -- right for a
## mouse-first UI like the Steam desktop client, where arrow keys go nowhere.
## A TABLE, not a flag on the entry, because installed entries come from
## apps.tsv and a column there would put shell input policy into a scanner
## whose whole job is reporting what is on disk. Gamepad-native apps must
## never appear here: Steam's Big Picture and Kodi read the pad themselves,
## and double-delivered input is worse than none -- which is also why the
## desktop launch has its own id, so Big Picture's cannot match it.
## "keys" currently has no member: the file manager it was built for
## (Dolphin) was replaced by the shell's own Files screen, which reads the
## pad natively. The dialect stays implemented -- the next keyboard-navigable
## desktop app is one line here.
const PAD_KEY_APPS := {
	"store.steam.desktop": "pointer",
}


## The bridge mode for an entry id: "keys", "pointer", or empty for the apps
## that speak gamepad natively and get no bridge at all.
static func pad_key_mode(app_id: String) -> String:
	return str(PAD_KEY_APPS.get(app_id, ""))


## The one-line description AVAILABLE_APPS carries for an id, or empty. The
## store grid asks this for INSTALLED applications too -- their records come
## from apps.tsv, which has no such column -- so the shelf can say what a
## thing is whether or not it is here yet.
static func tagline_for(app_id: String) -> String:
	for app in AVAILABLE_APPS:
		if str(app["id"]) == app_id:
			return str(app.get("tagline", ""))
	return ""


## ---------------------------------------------------------------------------
## THE STEAM METADATA CACHE, read side.
##
## The same shape as the icon cache above and in the same tree: marwanos-storeart
## writes /var/marwanos/store/meta/steam.<appid>.json, which is the `data` object
## of Steam's own appdetails answer -- name, short_description and the rest of
## what the store page says about a game. The shell never calls the API: it reads
## whatever file is there, so a machine that has been online once describes its
## library forever after, offline included.
##
## READ AT THE MOMENT IT IS SHOWN rather than polled into memory like the artwork
## table, because there is exactly one consumer and it is a button press: the
## details panel opens for one game at a time and asks for one file. Polling a
## directory of hundreds of JSON documents to keep an answer nobody is looking at
## would be the wrong trade in both directions.
##
## A MISSING OR MALFORMED FILE IS AN EMPTY ANSWER, not an error. The cache warms
## per game and only when the machine has a network; the panel has two more
## sources behind this one (see details_panel.gd) and drawing one of those is a
## complete screen.
const STORE_META_SUBDIR := "meta"


## Steam's own words about a game, as the appdetails `data` object, or empty.
static func steam_meta(entry_id: String) -> Dictionary:
	if not entry_id.begins_with("steam."):
		return {}

	var base := OS.get_environment(STORE_DIR_ENV)
	if base.is_empty():
		base = STORE_DIR
	var path := base.path_join(STORE_META_SUBDIR).path_join(entry_id + ".json")
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		ShellLog.warn("could not open %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		ShellLog.warn("%s is not a JSON object; ignoring it" % path)
		return {}
	return parsed


## `steam_description` USED TO SIT HERE and is gone rather than kept for
## politeness. It read short_description out of the document steam_meta returns,
## and its one caller was the details panel -- which now asks GameMeta for a
## description instead, because Steam is one source for that field and the panel
## has no business knowing it is the first one. Every other field GameMeta reads
## out of the same document is read the same way, so a wrapper for exactly one
## of them would have been the odd path.
## The cached icon for an application id, or empty if none has landed yet.
static func store_icon_path(app_id: String) -> String:
	if app_id.is_empty():
		return ""
	var base := OS.get_environment(STORE_DIR_ENV)
	if base.is_empty():
		base = STORE_DIR
	var path := base.path_join("icons").path_join(app_id + ".png")
	return path if FileAccess.file_exists(path) else ""
