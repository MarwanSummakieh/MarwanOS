extends Node

## The six actions the shell is allowed to use, defined here rather than in
## project.godot.
##
## Why here. Godot serialises an InputMap override into project.godot as a
## one-line `Object(InputEventJoypadButton,"resource_name":"","device":0,...)`
## blob per event. Those are unreviewable in a diff and easy to corrupt by hand,
## in a repo whose entire discipline is hand-authored, LF-normalised, reviewable
## text. Six calls in a file anyone can read is the better trade, and it can carry
## the comment explaining why each binding exists.
##
## Why redefine at all -- two things about the built-in map are not safe to
## inherit on this machine:
##
## 1. DEVICE SCOPING. The built-in events are built with create_reference(),
##    which never calls set_device(), so they inherit InputEvent's default
##    `device = 0`. InputMap::action_match only fires when the action's event is
##    ALL_DEVICES (-1) or its device equals the incoming event's. So the stock
##    d-pad and stick bindings answer to joypad index 0 and nothing else. Godot's
##    joypad index allocation has open bugs (godot#97539, godot#76879, godot#17566)
##    and a hotplug race can leave the only pad on index 1 -- at which point the
##    home rail renders perfectly and ignores the controller, which on an
##    appliance with no terminal is indistinguishable from a hung shell. Every
##    event added here is device -1.
##
## 2. THE ACTION BUTTONS. Sources disagree about whether 4.x binds A to
##    `ui_accept` and B to `ui_cancel` at all, and the answer has to be right on a
##    machine that has no keyboard to fall back to. Binding them explicitly makes
##    the question moot on every engine version, which is cheaper than being sure.
##
## DEADZONE. ProjectSettings registers the built-in directional actions with
##    InputMap::DEFAULT_TOGGLE_DEADZONE (0.5), not the 0.2 that
##    InputMap.add_action() uses. 0.5 is kept: a card rail wants a deliberate
##    push, and a worn stick that drifts past 0.2 would walk the focus on its own.
##    It is a number to tune from the couch, which is why it is named.
##
## `ui_select` (Triangle) is deliberately left alone. Nothing in this shell reads
## it, and adding A to it would give the appliance a second, undocumented activate.

const ALL_DEVICES := -1

## Deliberate push, not a nudge. See the header.
const STICK_DEADZONE := 0.5

## Actions the shell will not function without. Checked at startup because the
## symptom of getting this wrong is silence, and silence on this machine looks
## exactly like a crash.
const REQUIRED_JOYPAD_ACTIONS := [
	"ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel",
]


func _ready() -> void:
	# Focus navigation. Both the d-pad and the left stick, because a couch does
	# not care which one the person reached for.
	_define("ui_up", [
		_key(KEY_UP),
		_button(JOY_BUTTON_DPAD_UP),
		_axis(JOY_AXIS_LEFT_Y, -1.0),
	], STICK_DEADZONE)

	_define("ui_down", [
		_key(KEY_DOWN),
		_button(JOY_BUTTON_DPAD_DOWN),
		_axis(JOY_AXIS_LEFT_Y, 1.0),
	], STICK_DEADZONE)

	_define("ui_left", [
		_key(KEY_LEFT),
		_button(JOY_BUTTON_DPAD_LEFT),
		_axis(JOY_AXIS_LEFT_X, -1.0),
	], STICK_DEADZONE)

	_define("ui_right", [
		_key(KEY_RIGHT),
		_button(JOY_BUTTON_DPAD_RIGHT),
		_axis(JOY_AXIS_LEFT_X, 1.0),
	], STICK_DEADZONE)

	# JOY_BUTTON_A is the bottom face button: Cross on a DualSense, A on an Xbox
	# pad. JOY_BUTTON_B is the right one: Circle / B. Godot's mapping database
	# normalises both layouts to these names, so this is correct for either pad
	# without asking which is plugged in.
	_define("ui_accept", [
		_key(KEY_ENTER),
		_key(KEY_KP_ENTER),
		_key(KEY_SPACE),
		_button(JOY_BUTTON_A),
	], STICK_DEADZONE)

	_define("ui_cancel", [
		_key(KEY_ESCAPE),
		_button(JOY_BUTTON_B),
	], STICK_DEADZONE)

	_verify()


## Rebuilds one action from scratch. Erasing first matters: action_add_event
## appends, so without it the built-in device-0 events survive alongside ours and
## the device scoping this file exists to fix would still be half in force.
func _define(action: String, events: Array, deadzone: float) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, deadzone)
	else:
		InputMap.add_action(action, deadzone)
	for event in events:
		InputMap.action_add_event(action, event)


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.device = ALL_DEVICES
	return event


func _button(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.device = ALL_DEVICES
	return event


## `value` is only ever -1.0 or 1.0: InputMap matches on the sign, and the
## magnitude that matters is the action's deadzone, not this.
func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = ALL_DEVICES
	return event


## The regression guard, in the same spirit as the Containerfile's ICD and
## initramfs assertions: a build or an edit that removes the joypad half of an
## action must say so somewhere a human will find it, rather than shipping a shell
## that navigates and cannot be activated.
##
## It logs rather than aborts. A shell that refuses to start is a black TV; a
## shell that starts with a loud journal line is still recoverable over devmode
## ssh. assert() would also be compiled out of the release export, which is the
## only build that ever runs on the appliance.
func _verify() -> void:
	var missing := PackedStringArray()
	for action in REQUIRED_JOYPAD_ACTIONS:
		if not _has_joypad_binding(action):
			missing.append(action)
	if missing.is_empty():
		ShellLog.info("input map ready; joypad bindings present on all six actions")
		return
	ShellLog.error(
		"no joypad binding on %s -- the shell will be unusable from a controller"
		% ", ".join(missing)
	)


func _has_joypad_binding(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false
