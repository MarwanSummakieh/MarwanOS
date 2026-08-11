extends Control

## The service menu: what is running in the background, and a button per row that
## turns it off or on.
##
## Opened from the tray in the top bar (service_tray.gd). Same shape as the
## card menu -- a panel over a dimmed screen, one axis, B closes -- because a
## person who has learned what a menu is on a rail card has learned this one.
##
## ONE ROW PER SERVICE, and the row IS the switch. There is no separate Start and
## Stop pair: a service is running or it is not, so the row says which and A does
## the other thing. Two buttons where one state exists is how a menu grows a
## wrong answer somebody can press.
##
## THE ROW DOES NOT LIE WHILE IT WAITS. Writing the wish is instant; the session's
## supervisor notices within about two seconds and the client itself takes longer
## than that to go away. So a row that has been pressed says "Stopping" until the
## state file agrees, rather than flipping to "Stopped" and being wrong for the
## most visible seconds of the whole interaction. See Services.pending_of.
##
## NOTHING HERE CAN REMOVE ANYTHING. Stopping a service is a runtime state that
## the next boot forgets unless the wish file survives -- it lives on a tmpfs, so
## it does not. Uninstalling Steam is the store card's Options menu and stays
## there: one thing, one home.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")

## What a row says on the right, by what the service is doing. The pending words
## are verbs because something is happening; the settled ones are states.
const STATE_WORDS := {
	"running": "Running",
	"stopped": "Stopped",
	"unknown": "Not reported yet",
}

var _rows: Array = []
var _ids: Array = []
var _panel: PanelContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The dim, so the bar and the rail behind read as "still there, not
	# available" rather than being replaced. Same treatment as the card menu.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# TOP-LEFT, UNDER THE TRAY IT CAME FROM, rather than centred like the card
	# menu. It is a drop menu: a panel that appears somewhere unrelated to the
	# control that opened it makes a person hunt for the connection.
	var place := MarginContainer.new()
	place.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	place.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y + 90)
	add_child(place)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place.add_child(column)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	_panel.custom_minimum_size = Vector2(720, 0)
	column.add_child(_panel)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_right", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_ITEM_PAD * 2)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_ITEM_PAD * 2)
	_panel.add_child(pad)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	pad.add_child(_list)

	var heading := Label.new()
	heading.text = "Background services"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(heading)

	_build_rows()

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Start or stop"))
	hints.add_child(TvTheme.hint("B", "Close"))
	column.add_child(hints)

	# Live: the whole point of the menu is watching something change, so it has
	# to redraw when the seam says it did rather than when it is reopened.
	Services.services_changed.connect(_refresh_values)

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()


func _build_rows() -> void:
	var services: Array = Services.visible_services()
	if services.is_empty():
		# A real state on a machine with nothing installed, and it says so
		# rather than presenting an empty panel that looks like a failure.
		var empty := Label.new()
		empty.text = "Nothing runs in the background on this machine yet"
		empty.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
		empty.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(empty)
		return

	for service in services:
		var id := str(service.get("id", ""))
		var row := ActionRow.new()
		row.setup(str(service.get("label", "")), _value_for(id))
		row.activated.connect(_on_row.bind(id))
		_list.add_child(row)
		_rows.append(row)
		_ids.append(id)

	_wire_focus_neighbours()


## The settings list's table, a fourth time: one axis, hard stops at both ends,
## left and right pointed at self so Control's geometric search cannot wander
## out of the panel and into the bar behind it.
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


## What the row says on the right. The pending words win, because they are the
## most recent true thing about the service -- see the header.
func _value_for(id: String) -> String:
	var pending := Services.pending_of(id)
	if pending == "stop":
		return "Stopping"
	if pending == "start":
		return "Starting"
	return str(STATE_WORDS.get(Services.state_of(id), STATE_WORDS["unknown"]))


func _refresh_values() -> void:
	for index in _rows.size():
		var row: ActionRow = _rows[index]
		if is_instance_valid(row):
			row.set_value(_value_for(str(_ids[index])))


## A on a row: the other thing from whatever it is doing now.
##
## A service in an UNKNOWN state is treated as stopped, so A starts it. That is
## the useful direction: unknown means the supervisor has not reported, and on a
## machine where something has gone wrong the thing a person wants from this menu
## is to get the service up.
func _on_row(id: String) -> void:
	if not Services.pending_of(id).is_empty():
		# Already asked. Pressing again cannot make it happen faster and a second
		# wish written over the first is how a toggle ends up fighting itself.
		return
	var running := Services.is_running(id)
	Services.set_wanted(id, not running)
	_refresh_values()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the rail underneath never sees the same press.
	get_viewport().set_input_as_handled()
	closed.emit()
