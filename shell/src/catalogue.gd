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
		+ " down to this machine. Pressing A opens Steam itself, fullscreen,"
		+ " on its storefront; quitting Steam lands back on this page.",
	"accent": "#2A3F5A",
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


## The system's own shelf in the stores screen: every application the image
## ships, rendered as a grid of cards by the shell itself. Not a store entry --
## it carries no exec and no app_id, because there is nothing to launch and
## nothing to install ABOUT the tab; the cards on its page carry their own.
## "mark" names the drawn 2x2 tab mark (see store_tab.gd) rather than a font
## glyph, because the shipped Phosphor build carries no glyph names to look a
## new codepoint up by, and a guessed codepoint renders as a missing-glyph box
## on the one machine that matters.
const APPS_TAB := {
	"id": "store.apps",
	"title": "Apps",
	"mark": "grid",
}


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
	{
		"id": "org.kde.dolphin",
		"title": "Dolphin",
		"accent": "#22405A",
		"tagline": "A real file manager, driven by the pad",
	},
	{
		"id": "org.libretro.RetroArch",
		"title": "RetroArch",
		"accent": "#4A3A22",
		"tagline": "Retro consoles, emulated",
	},
	{
		"id": "org.videolan.VLC",
		"title": "VLC",
		"accent": "#5A3A1F",
		"tagline": "Plays practically any video file",
	},
	{
		"id": "com.moonlight_stream.Moonlight",
		"title": "Moonlight",
		"accent": "#2F4A3A",
		"tagline": "Stream games from your gaming PC",
	},
	{
		"id": "com.spotify.Client",
		"title": "Spotify",
		"accent": "#1F4A2A",
		"tagline": "Music through the good speakers",
	},
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


## THE APPLICATIONS THE PAD-KEYS BRIDGE COVERS: desktop programs with no
## gamepad support of their own, which the shell drives by translating pad
## presses into X key events while they run (see pad_keys.gd). A LIST, not a
## flag on the entry, because installed entries come from apps.tsv and a
## column there would put shell input policy into a scanner whose whole job
## is reporting what is on disk. Games and TV-native apps must never appear
## here: Steam and Kodi read the pad themselves, and double-delivered input
## is worse than none.
const PAD_KEY_APPS := ["org.kde.dolphin"]


static func pad_key_app(app_id: String) -> bool:
	return PAD_KEY_APPS.has(app_id)


## The one-line description AVAILABLE_APPS carries for an id, or empty. The
## store grid asks this for INSTALLED applications too -- their records come
## from apps.tsv, which has no such column -- so the shelf can say what a
## thing is whether or not it is here yet.
static func tagline_for(app_id: String) -> String:
	for app in AVAILABLE_APPS:
		if str(app["id"]) == app_id:
			return str(app.get("tagline", ""))
	return ""


## The cached icon for an application id, or empty if none has landed yet.
static func store_icon_path(app_id: String) -> String:
	if app_id.is_empty():
		return ""
	var base := OS.get_environment(STORE_DIR_ENV)
	if base.is_empty():
		base = STORE_DIR
	var path := base.path_join("icons").path_join(app_id + ".png")
	return path if FileAccess.file_exists(path) else ""
