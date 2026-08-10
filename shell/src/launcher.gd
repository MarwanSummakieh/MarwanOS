extends Node

## ============================================================================
## THE LAUNCH SEAM.
##
## This is the file Phase 1 replaces. Everything the shell knows about running
## something other than itself passes through launch() and the two signals below,
## and nothing else in this project reaches into the launch path. That is the
## whole point of the file existing: the plan's Phase 1 hook is "the shell's
## placeholder launch-a-scene seam becomes Launch over JSON-RPC", and this is
## where that bolts in.
##
## When it does, exactly two functions change:
##
##   _run(entry)    -> send `Launch { target_id }` to marwand over the WebSocket
##                     and return; do not wait.
##   _on_closed()   -> becomes the handler for marwand's `AppExited` event.
##
## Nothing else moves. The home rail, the cards, the focus handling and the hint
## row only ever see launch_started and launch_finished, so they do not care
## whether the thing that started was a placeholder scene or a Flatpak.
##
## Deliberately single-purpose. No process management, no queue, no retry, no
## state machine beyond "one thing at a time". Phase 1 puts all of that in the
## daemon, where it belongs: the shell is a renderer. If something wants to grow
## here, that is the signal it belongs in marwand instead.
## ============================================================================

## Emitted the moment a launch is requested, before anything is on screen. The
## home rail uses it to save focus and get out of the way.
signal launch_started(entry: Dictionary)

## Emitted when the launched thing is done and the home rail should come back. In
## Phase 1 this fires on marwand's AppExited rather than on a keypress; the
## consumer side is identical.
signal launch_finished(entry: Dictionary)

## Emitted when the overlay asks for the running app to be backgrounded rather
## than stopped. The rail comes back; the process does not go away, and
## launch_finished still fires later when it eventually exits.
signal minimized(entry: Dictionary)

const LaunchPlaceholder = preload("res://src/launch_placeholder.gd")
const LaunchSplash = preload("res://src/launch_splash.gd")
const PadKeys = preload("res://src/pad_keys.gd")
const Catalogue = preload("res://src/catalogue.gd")

var _current: Dictionary = {}

# Typed as the script rather than as Control so `entry` and `closed` resolve
# statically -- GDScript treats a missing member on a typed variable as an error,
# which is the point.
var _placeholder: LaunchPlaceholder = null

# The splash over the gap between spawn and the app's first frame. Owned here
# rather than by shell_root because only this file knows which branch _run
# took: the placeholder branch draws its own screen and must not get a second
# one. Removed on launch_finished like everything else the seam puts up.
var _splash: LaunchSplash = null

# The pad-to-keyboard bridge, alive only while a PAD_KEY_APPS application is
# confirmed on screen. Created by the watchdog's ELSEWHERE branch -- never
# earlier, so nothing types into an application that has not drawn -- and
# freed wherever the launch ends. See pad_keys.gd for what it is.
var _pad_keys: PadKeys = null

# REMEMBERED, not just forwarded. The overlay can be open before the bridge
# exists -- press home during a slow desktop-Steam start, and the watchdog
# births the bridge minutes later, under a menu or keyboard that owns the pad.
# A bridge that starts life unpaused in that state left-clicks in Steam for
# every A meant for the on-screen keyboard (found in review); the stored flag
# is applied to the bridge at creation, so pause state is a property of the
# SESSION, not of whichever object happened to exist when it was set.
var _pad_keys_paused := false


func is_busy() -> bool:
	return not _current.is_empty()


## What is running, for anything that needs to name it on screen. A copy, so a
## consumer cannot write back into the seam's own record of the launch.
func current_entry() -> Dictionary:
	return _current.duplicate()


## The only way anything gets launched.
func launch(entry: Dictionary) -> void:
	if is_busy():
		# One at a time. A second press while something is up is a bounced button
		# or an impatient person, not a request to launch twice.
		return

	_current = entry
	ShellLog.info("launch requested: %s" % _label(entry))
	launch_started.emit(entry)
	_run(entry)


## Phase 0's stand-in for running something else: a fullscreen scene that covers
## the home rail until it is dismissed. It exists to prove the seam and the focus
## handoff, not to look like anything.
##
## An entry carrying an "exec" array takes the other branch and starts a REAL
## process -- see _spawn. That branch is a spike, not the architecture.
func _run(entry: Dictionary) -> void:
	var exec: Array = entry.get("exec", [])
	if not exec.is_empty():
		_spawn(exec)
		return

	_placeholder = LaunchPlaceholder.new()
	_placeholder.entry = entry
	_placeholder.closed.connect(_on_closed, CONNECT_ONE_SHOT)
	get_tree().root.add_child(_placeholder)


## ============================================================================
## THE SPIKE, AND IT IS MARKED AS ONE.
##
## This answers exactly one question -- can this stack run a real application on
## the appliance's compositor at all -- and it answers it the cheapest way that
## is not a lie: spawn the process, watch the pid, put the rail back when it
## dies. Steam is the first thing pointed at it.
##
## IT VIOLATES THE RULE THIS FILE'S HEADER STATES, deliberately and visibly. The
## shell is a renderer; process supervision belongs in marwand, which is Phase 1
## M1 and does not exist yet. Writing marwand to answer a feasibility question
## would be building the answer before knowing whether the question has one. So
## this stays until marwand lands and then it goes -- _run() sends `Launch` over
## the WebSocket and this function is deleted whole, along with the poll timer
## and the window watchdog below it. The launch splash survives the deletion:
## every marwand launch is a real process, so it goes up when the Launch is
## sent, and marwand's events replace the watchdog as what clears it.
##
## WHY IT SHOULD WORK. The shell is an X client on gamescope's XWayland, and a
## child process inherits DISPLAY, so the app lands on the same compositor with
## gamescope's --force-windows-fullscreen already pointed at it. That is the
## same path Steam takes on a Deck. If it does not work, the journal says which
## half failed rather than leaving a black screen to interpret.
##
## No stdout capture: the child inherits this process's descriptors, which
## marwanos-session has already pointed at systemd-cat, so the app's own output
## lands in the journal under the session's tag for free.
## ============================================================================

## How often to ask whether the launched process is still alive. Half a second
## is far below the threshold where a person notices the rail coming back late,
## and far above the cost of the check.
const EXIT_POLL_SECONDS := 0.5

var _pid: int = -1
var _poll: Timer = null

## Set once a close has been asked for, so the exit poll stops interrogating a
## pid it knows is on its way out. See _check_exit.
var _terminating := false


func _spawn(exec: Array) -> void:
	# {W}/{H} become the primary screen's real pixels, at launch time rather
	# than at catalogue-write time, because the catalogue is a constant and
	# the screen is whatever panel this stick was plugged into. Today's one
	# consumer is Steam's nested gamescope; the tokens are generic because a
	# second nested client will want exactly the same two numbers.
	#
	# Guarded, because headless reports zero screens and screen_get_size(0)
	# answers (0, 0) there (measured on the pinned engine) -- and a
	# `gamescope -W 0` is an instant argument error dressed as a launch. The
	# window size is the next-best truth, and the design surface is the floor.
	var screen := DisplayServer.screen_get_size(DisplayServer.get_primary_screen())
	if screen.x <= 0 or screen.y <= 0:
		screen = DisplayServer.window_get_size()
	if screen.x <= 0 or screen.y <= 0:
		screen = Vector2i(1920, 1080)
	var program := str(exec[0])
	var args := PackedStringArray()
	for i in range(1, exec.size()):
		var word := str(exec[i])
		word = word.replace("{W}", str(screen.x)).replace("{H}", str(screen.y))
		args.append(word)

	ShellLog.info("spawning %s %s" % [program, " ".join(args)])
	_close_escalate_ticks = 0
	_pid = OS.create_process(program, args)

	if _pid <= 0:
		# The launch failed before anything drew. Handing the screen straight
		# back is the honest response: the alternative is a hidden rail behind
		# an application that never started, which on this machine is a black
		# TV with no way out.
		ShellLog.error("could not start %s -- returning to the rail" % program)
		_on_closed()
		return

	ShellLog.info("started pid %d; watching for exit" % _pid)

	_poll = Timer.new()
	_poll.wait_time = EXIT_POLL_SECONDS
	_poll.timeout.connect(_check_exit)
	add_child(_poll)
	_poll.start()

	# The splash and its watchdog exist only on this branch: a real process
	# takes real seconds to put a frame up, and the placeholder is its own
	# screen already. Both are torn down in _finish with everything else.
	_splash = LaunchSplash.new()
	_splash.entry = _current
	get_tree().root.add_child(_splash)
	_start_watchdog()


## ============================================================================
## THE WINDOW WATCHDOG -- part of the spike, deleted with it.
##
## The exit poll above answers "is the process alive"; this answers the
## question that actually matters on a TV: "did anything appear". They are
## different questions, and the desktop Steam client is the proof -- a wrapper
## pid that lives for hours in front of a screen showing nothing. gamescope
## publishes GAMESCOPE_FOCUSED_WINDOW on the X root, Kiosk reads it (see the
## focus question there), and this compares the answer to the shell's own
## window: the moment focus belongs to anyone else, the app is on screen and
## the splash has done its job.
##
## If the deadline passes with the shell STILL focused and the pid still
## alive, the splash swaps to its honest failure state instead of promising
## forever. UNKNOWN -- no gamescope, so a desk run or the Xvfb harness --
## never fails and never clears: the plain splash simply holds until
## launch_finished, which keeps this safe headless.
##
## In Phase 1 marwand supervises the window question along with the process
## and this whole block goes with _spawn: the splash stays, driven by launch
## events instead of a poll.
## ============================================================================

## One ask per second: a person waits whole seconds for a client to draw, so
## finer polling buys nothing, and each ask is an xprop round trip.
const WINDOW_POLL_SECONDS := 1.0

## How long a spawned process gets to put a window up before the splash stops
## promising. Steam's cold start -- sandbox, update check, CEF -- is the
## slowest thing this machine launches and lands well inside 25 s; a launch
## still windowless past it has taken the desktop-client failure shape.
const WINDOW_DEADLINE_SECONDS := 25.0

var _watch: Timer = null
var _watched_seconds := 0.0


func _start_watchdog() -> void:
	_watched_seconds = 0.0
	_watch = Timer.new()
	_watch.wait_time = WINDOW_POLL_SECONDS
	_watch.timeout.connect(_check_window)
	add_child(_watch)
	_watch.start()


func _check_window() -> void:
	_watched_seconds += WINDOW_POLL_SECONDS

	match Kiosk.focused_window():
		Kiosk.Focus.ELSEWHERE:
			# Someone else owns the screen: the app arrived. The splash goes
			# now rather than at launch_finished, so the frame the app exits
			# on shows the rail and not a stale "Starting".
			ShellLog.info("focus moved off the shell after %.0f s; %s is on screen"
				% [_watched_seconds, _label(_current)])
			_stop_watchdog()
			_remove_splash()
			# The one moment the bridge may start: there is now provably an
			# application on screen to type into. Which is also why a desk run
			# never gets one -- the watchdog only answers ELSEWHERE where
			# gamescope exists, and that is the only place XTEST injection
			# lands where a person can see what it did.
			var mode := Catalogue.pad_key_mode(str(_current.get("id", "")))
			if _pad_keys == null and not mode.is_empty():
				_pad_keys = PadKeys.new()
				_pad_keys.mode = mode
				# Born already respecting whatever surface owns the pad right
				# now -- see _pad_keys_paused for the overlay-first race.
				_pad_keys.paused = _pad_keys_paused
				get_tree().root.add_child(_pad_keys)
		Kiosk.Focus.SHELL:
			if _watched_seconds >= WINDOW_DEADLINE_SECONDS \
					and _pid > 0 and is_instance_valid(_splash):
				ShellLog.warn("%s alive as pid %d but no window after %.0f s; offering Close"
					% [_label(_current), _pid, _watched_seconds])
				_splash.show_failure()
				# Nothing left to decide: the splash now holds until the app
				# exits or the person closes it, both of which reach _finish.
				_stop_watchdog()
		_:
			# UNKNOWN. No claim, no action -- see the header. The plain splash
			# stands until launch_finished.
			pass


func _stop_watchdog() -> void:
	if is_instance_valid(_watch):
		_watch.stop()
		_watch.queue_free()
		_watch = null


func _remove_splash() -> void:
	var splash := _splash
	_splash = null
	if is_instance_valid(splash):
		# Same two-step as the placeholder in _finish: queue_free alone leaves
		# the node drawn for the rest of the frame.
		splash.get_parent().remove_child(splash)
		splash.queue_free()


func _remove_pad_keys() -> void:
	var bridge := _pad_keys
	_pad_keys = null
	if is_instance_valid(bridge):
		bridge.queue_free()


## shell_root's lever for the home menu: the same press must not both move
## the menu and type into the application behind it. The value is remembered
## even while no bridge exists, so one created later starts in the right
## state -- see _pad_keys_paused.
func set_pad_keys_paused(value: bool) -> void:
	_pad_keys_paused = value
	if is_instance_valid(_pad_keys):
		_pad_keys.set_paused(value)


## The second lever, for the same two moments and the same reason: the splash
## consumes the stick and the face buttons so a hidden rail cannot be driven
## blind behind it, and while the app menu is up that consumption is what stops
## A from choosing anything on the menu. A no-op once the splash is gone, which
## is every launch that actually put a window on screen.
func set_splash_paused(value: bool) -> void:
	if is_instance_valid(_splash):
		_splash.set_paused(value)


## Whether there is a running process this seam could stop. False for the
## placeholder branch, which has no pid and is dismissed with B.
func can_close() -> bool:
	return _pid > 0


## Ask the running application to go away.
##
## THE PID IS NOT ENOUGH FOR A FLATPAK, and that is the whole reason this is
## not a one-line OS.kill. `flatpak run` is a wrapper: it sets up the sandbox
## and the real application runs inside it, frequently under a different pid
## that is not this process's child. Killing the wrapper can leave the
## application on screen with the shell believing it has exited -- which is a
## worse state than not offering to close it at all, because the rail comes
## back underneath a window that is still there.
##
## So a flatpak entry is closed with `flatpak kill <app-id>`, which is the
## documented way to stop a sandbox, and anything else falls back to the pid.
##
## THE RAIL COMES BACK ON EVIDENCE, NOT ON HOPE. An earlier version armed the
## quiet-poll flag here and declared the process "terminated on request" on
## the very next tick, without checking -- so a `flatpak kill` that achieved
## nothing (a sandbox instance not yet registered, which is plausible in
## exactly the hung-startup state the failure splash sends people here from)
## returned the rail underneath an application that was still alive and could
## still map a window minutes later. Now the flatpak path stays on the normal
## exit poll -- the wrapper is unreaped until it actually dies, so asking
## is_process_running about it is safe and honest -- and only escalates to
## the wrapper SIGKILL if the sandbox has ignored the request for 10 s. The
## quiet flag is armed solely by _kill_pid, whose OS.kill is the thing that
## makes a later is_process_running an engine ERROR in the journal.
func close_current() -> void:
	if _current.is_empty():
		return

	var exec: Array = _current.get("exec", [])
	var app_id := _flatpak_app_id(exec)

	if not app_id.is_empty():
		ShellLog.info("closing flatpak %s" % app_id)
		# Fire and forget: the poll below is what decides the app is gone, and
		# blocking the UI on flatpak's own exit would freeze the overlay.
		var pid := OS.create_process("flatpak", ["kill", app_id])
		if pid <= 0:
			ShellLog.warn("could not run `flatpak kill %s`; falling back to the pid" % app_id)
			_kill_pid()
			return
		_close_escalate_ticks = CLOSE_ESCALATE_TICKS
		return

	_kill_pid()


## Leave the application running and give the screen back to the rail.
##
## HONEST ABOUT WHAT IT CAN AND CANNOT DO. Nothing here stops the process --
## that is the whole point -- so all this can do is stop being an overlay and
## ask gamescope to put the shell in front. Whether that happens is the
## COMPOSITOR'S decision: gamescope arbitrates focus between its clients, and an
## X client cannot insist. window_move_to_foreground is the strongest request
## available and it is a request.
##
## So this logs what it asked for. If the bench shows the app stays in front,
## the fix is a gamescope-side focus mechanism (it publishes GAMESCOPE_FOCUSED_
## WINDOW and friends, so there is somewhere to look) rather than more force
## from here -- and the journal will say so instead of leaving someone
## wondering whether the button did anything.
func minimize_current() -> void:
	if _current.is_empty():
		return
	ShellLog.info("minimize requested for %s; app stays running"
		% str(_current.get("title", "")))
	# If the splash is somehow still up -- possible only where the watchdog
	# answers UNKNOWN and nothing ever cleared it -- it must not cover the rail
	# this call is bringing back. The app keeps running; only the seam's own
	# furniture goes. The bridge goes with it: a rail the person is driving
	# must not also be typing arrows into a backgrounded file manager.
	_stop_watchdog()
	_remove_splash()
	_remove_pad_keys()
	DisplayServer.window_move_to_foreground()
	minimized.emit(_current)


## How many exit polls a `flatpak kill` gets to actually end the sandbox
## before the wrapper is killed outright. Ten seconds: Steam takes seconds to
## shut down cleanly and must get them, but the person who pressed Close is
## watching a screen that claims to be closing, and half a minute of that is
## the button reading as broken.
const CLOSE_ESCALATE_TICKS := 20

var _close_escalate_ticks := 0


func _kill_pid() -> void:
	if _pid <= 0:
		return
	ShellLog.info("terminating pid %d" % _pid)
	# The quiet-poll flag is armed HERE and only here: OS.kill is what makes a
	# later is_process_running an engine ERROR about a reaped pid, so this is
	# the one path that must stop asking. Every other close keeps polling and
	# the rail comes back when the process is actually gone.
	_terminating = true
	# OS.kill is SIGKILL on Unix. Abrupt, and acceptable here: this is the
	# button someone presses because the thing on screen will not go away, and
	# an application that ignored a polite request is exactly the case it
	# exists for. Anything that wants a graceful shutdown should offer its own
	# quit, as Steam does.
	var error := OS.kill(_pid)
	if error != OK:
		ShellLog.error("could not terminate pid %d (error %d)" % [_pid, error])


## The flatpak application id anywhere in an exec, else empty. Read from the
## entry rather than remembered separately so it cannot drift from what was
## actually launched. Scans for the `flatpak run` pair rather than requiring
## it at position zero, because Steam's exec now wraps it in a nested
## gamescope -- and `flatpak kill` remains the only close that reaches inside
## the sandbox no matter how many wrappers stand in front of it.
func _flatpak_app_id(exec: Array) -> String:
	for i in exec.size() - 1:
		if not str(exec[i]).ends_with("flatpak"):
			continue
		if str(exec[i + 1]) != "run":
			continue
		for j in range(i + 2, exec.size()):
			var word := str(exec[j])
			# Skip flatpak's own options; the first bare word is the id.
			if word.begins_with("-"):
				continue
			return word
	return ""


func _check_exit() -> void:
	# ONCE WE HAVE KILLED IT, STOP ASKING. Godot's is_process_running() logs an
	# engine-level ERROR when the pid has already been reaped -- "does not exist
	# or is not a child of the calling process" -- and after our own kill that is
	# the normal case, not a fault. It reached the journal at ERROR severity on
	# every single Close press, which on a machine where `journalctl -p err` is
	# the primary diagnostic surface is worse than noise: it is a red line that
	# means nothing, in the place someone looks when something is actually wrong.
	if _terminating:
		ShellLog.info("pid %d terminated on request" % _pid)
		_pid = -1
		_terminating = false
		_stop_poll()
		_on_closed()
		return

	if _pid > 0 and OS.is_process_running(_pid):
		# A close is pending and being ignored: give `flatpak kill` its ten
		# seconds, then stop asking politely. _kill_pid arms the quiet branch,
		# so the tick after the SIGKILL is the one that finishes.
		if _close_escalate_ticks > 0:
			_close_escalate_ticks -= 1
			if _close_escalate_ticks == 0:
				ShellLog.warn("flatpak kill has not ended pid %d after 10 s; killing the wrapper" % _pid)
				_kill_pid()
		return
	ShellLog.info("pid %d exited" % _pid)
	_pid = -1
	_stop_poll()
	_on_closed()


func _stop_poll() -> void:
	if is_instance_valid(_poll):
		_poll.stop()
		_poll.queue_free()
		_poll = null


func _on_closed() -> void:
	# Deferred because this arrives from inside the placeholder's own input
	# handling, and removing a node from the tree part-way through input
	# propagation is asking for trouble.
	_finish.call_deferred()


func _finish() -> void:
	var entry := _current
	_current = {}

	# The watchdog and splash go whatever state they are in: a launch that
	# ended ends the question of whether it drew, and a failure-state splash
	# left up over the returning rail would be the seam lying in the other
	# direction. The escalation counter dies with the launch it was counting
	# for, so a close pending on THIS app can never SIGKILL the next one.
	_close_escalate_ticks = 0
	# The remembered pause dies with the launch it described: the next launch
	# starts with no overlay up, and inheriting a stale true would be a bridge
	# that never speaks.
	_pad_keys_paused = false
	_stop_watchdog()
	_remove_splash()
	_remove_pad_keys()

	var placeholder := _placeholder
	_placeholder = null
	if is_instance_valid(placeholder):
		# remove_child first, queue_free second: queue_free is deferred to the end
		# of the frame, so on its own it would leave the placeholder drawn over
		# the home rail for the frame in which focus is being restored.
		placeholder.get_parent().remove_child(placeholder)
		placeholder.queue_free()

	ShellLog.info("launch finished: %s" % _label(entry))
	launch_finished.emit(entry)


func _label(entry: Dictionary) -> String:
	return str(entry.get("id", "<unknown>"))
