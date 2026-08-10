extends Control

## The store screen: side tabs on the left, the selected page rendered on the
## right -- the PS Store shape, at the shell's fidelity. Two kinds of tab now:
## a STORE (Steam), whose page describes it and whose A opens the client
## fullscreen, and the APPS shelf, whose page is a grid of every application
## the image ships -- installed or not -- drawn entirely by the shell from
## files already on disk. The grid is why this screen opens instantly: there
## is no network between a button press and the shelves, only the artwork
## cache marwanos-storeart filled long before anyone looked.
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
const Tile = preload("res://src/tile.gd")
const CardMenu = preload("res://src/card_menu.gd")

## The apps grid's shape. Five columns leaves the focused card's growth room
## inside the pane at the design width; six would overflow the frame the
## moment a card in a full row took focus, which is the card's resting state
## whenever someone is actually shopping.
const GRID_COLUMNS := 5

## How far a grid card grows when focused. The rail's 340 is a statement piece
## for a strip with one axis; in a grid the same growth shoves both axes of
## neighbours around, so the pop is kept to what registers as selection
## without reading as the layout collapsing.
const GRID_CARD_FOCUS := 240

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

## What the page says while marwanos-appctl is working on THIS store's
## application, and after it has finished. Separate from the table above because
## that one narrates the first-boot installer and this one narrates a request
## the person just made from this screen -- the same word would be describing
## two different machines.
const APPCTL_LINES := {
	"installing": "Installing -- this is a large download, give it minutes",
	"uninstalling": "Removing",
	"failed": "That did not work -- journalctl -t marwanos-appctl has the story",
	"refused": "This machine will not manage that application",
}

## appctl states that are a problem rather than progress.
const APPCTL_ALERT_STATES := ["failed", "refused"]

## What A does, and it is not always the same verb. An application that is not
## on the machine cannot be opened, and until this existed the tab offered to
## open it anyway and launched a `flatpak run` that failed instantly with
## nothing on screen to say why.
const HINT_OPEN := "Open store"
const HINT_INSTALL := "Install"

var _tabs: Array = []
var _selected: Dictionary = {}
var _hints: HBoxContainer = null

var _page_pane: Control = null
var _page_hero: Panel = null
var _page_title: Label = null
var _page_tagline: Label = null
var _page_description: Label = null
var _page_status: Label = null

# The apps shelf. The tab is kept by name because two behaviours hang off it
# specifically: right from it enters the grid, and B in the grid comes back to
# it. The cards array is the focus-wiring and B-detection surface.
var _apps_tab: Control = null
var _card_menu: CardMenu = null
var _grid_pane: Control = null
var _grid: GridContainer = null
var _grid_cards: Array = []
var _grid_title: Label = null
var _grid_tagline: Label = null
var _grid_status: Label = null


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
	heading.text = "Store"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", TvTheme.STORE_PAGE_GAP)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	# The tab column: one icon wide, tabs stacked from the top. The width used to
	# live here so the name-bearing rows inherited it; a tab is square and sizes
	# itself now, and this only keeps the column from collapsing narrower than
	# one.
	var tab_column := VBoxContainer.new()
	tab_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_column.custom_minimum_size = Vector2(TvTheme.STORE_TAB_SIZE, 0)
	tab_column.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	content.add_child(tab_column)

	# Stores first, the apps shelf last: the shelf is the general case and a
	# store is the destination someone came for by name, which is the PS5's
	# ordering too. One loop because a tab is a tab -- which KIND it is only
	# matters to _render_page.
	var tab_entries: Array = Catalogue.stores().duplicate()
	tab_entries.append(Catalogue.APPS_TAB)
	for entry in tab_entries:
		var tab := StoreTab.new()
		tab.setup_store(entry)
		tab.opened.connect(_on_store_opened)
		tab.focus_entered.connect(_on_tab_focused.bind(tab))
		tab_column.add_child(tab)
		_tabs.append(tab)
		if str(entry.get("id", "")) == "store.apps":
			_apps_tab = tab

	_page_pane = _build_page()
	content.add_child(_page_pane)
	_grid_pane = _build_grid_pane()
	_grid_pane.visible = false
	content.add_child(_grid_pane)
	_rebuild_grid()

	column.add_child(_build_hints())

	_wire_focus_neighbours()

	# The rail's lesson: nothing navigates until something is focused. Opening
	# on the first tab also renders the first page, via its focus_entered.
	if not _tabs.is_empty():
		var first: Control = _tabs[0]
		first.grab_focus()

	SystemStatus.steam_changed.connect(_on_steam_changed)
	# Both halves of "is it here yet": appctl says what is being done about it,
	# the installed seam says whether it has actually arrived or gone. The page
	# and the A hint depend on both, so both are watched.
	Apps.state_changed.connect(_on_apps_state_changed)
	Installed.apps_changed.connect(_on_installed_changed)
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


## The apps shelf's pane: identity block on top -- title, tagline, state, the
## rail's hero pattern at pane scale -- and the grid of cards under it. The
## block belongs to whichever card has focus, so moving through the grid reads
## the way the rail does: the cards are the browsing, the text is the answer.
func _build_grid_pane() -> Control:
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

	_grid_title = Label.new()
	_grid_title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	_grid_title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_grid_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_grid_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_grid_title)

	_grid_tagline = Label.new()
	_grid_tagline.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_grid_tagline.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_grid_tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_grid_tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_grid_tagline)

	_grid_status = Label.new()
	_grid_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_grid_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_grid_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_grid_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_grid_status)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", TvTheme.CARD_GAP)
	_grid.add_theme_constant_override("v_separation", TvTheme.CARD_GAP)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_grid)

	return pane


## Every shipped application as a card entry, in the rail's own shape so
## tile.gd's press behaviour -- launch when installed, download when available,
## refuse politely in between -- carries over without a line of policy here.
## Store applications are EXCLUDED for ADR 0006's reason turned around: a
## store's home is its own tab, and Steam appearing on the shelf next to the
## Steam tab would be the same thing with two homes.
func _grid_entries() -> Array:
	var store_ids: Array = Catalogue.store_app_ids()

	var known_ids: Array = []
	for entry in Installed.apps:
		known_ids.append(str(entry.get("id", "")))

	var entries: Array = []
	for entry in Installed.apps:
		if store_ids.has(str(entry.get("id", ""))):
			continue
		# Steam GAMES are on the rail but not on this shelf: the shelf's whole
		# verb set is install/uninstall through appctl, and a game is neither
		# installable nor removable by this machine's root -- Steam owns both
		# sides of that. A card whose only button is refused is not a card.
		if str(entry.get("id", "")).begins_with("steam."):
			continue
		var copy: Dictionary = entry.duplicate()
		# An installed application's art comes from appscan; a PENDING one has
		# no export yet, and the cache is what says what is downloading.
		if str(copy.get("icon", "")).is_empty():
			copy["icon"] = Catalogue.store_icon_path(str(copy.get("id", "")))
		entries.append(copy)
	for entry in Catalogue.available(known_ids):
		if store_ids.has(str(entry.get("id", ""))):
			continue
		entries.append(entry)
	return entries


## Torn down and rebuilt from the current lists, the rail's own strategy: the
## cards are cheap, the lists are the truth, and a rebuild cannot disagree
## with itself the way an in-place patch can. Focus is put back on the same
## application when it survives the rebuild, so an install finishing under
## the cursor does not teleport the cursor.
func _rebuild_grid() -> void:
	if _grid == null:
		return

	# Asked of the cards rather than of the viewport's focus owner: the cards
	# array is untyped on purpose, so the entry lookup stays dynamic instead
	# of a member access the type checker would reject on Control.
	var focused_id := ""
	var was_in_grid := false
	for card in _grid_cards:
		if card.has_focus():
			was_in_grid = true
			focused_id = str(card.entry.get("id", ""))
			break

	for card in _grid_cards:
		_grid.remove_child(card)
		card.queue_free()
	_grid_cards.clear()

	for entry in _grid_entries():
		var card := Tile.new()
		card.focused_size = GRID_CARD_FOCUS
		card.setup(entry)
		card.selected.connect(_on_grid_card_selected)
		_grid.add_child(card)
		_grid_cards.append(card)

	_wire_grid_focus()

	if was_in_grid:
		var restored := false
		for card in _grid_cards:
			if str(card.entry.get("id", "")) == focused_id:
				card.grab_focus()
				restored = true
				break
		# The application under the cursor left the shelf entirely -- the tab
		# is the one place guaranteed to still exist.
		if not restored and _apps_tab != null:
			_apps_tab.grab_focus()


## The settings list's table extended to two axes: hard stops at every edge,
## except left from the first column, which is the way back to the tab that
## brought focus here.
func _wire_grid_focus() -> void:
	var count := _grid_cards.size()
	for index in count:
		var card: Control = _grid_cards[index]
		var col := index % GRID_COLUMNS
		var row := index / GRID_COLUMNS
		var last_row := (count - 1) / GRID_COLUMNS

		var left: Control = card
		if col > 0:
			left = _grid_cards[index - 1]
		elif _apps_tab != null:
			left = _apps_tab
		var right: Control = card
		if col + 1 < GRID_COLUMNS and index + 1 < count:
			right = _grid_cards[index + 1]
		var up: Control = card
		if row > 0:
			up = _grid_cards[index - GRID_COLUMNS]
		var down: Control = card
		if index + GRID_COLUMNS < count:
			down = _grid_cards[index + GRID_COLUMNS]
		elif row < last_row:
			# The row below exists but is shorter than this column reaches:
			# its last card, rather than a dead press.
			down = _grid_cards[count - 1]

		card.focus_neighbor_left = card.get_path_to(left)
		card.focus_neighbor_right = card.get_path_to(right)
		card.focus_neighbor_top = card.get_path_to(up)
		card.focus_neighbor_bottom = card.get_path_to(down)

	# The doorway in: right from the apps tab lands on the first card. Re-set
	# on every rebuild because the first card is a NEW node each time, and a
	# NodePath to a freed one is a press that goes nowhere.
	if _apps_tab != null:
		var target: Control = _apps_tab
		if not _grid_cards.is_empty():
			target = _grid_cards[0]
		_apps_tab.focus_neighbor_right = _apps_tab.get_path_to(target)


## A grid card took focus: the identity block is its. Same contract as the
## rail's hero -- the tile hands out its entry, the screen renders it.
func _on_grid_card_selected(entry: Dictionary) -> void:
	if _grid_title == null:
		return
	_grid_title.text = str(entry.get("title", ""))
	var tagline := str(entry.get("tagline", ""))
	if tagline.is_empty():
		tagline = Catalogue.tagline_for(str(entry.get("id", "")))
	_grid_tagline.text = tagline

	var state := str(entry.get("state", ""))
	if state == "installed":
		_grid_status.text = "Installed -- A opens it"
	else:
		_grid_status.text = str(entry.get("subtitle", ""))
	_grid_status.add_theme_color_override(
		"font_color",
		TvTheme.TEXT_ALERT if ["failed", "no-network", "no-space"].has(state)
			else TvTheme.TEXT_SECONDARY)
	_refresh_hints()


## What the identity block says when the TAB has focus and no card does yet:
## the shelf's own name and how many things are on it.
func _render_grid_idle() -> void:
	if _grid_title == null:
		return
	_grid_title.text = "Apps"
	_grid_tagline.text = "Everything this machine can run"
	# Counted per state rather than "everything else is downloadable": a card
	# mid-download or mid-failure is neither installed nor an offer, and a
	# summary that misfiles it is a small lie on the one line that claims to
	# summarise.
	var installed_count := 0
	var available_count := 0
	for card in _grid_cards:
		match str(card.entry.get("state", "")):
			"installed":
				installed_count += 1
			"available":
				available_count += 1
	var line := "%d installed, %d ready to download" % [installed_count, available_count]
	var busy := _grid_cards.size() - installed_count - available_count
	if busy > 0:
		line += ", %d on the way" % busy
	_grid_status.text = line
	_grid_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)


func _build_hints() -> Control:
	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	_refresh_hints()
	return _hints


## Rebuilt rather than relabelled: TvTheme.hint returns an assembled badge and
## caption and does not hand back the caption to edit, and a hint row of two
## children is cheap enough that reaching into its internals to save two node
## allocations would be the worse trade.
func _refresh_hints() -> void:
	if _hints == null:
		return
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()

	# On the apps shelf the verb belongs to the focused CARD, and to the tab
	# itself only the act of entering. B's caption tracks the same split: from
	# the grid it backs out to the tab, from a tab it leaves the screen.
	if str(_selected.get("id", "")) == "store.apps":
		var focused: Dictionary = {}
		for card in _grid_cards:
			if card.has_focus():
				focused = card.entry
				break
		if focused.is_empty():
			_hints.add_child(TvTheme.hint("A", "Browse"))
			_hints.add_child(TvTheme.hint("B", "Back"))
		else:
			var state := str(focused.get("state", ""))
			if state == "installed":
				_hints.add_child(TvTheme.hint("A", "Open"))
			elif state == "available":
				_hints.add_child(TvTheme.hint("A", "Install"))
			_hints.add_child(TvTheme.hint("B", "Back"))
		return

	_hints.add_child(TvTheme.hint("A", HINT_OPEN if _selected_installed() else HINT_INSTALL))
	# The desktop client is a second, deliberate way to open the same store
	# application -- see Catalogue.steam_desktop_entry for why the in-client
	# switch cannot be that way. Offered only while installed: X on a store
	# that is not here would be a second Install with a stranger name.
	if _selected_installed() and str(_selected.get("id", "")) == "store.steam":
		_hints.add_child(TvTheme.hint("X", "Desktop mode"))
	# Uninstall, advertised for the rail's reason turned around: a store's
	# application deliberately has no rail card (one thing, one home), which
	# without this line would make the ONE application everyone installs the
	# one application nobody can remove.
	if _selected_installed():
		_hints.add_child(TvTheme.hint("Y", "Options"))
	_hints.add_child(TvTheme.hint("B", "Back"))


## Is the selected store's application actually on the machine? Answered from
## the installed seam -- the same list the rail draws -- rather than from the
## install state file, which says what the FIRST-BOOT installer last did and
## goes on saying it after someone removes the application by hand.
func _selected_installed() -> bool:
	var app_id := str(_selected.get("app_id", ""))
	if app_id.is_empty():
		return false
	for app in Installed.apps:
		if str(app.get("id", "")) == app_id and str(app.get("state", "")) == "installed":
			return true
	return false


## The settings list's table, verbatim: one axis, hard stops, perpendicular
## pointed at self -- except the apps tab's right, which is the doorway into
## the grid and is owned by _wire_grid_focus so a rebuild re-points it at the
## new first card.
func _wire_focus_neighbours() -> void:
	var count := _tabs.size()
	for index in count:
		var tab: Control = _tabs[index]
		var up := index - 1 if index > 0 else index
		var down := index + 1 if index + 1 < count else index

		tab.focus_neighbor_top = tab.get_path_to(_tabs[up])
		tab.focus_neighbor_bottom = tab.get_path_to(_tabs[down])
		tab.focus_neighbor_left = tab.get_path_to(tab)
		if tab != _apps_tab:
			tab.focus_neighbor_right = tab.get_path_to(tab)


func _on_tab_focused(tab: Control) -> void:
	_render_page(tab.entry)


func _render_page(entry: Dictionary) -> void:
	_selected = entry

	# Which pane the tab owns. The grid never renders a store and the store
	# page never renders the shelf; visibility is the entire dispatch.
	var is_apps := str(entry.get("id", "")) == "store.apps"
	_page_pane.visible = not is_apps
	_grid_pane.visible = is_apps
	if is_apps:
		_render_grid_idle()
		_refresh_hints()
		return

	_page_hero.add_theme_stylebox_override(
		"panel", TvTheme.card_art_box(TvTheme.accent(str(entry.get("accent", "")))))
	_page_title.text = str(entry.get("title", ""))
	_page_tagline.text = str(entry.get("tagline", ""))
	_page_description.text = str(entry.get("description", ""))
	_refresh_status()
	# The A hint belongs to the SELECTED store, so it changes with the tab and
	# not only when an install state does.
	_refresh_hints()


## Only the Steam page has an install narration today, because Steam is the
## only store and the status seam's steam state is the only install state the
## system reports. A second store arrives with marwand, which will report per-
## app states; this function is where that plugs in.
func _refresh_status() -> void:
	if _page_status == null or _selected.is_empty():
		return
	# The shelf narrates per card, not per page -- see _on_grid_card_selected.
	if str(_selected.get("id", "")) == "store.apps":
		return

	# WHAT THE PERSON JUST ASKED FOR WINS. If appctl is working on -- or has
	# just failed on -- this very application, that is the most recent true
	# thing about it, and it outranks both the first-boot installer's narration
	# and the static "installed" line. Matched on the app id so a request about
	# one store never narrates another's page.
	var app_id := str(_selected.get("app_id", ""))
	if not app_id.is_empty() and Apps.app == app_id and APPCTL_LINES.has(Apps.state):
		var line := str(APPCTL_LINES[Apps.state])
		# appctl's own detail is preferred where it has one, for the installer's
		# reason: a specific sentence beats a general one.
		if Apps.state == "failed" and not Apps.detail.is_empty():
			line = "%s -- %s" % [Apps.detail, line]
		_page_status.text = line
		_page_status.add_theme_color_override(
			"font_color",
			TvTheme.TEXT_ALERT if APPCTL_ALERT_STATES.has(Apps.state) else TvTheme.TEXT_SECONDARY)
		return

	# Nothing in flight and the application is not here. This is what a store
	# page says after someone removes the application from the rail, and it is
	# the state that used to render as "Checking the install state" forever.
	if not _selected_installed() and SystemStatus.steam_detail.is_empty() \
			and SystemStatus.steam != "downloading" and SystemStatus.steam != "waiting-network":
		_page_status.text = "Not installed -- A downloads and installs it"
		_page_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
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


func _on_apps_state_changed(_state: String, _app: String, _detail: String) -> void:
	_refresh_status()
	_refresh_hints()


func _on_installed_changed(_apps: Array) -> void:
	_refresh_status()
	_refresh_hints()
	# The shelf redraws from the new list: a download that just landed turns
	# its card pressable, an uninstall turns it back into an offer.
	_rebuild_grid()


func _on_store_opened(entry: Dictionary) -> void:
	# A on the apps tab is a door, not a verb: it walks focus onto the shelf,
	# the same place right on the stick goes. The cards own every action after
	# that.
	if str(entry.get("id", "")) == "store.apps":
		if not _grid_cards.is_empty():
			var first: Control = _grid_cards[0]
			first.grab_focus()
		return

	# A MEANS TWO DIFFERENT THINGS, and which one is not a preference -- an
	# application that is not on the machine cannot be opened. Before this the
	# tab launched `flatpak run` regardless, which failed in milliseconds and
	# left the page exactly as it was, so the button read as broken.
	var app_id := str(entry.get("app_id", ""))
	if not _selected_installed():
		if app_id.is_empty():
			ShellLog.error("store %s carries no app_id; cannot install it"
				% str(entry.get("id", "")))
			return
		if Apps.is_busy():
			ShellLog.info("install requested while another request is in flight; ignoring")
			return
		Apps.request_install(app_id)
		# Said immediately rather than waiting for the seam's next poll: the
		# request file is consumed within half a second, but the person pressed
		# a button and a screen that does not change for two seconds is a screen
		# that did not hear them.
		if _page_status != null:
			_page_status.text = str(APPCTL_LINES["installing"])
			_page_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		return

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
	# the viewport with none, which is the rail's _ensure_focus lesson. The
	# SELECTED tab, not the first: a launch from the apps shelf landing back on
	# the Steam tab would be a focus teleport dressed up as a restore.
	if get_viewport().gui_get_focus_owner() != null:
		return
	for tab in _tabs:
		if str(tab.entry.get("id", "")) == str(_selected.get("id", "")):
			tab.grab_focus()
			return
	if not _tabs.is_empty():
		var first: Control = _tabs[0]
		first.grab_focus()


## Y on a store page: the same options menu a rail card gets, with the same
## one-extra-press shape standing between a bounced button and a removal. The
## menu writes the request through the apps seam and the page's own status
## line narrates the removal -- see _refresh_status.
func _open_card_menu() -> void:
	if _card_menu != null or Launcher.is_busy() or Apps.is_busy():
		return
	if not _selected_installed():
		ShellLog.info("Y on a store page whose application is not installed; nothing to offer")
		return

	_card_menu = CardMenu.new()
	# The menu acts on the APPLICATION, so the entry it gets carries the
	# desktop-entry id appctl matches -- not the tab's own name for itself.
	_card_menu.entry = {
		"id": str(_selected.get("app_id", "")),
		"title": str(_selected.get("title", "")),
		"state": "installed",
	}
	_card_menu.closed.connect(_on_card_menu_closed, CONNECT_ONE_SHOT)
	# Deaf while the menu is up, for the launch case's reason: the menu is a
	# later sibling and consumes what it handles, but this screen must not be
	# one reparent away from B doing two things at once.
	set_process_unhandled_input(false)
	get_tree().root.add_child(_card_menu)


func _on_card_menu_closed() -> void:
	_close_card_menu.call_deferred()


func _close_card_menu() -> void:
	if _card_menu == null:
		return
	var menu := _card_menu
	_card_menu = null
	menu.get_parent().remove_child(menu)
	menu.queue_free()
	set_process_unhandled_input(true)
	# The tab is where focus was when Y was pressed, and the menu's own row
	# took it; without this the screen comes back ringless and dead-looking.
	for tab in _tabs:
		if str(tab.entry.get("id", "")) == str(_selected.get("id", "")):
			tab.grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	# Y opens the store application's options -- checked before everything
	# else for the rail's reason: it is the only way to remove this
	# application on a machine with no terminal.
	if event.is_action_pressed("ui_shell_y"):
		if str(_selected.get("id", "")) == "store.apps":
			return
		get_viewport().set_input_as_handled()
		_open_card_menu()
		return

	# X on the Steam page: the desktop client, with the stick as a mouse. The
	# entry's icon prefers appscan's resolved path -- the same art the tab
	# draws -- so the launch splash shows the real logo, not the cache's
	# maybe-stale copy.
	if event.is_action_pressed("ui_shell_x"):
		if str(_selected.get("id", "")) != "store.steam" or not _selected_installed():
			return
		get_viewport().set_input_as_handled()
		if Launcher.is_busy():
			return
		var entry := Catalogue.steam_desktop_entry()
		var app_id := str(entry.get("app_id", ""))
		for app in Installed.apps:
			if str(app.get("id", "")) == app_id and not str(app.get("icon", "")).is_empty():
				entry["icon"] = str(app.get("icon", ""))
				break
		Launcher.launch(entry)
		return

	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath never sees the same press.
	get_viewport().set_input_as_handled()
	# From inside the grid, B is "back to the tab", not "leave the screen" --
	# the same one-level-at-a-time backing out every console shelf does. Asked
	# of the cards, not the focus owner's type, for _rebuild_grid's reason.
	for card in _grid_cards:
		if card.has_focus():
			if _apps_tab != null:
				_apps_tab.grab_focus()
			return
	closed.emit()
