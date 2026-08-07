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

const StoresScreen = preload("res://src/stores_screen.gd")

# Typed as the script rather than as Control so `closed` resolves statically --
# the same argument as Launcher's _placeholder.
var _screen: StoresScreen = null


func is_open() -> bool:
	return _screen != null


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
	if Settings.is_open():
		# The two shell surfaces are peers, not layers: whichever is up owns
		# the screen until it closes. (Settings.open holds the mirror guard.)
		return

	ShellLog.info("stores opened")

	# Assigned BEFORE the emit and added to the tree AFTER it, for the seam's
	# standard ordering: is_open() is true for every handler of stores_opened,
	# and the home rail captures its focus owner before the screen's _ready
	# grabs focus.
	_screen = StoresScreen.new()
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)

	stores_opened.emit()
	get_tree().root.add_child(_screen)


func _on_closed() -> void:
	# Deferred for the launcher's reason: the signal arrives from inside the
	# screen's own input handling, and removing a node from the tree part-way
	# through input propagation is asking for trouble.
	_finish.call_deferred()


func _finish() -> void:
	var screen := _screen
	_screen = null
	if is_instance_valid(screen):
		# remove_child first, queue_free second: queue_free is deferred to the
		# end of the frame, so on its own it would leave the screen drawn over
		# the home rail for the frame in which focus is being restored.
		screen.get_parent().remove_child(screen)
		screen.queue_free()

	ShellLog.info("stores closed")
	stores_closed.emit()
