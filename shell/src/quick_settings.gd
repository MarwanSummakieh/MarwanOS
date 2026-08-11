extends Control

## Quick settings: the GNOME-style small panel from the bar's status corner.
##
## Opened from status_corner.gd. Same shape as the service menu -- a panel over
## a dimmed screen, one axis, B closes -- because a person who has learned what
## a drop menu is on the bell has learned this one. It hangs under the corner
## it came from, on the RIGHT, for the service menu's reason mirrored: a panel
## that appears somewhere unrelated to the control that opened it makes a
## person hunt for the connection.
##
## WHAT IS IN IT, AND WHY THESE FOUR. Everything here is a thing someone on the
## couch reaches for often enough that a trip through the full settings or
## power screen is ceremony: what the network is doing, the display profile
## (the flicker experiment lives or dies by how cheap cycling is), the
## background services, and the power verbs. Each row acts through the seam
## that already owns the action -- SystemStatus, DisplayProfile, Services,
## Updates -- so this panel adds no second authority over anything.
##
## THE POWER ROWS ACT IMMEDIATELY, power_screen.gd's argument verbatim: the
## deliberate act is opening the panel and moving to the row, and the costliest
## mistake is a restart on a machine that boots in under a minute. Off and
## restart leave the panel up -- the machine going dark is the acknowledgement,
## and closing first would flash the rail for the seconds the service defers
## by. Sleep closes it, because sleep COMES BACK, and it should come back to
## the rail rather than to a stale panel.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const SettingsRow = preload("res://src/settings_row.gd")
const ActionRow = preload("res://src/action_row.gd")

## What a service row says on the right -- service_menu.gd's table, and the two
## must keep agreeing: the same service shown through two doors with two
## vocabularies would read as two different services.
const STATE_WORDS := {
	"running": "Running",
	"stopped": "Stopped",
	"unknown": "Not reported yet",
}

var _rows: Array = []
var _network_row: SettingsRow = null
var _display_row: ActionRow = null
## The service rows by id, so a seam tick updates values in place rather than
## rebuilding rows out from under the focus.
var _service_rows: Array = []
var _service_ids: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The dim, so the bar and the rail behind read as "still there, not
	# available" rather than being replaced. Same treatment as the two menus.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var place := MarginContainer.new()
	place.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	place.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y + 90)
	add_child(place)

	var column := VBoxContainer.new()
	# SHRINK_END, where the service menu shrinks to the beginning: this panel
	# hangs under the right-hand corner, so it is the right edge that has to
	# line up with the control that opened it.
	column.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place.add_child(column)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	panel.custom_minimum_size = Vector2(760, 0)
	column.add_child(panel)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_right", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_ITEM_PAD * 2)
	panel.add_child(pad)

	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	pad.add_child(list)

	var heading := Label.new()
	heading.text = "Quick settings"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(heading)

	# THE NETWORK ROW IS READ-ONLY, like its settings-screen sibling, and for
	# the same Phase 0 reason: joining a network needs a keyboard UI and a
	# write path to NetworkManager, both marwand's. A read-only SettingsRow
	# logs its designed inertness on A rather than doing nothing silently.
	_network_row = SettingsRow.new()
	_network_row.setup("Network", _network_value(), "wifi")
	list.add_child(_network_row)
	_rows.append(_network_row)

	_display_row = ActionRow.new()
	_display_row.setup("Display", _display_value(), "display")
	_display_row.activated.connect(_on_display_row)
	list.add_child(_display_row)
	_rows.append(_display_row)

	# One row per background service, the service menu's switch through a
	# second door. Same seam, same pending words, so the two can never tell
	# different stories about the same service.
	var services: Array = Services.visible_services()
	for service in services:
		var id := str(service.get("id", ""))
		var row := ActionRow.new()
		row.setup(str(service.get("label", "")), _service_value(id))
		row.activated.connect(_on_service_row.bind(id))
		list.add_child(row)
		_rows.append(row)
		_service_rows.append(row)
		_service_ids.append(id)

	_add_power_row(list, "Turn off", "power", _on_poweroff)
	_add_power_row(list, "Restart", "restart", _on_restart)
	_add_power_row(list, "Sleep", "sleep", _on_suspend)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Close"))
	column.add_child(hints)

	_wire_focus_neighbours()

	# Live: the network can drop and a service can land while the panel is up,
	# and a panel whose whole job is current state must not need reopening.
	SystemStatus.network_changed.connect(_on_network_changed)
	SystemStatus.network_info_changed.connect(_on_network_info_changed)
	DisplayProfile.state_changed.connect(_on_display_state_changed)
	Services.services_changed.connect(_refresh_service_values)

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("quick settings up with %d rows" % _rows.size())


func _add_power_row(list: Control, name_text: String, icon_name: String,
		handler: Callable) -> void:
	var row := ActionRow.new()
	row.setup(name_text, "", icon_name)
	row.activated.connect(handler)
	list.add_child(row)
	_rows.append(row)


## The settings list's table, again: one axis, hard stops at both ends, left
## and right pointed at self so Control's geometric search cannot wander out of
## the panel and into the bar behind it.
func _wire_focus_neighbours() -> void:
	var count := _rows.size()
	for index in count:
		var row: Control = _rows[index]
		var up := index - 1 if index > 0 else index
		var down := index + 1 if index + 1 < count else index
		row.focus_neighbor_top = row.get_path_to(_rows[up])
		row.focus_neighbor_bottom = row.get_path_to(_rows[down])
		row.focus_neighbor_left = row.get_path_to(row)
		row.focus_neighbor_right = row.get_path_to(row)


## The state word plus the link's name when there is one: "Online -- HomeNet"
## answers both of the questions a person opens this corner with. The wording
## leans on the settings screen's rows without copying them -- this one line
## stands in for that screen's three.
func _network_value() -> String:
	match SystemStatus.network:
		"online":
			var info := SystemStatus.network_info
			if info.contains("\t"):
				info = info.get_slice("\t", 0)
			var link_name := info.substr(info.get_slice(" ", 0).length()).strip_edges()
			return "Online -- %s" % link_name if not link_name.is_empty() else "Online"
		"offline":
			return "Offline"
		_:
			return "Unknown -- the system has not said"


## settings_screen.gd's _display_profile_value, kept in step by hand: the row
## must say the same thing through both doors, and THE RESTART RIDES IN EVERY
## STATE for that screen's reason -- a profile changes nothing until gamescope
## restarts, and a person who cycles, sees the same flicker and concludes the
## setting is broken would stop on the one row that could fix their headache.
func _display_value() -> String:
	var profile_name := DisplayProfile.label_for(DisplayProfile.chosen_profile())
	if DisplayProfile.state == "refused":
		return "%s -- not changed, press A to try again" % profile_name
	if DisplayProfile.is_pending():
		return "%s -- restart to apply" % profile_name
	return "%s -- A changes it, restart applies" % profile_name


func _service_value(id: String) -> String:
	var pending := Services.pending_of(id)
	if pending == "stop":
		return "Stopping"
	if pending == "start":
		return "Starting"
	return str(STATE_WORDS.get(Services.state_of(id), STATE_WORDS["unknown"]))


func _refresh_network_row() -> void:
	if _network_row != null:
		_network_row.set_value(_network_value())


func _on_network_changed(_state: String) -> void:
	_refresh_network_row()


func _on_network_info_changed(_info: String) -> void:
	_refresh_network_row()


## Optimistic, DisplayProfile.request_next's argument: the consumer polls twice
## a second, and a button that looks dead for two seconds on the row somebody
## opened because their display is misbehaving reads as a second fault. The
## next poll overwrites this with whatever actually happened.
func _on_display_row() -> void:
	var want := DisplayProfile.request_next()
	if _display_row != null:
		_display_row.set_value(_display_value())
	ShellLog.info("quick settings: display cycled to \"%s\"" % want)


func _on_display_state_changed(_state: String, _profile: String) -> void:
	if _display_row != null:
		_display_row.set_value(_display_value())


## A on a service row: the other thing from whatever it is doing now, exactly
## service_menu.gd's rule, including treating unknown as stopped -- on a
## machine where something has gone wrong, the thing a person wants from this
## row is to get the service up.
func _on_service_row(id: String) -> void:
	if not Services.pending_of(id).is_empty():
		# Already asked. A second wish written over the first is how a toggle
		# ends up fighting itself.
		return
	Services.set_wanted(id, not Services.is_running(id))
	_refresh_service_values()


func _refresh_service_values() -> void:
	for index in _service_rows.size():
		var row: ActionRow = _service_rows[index]
		if is_instance_valid(row):
			row.set_value(_service_value(str(_service_ids[index])))


func _on_poweroff() -> void:
	ShellLog.info("quick settings: turn off")
	Updates.request_poweroff()


func _on_restart() -> void:
	ShellLog.info("quick settings: restart")
	Updates.request_restart()


func _on_suspend() -> void:
	ShellLog.info("quick settings: sleep")
	Updates.request_suspend()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the rail underneath never sees the same press.
	get_viewport().set_input_as_handled()
	closed.emit()
