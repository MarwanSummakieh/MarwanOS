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

const LaunchPlaceholder = preload("res://src/launch_placeholder.gd")

var _current: Dictionary = {}

# Typed as the script rather than as Control so `entry` and `closed` resolve
# statically -- GDScript treats a missing member on a typed variable as an error,
# which is the point.
var _placeholder: LaunchPlaceholder = null


func is_busy() -> bool:
	return not _current.is_empty()


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
## the WebSocket and this function is deleted whole, along with the poll timer.
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


func _spawn(exec: Array) -> void:
	var program := str(exec[0])
	var args := PackedStringArray()
	for i in range(1, exec.size()):
		args.append(str(exec[i]))

	ShellLog.info("spawning %s %s" % [program, " ".join(args)])
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


func _check_exit() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		return
	ShellLog.info("pid %d exited" % _pid)
	_pid = -1
	if is_instance_valid(_poll):
		_poll.stop()
		_poll.queue_free()
		_poll = null
	_on_closed()


func _on_closed() -> void:
	# Deferred because this arrives from inside the placeholder's own input
	# handling, and removing a node from the tree part-way through input
	# propagation is asking for trouble.
	_finish.call_deferred()


func _finish() -> void:
	var entry := _current
	_current = {}

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
