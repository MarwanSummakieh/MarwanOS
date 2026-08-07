extends Control

## The stores screen: side tabs on the left, the selected store's page
## rendered on the right -- the PS Store shape, at the shell's fidelity.
##
## WHAT "RENDERED" MEANS HERE, honestly. The page on the right is drawn BY THE
## SHELL: the store's wash, name, description, and its live install state from
## the status seam. It is not the store application's own UI in a pane --
## embedding a foreign client's window inside a Godot control is compositor
## work (XEmbed/subsurface composition) that gamescope does not offer a shell
## running as one of its clients, and a webview would be the project's first
## native extension. So the page is the shell's rendering of the store, and
## pressing A opens the store application itself, fullscreen, through the
## launch seam -- which is also exactly what the PS5 does: its store tile
## opens a fullscreen app. Quitting the store lands back on this page.
##
## NAVIGATION. The tab column is the settings list's argument verbatim: one
## axis, hard stops, perpendicular pointed at self. Focusing a tab renders its
## page; A opens the store; B closes the screen. While a launch is up this
## screen goes deaf (see _on_launch_started) -- the shell still receives pad
## events when another client has the screen, because both read evdev, and a B
## press meant for Steam must not close the screen underneath it.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Catalogue = preload("res://src/catalogue.gd")
const StoreTab = preload("res://src/store_tab.gd")

## What the Steam page's install line says in each state the status seam can
## report. The same narration that lived on the rail card before the third
## amendment moved Steam here; "unknown" doubles as the fallback so no state
## can render the page silent about the install.
const STEAM_INSTALL_LINES := {
	"installed": "Installed -- A opens the storefront",
	"downloading": "Downloading from Flathub -- a few GB, so give it minutes",
	"waiting-network": "Waiting for a network before downloading",
	"no-network": "No network found -- plug in ethernet; the install retries next boot",
	"no-space": "Not enough free space on the drive for Steam",
	"failed": "Install failed -- journalctl -t marwanos-install has the story",
	"unknown": "Checking the install state",
}

## The states whose install line names a problem a person can act on -- they
## render in TEXT_ALERT, same argument as the rail's subtitle had.
const STEAM_ALERT_STATES := ["no-network", "no-space", "failed"]

var _tabs: Array = []
var _selected: Dictionary = {}

var _page_hero: Panel = null
var _page_title: Label = null
var _page_tagline: Label = null
var _page_description: Label = null
var _page_status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The full TV-safe inset, all four edges -- everything on this screen is
	# text or carries a focus ring; nothing has the rail's licence to bleed.
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
	heading.text = "Stores"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", TvTheme.STORE_PAGE_GAP)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	# The tab column: fixed width, tabs stacked from the top. The width lives
	# on this container rather than on each tab so the rows inherit it the way
	# settings rows inherit the safe width.
	var tab_column := VBoxContainer.new()
	tab_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_column.custom_minimum_size = Vector2(TvTheme.STORE_TAB_WIDTH, 0)
	tab_column.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	content.add_child(tab_column)

	for entry in Catalogue.stores():
		var tab := StoreTab.new()
		tab.setup_store(entry)
		tab.opened.connect(_on_store_opened)
		tab.focus_entered.connect(_on_tab_focused.bind(tab))
		tab_column.add_child(tab)
		_tabs.append(tab)

	content.add_child(_build_page())

	column.add_child(_build_hints())

	_wire_focus_neighbours()

	# The rail's lesson: nothing navigates until something is focused. Opening
	# on the first tab also renders the first page, via its focus_entered.
	if not _tabs.is_empty():
		var first: Control = _tabs[0]
		first.grab_focus()

	SystemStatus.steam_changed.connect(_on_steam_changed)
	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)

	ShellLog.info("stores screen up with %d tabs" % _tabs.size())


## The page pane: a surface panel holding the store's wash, name, tagline,
## description and live install line. One pane re-rendered per tab rather than
## a pane per store -- with the content data-driven there is nothing for a
## second pane to hold.
func _build_page() -> Control:
	var pane := Panel.new()
	pane.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_right", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_PAGE_PAD)
	pane.add_child(pad)

	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	pad.add_child(page)

	# The wash stands in for key art, exactly as the rail's hero does; real art
	# arrives with Phase 1's AppStream data and gets rounded the same way.
	_page_hero = Panel.new()
	_page_hero.custom_minimum_size = Vector2(0, TvTheme.STORE_PAGE_HERO_HEIGHT)
	_page_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_page_hero)

	_page_title = Label.new()
	_page_title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	_page_title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_page_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_page_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_page_title)

	_page_tagline = Label.new()
	_page_tagline.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_page_tagline.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_page_tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_page_tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_page_tagline)

	_page_description = Label.new()
	_page_description.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_page_description.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_page_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_page_description)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(spacer)

	# The live line: what the machine is doing about this store right now,
	# from the status seam. The one line on the page that changes on its own.
	_page_status = Label.new()
	_page_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_page_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_page_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_page_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_page_status)

	return pane


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Open store"))
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


## The settings list's table, verbatim: one axis, hard stops, perpendicular
## pointed at self.
func _wire_focus_neighbours() -> void:
	var count := _tabs.size()
	for index in count:
		var tab: Control = _tabs[index]
		var up := index - 1 if index > 0 else index
		var down := index + 1 if index + 1 < count else index

		tab.focus_neighbor_top = tab.get_path_to(_tabs[up])
		tab.focus_neighbor_bottom = tab.get_path_to(_tabs[down])
		tab.focus_neighbor_left = tab.get_path_to(tab)
		tab.focus_neighbor_right = tab.get_path_to(tab)


func _on_tab_focused(tab: Control) -> void:
	_render_page(tab.entry)


func _render_page(entry: Dictionary) -> void:
	_selected = entry
	_page_hero.add_theme_stylebox_override(
		"panel", TvTheme.card_art_box(TvTheme.accent(str(entry.get("accent", "")))))
	_page_title.text = str(entry.get("title", ""))
	_page_tagline.text = str(entry.get("tagline", ""))
	_page_description.text = str(entry.get("description", ""))
	_refresh_status()


## Only the Steam page has an install narration today, because Steam is the
## only store and the status seam's steam state is the only install state the
## system reports. A second store arrives with marwand, which will report per-
## app states; this function is where that plugs in.
func _refresh_status() -> void:
	if _page_status == null or _selected.is_empty():
		return
	var state := SystemStatus.steam
	# The installer's live progress line wins over the fixed wording, for the
	# rail's reason: a number that moves is the difference between "working"
	# and "hung" to the person watching.
	if not SystemStatus.steam_detail.is_empty():
		_page_status.text = "Installing -- %s" % SystemStatus.steam_detail
	else:
		_page_status.text = str(STEAM_INSTALL_LINES.get(state, STEAM_INSTALL_LINES["unknown"]))
	_page_status.add_theme_color_override(
		"font_color",
		TvTheme.TEXT_ALERT if STEAM_ALERT_STATES.has(state) else TvTheme.TEXT_SECONDARY)


func _on_steam_changed(_state: String) -> void:
	_refresh_status()


func _on_store_opened(entry: Dictionary) -> void:
	# Through the launch seam like every launch in the project. The screen
	# stays open underneath: when the store quits, this page is what the
	# person lands back on, which is the PS Store's own behaviour too.
	Launcher.launch(entry)


## Deaf while a launch is up. The launched client owns the screen, but the
## shell still reads the same evdev devices, so without this a B press meant
## for Steam would close the stores screen invisibly behind it.
func _on_launch_started(_entry: Dictionary) -> void:
	set_process_unhandled_input(false)


func _on_launch_finished(_entry: Dictionary) -> void:
	set_process_unhandled_input(true)
	# The launch stole focus bookkeeping nowhere -- the tab is still the focus
	# owner -- but grab it again in case the launched app's window shuffle left
	# the viewport with none, which is the rail's _ensure_focus lesson.
	if not _tabs.is_empty() and get_viewport().gui_get_focus_owner() == null:
		var first: Control = _tabs[0]
		first.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath never sees the same press.
	get_viewport().set_input_as_handled()
	closed.emit()
