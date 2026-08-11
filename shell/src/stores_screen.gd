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
const Keyboard = preload("res://src/keyboard.gd")

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
## What A does on a store tab, and there are now three answers because there are
## three situations. "Open store" is gone: it opened Big Picture on Valve's
## storefront, and this panel IS a storefront -- so the button spent its press
## replacing a page the shell had already drawn with somebody else's copy of it,
## on the one UI the owner cannot navigate without a flicker.
const HINT_BROWSE := "Browse"
const HINT_SIGN_IN := "Sign in to Steam"
const HINT_INSTALL := "Install"
## There is DELIBERATELY no fallback verb for "signed in, installed, nothing to
## browse". The first draft had one -- "Open store", which opened Big Picture on
## the theory that the client might have something to show when the shell did
## not. It would not have: the empty-storefront state is almost always a machine
## with no network, where the client's store page is exactly as dead, drawn by
## the one UI this screen exists to keep off the television. The status line
## already names the real cause (offline, fetching, Valve down); A advertising a
## door to a broken page on top of that explanation was the relapse, not the
## honesty. See _page_action_hint and _on_store_opened, which both go quiet in
## that state instead.

## WHAT THE PANEL IS SHOWING. Four renderings of one pane rather than four
## panes: with the content data-driven there is nothing for a second pane to
## hold, which was already this file's argument for one page pane per screen.
##
## MODE_SEARCH REUSES THE SHELF GRID rather than owning a second one, and that is
## a deliberate reuse rather than a saving. A search result and a shelf item are
## the same kind of thing -- the seam publishes them in the same shape for that
## reason -- so they get the same tile, the same focus wiring, the same left-edge
## doorway back to the tabs and the same detail page. What differs is the heading
## above them and where B goes, which is what _search_active tracks.
enum { MODE_PAGE, MODE_GRID, MODE_DETAIL, MODE_SEARCH }

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
## The purchase action, and it no longer names Steam because it no longer opens
## Steam. See _on_detail_store_action: buying happens on Valve's own store page
## in the browser, which is the last Steam-client door on this screen being shut.
const HINT_BUY := "Buy in browser"

## The primary action on a game's page, by what this machine already has. All
## three go through steam:// URLs against a client started `-silent`, so none of
## them puts Valve's UI on the television -- which is the whole reason they
## exist. See _refresh_detail_actions.
const HINT_PLAY := "Play"
const HINT_INSTALL_GAME := "Install"
## Not a verb, because there is nothing to press: a download is already
## happening and the row exists to say how far along it is.
const HINT_DOWNLOADING := "Downloading"

## What the search half says when there is nothing to draw, by the seam's state
## word. Same first-class-render argument as FRONT_STATE_LINES, and the same
## table shape -- but the sentences differ because the situations do: a person
## who has just typed a word is asking a question, and "Steam's store had nothing
## to show" is not an answer to it.
const SEARCH_STATE_LINES := {
	"unknown": "Searching",
	"idle": "Searching",
	"fetching": "Searching",
	"done": "Nothing on Steam matches that",
	"offline": "No network -- searching the store needs one",
	"failed": "Steam's store did not answer",
}

## What Y does, and it is the only button on this screen that opens a keyboard.
const HINT_SEARCH := "Search"

var _tabs: Array = []
var _selected: Dictionary = {}
var _hints: HBoxContainer = null

var _page_pane: Control = null
var _page_hero: Panel = null
var _page_title: Label = null
var _page_tagline: Label = null
var _page_description: Label = null
var _page_status: Label = null
var _account_line: Label = null

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
var _detail_store_action: ActionRow = null
var _detail_item: Dictionary = {}
var _detail_tile: Control = null

var _mode := MODE_PAGE

## Whether the status line is currently saying something a person could act on,
## as opposed to confirming a state they can already see. Set by _refresh_status,
## which is the only thing that knows which sentence it just wrote, and read by
## _refresh_page_chrome to decide whether the line survives a live storefront.
var _status_is_news := false

## Whether the grid currently holds SEARCH RESULTS rather than the shelves. Kept
## separately from _mode because the two answer different questions and both are
## needed at once: _mode says where the selection is standing (a game's page
## opened from a result is MODE_DETAIL, but the grid behind it is still a search),
## and this says what is in the grid underneath.
var _search_active := false

## The term the grid is currently showing results for, for the heading.
var _search_shown := ""

## Where B goes from a game's page -- the grid it was opened from, which is not
## always the shelves. Without this, backing out of a result landed on the
## storefront's front page and the search a person was halfway through reading
## was simply gone.
var _detail_from := MODE_GRID

var _keyboard: Keyboard = null

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
	Steamfront.search_changed.connect(_on_search_changed)
	# The account line and the wishlist shelf both react to their own arrivals:
	# signing into Steam from Big Picture and coming back here is the case, and
	# neither of them rides on the featured list's signal.
	Steamfront.account_changed.connect(_on_account_changed)
	Steamfront.wishlist_changed.connect(_on_wishlist_changed)

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

	# THE ACCOUNT LINE, and it is what the trimmed prose left room for. Above the
	# shelves rather than below them because it is the answer to "whose store is
	# this" -- a question a person asks before they look at what is on it, and
	# the one thing the old title and tagline never said. Hidden entirely until
	# there is a storefront: on a machine with no Steam it would be a fact about
	# nothing.
	_account_line = Label.new()
	_account_line.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_account_line.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_account_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_account_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_account_line.visible = false
	page.add_child(_account_line)

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

	# TWO ACTIONS NOW, AND THE FIRST ONE IS THE POINT OF THIS WHOLE SCREEN.
	#
	# It used to be one: "Open in Steam", which handed the game to Big Picture
	# and stopped. That was the honest limit while the shell could only describe
	# a store -- but the two things a person actually wants from a game's page,
	# playing it and getting it, are both reachable through steam:// URLs that
	# need no UI from Valve at all. So the primary row says Play, or Install, or
	# how far a download has got, depending on what this machine already has.
	#
	# THE SECOND ROW IS THE PURCHASE DOOR, and it goes to the BROWSER now. Money
	# still never changes hands in this shell -- see the header -- but it no
	# longer changes hands in Valve's client on this television either: the store
	# page opens in Zen, which is a pointer-driven UI this machine already ships
	# and already knows how to drive with the right stick. That is the last
	# Steam-client door on this screen, and closing it is the whole point of the
	# panel existing.
	#
	# The first row's text here is a placeholder: _refresh_detail_actions sets
	# the real verb from what the machine has, before this view is ever shown.
	_detail_action = ActionRow.new()
	_detail_action.setup(HINT_INSTALL_GAME, "")
	_detail_action.activated.connect(_on_detail_action)
	detail.add_child(_detail_action)

	_detail_store_action = ActionRow.new()
	_detail_store_action.setup(HINT_BUY, "")
	_detail_store_action.activated.connect(_on_detail_store_action)
	detail.add_child(_detail_store_action)

	# One axis, hard stops -- the settings list's table, for the third time on
	# this screen. Left and right point at self so Control's geometric search
	# cannot wander out of the pane and into a shelf tile behind it.
	_detail_action.focus_neighbor_top = _detail_action.get_path_to(_detail_action)
	_detail_action.focus_neighbor_bottom = _detail_action.get_path_to(_detail_store_action)
	_detail_action.focus_neighbor_left = _detail_action.get_path_to(_detail_action)
	_detail_action.focus_neighbor_right = _detail_action.get_path_to(_detail_action)
	_detail_store_action.focus_neighbor_top = _detail_store_action.get_path_to(_detail_action)
	_detail_store_action.focus_neighbor_bottom = _detail_store_action.get_path_to(_detail_store_action)
	_detail_store_action.focus_neighbor_left = _detail_store_action.get_path_to(_detail_store_action)
	_detail_store_action.focus_neighbor_right = _detail_store_action.get_path_to(_detail_store_action)

	return detail


## What this machine already has to say about one Steam appid, from the same
## installed seam the rail draws: "installed", "downloading", or "" for a game
## that is not on the disk at all.
##
## ASKED OF THE SEAM AND NOT OF STEAM. appscan reads the appmanifests and
## publishes them; this is a lookup in a list the shell already polls, so a
## detail page costs no process and no file read to know whether its game is
## here.
func _local_state(appid: int) -> String:
	var id := "steam.%d" % appid
	for app in Installed.apps:
		if str(app.get("id", "")) == id:
			return str(app.get("state", ""))
	return ""


## The live progress line for a downloading game, or empty. appscan puts it in
## the comment column and installed.gd surfaces it as the subtitle.
func _local_detail(appid: int) -> String:
	var id := "steam.%d" % appid
	for app in Installed.apps:
		if str(app.get("id", "")) == id:
			return str(app.get("subtitle", ""))
	return ""


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
		# "Select" rather than a verb, because there are two rows now and A does
		# whatever the lit one says. Naming one of them here would be advertising
		# the wrong action half the time -- the settings screen's own reasoning
		# for the same word.
		_hints.add_child(TvTheme.hint("A", "Select"))
		# Named for where it actually goes, which is not always the same place.
		# "Back to the store" under a result would point at the shelves the
		# person never opened.
		_hints.add_child(TvTheme.hint("B",
			"Back to results" if _detail_from == MODE_SEARCH else "Back to the store"))
		return
	if _mode == MODE_SEARCH:
		_hints.add_child(TvTheme.hint("A", "Open"))
		_hints.add_child(TvTheme.hint("Y", "Search again"))
		_hints.add_child(TvTheme.hint("B", "Back to the store"))
		return
	if _mode == MODE_GRID:
		_hints.add_child(TvTheme.hint("A", "Open"))
		_hints.add_child(TvTheme.hint("Y", HINT_SEARCH))
		_hints.add_child(TvTheme.hint("B", "Back to stores"))
		return

	# Skipped entirely when the hint is empty -- see _page_action_hint: an A
	# badge with no caption is a button advertised as doing something unnamed,
	# which is worse than no badge.
	var page_hint := _page_action_hint()
	if not page_hint.is_empty():
		_hints.add_child(TvTheme.hint("A", page_hint))
	# The doorway, advertised: the grid is the pane's biggest feature and
	# nothing else on this screen has ever answered Right, so a person has no
	# reason to try it unless told.
	# Spelled as a WORD rather than as an arrow mark: TvTheme.hint draws
	# anything that is not a face button as text in the shipped UI font, and a
	# glyph that font turns out not to carry would render as a box.
	if _front_available() and not _tiles.is_empty():
		_hints.add_child(TvTheme.hint("Right", "Browse the store"))
	# Advertised wherever it works, for the doorway's reason: a keyboard behind a
	# face button is not something anybody guesses at on a television.
	if _front_available():
		_hints.add_child(TvTheme.hint("Y", HINT_SEARCH))
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
		# A request the person made moments ago is always news, including the
		# ones that worked: "Removing" is the only feedback that button has.
		_status_is_news = true
		_refresh_page_chrome()
		return

	# Nothing in flight and the application is not here. This is what a store
	# page says after someone removes the application from the rail, and it is
	# the state that used to render as "Checking the install state" forever.
	if not _selected_installed() and SystemStatus.steam_detail.is_empty() \
			and SystemStatus.steam != "downloading" and SystemStatus.steam != "waiting-network":
		_page_status.text = "Not installed -- A downloads and installs it"
		_page_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		_status_is_news = true
		_refresh_page_chrome()
		return

	var state := SystemStatus.steam
	# The installer's live progress line wins over the fixed wording, for the
	# rail's reason: a number that moves is the difference between "working"
	# and "hung" to the person watching.
	if not SystemStatus.steam_detail.is_empty():
		_page_status.text = "Installing -- %s" % SystemStatus.steam_detail
		_status_is_news = true
	else:
		_page_status.text = str(STEAM_INSTALL_LINES.get(state, STEAM_INSTALL_LINES["unknown"]))
		# TWO SENTENCES THAT ARE NOT NEWS, and the second was found by looking at
		# the card rather than by reading this function.
		#
		# "installed" under a working storefront is the machine confirming what
		# the screen already shows. "unknown" -- "Checking the install state" --
		# is worse than that: it is the machine saying it does not know, printed
		# under a storefront it is visibly drawing, and it never resolves on a
		# machine whose install state file was never written (Steam installed
		# from this very card rather than by the first-boot installer is exactly
		# that machine). Reaching this branch at all means the INSTALLED seam
		# already said Steam is here -- see _front_available -- so the installer's
		# vagueness adds nothing to a person's understanding of the screen.
		#
		# Every other word in that table is a reason the storefront might not be
		# what somebody expected, and survives.
		_status_is_news = state != "installed" and state != "unknown"
	_page_status.add_theme_color_override(
		"font_color",
		TvTheme.TEXT_ALERT if STEAM_ALERT_STATES.has(state) else TvTheme.TEXT_SECONDARY)
	_refresh_page_chrome()


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
	# THE PROSE AND THE STOREFRONT ARE ALTERNATIVES, NOT NEIGHBOURS, and this now
	# covers every line of it rather than just the long one.
	#
	# The page was written for a card that had nothing on it: a title, a tagline,
	# a paragraph and a wash standing in for the store it could not show. All four
	# were doing the same job -- describing an absent thing -- and the moment
	# Valve's actual front page is on screen every one of them is a caption on a
	# photograph of itself. "Steam" over the Steam tab's own logo, "Valve's
	# storefront and library" over Valve's storefront, and "Installed -- A opens
	# the storefront" under the storefront it is already open on.
	#
	# So once there is a grid, the card is the grid. What survives is the ONE line
	# that could still be news -- see _refresh_status for which, and why "the
	# install is fine" is not it.
	_page_description.visible = not available
	_page_hero.visible = not available
	_page_spacer.visible = not available
	_refresh_page_chrome()

	if not available:
		return

	# THE SEARCH OWNS THE GRID WHILE IT IS UP. This function runs on every tab
	# focus, every install-state change and every arrival from the seam, and each
	# of those would otherwise rebuild the shelves straight over somebody's
	# results -- the storefront poll alone would do it within two seconds of the
	# first search. The featured request below is skipped for the same reason:
	# it is what triggers the arrival that does the rebuilding.
	if _search_active:
		_refresh_front_status()
		return

	if _tiles.is_empty() or _shelves_changed():
		_rebuild_grid()
	_refresh_front_status()

	# Asked for on every visit rather than once: the request is cheap by
	# construction (the service answers from disk without touching the network
	# while its copy is under an hour old), and the alternative is a storefront
	# that never refreshes on a machine nobody reboots.
	Steamfront.request_featured()
	# The account is cheaper still -- one local file, no network at all -- and it
	# is the one that changes without warning: somebody signs into Steam from Big
	# Picture and comes back here, and this is what notices.
	Steamfront.request_account()
	Steamfront.request_wishlist()


func _shelves_changed() -> bool:
	return _shelf_signature != _current_signature()


func _current_signature() -> String:
	var signature := ""
	# THE WISHLIST IS PART OF THE SIGNATURE, so a page landing for a wishlisted
	# game rebuilds the shelf that was waiting for it. Without this the shelf
	# would be drawn once, short by however many detail pages had not arrived in
	# the first two seconds, and stay that way until the featured list changed.
	signature += "wishlist:"
	for item in Steamfront.wishlist_items():
		signature += "%d," % int(item.get("appid", 0))
	signature += ";"
	for category in Steamfront.categories:
		signature += "%s:" % str(category.get("id", ""))
		for item in category.get("items", []):
			signature += "%d," % int(item.get("appid", 0))
		signature += ";"
	return signature


func _rebuild_grid() -> void:
	_shelf_signature = _current_signature()
	_clear_grid()

	# THE WISHLIST GOES FIRST, ahead of Valve's own shelves, and that ordering is
	# the argument for having it at all: everything below it is what a shop wants
	# to sell, and this is what the person already said they wanted. It is also
	# the only shelf on this screen that is about THEM.
	#
	# A synthetic category rather than a separate rendering path, so it gets the
	# same heading, the same tiles, the same focus wiring and the same detail page
	# as everything else. It disappears entirely when it is empty -- nobody signed
	# in, an empty or private wishlist, or the pages not fetched yet all render as
	# "no shelf", which is right: a heading over nothing is the machine drawing
	# attention to something it has nothing to say about.
	var shelves: Array = []
	var wishlist: Array = Steamfront.wishlist_items()
	if not wishlist.is_empty():
		shelves.append({"id": "wishlist", "name": "Your wishlist", "items": wishlist})
	shelves.append_array(Steamfront.categories)

	for category in shelves:
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
	# A's verb depends on whether there is anything to browse, so the hint row
	# is refreshed wherever _tiles changes -- not only where the page is drawn.
	# The shelves land a second or two after this screen opens on a cold
	# machine, and without this the row would still say "Open store" over a
	# storefront that had already arrived.
	_refresh_hints()
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
	# TWO TABLES, because an empty grid means two different things. With no
	# search running it is the storefront that has nothing on it; with one
	# running it is an answer to a question somebody asked, and "Steam's store
	# had nothing to show" would be answering a different one.
	var lines: Dictionary = SEARCH_STATE_LINES if _search_active else FRONT_STATE_LINES
	_front_status.text = str(lines.get(state, lines["unknown"]))
	_front_status.add_theme_color_override("font_color",
		TvTheme.TEXT_ALERT if FRONT_ALERT_STATES.has(state) else TvTheme.TEXT_SECONDARY)


# ---------------------------------------------------------------------------
# Searching
# ---------------------------------------------------------------------------

## Y on the Steam page or in the shelves: the keyboard, then a search.
##
## Y RATHER THAN X OR OPTIONS, and the other two were both taken by things that
## act on the Steam APPLICATION -- desktop mode and the remove menu. A third
## button on the same screen doing something to a different subject is how a pad
## stops being learnable, so search got the one face button this screen had left.
##
## Offered only where a search could be run: the storefront gate is the same one
## the grid is behind (see _front_available), because a search that returned
## results a person could not open would be a shop they cannot walk out of --
## this file's own argument for why the grid waits for Steam to be installed.
func _open_search() -> void:
	if _keyboard != null or not _front_available():
		return

	_keyboard = Keyboard.new()
	_keyboard.title_text = "Search Steam"
	# NOT MASKED, unlike the only other caller. The wifi screen hides what is
	# typed because it is somebody's passphrase; a search term is the one thing
	# on this screen a person most needs to see while they thumbstick it.
	_keyboard.masked = false
	# Opens holding the last term, for the file manager's rename reason: coming
	# back to narrow a search by one word should not be a full retype on a
	# thumbstick. Empty on the first search of a session, which is correct --
	# there is nothing to narrow.
	_keyboard.initial_text = _search_shown
	_keyboard.submitted.connect(_on_search_submitted)
	_keyboard.cancelled.connect(_on_search_cancelled)
	# A child of this screen rather than of the root, so closing the store can
	# never leave a keyboard orphaned over the rail -- the wifi screen's rule.
	add_child(_keyboard)
	# Deaf while the keyboard is up: its own _unhandled_input owns B, and both
	# reacting would close the keyboard and the screen behind it on one press.
	set_process_unhandled_input(false)


func _close_search_keyboard() -> void:
	if _keyboard == null:
		return
	var keyboard := _keyboard
	_keyboard = null
	remove_child(keyboard)
	keyboard.queue_free()
	set_process_unhandled_input(true)


func _on_search_cancelled() -> void:
	_close_search_keyboard()
	# Back to whatever was on screen before, with focus somewhere real: the
	# keyboard held it, and a screen that comes back ringless is a screen the pad
	# appears to have stopped working on.
	_restore_focus_after_search()


func _on_search_submitted(term: String) -> void:
	_close_search_keyboard()
	var trimmed := term.strip_edges()
	if trimmed.is_empty():
		_restore_focus_after_search()
		return

	_search_shown = trimmed
	_search_active = true
	_set_mode(MODE_SEARCH)
	Steamfront.request_search(trimmed)

	# RENDERED SYNCHRONOUSLY WHEN THE ANSWER IS ALREADY IN HAND, and this is not
	# an optimisation -- it is the fix for a stall. The service answers a repeated
	# term from disk by writing the state file, and if the state was already
	# `done search` that write changes nothing at all: no transition, no signal.
	# A screen that only ever rendered on search_changed would sit on "Searching"
	# forever for the one case a person is most likely to hit, which is searching
	# the same thing twice. See Steamfront._ready.
	if Steamfront.search_term == trimmed and not Steamfront.search_items.is_empty():
		_rebuild_search_grid(Steamfront.search_items)
	else:
		_clear_grid()
	_refresh_front_status()
	_refresh_hints()
	_focus_first_result()
	ShellLog.info("storefront search submitted (%d character(s))" % trimmed.length())


## Where focus goes when the keyboard closes. The first result if there is one,
## and otherwise the tab -- never nowhere.
func _focus_first_result() -> void:
	if not _tiles.is_empty():
		var first: Control = _tiles[0]
		first.grab_focus()
		return
	_restore_focus_after_search()


func _restore_focus_after_search() -> void:
	var tab := _selected_tab()
	if tab != null:
		tab.grab_focus()


func _on_search_changed(term: String, items: Array) -> void:
	# Only if this is the answer to the question on screen. The seam publishes
	# whatever the service last searched for, and a stale term arriving under a
	# newer one would replace a person's results with somebody else's.
	if not _search_active or term != _search_shown:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var was_in_grid := _tiles.has(focused)
	_rebuild_search_grid(items)
	_refresh_front_status()
	if _mode == MODE_SEARCH and (was_in_grid or focused == null) and not _tiles.is_empty():
		var first: Control = _tiles[0]
		first.grab_focus()


## The results, into the same grid the shelves use. One heading and one block of
## tiles, rather than the shelves' several.
func _rebuild_search_grid(items: Array) -> void:
	_clear_grid()
	# The shelf signature is emptied rather than set, so that leaving search
	# rebuilds the shelves from scratch instead of finding a signature that
	# matches the grid it is not looking at.
	_shelf_signature = ""

	if items.is_empty():
		_wire_grid_neighbours()
		return

	var heading := Label.new()
	# The term is drawn back to the person because a results list with no
	# question above it is a list of games with no reason. It is text they typed
	# on this machine's own keyboard, which is the only text on this screen that
	# did not come from Valve.
	heading.text = "Results for \"%s\"" % _search_shown
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
		# The search endpoint's own picture, which is a third the width of a
		# shelf capsule. See StoreFrontTile.small_art -- it still prefers the big
		# one when the game is also on a shelf.
		tile.small_art = true
		tile.setup_item(item)
		tile.opened.connect(_on_tile_opened)
		tile.focus_entered.connect(_on_tile_focused)
		grid.add_child(tile)
		_tiles.append(tile)
		row.append(tile)
		# Accumulated per block for _rebuild_grid's reason: the last row is short
		# whenever the result count is not a multiple of the column count, and
		# index arithmetic across it wires "down" into a column that is not there.
		if row.size() == TvTheme.STORE_GRID_COLUMNS:
			_tile_rows.append(row)
			row = []
	if not row.is_empty():
		_tile_rows.append(row)

	_wire_grid_neighbours()
	ShellLog.info("storefront search grid: %d result(s) in %d row(s)"
		% [_tiles.size(), _tile_rows.size()])


## Empty the grid and forget its focus structure. Shared by both rebuilds so the
## two can never disagree about what "empty" leaves behind.
func _clear_grid() -> void:
	for child in _front_column.get_children():
		_front_column.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_tile_rows.clear()


## Leave the results and go back to the shelves. The grid is rebuilt rather than
## restored: the shelf signature was emptied when the search took the grid over,
## so _refresh_front finds it stale and puts Valve's front page back.
func _leave_search() -> void:
	_search_active = false
	_search_shown = ""
	_set_mode(MODE_PAGE)
	_refresh_front()
	_restore_focus_after_search()
	ShellLog.info("storefront search left")


func _on_featured_changed(_categories: Array) -> void:
	# Same rule as _refresh_front: the shelves may not touch a grid that is
	# showing search results. The storefront refreshes on its own schedule and
	# a person reading their results is not expecting them to vanish.
	if not _front_available() or _search_active:
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


## Signing into Steam from Big Picture and coming back here is the case this
## exists for: only the line changes, so only the line is redrawn.
func _on_account_changed(_signed_in: bool, _persona: String) -> void:
	_refresh_page_chrome()
	# AND THE HINT ROW, because A's verb depends on this: signing in from Big
	# Picture and coming back has to change the button from "Sign in to Steam"
	# to "Browse". A hint row that kept the old word would be advertising a
	# door that is already open.
	_refresh_hints()


## The wishlist arriving, or its detail pages filling in behind it. Goes through
## the ordinary shelf path -- the signature now covers the wishlist, so the
## rebuild happens exactly when its contents actually changed.
func _on_wishlist_changed(_items: Array) -> void:
	if not _front_available() or _search_active:
		return
	if not _shelves_changed():
		return
	var focused := get_viewport().gui_get_focus_owner()
	var was_in_grid := _tiles.has(focused)
	_rebuild_grid()
	# A rebuild frees the node focus was on, and the wishlist shelf lands at the
	# TOP -- so a shelf appearing under somebody would otherwise shift every tile
	# down a row while their thumb was on one. Landing on the first tile is the
	# same honest restore _on_featured_changed makes for the same reason.
	if was_in_grid and not _tiles.is_empty():
		var first: Control = _tiles[0]
		first.grab_focus()
	_refresh_front_status()


func _on_front_state_changed(_state: String, _detail: String) -> void:
	_refresh_front_status()
	if _mode == MODE_DETAIL:
		_render_detail()


func _on_app_changed(appid: int, _details: Dictionary) -> void:
	if _mode == MODE_DETAIL and int(_detail_item.get("appid", 0)) == appid:
		_render_detail()
	# A DETAIL PAGE IS ALSO A WISHLIST TILE. The wishlist arrives as bare appids
	# and its shelf is assembled from these pages, so on a cold machine the shelf
	# is short until they land -- one tile at a time, each arriving here. Without
	# this the shelf would freeze at whatever it managed in the first two seconds.
	# _on_wishlist_changed does the signature check, so an appid that is not on
	# the wishlist costs one comparison.
	_on_wishlist_changed([])


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
	_refresh_page_chrome()
	_refresh_front_status()
	_refresh_hints()


## Which of the store page's own lines are showing. ONE FUNCTION rather than the
## two places that used to decide it, because they had started to disagree: the
## mode switch hid the title for a game's page and the storefront switch hid the
## description for a grid, and neither knew about the other, so a title survived
## onto a page that had a whole storefront on it.
##
## Three rules, in order of how much they take away:
##
##   A GAME'S PAGE GETS THE PANE TO ITSELF. The title and the tagline belong to
##   the STORE and the detail belongs to a game.
##   A LIVE STOREFRONT REPLACES THE PROSE ABOUT IT. See _refresh_front.
##   THE STATUS LINE SURVIVES ONLY WHEN IT IS NEWS. "Installed -- A opens the
##   storefront", printed under an open storefront, is the machine describing
##   what a person is looking at. An install that is downloading, out of space or
##   failed is the opposite: it is the only place that says so, and hiding it to
##   tidy the card would be hiding the one line somebody needs.
func _refresh_page_chrome() -> void:
	var detail := _mode == MODE_DETAIL
	var storefront := _front_available()

	if _page_title != null:
		_page_title.visible = not detail and not storefront
	if _page_tagline != null:
		_page_tagline.visible = not detail and not storefront
	if _page_status != null:
		_page_status.visible = not detail and (not storefront or _status_is_news)

	if _account_line != null:
		_account_line.visible = not detail and storefront
		if _account_line.visible:
			# THE SIGN-IN PROMPT IS NOT A FORM, and this line is the whole of the
			# account boundary on this screen. Nothing here takes a password:
			# pressing A opens Valve's client, which is where signing in belongs
			# for the same reason buying does. See the file header.
			_account_line.text = ("Signed in as %s" % Steamfront.account_persona) \
				if Steamfront.account_signed_in and not Steamfront.account_persona.is_empty() \
				else ("Signed in" if Steamfront.account_signed_in
					else "Not signed in -- A opens Steam, where you can sign in")


## Focus arriving on a tile IS entering the grid, and there is no key handler
## for it: the tab's focus_neighbor_right already points at the first tile, so
## Godot's own navigation does the move and this only notices. Doing it the
## other way -- intercepting Right in _unhandled_input -- would mean two things
## deciding where focus goes, which is the bug class the settings list's
## neighbour table exists to avoid.
func _on_tile_focused() -> void:
	if _mode == MODE_PAGE:
		# Which grid it is depends on what is IN it, not on how focus got here:
		# the left-edge doorway comes back to the tab and going right again
		# returns to whatever the grid was still holding.
		_set_mode(MODE_SEARCH if _search_active else MODE_GRID)
		ShellLog.info("storefront %s entered" % ("results" if _search_active else "grid"))


func _on_tile_opened(item: Dictionary) -> void:
	_detail_item = item
	_detail_tile = get_viewport().gui_get_focus_owner()
	# Remembered BEFORE the mode changes, because after it there is no way left
	# to tell a result from a shelf tile.
	_detail_from = MODE_SEARCH if _search_active else MODE_GRID
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
	_set_mode(_detail_from)
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

	_refresh_detail_actions()

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


## What the two rows say right now. Called from _render_detail, and again
## whenever the installed seam changes, so a download that starts while its page
## is open counts up on screen instead of going quiet until somebody backs out.
func _refresh_detail_actions() -> void:
	if _detail_action == null or _detail_store_action == null:
		return
	var appid := int(_detail_item.get("appid", 0))
	var state := _local_state(appid)

	# set_name_text / set_value, NOT setup(): setup only stores strings and the
	# labels are built once in _ready, so a re-setup on a row already in the tree
	# changes nothing on screen. That is the bug this page would have shipped
	# with -- a row that said "Install" forever while the download it started ran
	# to completion behind it.
	if state == "installed":
		_detail_action.set_name_text(HINT_PLAY)
		_detail_action.set_value("")
	elif state == "downloading":
		# The seam's own live line, which appscan built out of the
		# appmanifest's byte counters. Empty on a manifest Steam has only just
		# created, and the row still says Downloading -- which is true, and
		# better than an invented 0%.
		_detail_action.set_name_text(HINT_DOWNLOADING)
		_detail_action.set_value(_local_detail(appid))
	else:
		_detail_action.set_name_text(HINT_INSTALL_GAME)
		_detail_action.set_value("")


## The primary row. Three verbs, one boundary: every one of these hands a
## steam:// URL to a client running `-silent`, so the only window that can reach
## the television is the game's own.
##
## DOWNLOADING DOES NOTHING ON PURPOSE. The row is a readout, not a button, and
## the alternatives are both worse: cancelling a download from a button somebody
## pressed expecting "play" is destructive, and opening Big Picture to show a
## progress bar is the UI this screen exists to avoid.
func _on_detail_action() -> void:
	if Launcher.is_busy() or _detail_item.is_empty():
		return
	var appid := int(_detail_item.get("appid", 0))
	if appid <= 0:
		return
	var state := _local_state(appid)
	if state == "downloading":
		ShellLog.info("storefront: A on a game that is already downloading; nothing to do")
		return

	if state == "installed":
		# THE SAME COMMAND THE RAIL CARD CARRIES, deliberately not a second
		# spelling of it: appscan publishes `-silent steam://rungameid/<appid>`
		# and this is the same game, so a page that launched it differently
		# would be a second launch path to keep in step with the first.
		Launcher.launch({
			"id": "steam.%d" % appid,
			"title": str(_detail_item.get("name", "")),
			"accent": str(_selected.get("accent", "")),
			"exec": ["flatpak", "run", "com.valvesoftware.Steam", "-silent",
				"steam://rungameid/%d" % appid],
			"app_id": str(_selected.get("app_id", "")),
			"icon": Steamfront.art_path(appid),
		})
		ShellLog.info("storefront launching installed appid %d" % appid)
		return

	# NOT HERE YET. `steam://install/<appid>` is Steam's own install URL and it
	# is the one action on this page whose UI cannot be predicted from here: a
	# game the account owns starts downloading, and one it does not gets Valve's
	# own answer, which may be a window. That is the honest limit of a shell that
	# cannot know what somebody owns -- Steam retired every keyless way to ask,
	# measured 2026-08-11.
	#
	# What makes it recoverable either way is the row above: the moment Steam
	# writes an appmanifest, appscan publishes the game as `downloading` and this
	# same page starts counting up. So a press that worked says so within a
	# couple of seconds, on this screen, without Big Picture.
	Launcher.launch({
		"id": "steam.install.%d" % appid,
		"title": str(_detail_item.get("name", "")),
		"accent": str(_selected.get("accent", "")),
		"exec": ["flatpak", "run", "com.valvesoftware.Steam", "-silent",
			"steam://install/%d" % appid],
		"app_id": str(_selected.get("app_id", "")),
		"icon": Steamfront.art_path(appid),
	})
	ShellLog.info("storefront requested an install of appid %d" % appid)


## The purchase door, and it goes to the BROWSER. This is the last place on this
## screen that used to open Valve's client, and it was the hardest one to argue
## away: buying needs a real store page, a cart and a card field, and none of
## those are things this shell will ever draw.
##
## The answer is that Steam's own store page is a WEBSITE, and this machine ships
## a browser. `store.steampowered.com/app/<appid>` is the same page the client
## renders, with the same checkout behind it, driven by a pointer this machine
## already has -- pad_keys.gd puts the right stick on the cursor for exactly this
## kind of application. So the transaction still happens entirely on Valve's
## side, in Valve's UI, and the flickering ten-foot client the owner cannot
## navigate never enters into it.
##
## STILL NO MONEY ANYWHERE NEAR THIS SHELL. What changed is which of somebody
## else's UIs the handover goes to, not whether there is a handover.
##
## The appid is a NUMBER by the time it reaches this line -- the seam parsed it
## out of Valve's own JSON as an int -- so there is nothing here for a URL to be
## broken open with.
func _on_detail_store_action() -> void:
	if Launcher.is_busy() or _detail_item.is_empty():
		return
	var appid := int(_detail_item.get("appid", 0))
	if appid <= 0:
		return

	var entry := {
		# A distinct id, for steam_desktop_entry's reason: the launch seam, the
		# splash and the pad bridge all key on this, and "the browser showing one
		# game's store page" wants the splash to say the game's name. It is also
		# why this id had to be ADDED to Catalogue.PAD_KEY_APPS as "pointer": a
		# web page has no controller support of its own, and a checkout nobody
		# can click is a dead end with a card field on it.
		"id": "store.steam.buy",
		"title": str(_detail_item.get("name", "")),
		"accent": str(_selected.get("accent", "")),
		"exec": ["flatpak", "run", "app.zen_browser.zen",
			"https://store.steampowered.com/app/%d/" % appid],
		"app_id": "app.zen_browser.zen",
		"icon": Steamfront.art_path(appid),
	}
	ShellLog.info("storefront opening appid %d in the browser to buy" % appid)
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
	# AND THE GAME PAGE'S OWN ROWS, which is what makes a download count up while
	# somebody watches it. appscan republishes apps.tsv every time a manifest's
	# byte counters move, so this arrives on its own every few seconds for the
	# whole of a download -- and it is also how Install turns into Downloading,
	# and Downloading into Play, without anybody leaving the page.
	if _mode == MODE_DETAIL:
		_refresh_detail_actions()


## What A offers on a store tab. Three situations, three verbs -- see
## _on_store_opened, which must agree with this or the hint row is a lie.
func _page_action_hint() -> String:
	if not _selected_installed():
		return HINT_INSTALL
	if not Steamfront.account_signed_in:
		return HINT_SIGN_IN
	# NOTHING TO BROWSE ADVERTISES NOTHING. An empty string here makes the hint
	# row skip A entirely, which is the truthful rendering of a state where A
	# has no job: the grid is empty, the status line under it says why, and the
	# door Big Picture used to provide from this spot opened onto a client
	# store page that was dead for the same reason the grid was.
	return HINT_BROWSE if not _tiles.is_empty() else ""


func _on_store_opened(entry: Dictionary) -> void:
	# A MEANS THREE DIFFERENT THINGS, and none of them is a preference.
	#
	# NOT INSTALLED -- an application that is not on the machine cannot be
	# opened, so A downloads it. Before this existed the tab launched
	# `flatpak run` regardless, which failed in milliseconds and left the page
	# exactly as it was, so the button read as broken.
	#
	# NOT SIGNED IN -- the ONE remaining reason this shell opens Big Picture on
	# purpose. A password is Valve's to collect and this shell will never have a
	# field for one, so the honest button hands over to the client and stops.
	#
	# SIGNED IN -- A goes into the shelves. It used to open Big Picture on
	# Valve's storefront, which is the page this panel already draws, at this
	# shell's fidelity, with this shell's pad. Spending the button on a second
	# copy of what is on screen was the last habit left over from when this
	# screen could only describe a store instead of being one.
	var app_id := str(entry.get("app_id", ""))
	if _selected_installed() and Steamfront.account_signed_in and not _tiles.is_empty():
		var first: Control = _tiles[0]
		first.grab_focus()
		return
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

	# Signed in with nothing to browse: A does NOTHING, on purpose, and quietly.
	# The status line above is already explaining why the grid is empty; the old
	# behaviour here opened Big Picture's store page, which in this state (it is
	# nearly always a machine with no network) was equally empty and drawn by
	# the one client this screen exists to keep off the television.
	if Steamfront.account_signed_in:
		ShellLog.info("A on the store tab with nothing to browse; the status line says why")
		return

	# Installed but signed out -- THE ONE REMAINING CLIENT DOOR, kept until the
	# QR sign-in flow replaces it: a password is Valve's to collect, and today
	# the client is the only surface that can collect it. Through the launch
	# seam like every launch; when the client quits, this page is what the
	# person lands back on -- by which point the account line above the shelves
	# will have noticed the sign-in, because the seam re-reads Steam's
	# loginusers.vdf on every visit to this screen.
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

	# Y OPENS THE KEYBOARD, from the store page and from either grid. Not from a
	# game's page: the selection there is one game, and a search box appearing
	# over it would be a button that abandons what somebody was reading rather
	# than acting on it -- B first, then Y, which is one more press and no
	# ambiguity.
	#
	# TRIANGLE IS FREE ON THIS SCREEN. ui_shell_y is the on-screen keyboard's
	# backspace shortcut and nothing else in the shell reads it, and this screen
	# goes deaf the whole time that keyboard is up (see _open_search), so the two
	# uses of the button can never both be live.
	if event.is_action_pressed("ui_shell_y"):
		if _mode == MODE_DETAIL or not _front_available():
			return
		get_viewport().set_input_as_handled()
		_open_search()
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
	# THE RESULTS ARE A LEVEL OF THEIR OWN, and B unwinds them to the store page
	# rather than to the shelves. Going "back" from a search to a grid the person
	# never opened would be arriving somewhere new on the button whose whole
	# meaning is returning.
	if _mode == MODE_SEARCH:
		_leave_search()
		return
	if _mode == MODE_GRID:
		_set_mode(MODE_PAGE)
		var tab := _selected_tab()
		if tab != null:
			tab.grab_focus()
		ShellLog.info("storefront grid left")
		return
	closed.emit()
