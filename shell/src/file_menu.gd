extends Control

## The options menu for a row in the file manager: what you can do to a file
## or folder that is just sitting there.
##
## A SIBLING OF card_menu.gd, NOT A PARAMETER ON IT, and the precedent is
## card_menu's own header: it and app_overlay share the row type and the
## navigation table and nothing else, "which is why this is fifty lines rather
## than a parameter on the other". The same fork happens here. card_menu knows
## about applications -- its one item is Uninstall, its note prices the
## re-download, and its chosen-branch writes through the apps seam. None of
## that is true of a file, and threading "unless it is a file" through it
## would cost more lines than this file is.
##
## What IS shared is the row: AppMenuRow, reused as-is, because tabs, rows,
## cards and menu items are one family of focusable rectangles (store_tab.gd's
## argument) and a second menu-row class would be the same rectangle twice.
##
## THE MENU DECIDES NOTHING. The items arrive as data and the choice leaves as
## an id; the files screen owns the clipboard, the paths and the consequences.
## That is what lets the same fifty lines serve "options on this file" and
## "paste into this empty folder" without knowing the difference.

signal closed()
signal chosen(id: String)

const TvTheme = preload("res://src/tv_theme.gd")
const AppMenuRow = preload("res://src/app_menu_row.gd")

const MENU_WIDTH := 720

## card_menu's scrim, for card_menu's reason: there is nothing live underneath
## worth keeping visible -- only the file list the person just came from.
const SCRIM_ALPHA := 0.82

## What the menu is about -- a file name, a folder name. Set before add_child.
var title_text: String = ""

## The rows, as [{id, label, icon}] dictionaries. Set before add_child; which
## items exist (Paste only when the clipboard is armed) is the caller's call.
var items: Array = []

## One optional sentence under the rows, same slot card_menu uses to price a
## re-download. Empty means none.
var note_text: String = ""

var _rows: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build()
	_wire_focus_neighbours()

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("file menu up for %s with %d item(s)" % [title_text, _rows.size()])


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(TvTheme.BACKGROUND.r, TvTheme.BACKGROUND.g, TvTheme.BACKGROUND.b, SCRIM_ALPHA)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	# PanelContainer, not Panel, for the reason app_overlay.gd spells out: Panel
	# computes nothing from its children and would draw a zero-height background
	# under spilled content.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	panel.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(panel)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_right", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_PAGE_PAD)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	pad.add_child(column)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var item_box := VBoxContainer.new()
	item_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_box.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(item_box)

	for item in items:
		var row := AppMenuRow.new()
		row.setup_item(str(item["id"]), str(item["label"]), str(item["icon"]))
		row.chosen.connect(_on_item_chosen)
		item_box.add_child(row)
		_rows.append(row)

	if not note_text.is_empty():
		var note := Label.new()
		note.text = note_text
		note.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
		note.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(note)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)


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


func _on_item_chosen(id: String) -> void:
	ShellLog.info("file menu: %s chosen" % id)
	# The choice first, the close second: the screen's handler may open the
	# keyboard (Rename), and its close handler checks for that to decide who
	# gets input back.
	chosen.emit(id)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
