extends Control

## The settings page -- the first screen in the shell that is not the home rail.
##
## READ-ONLY ON PURPOSE. There is no marwand yet, and the shell is a renderer:
## a row that could CHANGE something would need somewhere to send the change,
## and building a second, temporary path for that -- the shell shelling out, or
## writing config -- is exactly the growth launcher.gd's header says belongs in
## the daemon. So Phase 0's settings screen answers questions instead of taking
## orders, and the questions are the ones this project has so far had to answer
## with journalctl: what image is this, which adapter drew it, what mode, which
## display server, is the pad claimed. On an appliance with no terminal, a
## screen that says those five things is a diagnostic surface, not filler.
##
## NAVIGATION IS THE RAIL'S ARGUMENT ROTATED 90 DEGREES. One axis -- up and
## down are the only moves, the ends are hard stops, left and right are pointed
## at self so Control's geometric search cannot wander to the hint row. B
## closes the screen; there is no deeper level to be lost in.
##
## The screen assumes nothing about why it is on screen. Settings (the seam)
## opens it and tears it down; the home rail hides and restores itself off the
## seam's signals. This file only builds rows and emits closed.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const SettingsRow = preload("res://src/settings_row.gd")

var _rows: Array = []
var _controller_row: SettingsRow = null
var _network_row: SettingsRow = null
var _connection_row: SettingsRow = null
var _wifi_row: SettingsRow = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The full TV-safe inset, all four edges. Every control on this screen is
	# text or carries a focus ring; nothing here is background-class furniture
	# with the rail's licence to bleed.
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)

	var heading := Label.new()
	heading.text = "Settings"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(list)

	_add_row(list, "System", _system_value())
	_add_row(list, "Engine", _engine_value())
	_add_row(list, "Display", _display_value())
	_add_row(list, "Renderer", RenderingServer.get_video_adapter_name())
	_controller_row = _add_row(list, "Controller", _controller_value())
	# The network rows answer from the status seam, live -- the same files the
	# top bar's wifi glyph renders, at more length. Read-only like every row:
	# JOINING a network needs a keyboard UI and somewhere to send credentials,
	# and both are marwand's (the per-stick NetworkManager profile is the
	# Phase 0 mechanism -- see docs/handoff.md). The Wi-Fi row says so instead
	# of pretending.
	_network_row = _add_row(list, "Network", _network_value())
	_connection_row = _add_row(list, "Connection", _connection_value())
	_wifi_row = _add_row(list, "Wi-Fi", _wifi_value())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	column.add_child(_build_hints())

	_wire_focus_neighbours()

	# The rail's lesson holds here too: nothing navigates until something is
	# focused. The screen opens with the first row lit rather than with a page
	# the pad cannot reach into.
	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	PlayerOne.player_one_present.connect(_on_player_one_present)
	PlayerOne.player_one_absent.connect(_on_player_one_absent)
	SystemStatus.network_changed.connect(_on_network_changed)
	SystemStatus.network_info_changed.connect(_on_network_info_changed)

	ShellLog.info("settings screen up with %d rows" % _rows.size())


func _add_row(list: Control, name_text: String, value_text: String) -> SettingsRow:
	var row := SettingsRow.new()
	row.setup(name_text, value_text)
	list.add_child(row)
	_rows.append(row)
	return row


## The vertical mirror of the rail's table: hard stops at both ends, and the
## perpendicular axis pointed at self so focus cannot leave the list sideways.
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


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


# ---------------------------------------------------------------------------
# Values
# ---------------------------------------------------------------------------

## PRETTY_NAME from os-release, which on the appliance is the image name and
## version the build stamped -- the same string that identifies a stick in the
## handoff notes. On a desk run it truthfully names whatever the container is.
func _system_value() -> String:
	var file := FileAccess.open("/etc/os-release", FileAccess.READ)
	if file == null:
		return "Unknown"
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("PRETTY_NAME="):
			return line.trim_prefix("PRETTY_NAME=").trim_prefix("\"").trim_suffix("\"")
	return "Unknown"


func _engine_value() -> String:
	var info := Engine.get_version_info()
	return "Godot %s.%s.%s" % [info.get("major", 0), info.get("minor", 0), info.get("patch", 0)]


## Server name and window size, the two things Kiosk logs that a person might
## want without ssh. get_name() says X11 under gamescope's XWayland -- see the
## README's display-driver section for why that is not evidence about the
## compositor.
func _display_value() -> String:
	var window := get_window()
	if window == null:
		return DisplayServer.get_name()
	return "%s, %d x %d" % [DisplayServer.get_name(), window.size.x, window.size.y]


func _controller_value() -> String:
	if PlayerOne.has_controller():
		return PlayerOne.pad_name
	return "Not connected"


func _network_value() -> String:
	match SystemStatus.network:
		"online":
			return "Online -- Flathub answers"
		"offline":
			return "Offline"
		_:
			return "Unknown -- the system has not said"


## netcheck's one-line link description, made readable: "wifi HomeNet" becomes
## "Wi-Fi -- HomeNet". The raw first word decides the family; everything after
## it is the connection's name and passes through untouched.
func _connection_value() -> String:
	var info := SystemStatus.network_info
	if info.is_empty():
		return "Unknown"
	var kind := info.get_slice(" ", 0)
	var name := info.substr(kind.length()).strip_edges()
	match kind:
		"wifi":
			return "Wi-Fi -- %s" % name if not name.is_empty() else "Wi-Fi"
		"ethernet":
			return "Ethernet -- %s" % name if not name.is_empty() else "Ethernet"
		"link":
			return "Link on %s" % name if not name.is_empty() else "Link up"
		"none":
			return "No link"
		_:
			return info


## What a wifi SETTINGS row can honestly say in Phase 0: the network's name
## when wifi carries the link, and otherwise where the credentials actually
## live. Joining a network from the couch needs an on-screen keyboard and a
## write path to NetworkManager -- both marwand, both Phase 1.
func _wifi_value() -> String:
	var info := SystemStatus.network_info
	if info.get_slice(" ", 0) == "wifi":
		return info.substr("wifi".length()).strip_edges()
	return "No on-screen setup yet -- profile lives on the stick"


func _refresh_network_rows() -> void:
	if _network_row != null:
		_network_row.set_value(_network_value())
	if _connection_row != null:
		_connection_row.set_value(_connection_value())
	if _wifi_row != null:
		_wifi_row.set_value(_wifi_value())


func _on_network_changed(_state: String) -> void:
	_refresh_network_rows()


func _on_network_info_changed(_info: String) -> void:
	_refresh_network_rows()


func _refresh_controller() -> void:
	if _controller_row != null:
		_controller_row.set_value(_controller_value())


func _on_player_one_present(_device: int, _pad_name: String) -> void:
	_refresh_controller()


func _on_player_one_absent() -> void:
	_refresh_controller()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath -- hidden until the seam restores it
	# -- never sees the same press as a second back-out.
	get_viewport().set_input_as_handled()
	closed.emit()
