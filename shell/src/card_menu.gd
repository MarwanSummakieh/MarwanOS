extends Control

## The options menu for a card on the home rail: what you can do to an
## application that is not running.
##
## A SEPARATE SCREEN FROM app_overlay.gd, and the difference is what is behind
## it. That one is composited over a live application by gamescope and has to be
## transparent and stay out of the way; this one sits over the shell's own rail,
## which the shell is free to dim. They share the row type and the navigation
## table and nothing else, which is why this is fifty lines rather than a
## parameter on the other.
##
## ONE ENTRY FOR NOW. Uninstall is the one that was missing and the one that
## cannot be done any other way on a machine with no terminal. MENU_ITEMS is the
## same extension seam as the app menu's: a line here and a branch in
## _on_item_chosen.
##
## THE MENU DOES NOT WAIT FOR THE REMOVAL. Apps.request_uninstall writes a
## request file and returns; marwanos-appctl does the work and the installed
## seam notices the application is gone within a poll, at which point the rail
## rebuilds without it. Blocking here would mean a menu sitting over a rail that
## has already changed underneath it.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const AppMenuRow = preload("res://src/app_menu_row.gd")

const MENU_ITEMS := [
	{"id": "uninstall", "label": "Uninstall", "icon": "trash"},
]

const MENU_WIDTH := 720

## Heavier than the app menu's scrim. There is no live application underneath
## worth keeping visible here -- only the rail, which the person just came from
## and is about to come back to.
const SCRIM_ALPHA := 0.82

var entry: Dictionary = {}

var _rows: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build()
	_wire_focus_neighbours()

	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("card menu up for %s" % str(entry.get("title", "<unknown>")))


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
	title.text = str(entry.get("title", ""))
	title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var items := VBoxContainer.new()
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	column.add_child(items)

	for item in MENU_ITEMS:
		var row := AppMenuRow.new()
		row.setup_item(str(item["id"]), str(item["label"]), str(item["icon"]))
		row.chosen.connect(_on_item_chosen)
		items.add_child(row)
		_rows.append(row)

	# NAMED, not "this cannot be undone". Uninstalling is reversible here -- the
	# store page offers it back -- and the honest cost is the download, which is
	# what a person on a domestic line actually wants warned about.
	var note := Label.new()
	note.text = "Removing frees the disk space. Installing it again means downloading it again."
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
	ShellLog.info("card menu: %s chosen" % id)
	match id:
		"uninstall":
			# The desktop-entry id is what appctl matches against its allow-list,
			# and it is the rail entry's own id -- marwanos-appscan built the
			# record from that .desktop file's basename.
			Apps.request_uninstall(str(entry.get("id", "")))
			closed.emit()
		_:
			ShellLog.error("card menu item \"%s\" has no action" % id)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
