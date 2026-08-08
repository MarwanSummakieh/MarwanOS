extends Control

## The home-button menu: what you get while an application is running.
##
## THE APPLICATION KEEPS THE WHOLE SCREEN. This draws nothing behind its own
## panel -- the background is transparent, gamescope composites this window on
## top of the running application, and what shows around the menu is the
## application itself, live and at full size. There is no screenshot, no
## thumbnail and no capture.
##
## That is possible because of one X property. gamescope reads
## GAMESCOPE_EXTERNAL_OVERLAY on a window and, when set, composites that window
## over the focused application instead of replacing it -- the same mechanism
## Steam's overlay uses on a Deck. Kiosk.set_overlay() sets and clears it; see
## there for how, and for what happens if it does not take.
##
## WHY A MENU AND NOT THE FRAMED CARD IT REPLACES. The first version of this
## screen drew a frame around the application, shrank the visible area to 72% of
## the height and put two circular buttons in the strip underneath. It worked,
## and it cost the application most of the screen to offer two choices -- so the
## thing you pressed home to look at was the thing that got covered. A menu is
## the same two presses, keeps the application whole behind it, and has somewhere
## obvious to put the third and fourth entries when they arrive.
##
## ONE ENTRY FOR NOW, AND THAT IS THE POINT. MENU_ITEMS is the extension seam:
## adding a line there and a case to _on_item_chosen is the entire change. The
## menu deliberately ships with only what it can actually do.
##
## MINIMIZE IS GONE FROM THE MENU, NOT FROM THE SHELL. It was always the weaker
## of the two controls -- it depends on gamescope handing focus back to the
## shell, which is the compositor's decision and not something a client can
## insist on. Launcher.minimize_current() is untouched and still wired; nothing
## in the UI calls it today. When the menu grows, that is the first entry to
## reconsider, and the bench is what decides whether it earns its place.
##
## Navigation is the settings list's, verbatim: one axis, hard stops,
## perpendicular pointed at self. B closes the menu and returns to the
## application.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const AppMenuRow = preload("res://src/app_menu_row.gd")

## The menu, in order. Adding an entry here and a branch in _on_item_chosen is
## the whole of adding a menu item -- the panel sizes itself and the focus chain
## is wired from this list.
const MENU_ITEMS := [
	{"id": "close", "label": "Close", "icon": "close"},
]

## Width of the menu panel. Fixed rather than a fraction of the screen: the
## entries are short labels and a panel that grew with the display would just
## put more empty space between an icon and a word.
const MENU_WIDTH := 720

## How far the scrim dims the application behind the menu. Enough that a white
## storefront cannot wash out the panel's edge, light enough that the
## application is plainly still there -- which is the whole reason this is an
## overlay rather than a screen.
const SCRIM_ALPHA := 0.55

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

	ShellLog.info("app menu up for %s" % str(entry.get("title", "<unknown>")))


func _build() -> void:
	# The dim covers the whole screen, unlike the strip it replaces. With the
	# application no longer framed there is no region the menu is deliberately
	# keeping clear, so a partial dim would just be an edge with no meaning.
	var scrim := ColorRect.new()
	scrim.color = Color(TvTheme.BACKGROUND.r, TvTheme.BACKGROUND.g, TvTheme.BACKGROUND.b, SCRIM_ALPHA)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# Centred both ways. A pause menu is the one surface in this shell that is
	# not anchored to an edge: it belongs to the application underneath rather
	# than to the shell's furniture, and the middle is where every console puts
	# it.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	# PanelContainer, NOT Panel, and the Xvfb run is why this comment exists.
	# Panel is not a Container: it takes its size from custom_minimum_size and
	# anchors, and computes nothing from its children. With a minimum height of
	# zero it drew a zero-height background while the title, the rows and the
	# hints spilled out and rendered over the application with no surface behind
	# them -- legible only by luck, over whatever the app happened to be showing.
	# PanelContainer sizes itself to its child and draws the same stylebox, which
	# is the whole fix; the width stays a minimum so short menus are not narrow.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	panel.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(panel)

	# No full-rect preset here any more: inside a PanelContainer the child is
	# laid out by the container, and presetting anchors would fight it.
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

	# The application's name, not "Menu". Which application this is about is the
	# one thing a person needs before pressing Close, and the menu is opened
	# from inside the application rather than from a list that already said so.
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

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back to app"))
	column.add_child(hints)


## The settings list's table, verbatim: one axis, hard stops, perpendicular
## pointed at self. Vertical here where the circles were horizontal, which is
## the one navigational consequence of the menu replacing them.
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
	ShellLog.info("app menu: %s chosen" % id)
	match id:
		"close":
			Launcher.close_current()
			# The menu goes away immediately; the rail comes back when the launch
			# seam's poll notices the process is gone, which is the same path a
			# normal exit takes. Waiting here would leave the menu on screen over
			# a dying application.
			closed.emit()
		_:
			# Unreachable while MENU_ITEMS and this match agree, which is exactly
			# why it is logged: the failure it catches is an entry added to the
			# list and not to the switch, and on this machine a press that does
			# nothing silently is indistinguishable from broken input.
			ShellLog.error("app menu item \"%s\" has no action" % id)


func _unhandled_input(event: InputEvent) -> void:
	# B returns to the application. The home button does the same, so the button
	# that opened the menu also dismisses it -- which is what every console does
	# and what a person will try first.
	if event.is_action_pressed("ui_cancel") \
			or (InputMap.has_action("ui_shell_home") and event.is_action_pressed("ui_shell_home")):
		get_viewport().set_input_as_handled()
		ShellLog.info("app menu dismissed; returning to the app")
		closed.emit()
