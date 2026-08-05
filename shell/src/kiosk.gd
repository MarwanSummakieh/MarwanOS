extends Node

## Fullscreen, borderless, no cursor -- asserted by the client rather than left to
## the compositor.
##
## Under plan A gamescope covers most of this: --force-windows-fullscreen sizes
## the window to the nested display and --hide-cursor-delay 1 takes the pointer
## away. Under plan B none of it exists -- cage 0.2.0's entire CLI is
## `-d -h -m -s -v` (ADR 0004 finding 9) and there is no cursor flag at all. D4
## says the shell code is identical either way, so the shell has to be the thing
## that makes it true.
##
## Doing it here as well as in project.godot is not belt and braces. The project
## settings apply once, at window creation, before the compositor has necessarily
## finished sizing anything; these run after the tree is up and again whenever the
## window regains focus, which is when a compositor is most likely to have handed
## the pointer back.

func _ready() -> void:
	_assert_display_policy()
	ShellLog.info("kiosk display policy applied (fullscreen, borderless, cursor hidden)")


func _notification(what: int) -> void:
	# A compositor that takes focus away and gives it back can restore the
	# pointer. Cheap to re-apply, and a cursor on screen is a failed acceptance
	# criterion, not a cosmetic issue.
	#
	# Both notifications, because which one a display server actually delivers
	# varies and neither is guaranteed under a kiosk compositor with one client.
	# _ready is what covers the normal case; these are for the ones it does not.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_assert_display_policy()


func _assert_display_policy() -> void:
	var window := get_window()
	if window != null:
		window.mode = Window.MODE_FULLSCREEN
		window.borderless = true

	# MOUSE_MODE_HIDDEN rather than MOUSE_MODE_CAPTURED. Captured confines the
	# pointer and feeds relative motion, which is what a first-person game wants
	# and would make a stray mouse generate a stream of events into a UI that has
	# no use for them. Hidden is exactly the requirement: no cursor.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
