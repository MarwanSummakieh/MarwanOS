extends Control

## The store screen: side tabs on the left, the selected page rendered on the
## right -- the PS Store shape, at the shell's fidelity. One kind of tab: a
## STORE (Steam), whose page describes it and whose A opens the client
## fullscreen.
##
## THERE WAS A SECOND KIND AND IT IS GONE. An "Apps" tab used to sit under the
## stores with a grid of every application the image ships, installed or not.
## The owner asked for it out, and the reason it was right to go is ADR 0006's
## own rule: the RAIL already draws exactly that set -- installed cards, and
## "press A to download it" cards for what the image ships and has not got --
## so the shelf was the machine's own library listed a second time, inside the
## screen that exists to reach somebody else's catalogue. Removing an
## application is still not a one-way door; the rail's available cards are what
## guarantee that, and they predate the shelf.
##
## WHAT "RENDERED" MEANS HERE, honestly -- and this paragraph has been rewritten
## because the answer changed. Embedding is still impossible: a foreign client's
## window inside a Godot control is compositor work (XEmbed/subsurface
## composition) that gamescope does not offer a shell running as one of its
## clients, and a webview would be the project's first native extension. What
## that paragraph used to conclude was that the page could therefore only
## DESCRIBE the store, which made this the one screen in the shell whose subject
## was absent from it.
##
## It does not follow. Valve publishes the same front page as public JSON, so
## the shell can draw the STOREFRONT without embedding the CLIENT: once Steam is
## installed, this panel is a browsable grid of Valve's featured games -- real
## capsule art, real names, real prices, fetched by marwanos-steamfront and read
## off disk like every other picture in this shell. See steamfront.gd. That is
## better than an embedded window would have been, not a consolation for it: a
## page drawn here is drawn at this shell's fidelity and read with this shell's
## pad, rather than being a smaller television inside the television.
##
## PURCHASING IS THE CLIENT'S, DELIBERATELY, and there is no Buy button anywhere
## on this screen by design: the panel is for browsing at shell fidelity, and
## money changes hands only inside Valve's own UI. A game's page offers exactly
## one action, which opens Big Picture on that game's store page and stops
## there. Nothing in this shell handles a card number, an account, or a
## purchase, and nothing should ever be added here that does.
##
## NAVIGATION. The tab column is the settings list's argument verbatim: one
## axis, hard stops, perpendicular pointed at self -- with one deliberate
## doorway, which is the shape the deleted apps shelf used too: RIGHT off a tab
## enters that store's grid, and LEFT off the grid's first column comes back.
## Inside the grid the argument holds again (rows and columns, hard stops at
## every edge). A on a tile opens the game's page in the same panel; B backs out
## one level each time -- page to grid, grid to tabs, tabs to closed. While a
## launch is up this screen goes deaf (see _on_launch_started) -- the shell
## still receives pad events when another client has the screen, because both
## read evdev, and a B press meant for Steam must not close the screen
## underneath it.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Catalogue = preload("res://src/catalogue.gd")
const StoreTab = preload("res://src/store_tab.gd")
const CardMenu = preload("res://src/card_menu.gd")
const StoreFrontTile = preload("res://src/store_front_tile.gd")
const ActionRow = preload("res://src/action_row.gd")

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

## WHAT THE PANEL IS SHOWING. Three renderings of one pane rather than three
## panes: with the content data-driven there is nothing for a second pane to
## hold, which was already this file's argument for one page pane per screen.
enum { MODE_PAGE, MODE_GRID, MODE_DETAIL }

## What the grid area says when there are no shelves to draw, by the seam's
## state word. EVERY ONE OF THESE IS A FIRST-CLASS RENDER -- the wifi screen's
## lesson, applied to a slower and more failure-prone thing than a radio: a
## storefront that is fetching, a machine with no network, and a Valve endpoint
## that did not answer are three different situations leading three different
## places, and a blank pane says none of them. "unknown" doubles as the fallback
## so a state word from a newer service renders as something.
const FRONT_STATE_LINES := {
	"unknown": "Fetching the storefront",
	"idle": "Fetching the storefront",
	"fetching": "Fetching the storefront",
	"done": "Steam's store had nothing to show",
	"offline": "No network -- the storefront needs one, and keeps the last one it fetched",
	"failed": "Steam's store did not answer",
}

## The grid states that name a problem rather than progress.
const FRONT_ALERT_STATES := ["offline", "failed"]

## What the ONE action on a game's page says. Named for what it does rather than
## for what somebody might want it to do: it opens Steam, on that game's page,
## and everything after that -- including every step of a purchase -- happens
## inside Valve's client where it belongs.
const HINT_OPEN_IN_STEAM := "Open in Steam"

var _tabs: Array = []
var _selected: Dictionary = {}
var _hints: HBoxContainer = null

var _page_pane: Control = null
var _page_hero: Panel = null
var _page_title: Label = null
var _page_tagline: Label = null
var _page_description: Label = null
var _page_status: Label = null

## The storefront half of the pane: a scrolling column of shelves, or one line
## explaining why there are none.
var _front: Control = null
var _front_scroll: ScrollContainer = null
var _front_column: VBoxContainer = null
var _front_status: Label = null

## Every tile in reading order, and the same tiles arranged as rows (which is
## NOT one row per shelf -- a shelf of eight at four columns is two rows). The
## row structure is what the focus wiring walks; see _wire_grid_neighbours for
## why an index-arithmetic version would break on a short shelf.
var _tiles: Array = []
var _tile_rows: Array = []

## The signature of what is currently drawn, against what the seam now holds. A
## rebuild drops focus, and this screen is fed by a two-second poll, so a
## rebuild on every poll would pull the selection out from under a thumb
## continuously -- the wifi screen's lesson, and its solution.
var _shelf_signature := ""

## The game page inside the panel, and the tile it was opened from -- kept so B
## puts focus back where the thumb left it rather than at the top of the grid.
var _detail: Control = null
var _detail_art: TextureRect = null
var _detail_wash: Panel = null
var _detail_title: Label = null
var _detail_price: Label = null
var _detail_was: Label = null
var _detail_summary: Label = null
var _detail_action: ActionRow = null
var _detail_item: Dictionary = {}
var _detail_tile: Control = null

var _mode := MODE_PAGE

var _page_spacer: Control = null

var _card_menu: CardMenu = null


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

	for entry in Catalogue.stores():
		var tab := StoreTab.new()
		tab.setup_store(entry)
		tab.opened.connect(_on_store_opened)
		tab.focus_entered.connect(_on_tab_focused.bind(tab))
		tab_column.add_child(tab)
		_tabs.append(tab)

	_page_pane = _build_page()
	content.add_child(_page_pane)

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
	# The storefront: its shelves, and what the fetcher has to say about them.
	# Both are watched because a grid with nothing in it is a rendering
	# question, not an absence -- see FRONT_STATE_LINES.
	Steamfront.featured_changed.connect(_on_featured_changed)
	Steamfront.state_changed.connect(_on_front_state_changed)
	Steamfront.app_changed.connect(_on_app_changed)

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

	_front = _build_front()
	page.add_child(_front)

	_page_spacer = Control.new()
	_page_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_page_spacer)

	# The live line: what the machine is doing about this store right now,
	# from the status seam. The one line on the page that changes on its own.
	_page_status = Label.new()
	_page_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_page_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_page_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_page_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_page_status)

	return pane


## The storefront half of the pane. A scrolling column of shelves plus one
## status line, both children of the same container so exactly one of them is
## ever showing and the pane can never be blank.
##
## THE SCROLL CONTAINER FOLLOWS FOCUS, which is the whole of the scrolling
## design: there is no scrollbar to grab on a machine with no pointer, so the
## only thing that may move the view is the selection moving, and Godot does
## that for free. Three shelves of eight tiles is six rows against a pane that
## shows two, so without this the fourth row would be reachable and invisible.
func _build_front() -> Control:
	var front := VBoxContainer.new()
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.size_flags_vertical = Control.SIZE_EXPAND_FILL
	front.add_theme_constant_override("separation", TvTheme.STORE_SHELF_GAP)

	_front_status = Label.new()
	_front_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_front_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_front_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_front_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(_front_status)

	_front_scroll = ScrollContainer.new()
	_front_scroll.follow_focus = true
	_front_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_front_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The bar is hidden rather than merely unused: nothing can grab it, and a
	# grey stripe down the edge of a storefront is decoration that says "there
	# is a mouse here" on a machine that has none.
	_front_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_front_scroll.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	front.add_child(_front_scroll)

	_front_column = VBoxContainer.new()
	_front_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_front_column.add_theme_constant_override("separation", TvTheme.STORE_SHELF_GAP)
	_front_scroll.add_child(_front_column)

	_detail = _build_detail()
	front.add_child(_detail)

	return front


## A game's page, inside the same pane. Built once and repopulated, for the
## page's own reason: the content is data and there is nothing for a second one
## to hold.
func _build_detail() -> Control:
	var detail := VBoxContainer.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", TvTheme.STORE_ITEM_PAD)
	detail.visible = false

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0, TvTheme.STORE_DETAIL_ART_HEIGHT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	detail.add_child(frame)

	# The wash under the picture, for the tile's reason: a page opened before
	# its screenshot has landed is a coloured rectangle of the right size rather
	# than a collapsed layout that jumps when the art arrives.
	_detail_wash = Panel.new()
	_detail_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_detail_wash)

	_detail_art = TextureRect.new()
	_detail_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_detail_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_art.visible = false
	frame.add_child(_detail_art)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	_detail_title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(_detail_title)

	var prices := HBoxContainer.new()
	prices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prices.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	detail.add_child(prices)

	_detail_price = Label.new()
	_detail_price.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_detail_price.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_detail_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prices.add_child(_detail_price)

	_detail_was = Label.new()
	_detail_was.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_detail_was.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_detail_was.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prices.add_child(_detail_was)

	_detail_summary = Label.new()
	_detail_summary.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_detail_summary.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_detail_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(_detail_summary)

	# ONE ACTION, AND IT IS NOT A PURCHASE. See the header: the panel browses,
	# Valve's client transacts. A row rather than a bare hint because it has to
	# be focusable -- it is the only thing on this view a pad can land on, and a
	# view with nothing focusable is a view B is the only escape from.
	_detail_action = ActionRow.new()
	_detail_action.setup(HINT_OPEN_IN_STEAM, "")
	_detail_action.activated.connect(_on_detail_action)
	detail.add_child(_detail_action)

	return detail


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

	# THE HINT ROW IS THE ONLY THING THAT DIFFERS between standing on a tab and
	# standing in the grid, so it carries the whole of that difference: what A
	# does here, and where B goes. Both branches return early -- a store's
	# Options and Desktop-mode hints belong to the STORE, and offering them
	# while the selection is on a game would be advertising a button that acts
	# on something else.
	if _mode == MODE_DETAIL:
		_hints.add_child(TvTheme.hint("A", HINT_OPEN_IN_STEAM))
		_hints.add_child(TvTheme.hint("B", "Back to the store"))
		return
	if _mode == MODE_GRID:
		_hints.add_child(TvTheme.hint("A", "Open"))
		_hints.add_child(TvTheme.hint("B", "Back to stores"))
		return

	_hints.add_child(TvTheme.hint("A", HINT_OPEN if _selected_installed() else HINT_INSTALL))
	# The doorway, advertised: the grid is the pane's biggest feature and
	# nothing else on this screen has ever answered Right, so a person has no
	# reason to try it unless told.
	# Spelled as a WORD rather than as an arrow mark: TvTheme.hint draws
	# anything that is not a face button as text in the shipped UI font, and a
	# glyph that font turns out not to carry would render as a box.
	if _front_available() and not _tiles.is_empty():
		_hints.add_child(TvTheme.hint("Right", "Browse the store"))
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
		_hints.add_child(TvTheme.hint("OPTIONS", "Options"))
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
## pointed at self. The apps tab's right used to be the exception -- the
## doorway into the shelf's grid -- and with the shelf gone there is nothing
## left to except.
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
	# Focus landing back on a tab IS leaving the grid -- through the doorway off
	# the first column, or through B. Same argument as _on_tile_focused: the
	# neighbour table moves focus and this notices, rather than two things
	# both deciding.
	if _mode != MODE_PAGE:
		_set_mode(MODE_PAGE)
		ShellLog.info("storefront grid left")
	_render_page(tab.entry)


func _render_page(entry: Dictionary) -> void:
	_selected = entry

	_page_hero.add_theme_stylebox_override(
		"panel", TvTheme.card_art_box(TvTheme.accent(str(entry.get("accent", "")))))
	_page_title.text = str(entry.get("title", ""))
	_page_tagline.text = str(entry.get("tagline", ""))
	_page_description.text = str(entry.get("description", ""))
	_refresh_status()
	_refresh_front()
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


# ---------------------------------------------------------------------------
# The storefront
# ---------------------------------------------------------------------------

## Does the selected tab get a storefront at all? Only Steam does, and only once
## Steam is actually on the machine.
##
## THE INSTALL GATE IS DELIBERATE AND IT IS NOT ABOUT DATA. The fetcher would
## happily serve a storefront to a machine with no Steam on it, and the shell
## could draw it -- and every tile would open a page whose one button launches
## an application that is not there. A shop you cannot walk out of is worse than
## a shop that is closed, so before Steam arrives this panel stays exactly the
## page it always was: the install narration, unchanged, which is the only thing
## a person can act on at that point.
func _front_available() -> bool:
	return str(_selected.get("id", "")) == "store.steam" and _selected_installed()


## Put the pane in the right one of its three renderings, and keep the grid's
## contents current. Called on every tab focus, every install-state change and
## every arrival from the seam, because all three can change the answer.
func _refresh_front() -> void:
	if _front == null:
		return

	var available := _front_available()
	if not available and _mode != MODE_PAGE:
		# The application went away under an open grid -- somebody removed it
		# from the options menu while the storefront was up. Falling back to the
		# page rather than leaving a grid of tiles that can no longer open
		# anything.
		_set_mode(MODE_PAGE)

	_front.visible = available
	# The long description and the storefront are alternatives, not neighbours:
	# the description explains what pressing A does, which is the hint row's job
	# once there is a shelf of games competing for the same pixels.
	_page_description.visible = not available
	_page_hero.visible = not available
	_page_spacer.visible = not available

	if not available:
		return

	if _tiles.is_empty() or _shelves_changed():
		_rebuild_grid()
	_refresh_front_status()

	# Asked for on every visit rather than once: the request is cheap by
	# construction (the service answers from disk without touching the network
	# while its copy is under an hour old), and the alternative is a storefront
	# that never refreshes on a machine nobody reboots.
	Steamfront.request_featured()


func _shelves_changed() -> bool:
	return _shelf_signature != _current_signature()


func _current_signature() -> String:
	var signature := ""
	for category in Steamfront.categories:
		signature += "%s:" % str(category.get("id", ""))
		for item in category.get("items", []):
			signature += "%d," % int(item.get("appid", 0))
		signature += ";"
	return signature


func _rebuild_grid() -> void:
	_shelf_signature = _current_signature()

	for child in _front_column.get_children():
		_front_column.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_tile_rows.clear()

	for category in Steamfront.categories:
		var items: Array = category.get("items", [])
		if items.is_empty():
			continue

		var heading := Label.new()
		heading.text = str(category.get("name", ""))
		heading.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
		heading.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_front_column.add_child(heading)

		var grid := GridContainer.new()
		grid.columns = TvTheme.STORE_GRID_COLUMNS
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", TvTheme.STORE_GRID_GAP)
		grid.add_theme_constant_override("v_separation", TvTheme.STORE_GRID_GAP)
		_front_column.add_child(grid)

		var row: Array = []
		for item in items:
			var tile := StoreFrontTile.new()
			tile.setup_item(item)
			tile.opened.connect(_on_tile_opened)
			tile.focus_entered.connect(_on_tile_focused)
			grid.add_child(tile)
			_tiles.append(tile)
			row.append(tile)
			# ROWS ARE ACCUMULATED PER SHELF, not derived from a global index.
			# A shelf is capped at eight but nothing guarantees it arrives full
			# -- Valve returns what it returns -- and index arithmetic across a
			# short shelf would wire "down" to a tile in the wrong column.
			if row.size() == TvTheme.STORE_GRID_COLUMNS:
				_tile_rows.append(row)
				row = []
		if not row.is_empty():
			_tile_rows.append(row)

	_wire_grid_neighbours()
	ShellLog.info("storefront grid: %d tile(s) in %d row(s)" % [_tiles.size(), _tile_rows.size()])


## Rows and columns, hard stops at every edge -- with the one doorway back to
## the tab column off the first column, which is the same doorway RIGHT came
## through.
func _wire_grid_neighbours() -> void:
	var count := _tile_rows.size()
	for index in count:
		var row: Array = _tile_rows[index]
		var above: Array = _tile_rows[index - 1] if index > 0 else row
		var below: Array = _tile_rows[index + 1] if index + 1 < count else row

		for column in row.size():
			var tile: Control = row[column]
			# Clamped rather than wrapped: a short last row must not send the
			# selection to a column that does not exist there, and landing on
			# the nearest tile is what a person expects from pressing down.
			var up: Control = above[mini(column, above.size() - 1)]
			var down: Control = below[mini(column, below.size() - 1)]
			tile.focus_neighbor_top = tile.get_path_to(up)
			tile.focus_neighbor_bottom = tile.get_path_to(down)
			tile.focus_neighbor_right = tile.get_path_to(
				row[column + 1] if column + 1 < row.size() else tile)
			if column > 0:
				tile.focus_neighbor_left = tile.get_path_to(row[column - 1])
			else:
				tile.focus_neighbor_left = tile.get_path_to(_selected_tab())

	# The doorway, from the other side. Re-wired on every rebuild because the
	# first tile is a different node each time.
	var tab := _selected_tab()
	if tab != null:
		tab.focus_neighbor_right = tab.get_path_to(
			_tiles[0] if not _tiles.is_empty() else tab)


func _selected_tab() -> Control:
	for tab in _tabs:
		if str(tab.entry.get("id", "")) == str(_selected.get("id", "")):
			return tab
	return _tabs[0] if not _tabs.is_empty() else null


## The line that stands in for shelves that are not there. Never blank -- see
## FRONT_STATE_LINES.
##
## Shelves and this line are alternatives and exactly one of them shows, which
## is the whole of "a cold storefront is a first-class render": there is no
## arrangement of states that leaves the pane empty.
func _refresh_front_status() -> void:
	if _front_status == null or _front_scroll == null:
		return
	var have := not _tiles.is_empty()
	_front_scroll.visible = have and _mode != MODE_DETAIL
	_front_status.visible = not have and _mode != MODE_DETAIL
	if have:
		return
	var state := Steamfront.state
	_front_status.text = str(FRONT_STATE_LINES.get(state, FRONT_STATE_LINES["unknown"]))
	_front_status.add_theme_color_override("font_color",
		TvTheme.TEXT_ALERT if FRONT_ALERT_STATES.has(state) else TvTheme.TEXT_SECONDARY)


func _on_featured_changed(_categories: Array) -> void:
	if not _front_available():
		return
	if _shelves_changed():
		var focused := get_viewport().gui_get_focus_owner()
		var was_in_grid := _tiles.has(focused)
		_rebuild_grid()
		# A rebuild frees the node focus was on. Landing on the first tile is
		# the only honest restore: the shelves are somebody else's ordering and
		# the game that was selected may not be on them any more.
		if was_in_grid and not _tiles.is_empty():
			var first: Control = _tiles[0]
			first.grab_focus()
	else:
		# Same games, and the pictures may have arrived since. This is the cold
		# machine's second or two between the JSON landing and the capsules
		# following it.
		for tile in _tiles:
			tile.refresh_art()
	_refresh_front_status()


func _on_front_state_changed(_state: String, _detail: String) -> void:
	_refresh_front_status()
	if _mode == MODE_DETAIL:
		_render_detail()


func _on_app_changed(appid: int, _details: Dictionary) -> void:
	if _mode == MODE_DETAIL and int(_detail_item.get("appid", 0)) == appid:
		_render_detail()


# ---------------------------------------------------------------------------
# The three renderings
# ---------------------------------------------------------------------------

## MODE_PAGE AND MODE_GRID LOOK IDENTICAL, and that is not an oversight. The
## shelves are the pane's content whether or not the selection is standing in
## them -- a storefront that appeared only once you had pressed Right would be a
## screen keeping its own contents secret. The two modes differ in exactly one
## visible thing, the hint row, because that is the only thing that actually
## differs: where B goes and what A does. MODE_DETAIL is the real swap.
func _set_mode(mode: int) -> void:
	_mode = mode
	if _detail != null:
		_detail.visible = mode == MODE_DETAIL
	# The title and the tagline belong to the STORE and the detail belongs to a
	# game, so the game's page gets the pane to itself.
	if _page_title != null:
		_page_title.visible = mode != MODE_DETAIL
	if _page_tagline != null:
		_page_tagline.visible = mode != MODE_DETAIL
	if _page_status != null:
		_page_status.visible = mode != MODE_DETAIL
	_refresh_front_status()
	_refresh_hints()


## Focus arriving on a tile IS entering the grid, and there is no key handler
## for it: the tab's focus_neighbor_right already points at the first tile, so
## Godot's own navigation does the move and this only notices. Doing it the
## other way -- intercepting Right in _unhandled_input -- would mean two things
## deciding where focus goes, which is the bug class the settings list's
## neighbour table exists to avoid.
func _on_tile_focused() -> void:
	if _mode == MODE_PAGE:
		_set_mode(MODE_GRID)
		ShellLog.info("storefront grid entered")


func _on_tile_opened(item: Dictionary) -> void:
	_detail_item = item
	_detail_tile = get_viewport().gui_get_focus_owner()
	_set_mode(MODE_DETAIL)
	# Asked for BEFORE the first render, so the render draws whatever is
	# already cached and the arrival redraws it. The seam answers from disk
	# immediately when it has something, which is what makes a page opened
	# twice appear at once.
	Steamfront.request_app(int(item.get("appid", 0)))
	_render_detail()
	_detail_action.grab_focus()
	ShellLog.info("storefront page opened for appid %d" % int(item.get("appid", 0)))


func _close_detail() -> void:
	_set_mode(MODE_GRID)
	_refresh_front_status()
	if is_instance_valid(_detail_tile) and _tiles.has(_detail_tile):
		_detail_tile.grab_focus()
	elif not _tiles.is_empty():
		var first: Control = _tiles[0]
		first.grab_focus()
	_detail_item = {}
	_detail_tile = null
	ShellLog.info("storefront page closed")


## The game's page. THE PRICE COMES FROM THE TILE, not from the fetched page,
## and that is a correctness fix rather than a shortcut: Valve's two endpoints
## geolocate differently -- measured 2026-08-10, the featured list answered in
## USD and the per-app endpoint in EUR from the same machine, seconds apart --
## so taking the price from the page would show a different number here than
## the tile the person just pressed. One number, from one endpoint, for the
## whole journey. What the fetched page adds is the words and the picture.
##
## Neither of which may be there yet, and both states are drawn rather than left
## blank: a summary that is still coming says so.
func _render_detail() -> void:
	if _detail_item.is_empty():
		return
	var appid := int(_detail_item.get("appid", 0))
	var details := Steamfront.app_details(appid)

	_detail_title.text = str(_detail_item.get("name", ""))

	var prices: Array = Steamfront.price_lines(_detail_item)
	_detail_price.text = str(prices[0])
	_detail_price.add_theme_color_override("font_color",
		TvTheme.TEXT_DISCOUNT if not str(prices[1]).is_empty() else TvTheme.TEXT_PRIMARY)
	_detail_was.text = str(prices[1])

	if not details.is_empty():
		_detail_summary.text = str(details.get("short_description", ""))
		_detail_summary.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	else:
		# The three reasons there is no text yet, told apart: still coming, no
		# network, or Steam declined to answer for this one. Same table the grid
		# uses, because they are the same three situations.
		var state := Steamfront.state
		_detail_summary.text = str(FRONT_STATE_LINES.get(state, FRONT_STATE_LINES["unknown"]))
		_detail_summary.add_theme_color_override("font_color",
			TvTheme.TEXT_ALERT if FRONT_ALERT_STATES.has(state) else TvTheme.TEXT_SECONDARY)

	# WHAT THE PANE ACTUALLY DREW, in one line. This is the only surface the
	# invisible harness has -- there is no way to assert on a pixel from a
	# script -- and it is the same reason every other screen here logs what it
	# put up. The summary is counted rather than quoted: it is text from
	# somebody else's server, and the journal is not the place to copy it into.
	ShellLog.info("storefront page appid %d: price \"%s\" %s, summary %d character(s)"
		% [appid, _detail_price.text,
			str(prices[1]) if not str(prices[1]).is_empty() else "at full price",
			str(details.get("short_description", "")).length()])

	_detail_wash.add_theme_stylebox_override("panel",
		TvTheme.card_art_box(TvTheme.accent_for_id(str(appid))))
	var art := Steamfront.art_path(appid, true)
	_detail_art.visible = false
	if not art.is_empty():
		var image := Image.new()
		if image.load(art) == OK:
			_detail_art.texture = ImageTexture.create_from_image(image)
			_detail_art.visible = true
		else:
			ShellLog.warn("steamfront: could not load %s" % art)


## The one action, and the whole boundary this screen draws. `steam://store/<id>`
## is Big Picture's own URL for a game's store page, handed over exactly the way
## catalogue.gd's STEAM_STORE hands over `steam://store` -- same client, same
## -gamepadui flag, same launch seam. What happens after that is Valve's: the
## page, the cart, the card details and the receipt all live inside their client,
## and this shell never sees any of it.
func _on_detail_action() -> void:
	if Launcher.is_busy() or _detail_item.is_empty():
		return
	var appid := int(_detail_item.get("appid", 0))
	if appid <= 0:
		return
	var entry := {
		# A distinct id from the store tab's, for steam_desktop_entry's reason:
		# the launch seam, the splash and the pad bridge all key on this, and
		# "Steam showing one game's page" wants the splash to say the game's
		# name. It is deliberately NOT in Catalogue.PAD_KEY_APPS -- Big Picture
		# reads the pad itself, and double-delivered input is worse than none.
		"id": "store.steam.page",
		"title": str(_detail_item.get("name", "")),
		"accent": str(_selected.get("accent", "")),
		"exec": ["flatpak", "run", "com.valvesoftware.Steam", "-gamepadui",
			"steam://store/%d" % appid],
		"app_id": str(_selected.get("app_id", "")),
		"icon": Steamfront.art_path(appid),
	}
	ShellLog.info("storefront handing appid %d to Steam" % appid)
	Launcher.launch(entry)


func _on_steam_changed(_state: String) -> void:
	_refresh_status()


func _on_apps_state_changed(_state: String, _app: String, _detail: String) -> void:
	_refresh_status()
	_refresh_front()
	_refresh_hints()


## The install landing is what turns this panel from a description into a
## storefront, so it is the moment the grid appears -- and a removal is the
## moment it has to go again. Both arrive here.
func _on_installed_changed(_apps: Array) -> void:
	_refresh_status()
	_refresh_front()
	_refresh_hints()


func _on_store_opened(entry: Dictionary) -> void:
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
	# SELECTED tab, not the first: with a second store added, a launch from its
	# page landing back on the Steam tab would be a focus teleport dressed up
	# as a restore.
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
	# OPTIONS opens the store application's options -- checked before everything
	# else for the rail's reason: it is the only way to remove this
	# application on a machine with no terminal.
	#
	# Only while the selection is on the STORE, though. Options and Desktop mode
	# both act on the Steam application, and pressing either while standing on a
	# game would be a button doing something to a different thing than the one
	# with the ring around it.
	if event.is_action_pressed("ui_shell_options"):
		if _mode != MODE_PAGE:
			return
		get_viewport().set_input_as_handled()
		_open_card_menu()
		return

	# X on the Steam page: the desktop client, with the stick as a mouse. The
	# entry's icon prefers appscan's resolved path -- the same art the tab
	# draws -- so the launch splash shows the real logo, not the cache's
	# maybe-stale copy.
	if event.is_action_pressed("ui_shell_x"):
		if _mode != MODE_PAGE:
			return
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

	# THREE LEVELS NOW, and B unwinds them one at a time. The deleted apps shelf
	# had exactly this shape and its removal is what left the comment here
	# saying "B always leaves the screen"; the storefront puts the depth back,
	# for a better reason -- a game's page and the shelf it came from are two
	# places, not one screen with a mode.
	if _mode == MODE_DETAIL:
		_close_detail()
		return
	if _mode == MODE_GRID:
		_set_mode(MODE_PAGE)
		var tab := _selected_tab()
		if tab != null:
			tab.grab_focus()
		ShellLog.info("storefront grid left")
		return
	closed.emit()
