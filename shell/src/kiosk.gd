extends Node

## Fullscreen, borderless, no cursor -- asserted by the client rather than left to
## the compositor -- and an honest report of the geometry it was actually handed.
##
## Under plan A gamescope covers most of the first half: --force-windows-fullscreen
## sizes the window to the nested display and --hide-cursor-delay 1 takes the
## pointer away. Under plan B none of it exists -- cage 0.2.0's entire CLI is
## `-d -h -m -s -v` and there is no cursor flag at all (ADR 0004 finding 9). D4
## says the shell code is identical either way, so the shell has to be the thing
## that makes it true.
##
## Doing it here as well as in project.godot is not belt and braces. The project
## settings apply once, at window creation, before the compositor has necessarily
## finished sizing anything; these run after the tree is up and again whenever the
## window regains focus, which is when a compositor is most likely to have handed
## the pointer back.
##
## What this file deliberately does NOT do is choose a screen. The single screen is
## delivered below the shell -- `video=<internal>:d` in the kargs,
## marwanos-panel.service, and WLR_DRM_DEVICES under plan B (see ADR 0007) -- and
## it is delivered there because that is the only layer that also covers the boot.
## Every client-side fix leaves the lid panel showing plymouth for the whole of it.
##
## Two things a design pass believed about this file that a VM run on 2026-08-05
## disproved, kept here so they are not re-derived:
##
##   * "The shell runs native Wayland under cage." It does not. cage ships with
##     Xwayland, Godot's linuxbsd default driver order puts x11 first, and the
##     measured run under cage reported server "X11". So the shell is on XWayland
##     under BOTH plans, and the Wayland-backend limitations that were about to be
##     cited as the reason it cannot pick a screen do not even apply.
##   * "DisplayServer.get_name() is therefore an oracle for D4." It is not, for the
##     same reason -- it says X11 either way. The session script's own line is the
##     oracle. get_name() is still logged, because it is the thing that would change
##     if the driver order or cage's Xwayland support ever did.
##
## What remains true regardless: there is no DisplayServer.screen_get_name() in
## Godot 4.7.1 at all, so the shell cannot map "HDMI-A-1" to a screen index even in
## principle, and picking by index would be picking by enumeration order -- the same
## coin flip that makes cage's `-m last` unusable.
##
## So what the shell owes is the measurement. On 2026-08-05 the only evidence of the
## spanning defect was a phone camera pointed at a laptop; one boot with the lines
## below in it settles the geometry permanently.


func _ready() -> void:
	_assert_display_policy()
	if _windowed_for_desk():
		# Said once, here, rather than from _assert_display_policy: that runs again
		# on every focus-in, and a warning repeated three times in the first second
		# reads like something going wrong repeatedly instead of a mode being set.
		ShellLog.warn("%s is set: windowed with a cursor, at %dx%d. Kiosk policy NOT applied."
			% [WINDOWED_ENV, DESK_WINDOW_SIZE.x, DESK_WINDOW_SIZE.y])
		ShellLog.warn("this is a desk run; the appliance never sets that variable")
	else:
		ShellLog.info("kiosk display policy applied (fullscreen, borderless, cursor hidden)")
	_log_display_geometry("at startup")

	# A Wayland compositor's first xdg_toplevel configure can arrive after _ready,
	# so the numbers above may be what Godot guessed rather than what it was
	# handed. Trust the second pass.
	#
	# A one-shot signal connection rather than `await get_tree().process_frame`,
	# deliberately: awaiting turns _ready into a coroutine that returns early, and
	# autoload order is load-bearing here (see project.godot's [autoload] note).
	get_tree().process_frame.connect(_log_after_first_frame, CONNECT_ONE_SHOT)


func _log_after_first_frame() -> void:
	_log_display_geometry("after the first frame")


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


## Set to anything non-empty to run windowed with a visible cursor, for testing
## the UI on a desk instead of on the appliance.
##
## This exists because the policy below is otherwise inescapable: fullscreen,
## borderless and no cursor is correct on a machine whose only input is a
## gamepad, and hostile on a developer's desktop, where it covers the screen with
## no pointer and no window furniture to close. scripts/run-shell-wsl.sh sets it.
##
## Nothing in the appliance sets it. The session script does not export it, so on
## the target this branch is unreachable -- it is not a runtime switch that a
## misconfigured machine could trip into, it is a variable that only exists if a
## human typed it. That is the same shape as D5's devmode flag and deliberately
## not the same shape as the compositor lever ADR 0005 removed.
const WINDOWED_ENV := "MARWANOS_SHELL_WINDOWED"

## 16:9, because the design surface is 1920x1080 and a desk window that is not
## 16:9 pillarboxes itself -- which would make every judgement about margins and
## focus visibility a judgement about the wrong rectangle. Small enough to leave
## the rest of the screen usable: MODE_WINDOWED alone kept the 3440x1440 size
## Godot had already picked, so it was a window covering the whole display, which
## is most of what was wrong with fullscreen in the first place.
const DESK_WINDOW_SIZE := Vector2i(1600, 900)


func _windowed_for_desk() -> bool:
	return not OS.get_environment(WINDOWED_ENV).is_empty()


func _assert_display_policy() -> void:
	var window := get_window()

	if _windowed_for_desk():
		if window != null:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			window.size = DESK_WINDOW_SIZE
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if window != null:
		window.mode = Window.MODE_FULLSCREEN
		window.borderless = true

	# MOUSE_MODE_HIDDEN rather than MOUSE_MODE_CAPTURED. Captured confines the
	# pointer and feeds relative motion, which is what a first-person game wants
	# and would make a stray mouse generate a stream of events into a UI that has
	# no use for them. Hidden is exactly the requirement: no cursor.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


## Everything the shell can see about the displays, in the journal.
func _log_display_geometry(when: String) -> void:
	# get_name() was expected to name the compositor -- "X11" for gamescope's
	# XWayland, "Wayland" for cage -- and the 2026-08-05 VM run measured "X11"
	# while cage was demonstrably the compositor. cage ships Xwayland and Godot
	# prefers x11, so this says X11 under both plans. Logged anyway: it is exactly
	# the line that would change if the driver order or cage's Xwayland support
	# moved, and a shell that is suddenly on native Wayland is a different program
	# from the one these notes describe.
	ShellLog.info("display %s: server %s, adapter %s" % [
		when, DisplayServer.get_name(), RenderingServer.get_video_adapter_name(),
	])

	var count := DisplayServer.get_screen_count()
	ShellLog.info("screens: %d, primary %d, keyboard focus %d" % [
		count, DisplayServer.get_primary_screen(), DisplayServer.get_keyboard_focus_screen(),
	])

	for index in count:
		# No name is logged because there is none to log -- see the class comment.
		# Position and size are the identification: on a side-by-side layout the
		# second screen's position.x equals the first one's width, and that is the
		# fingerprint of the bug this logging exists for.
		#
		# One Wayland caveat worth knowing before trusting these numbers:
		# screen_get_size comes from wl_output::mode and is in physical pixels,
		# while screen_get_position comes from wl_output::geometry and is logical.
		# They agree only while scale is 1, which it is under both plans.
		ShellLog.info("screen %d: size %s pos %s scale %.2f dpi %d refresh %.2f" % [
			index,
			DisplayServer.screen_get_size(index),
			DisplayServer.screen_get_position(index),
			DisplayServer.screen_get_scale(index),
			DisplayServer.screen_get_dpi(index),
			DisplayServer.screen_get_refresh_rate(index),
		])

	var window := get_window()
	if window == null:
		ShellLog.error("no window; nothing else can be measured")
		return

	# window_get_position is deliberately absent: DisplayServerWayland returns a
	# constant zero for it, so logging it would be logging a zero and inviting
	# someone to draw a conclusion from it.
	var window_size := DisplayServer.window_get_size()
	ShellLog.info("window: mode %d size %s" % [DisplayServer.window_get_mode(), window_size])
	ShellLog.info("viewport: canvas %s design %s stretch mode %d aspect %d" % [
		window.get_visible_rect().size,
		window.content_scale_size,
		window.content_scale_mode,
		window.content_scale_aspect,
	])

	# What the stretch actually does with the space, which depends on the aspect
	# mode and must not be assumed. Under EXPAND there are no bars at all -- the
	# viewport grows into the extra width instead -- so the bar arithmetic below
	# would report a letterbox that is not on the screen. On a machine whose only
	# surface is the journal, a confidently wrong line is worse than no line.
	if window.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND:
		var surface := window.get_visible_rect().size
		ShellLog.info("stretch: expand -- no bars; design surface is %dx%d (%d px wider than the %d base)" % [
			int(surface.x), int(surface.y),
			int(surface.x) - window.content_scale_size.x, window.content_scale_size.x,
		])
	elif window.content_scale_size.y > 0 and window_size.y > 0:
		# The pillarbox aspect "keep" produces: with a window wider than the
		# design surface the content is scaled to the window's HEIGHT and
		# centred, leaving an equal black bar each side. On one display that is
		# a harmless letterbox. Across two it is the UI cut in half -- one bar
		# landing invisibly on the lid panel and the other showing up as the
		# black band on the right of the TV.
		var design_aspect := float(window.content_scale_size.x) / float(window.content_scale_size.y)
		var window_aspect := float(window_size.x) / float(window_size.y)
		if window_aspect > design_aspect:
			var drawn_width := int(round(window_size.y * design_aspect))
			ShellLog.info("stretch: drawing %dx%d with a %d px black bar each side" % [
				drawn_width, window_size.y, (window_size.x - drawn_width) / 2,
			])
		elif window_aspect < design_aspect:
			# The other half of the same arithmetic. Logged rather than left to
			# be inferred from its absence: a missing line reads as "the check
			# did not run", and on a machine whose only surface is the journal
			# that is indistinguishable from a bug.
			var drawn_height := int(round(window_size.x / design_aspect))
			ShellLog.info("stretch: drawing %dx%d with a %d px black bar top and bottom" % [
				window_size.x, drawn_height, (window_size.y - drawn_height) / 2,
			])
		else:
			ShellLog.info("stretch: window matches the design aspect exactly; no bars")

	# The one line that names the bug outright if it ever happens again.
	var matches_a_screen := false
	for index in count:
		if DisplayServer.screen_get_size(index) == window_size:
			matches_a_screen = true
	if count > 1 and not matches_a_screen:
		ShellLog.error("window %s matches no single screen of %d -- the compositor handed the shell a surface spanning outputs" % [window_size, count])
