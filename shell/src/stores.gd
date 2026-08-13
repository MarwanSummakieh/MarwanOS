extends Node

## ============================================================================
## THE STORES SEAM.
##
## The third fullscreen surface, and the first to copy the pattern the settings
## seam left for it -- one entry point, two signals, one thing at a time. The
## settings seam's header predicted "a third fullscreen surface (Phase 1's
## store, a guide overlay) has a pattern to copy rather than a precedent to
## untangle"; this is that surface, arriving in Phase 0 at the owner's request
## (ADR 0006, third amendment).
##
## Deliberately SEPARATE from the launch seam, same as settings: opening the
## stores screen is a shell-internal swap and must not become an RPC when
## Phase 1 rewires launcher.gd. The screen itself DOES launch things -- a store
## tab's A press goes through Launcher.launch like every other launch in the
## project -- but opening the screen that offers the choice is not launching.
## ============================================================================

## Emitted the moment the screen is requested, before anything is on screen.
## The home rail uses it to save focus and get out of the way.
signal stores_opened()

## Emitted when the screen is gone and the home rail should come back.
signal stores_closed()

## THIS SEAM NO LONGER OPENS A SCREEN AT ALL, and the name survives for the same
## reason it survived the last change: the HOME RAIL is what listens to
## `stores_opened`/`stores_closed`, and what they mean to it is unchanged --
## something took the screen, get out of the way; it went, come back.
##
## The history in two lines. This was a storefront; then ADR 0010 replaced it
## with this repository's own Steam client, and the bag icon opened
## steam_screen.gd. On 2026-08-13 that client was deleted in favour of Valve's
## own Big Picture, so there is no in-shell screen left to open -- the bag icon
## now raises STEAM ITSELF, which the session keeps running.
##
## Handed to the Launcher rather than run here, deliberately: the launcher owns
## the busy state, the splash, and the return-to-rail seam, and a second way to
## put something on the screen is exactly the kind of parallel path this shell
## has been bitten by before. Against a warm client `flatpak run` hands over and
## exits in about a second, which the launcher's pid poll already handles.
const STEAM_ENTRY := {
	"id": "steam.bigpicture",
	"title": "Steam",
	"exec": ["flatpak", "run", "com.valvesoftware.Steam", "-gamepadui"],
}


## Never open, now that this launches rather than draws. Kept because the peer
## surfaces (settings, power, files, info) each guard on every other one's
## is_open(), and a seam that quietly stopped answering would turn those guards
## into silent no-ops rather than a compile error.
func is_open() -> bool:
	return false


## The only way the stores screen gets opened.
func open() -> void:
	if is_open():
		# One at a time, same as the launcher: a second press while the screen
		# is up is a bounced button, not a request for two.
		return
	if Launcher.is_busy():
		# The home rail is already hidden behind a launch; stacking a second
		# restoring surface would restore it twice. Same guard as settings.
		return
	if Settings.is_open() or Power.is_open() or Files.is_open() or Info.is_open():
		# The shell surfaces are peers, not layers: whichever is up owns the
		# screen until it closes. (The others hold the mirror guards.)
		return

	ShellLog.info("stores opened")

	# Emitted before the launch so the home rail gets out of the way in the same
	# frame, exactly as it did when this opened a screen. `stores_closed` is NOT
	# emitted here and is not emitted later either: the launcher owns the return
	# journey now and fires launch_finished, which shell_root already handles.
	stores_opened.emit()
	Launcher.launch(STEAM_ENTRY)
