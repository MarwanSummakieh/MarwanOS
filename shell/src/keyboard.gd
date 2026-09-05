extends Control

## Shared controller keyboard. Draft inputs stay local until Done; browser inputs
## emit edits immediately and leave the real field visible beside this panel.
signal submitted(text: String)
signal cancelled()
signal text_inserted(text: String)
signal editing_key(key: String)

const TvTheme = preload("res://src/tv_theme.gd")
const PANEL_WIDTH := 792
const PANEL_GAP := 96
const KEY_SIZE := 64
const KEY_GAP := 6

const ROWS_LOWER := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "-"],
	["z", "x", "c", "v", "b", "n", "m", ".", "_", "@"],
	["!", "#", "$", "%", "&", "*", "+", "=", "?", "/"],
]

const ROWS_UPPER := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
	["A", "S", "D", "F", "G", "H", "J", "K", "L", "-"],
	["Z", "X", "C", "V", "B", "N", "M", ".", "_", "@"],
	["~", "(", ")", "[", "]", "{", "}", "<", ">", "\\"],
]


var title_text := "Enter password"
var masked := true
var initial_text := ""
var background_alpha := 0.0
var input_context := "text"
var live_input := false
var done_label := "Done"
var _text := ""
var _caret := 0
var _shift := false
var _keys: Array = []
var _flat: Array = []
var _entry: Label
var _panel: PanelContainer
var _left_trigger := false
var _right_trigger := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if PlayerOne.device >= 0:
		_left_trigger = Input.get_joy_axis(PlayerOne.device, JOY_AXIS_TRIGGER_LEFT) > 0.6
		_right_trigger = Input.get_joy_axis(PlayerOne.device, JOY_AXIS_TRIGGER_RIGHT) > 0.6
	var background := ColorRect.new()
	background.color = Color(TvTheme.BACKGROUND, minf(background_alpha, 0.15))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -PANEL_WIDTH - 48
	_panel.offset_right = -48
	_panel.offset_top = -798
	_panel.offset_bottom = -54
	var surface := TvTheme.card_idle_box()
	surface.bg_color = TvTheme.BACKGROUND
	_panel.add_theme_stylebox_override("panel", surface)
	var pad := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + edge, 24)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 32)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	_entry = Label.new()
	_entry.add_theme_font_size_override("font_size", 26)
	_entry.custom_minimum_size.y = 48
	_entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_entry.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_entry)
	column.add_child(_build_grid())
	var hints := Label.new()
	hints.text = "Cross: type   Square: delete   Triangle: space\nL2: shift   L1 / R1: cursor   R2 / Options: %s\nCircle: %s" % [done_label.to_lower(), "close" if live_input else "cancel"]
	hints.add_theme_font_size_override("font_size", 24)
	hints.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	column.add_child(hints)
	_wire_focus_neighbours()
	_text = initial_text
	_caret = _text.length()
	_refresh_entry()
	var first_row := 0 if input_context in ["numeric", "decimal", "tel", "number"] else 1
	_keys[first_row][0].grab_focus()
	ShellLog.info("compact keyboard up (%s)" % input_context)

func _build_grid() -> Control:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", KEY_GAP)
	var rows: Array = _letter_rows()
	if input_context in ["numeric", "decimal", "tel", "number"]:
		rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["+", "0", "."], ["-", "#", "*"]]
	for labels in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", KEY_GAP)
		grid.add_child(row)
		var keys: Array = []
		for label in labels:
			var key := _make_key(str(label))
			row.add_child(key)
			key.pressed.connect(_on_character.bind(key))
			keys.append(key)
			_flat.append(key)
		_keys.append(keys)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", KEY_GAP)
	grid.add_child(actions)
	var action_keys: Array = []
	for label in ["Shift", "Space", "Delete", done_label]:
		var key := _make_key(label)
		actions.add_child(key)
		action_keys.append(key)
	action_keys[0].pressed.connect(_on_shift)
	action_keys[1].pressed.connect(_on_space)
	action_keys[2].pressed.connect(_on_backspace)
	action_keys[3].pressed.connect(_on_done)
	_keys.append(action_keys)
	return grid

func _make_key(label: String) -> Button:
	var key := Button.new()
	key.text = label
	key.custom_minimum_size = Vector2(KEY_SIZE, KEY_SIZE)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.add_theme_font_size_override("font_size", 26)
	key.add_theme_stylebox_override("normal", TvTheme.card_idle_box())
	key.add_theme_stylebox_override("hover", TvTheme.card_focus_box())
	key.add_theme_stylebox_override("pressed", TvTheme.row_pressed_box())
	key.add_theme_stylebox_override("focus", TvTheme.card_focus_ring())
	return key

func _wire_focus_neighbours() -> void:
	for row_index in _keys.size():
		var row: Array = _keys[row_index]
		for col_index in row.size():
			var key: Control = row[col_index]

			var left := col_index - 1 if col_index > 0 else col_index
			var right := col_index + 1 if col_index + 1 < row.size() else col_index
			key.focus_neighbor_left = key.get_path_to(row[left])
			key.focus_neighbor_right = key.get_path_to(row[right])

			key.focus_neighbor_top = key.get_path_to(
				_proportional(row_index - 1, col_index, row.size(), key))
			key.focus_neighbor_bottom = key.get_path_to(
				_proportional(row_index + 1, col_index, row.size(), key))


func _proportional(target_row: int, col_index: int, width: int, fallback: Control) -> Control:
	if target_row < 0 or target_row >= _keys.size():
		return fallback
	var row: Array = _keys[target_row]
	if row.is_empty():
		return fallback
	# +0.5 so the mapping picks the column the key's CENTRE sits over rather
	# than the one its left edge does; without it, moving down then up from the
	# action row drifts leftward one column at a time.
	var index := int((float(col_index) + 0.5) / float(width) * float(row.size()))
	index = clampi(index, 0, row.size() - 1)
	return row[index]


func _insert(value: String) -> void:
	if live_input:
		text_inserted.emit(value)
	else:
		_text = _text.insert(_caret, value)
		_caret += value.length()
	_refresh_entry()

func _on_character(key: Button) -> void:
	_insert(key.text)

func _on_space() -> void:
	_insert(" ")

func _on_backspace() -> void:
	if live_input:
		editing_key.emit("BackSpace")
	elif _caret > 0:
		_text = _text.erase(_caret - 1, 1)
		_caret -= 1
	_refresh_entry()

func _move_caret(direction: int) -> void:
	if live_input:
		editing_key.emit("Left" if direction < 0 else "Right")
	else:
		_caret = clampi(_caret + direction, 0, _text.length())
	_refresh_entry()

func _letter_rows() -> Array:
	var rows: Array = (ROWS_UPPER if _shift else ROWS_LOWER).duplicate(true)
	if input_context == "email":
		rows[4] = ["@", ".com", ".net", "_", "-", "+", "!", "#", "$", "%"]
	elif input_context == "url":
		rows[4] = ["/", ":", ".com", ".org", ".net", "?", "=", "&", "-", "_"]
	return rows

func _on_shift() -> void:
	if _flat.size() != 50:
		return
	_shift = not _shift
	var rows: Array = _letter_rows()
	for index in _flat.size():
		_flat[index].text = rows[index / 10][index % 10]
	_keys.back()[0].text = "SHIFT" if _shift else "Shift"

func _on_done() -> void:
	submitted.emit(_text)

func _refresh_entry() -> void:
	if live_input:
		_entry.text = "Typing into the password field" if masked else "Text appears in the page as you type"
		return
	var value := "*".repeat(_text.length()) if masked else _text
	var start := maxi(0, _caret - 22)
	_entry.text = ("…" if start > 0 else "") + value.substr(start, _caret - start) + "│" + value.substr(_caret, 22)

## Capture shortcuts before focused buttons consume them. Directional navigation
## and Cross still use Godot's normal focus handling and hold-to-repeat.
func _input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and PlayerOne.device >= 0 and event.device != PlayerOne.device:
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_BACKSPACE, KEY_SHIFT]:
		if event.keycode == KEY_BACKSPACE:
			_on_backspace()
		elif event.keycode == KEY_SHIFT:
			if not event.echo:
				_on_shift()
		else:
			return
		viewport.set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_TRIGGER_LEFT:
			if event.axis_value > 0.6 and not _left_trigger:
				_on_shift()
			_left_trigger = event.axis_value > 0.6
		elif event.axis == JOY_AXIS_TRIGGER_RIGHT:
			if event.axis_value > 0.6 and not _right_trigger:
				_on_done()
			_right_trigger = event.axis_value > 0.6
		else:
			return
		viewport.set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
	elif event.is_action_pressed("ui_shell_x"):
		_on_backspace()
	elif event.is_action_pressed("ui_shell_y"):
		_on_space()
	elif event.is_action_pressed("ui_shell_l1"):
		_move_caret(-1)
	elif event.is_action_pressed("ui_shell_r1"):
		_move_caret(1)
	elif event.is_action_pressed("ui_shell_options"):
		_on_done()
	else:
		return
	viewport.set_input_as_handled()
