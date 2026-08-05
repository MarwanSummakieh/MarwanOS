extends Control

## The grid screen -- everything the appliance shows when nothing is launched.
##
## The whole layout is built in code rather than in a .tscn. Two reasons, both
## specific to this repo: a scene file is authored by a GUI tool that rewrites it
## on its own schedule (which is how CRLF and unreviewable diffs get into a repo
## that has spent real days on both), and Phase 1 M2 replaces this catalogue with
## a live list from marwand that has to be built at runtime anyway. A scene tree
## laid out by hand would be thrown away at the first `LibraryChanged` event.
##
## FOCUS NEIGHBOURS ARE SET EXPLICITLY ON EVERY TILE, and that is not belt and
## braces. With focus_neighbor_* empty, Control falls back to a geometric search
## that considers any focusable control in a band in that direction and picks the
## nearest by edge distance. At the end of a row the nearest control in the +x
## band is not the first tile of the next row, and the answer it does give is hard
## to predict from the code. Explicit NodePaths turn "why did focus jump there"
## into a table anyone can read.
##
## Edges are hard stops: a tile at the left of a row points its left neighbour at
## itself, so pushing further does nothing rather than wrapping. Wrapping is a
## defensible choice and this is not it -- on a grid this small, a cursor that
## teleports across the screen when you lean on the stick reads as a glitch.

const TvTheme = preload("res://src/tv_theme.gd")
const Catalogue = preload("res://src/catalogue.gd")
const Tile = preload("res://src/tile.gd")

var _grid: GridContainer = null
var _status: Label = null
var _tiles: Array = []
var _last_focused: Control = null


func _ready() -> void:
	_build()
	_populate()
	_wire_focus_neighbours()

	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)
	PlayerOne.player_one_present.connect(_on_player_one_present)
	PlayerOne.player_one_absent.connect(_on_player_one_absent)
	_refresh_status()

	# Nothing navigates until something is focused: the viewport's directional
	# navigation starts from the current focus owner, and with none there is no
	# origin to move from. This is the single most common way a gamepad UI ships
	# looking dead.
	_ensure_focus()

	ShellLog.info("grid ready with %d tiles" % _tiles.size())


func _build() -> void:
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The TV-safe inset. Backgrounds may bleed past it; text, tiles and focus
	# rings never may, which is why everything else is inside this container.
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

	column.add_child(_build_header())

	_grid = GridContainer.new()
	_grid.columns = TvTheme.GRID_COLUMNS
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", TvTheme.GRID_SEPARATION)
	_grid.add_theme_constant_override("v_separation", TvTheme.GRID_SEPARATION)
	column.add_child(_grid)

	column.add_child(_build_hints())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var wordmark := Label.new()
	wordmark.text = "MarwanOS"
	wordmark.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	wordmark.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(wordmark)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	# Controller state lives in the header rather than in a modal overlay. A pad
	# that has been unplugged should not also take the grid away -- the person is
	# reaching for a cable, and the UI they come back to should be the one they
	# left, with focus where it was.
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_status)

	return header


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", 36)
	hints.add_child(_hint("A", "Open"))
	hints.add_child(_hint("B", "Back"))
	return hints


func _hint(glyph: String, action: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)

	var badge := Label.new()
	badge.text = glyph
	badge.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	badge.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	badge.add_theme_stylebox_override("normal", TvTheme.glyph_box())
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)

	var caption := Label.new()
	caption.text = action
	caption.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	caption.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(caption)

	return row


func _populate() -> void:
	for entry in Catalogue.entries():
		var tile := Tile.new()
		tile.setup(entry)
		_grid.add_child(tile)
		_tiles.append(tile)


## Builds the neighbour table described in the file header. The paths are relative
## to each tile, which is what Control.focus_neighbor_* expects.
func _wire_focus_neighbours() -> void:
	var columns := TvTheme.GRID_COLUMNS
	var count := _tiles.size()

	for index in count:
		var tile: Control = _tiles[index]
		var column := index % columns

		var left := index - 1 if column > 0 else index
		var right := index + 1 if column < columns - 1 and index + 1 < count else index
		var up := index - columns if index - columns >= 0 else index
		var down := index + columns if index + columns < count else index

		tile.focus_neighbor_left = tile.get_path_to(_tiles[left])
		tile.focus_neighbor_right = tile.get_path_to(_tiles[right])
		tile.focus_neighbor_top = tile.get_path_to(_tiles[up])
		tile.focus_neighbor_bottom = tile.get_path_to(_tiles[down])


func _ensure_focus() -> void:
	if _tiles.is_empty():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	if is_instance_valid(_last_focused):
		_last_focused.grab_focus()
	else:
		var first: Control = _tiles[0]
		first.grab_focus()


func _on_launch_started(_entry: Dictionary) -> void:
	# Captured before hiding: hiding a Control releases focus, so asking
	# afterwards would always answer null.
	_last_focused = get_viewport().gui_get_focus_owner()
	hide()
	# Hiding a Control stops it drawing and stops it receiving GUI input, but
	# _unhandled_input keeps arriving regardless. The placeholder is a later
	# sibling and so is called first, and it consumes the press -- but relying on
	# dispatch order for "B does not do two things at once" is the kind of
	# assumption that breaks silently when a node is reparented.
	set_process_unhandled_input(false)


func _on_launch_finished(_entry: Dictionary) -> void:
	show()
	set_process_unhandled_input(true)
	_ensure_focus()


func _on_player_one_present(_device: int, _pad_name: String) -> void:
	_refresh_status()
	# A controller arriving is also the moment a shell that came up with nothing
	# focused becomes usable, so take the opportunity.
	_ensure_focus()


func _on_player_one_absent() -> void:
	_refresh_status()


func _refresh_status() -> void:
	if _status == null:
		return
	if PlayerOne.has_controller():
		_status.text = "Player 1  %s" % PlayerOne.pad_name
		_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	else:
		_status.text = "Reconnect the controller"
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# The grid is the root of the shell, so there is nowhere to back out to and
	# nothing here quits. Exiting would be a client exit as far as
	# marwanos-session is concerned: the supervision loop would count it as a
	# crash, restart it, and five of those inside sixty seconds would trip the
	# guard and leave the compositor holding an empty screen. B is inert here on
	# purpose.
	ShellLog.info("back pressed at the grid; nothing above this")
