extends Node

## The pad-to-keyboard bridge: how a gamepad drives an application that has
## never heard of one.
##
## Dolphin is the reason this exists. The person on the couch wants a real
## file manager, a real file manager is a Qt desktop application, and a Qt
## desktop application listens to keyboards and mice -- neither of which this
## machine has. What it does have is a shell that KEEPS RECEIVING PAD INPUT
## while another client owns the screen (both read evdev; see stores_screen's
## deafness note, which exists because of exactly this), and an X server on
## which XTEST can type into whatever holds focus -- which under gamescope is
## the running application. So: pad events in, `xdotool key` out, and Dolphin
## behaves as if a very disciplined typist were sitting at it.
##
## THE MAPPING IS NAVIGATION, NOT A KEYBOARD. Arrows, open, back, context
## menu -- the verbs a file manager can honour from a stick. Anything that
## needs typing (rename, a path bar) needs the on-screen keyboard grown up
## into an injector, which is Phase 1 work; mapping X to a key nobody can
## follow up on would be a button that breaks a flow instead of one that is
## honestly absent.
##
## WHO STARTS AND STOPS THIS IS THE SEAM'S BUSINESS, NOT OURS. Launcher
## creates the bridge only once the window watchdog has SEEN the application
## take the screen (Focus.ELSEWHERE) -- typing into an app that has not drawn
## yet is how a splash-covered machine ends up with three phantom keystrokes
## queued -- and frees it when the launch finishes or is minimized. While the
## home menu is over the application, shell_root pauses it: the same press
## must not both move the menu and type into the app behind it. The pause is
## explicit rather than inferred from focus, because a launch from the stores
## screen leaves a deaf store tab holding GUI focus the whole time and any
## focus-based inference reads that as "shell UI active" forever.
##
## Per-press process spawn is the cost, and it is fine: xdotool is a few
## milliseconds of X round trip, create_process does not block the frame, and
## a file manager is driven at human browsing speed. If a future bridge needs
## gaming-rate input it needs uinput and a daemon, not a faster xdotool.

const REPEAT_DELAY := 0.4
const REPEAT_INTERVAL := 0.12

## Action -> X keysym. Only the arrows repeat; Return, BackSpace and Menu on
## hold would be a machine gun pointed at a file tree.
const KEY_FOR_ACTION := {
	"ui_up": "Up",
	"ui_down": "Down",
	"ui_left": "Left",
	"ui_right": "Right",
	"ui_accept": "Return",
	"ui_cancel": "BackSpace",
	"ui_shell_y": "Menu",
}

const REPEATING := ["ui_up", "ui_down", "ui_left", "ui_right"]

var paused := false

var _held := ""
var _repeat: Timer = null

## Said once if xdotool cannot be run, not once per press: the bridge failing
## is one fact, and the journal needs it exactly one time to name the missing
## binary.
var _spawn_warned := false


func _ready() -> void:
	_repeat = Timer.new()
	_repeat.one_shot = true
	_repeat.timeout.connect(_on_repeat)
	add_child(_repeat)
	ShellLog.info("pad-keys bridge up")


func _input(event: InputEvent) -> void:
	if paused:
		return

	for action in KEY_FOR_ACTION:
		if event.is_action_pressed(action):
			# Consumed so the deaf-but-listening shell surfaces underneath
			# never act on the same press the application just received.
			get_viewport().set_input_as_handled()
			_send(str(KEY_FOR_ACTION[action]))
			if REPEATING.has(action):
				_held = action
				_repeat.start(REPEAT_DELAY)
			return
		if event.is_action_released(action):
			if action == _held:
				_held = ""
				_repeat.stop()
			return


## Releasing the pause mid-hold must not resurrect a repeat armed before the
## menu opened; the person's thumb has long since moved on.
func set_paused(value: bool) -> void:
	paused = value
	if paused:
		_held = ""
		_repeat.stop()


func _on_repeat() -> void:
	if _held.is_empty() or paused:
		return
	_send(str(KEY_FOR_ACTION[_held]))
	_repeat.start(REPEAT_INTERVAL)


func _send(key: String) -> void:
	# --clearmodifiers: gamescope or a previous injection can leave a phantom
	# modifier latched, and "Down" arriving as "Shift+Down" turns navigation
	# into range selection.
	var pid := OS.create_process("xdotool", ["key", "--clearmodifiers", key])
	if pid <= 0 and not _spawn_warned:
		_spawn_warned = true
		ShellLog.warn("cannot run xdotool; the pad-keys bridge is typing into a void")
