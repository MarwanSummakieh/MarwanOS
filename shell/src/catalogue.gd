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
## The steam://store argument opens the client on its storefront, which is the
## page the person asked for by pressing A on a STORE tab -- the client
## bootstraps first if it has to, and that is what the page's install line has
## already told them to expect.
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
	"exec": ["flatpak", "run", "com.valvesoftware.Steam", "steam://store"],
	# The desktop-entry id, which is how the tab finds the application's REAL
	# icon: marwanos-appscan resolves an absolute path for everything installed,
	# and store_tab.gd matches on this rather than on the "id" above. The two are
	# deliberately different strings -- "store.steam" is the shell's name for a
	# tab, and this is what the file on disk is called. Empty or absent means the
	# tab draws its fallback glyph, which is also what happens until Steam is
	# actually installed.
	"app_id": "com.valvesoftware.Steam",
}


static func stores() -> Array:
	return [STEAM_STORE]


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
const AVAILABLE_APPS := [
	{
		"id": "com.valvesoftware.Steam",
		"title": "Steam",
		"accent": "#2A3F5A",
	},
	{
		"id": "app.zen_browser.zen",
		"title": "Zen Browser",
		"accent": "#3B2F5A",
	},
	{
		"id": "tv.kodi.Kodi",
		"title": "Kodi",
		"accent": "#1F4E63",
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
			"icon": "",
			"exec": [],
			"state": "available",
			"accent": str(app["accent"]),
		})
	return result
