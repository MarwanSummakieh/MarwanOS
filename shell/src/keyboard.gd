extends Control

## An on-screen keyboard, driven by a thumbstick and four buttons.
##
## THIS IS THE PIECE THAT MADE SETTINGS READ-ONLY FOR SO LONG. "Joining a
## network needs a keyboard UI" was the stated reason mutable settings waited
## for marwand -- so this file is that reason being paid off rather than
## deferred again. It is deliberately general (it returns a string; it knows
## nothing about wifi) so the next thing that needs typed input does not grow a
## second one.
##
## THE GRID IS THE FOCUS TABLE, NOT A LAYOUT. Every key is a real focusable
## Button wired to its four neighbours explicitly, exactly like the rail and
## the settings list, because that is the only way this project has found to
## make directional navigation predictable: no geometric search, no wrapping,
## hard stops at the edges. The alternative -- one Control drawing a grid and
## tracking a cursor index -- would need its own input handling, its own focus
## visuals, and would not benefit from FocusRepeat's hold-to-repeat.
##
## SHIFT IS A MODE, NOT A SECOND LAYOUT TREE. Pressing shift relabels the keys
## in place, so focus stays exactly where it is and the neighbour table never
## changes. Rebuilding the grid would drop focus to nowhere mid-word.
##
## The password is masked on screen and never logged. See wifi.gd.

signal submitted(text: String)
signal cancelled()

const TvTheme = preload("res://src/tv_theme.gd")

## Rows of the main grid. Deliberately not a full QWERTY: this is aimed at
## passphrases typed once with a thumbstick, where a shorter path to any
## character beats muscle memory nobody has on a TV. Digits on top because
## passphrases start with them more often than letters.
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

const KEY_SIZE := 96
const KEY_GAP := 12

var title_text: String = "Enter password"
var masked: bool = true

var _text: String = ""
var _shift: bool = false

var _title: Label = null
var _entry: Label = null
var _keys: Array = []          # Array[Array[Button]], row-major
var _flat: Array = []          # every key button, for relabelling
var _hint_row: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

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
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	safe.add_child(column)

	_title = Label.new()
	_title.text = title_text
	_title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	_title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	# The entry line. A Panel behind it so an empty field still reads as a
	# field -- an unbordered empty label looks like the screen failed to draw.
	var entry_box := PanelContainer.new()
	entry_box.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	entry_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(entry_box)

	var entry_pad := MarginContainer.new()
	entry_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_pad.add_theme_constant_override("margin_left", TvTheme.SETTINGS_ROW_PAD)
	entry_pad.add_theme_constant_override("margin_right", TvTheme.SETTINGS_ROW_PAD)
	entry_pad.add_theme_constant_override("margin_top", 12)
	entry_pad.add_theme_constant_override("margin_bottom", 12)
	entry_box.add_child(entry_pad)

	_entry = Label.new()
	_entry.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	_entry.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_entry.custom_minimum_size = Vector2(0, TvTheme.SIZE_HERO_TITLE + 16)
	_entry.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_pad.add_child(_entry)

	column.add_child(_build_grid())
	column.add_child(_build_hints())

	_wire_focus_neighbours()
	_refresh_entry()

	# Nothing navigates until something is focused. Opening on the first letter
	# rather than a digit: it is the middle of where a thumb starts.
	if not _keys.is_empty():
		var first_letter_row: Array = _keys[1]
		var first: Control = first_letter_row[0]
		first.grab_focus()

	# Counted from _keys, which holds every row including the actions, rather
	# than from _flat, which holds only the character keys Shift relabels. The
	# two differ by four and the log used to quote the smaller one while calling
	# it "keys", which reads as the grid having lost the action row.
	var total := 0
	for row in _keys:
		total += row.size()
	ShellLog.info("keyboard up: %d keys (%d of them relabelled by shift)"
		% [total, _flat.size()])


func _build_grid() -> Control:
	var grid := VBoxContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("separation", KEY_GAP)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER

	for row_index in ROWS_LOWER.size():
		var row_box := HBoxContainer.new()
		row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_box.add_theme_constant_override("separation", KEY_GAP)
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		grid.add_child(row_box)

		var row_keys: Array = []
		for label in ROWS_LOWER[row_index]:
			var key := _make_key(str(label), KEY_SIZE)
			key.pressed.connect(_on_character.bind(key))
			row_box.add_child(key)
			row_keys.append(key)
			_flat.append(key)
		_keys.append(row_keys)

	# The action row. Wider keys because they are words rather than glyphs, and
	# because they are the three a person reaches for under time pressure.
	var actions := HBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", KEY_GAP)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_child(actions)

	var shift_key := _make_key("Shift", KEY_SIZE * 2 + KEY_GAP)
	shift_key.pressed.connect(_on_shift)
	actions.add_child(shift_key)

	var space_key := _make_key("Space", KEY_SIZE * 3 + KEY_GAP * 2)
	space_key.pressed.connect(_on_space)
	actions.add_child(space_key)

	var back_key := _make_key("Delete", KEY_SIZE * 2 + KEY_GAP)
	back_key.pressed.connect(_on_backspace)
	actions.add_child(back_key)

	var done_key := _make_key("Done", KEY_SIZE * 2 + KEY_GAP)
	done_key.pressed.connect(_on_done)
	actions.add_child(done_key)

	_keys.append([shift_key, space_key, back_key, done_key])
	return grid


func _make_key(label: String, width: float) -> Button:
	var key := Button.new()
	key.text = label
	key.custom_minimum_size = Vector2(width, KEY_SIZE)
	key.focus_mode = Control.FOCUS_ALL
	key.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	key.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	key.add_theme_color_override("font_focus_color", TvTheme.TEXT_PRIMARY)
	key.add_theme_color_override("font_hover_color", TvTheme.TEXT_PRIMARY)
	key.add_theme_color_override("font_pressed_color", TvTheme.TEXT_PRIMARY)
	# Same boxes as every other focusable thing in the shell, so a key reads as
	# the same kind of object as a card and a settings row.
	key.add_theme_stylebox_override("normal", TvTheme.card_idle_box())
	key.add_theme_stylebox_override("hover", TvTheme.card_idle_box())
	key.add_theme_stylebox_override("pressed", TvTheme.row_pressed_box())
	key.add_theme_stylebox_override("focus", TvTheme.card_focus_ring())
	# The focus surface is swapped on enter/exit rather than themed, because
	# Button's "normal" is what shows under the ring and it does not vary with
	# focus on its own.
	key.focus_entered.connect(_on_key_focus.bind(key, true))
	key.focus_exited.connect(_on_key_focus.bind(key, false))
	return key


func _on_key_focus(key: Button, focused: bool) -> void:
	var box := TvTheme.card_focus_box() if focused else TvTheme.card_idle_box()
	key.add_theme_stylebox_override("normal", box)
	key.add_theme_stylebox_override("hover", box)


func _build_hints() -> Control:
	_hint_row = HBoxContainer.new()
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	_hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_row.add_child(TvTheme.hint("A", "Type"))
	_hint_row.add_child(TvTheme.hint("X", "Shift"))
	_hint_row.add_child(TvTheme.hint("Y", "Delete"))
	_hint_row.add_child(TvTheme.hint("B", "Back"))
	return _hint_row


## The grid's neighbour table. Rows may differ in length (the action row has
## four wide keys against ten narrow ones), so moving between them maps by
## PROPORTION rather than by index -- pressing down from the middle of the
## letters lands on the middle of the action row, which is what the eye expects
## when the keys below are visibly wider.
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


# ---------------------------------------------------------------------------
# Editing
# ---------------------------------------------------------------------------

func _on_character(key: Button) -> void:
	_text += key.text
	_refresh_entry()


func _on_space() -> void:
	_text += " "
	_refresh_entry()


func _on_backspace() -> void:
	if _text.is_empty():
		return
	_text = _text.substr(0, _text.length() - 1)
	_refresh_entry()


func _on_shift() -> void:
	_shift = not _shift
	# Relabel in place; see the header for why the grid is not rebuilt.
	var rows := ROWS_UPPER if _shift else ROWS_LOWER
	var flat_index := 0
	for row_index in rows.size():
		for label in rows[row_index]:
			var key: Button = _flat[flat_index]
			key.text = str(label)
			flat_index += 1


func _on_done() -> void:
	submitted.emit(_text)


## Masked by default, because a passphrase on a TV is visible to the whole
## room. The length is shown so a mistyped key is still noticeable -- a field
## that shows nothing at all makes it impossible to tell a stuck button from a
## working one.
func _refresh_entry() -> void:
	if _text.is_empty():
		_entry.text = ""
		_entry.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		return
	_entry.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	if masked:
		_entry.text = "*".repeat(_text.length())
	else:
		_entry.text = _text


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Shortcuts for the two edits that would otherwise cost a trip across the
## grid. Typing a passphrase with a stick is slow enough without making every
## correction a journey to the Delete key.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
		return
	# ui_shell_x / ui_shell_y are the shell's own two spare face buttons; see
	# shell_input.gd. Guarded with has_action so a shell built before they
	# existed cannot crash here.
	if InputMap.has_action("ui_shell_y") and event.is_action_pressed("ui_shell_y"):
		get_viewport().set_input_as_handled()
		_on_backspace()
		return
	if InputMap.has_action("ui_shell_x") and event.is_action_pressed("ui_shell_x"):
		get_viewport().set_input_as_handled()
		_on_shift()
