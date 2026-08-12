extends Control

## The Steam screen: sign in by scanning a code, then a shelf of the games this
## account owns, each of which downloads and starts from here.
##
## IT IS A LIBRARY AND NOT A SHOP, which is the whole of ADR 0010 and the reason
## this file is a rewrite rather than an edit of the storefront it replaces.
## There is no front page, no search, no wishlist, no price and no buy button,
## and none of them is coming back: a store is where money changes hands, this
## appliance has no surface where it can, and the owner's instruction was
## exactly one sentence long -- "implementing my own steam client in the stores
## menu where I can sign in and download my library games".
##
## FOUR THINGS THIS SCREEN CAN BE, and every one of them is a first-class
## render rather than a blank pane with something missing from it:
##
##   1. THE CLIENT IS NOT HERE YET. The first-boot state: Valve's client is
##      still downloading from Flathub, so the page is the catalogue's prose
##      about what this will be plus the installer's live line. Nothing is
##      focusable, because there is nothing here anybody can do about it.
##   2. NOBODY IS SIGNED IN. One row, which asks for a code.
##   3. A SCAN IS RUNNING. The code, and one sentence about what to do with it.
##   4. SIGNED IN. The shelf.
##
## WHY THE CLIENT'S INSTALL GATES ALL OF IT, since the downloader does not need
## it: DepotDownloader ships in this image and fetches a game perfectly well
## with no flatpak anywhere. What needs Valve's client is STARTING a game -- its
## DRM refuses to run without one -- so a shelf drawn before the client arrives
## would download games that cannot be played, which is the storefront's own
## "a shop you cannot walk out of" argument arriving from the other side. The
## client is installed automatically on first boot, so this state is minutes
## long and once per machine.
##
## NAVIGATION. The settings list's argument, rotated into two dimensions where
## the shelf needs it: hard stops at every edge, and left off the first column
## stays put rather than wandering -- there is no second focus region on this
## screen for a doorway to lead to, so every edge is a wall and that is the
## whole table. B unwinds one level (the code panel folds back to the sign-in
## row; anything else closes the screen). While a launch is up the screen HIDES
## rather than merely going deaf, for settings_screen.gd's reason: every control
## here is a focusable Button driven through the viewport's focus, the shell
## keeps receiving pad input while another client owns the screen, and a
## deaf-but-visible screen would still walk its focus ring under a running game
## and paint its background over it.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Catalogue = preload("res://src/catalogue.gd")
const ActionRow = preload("res://src/action_row.gd")
const ListMenu = preload("res://src/list_menu.gd")
const SteamTile = preload("res://src/steam_tile.gd")

## The four renderings. One pane per rendering rather than one pane re-rendered:
## they hold genuinely different objects (a paragraph, a picture, a grid), and
## the deleted storefront's single pane was only ever one because its four
## renderings were all lists of the same tile.
enum { VIEW_ABSENT, VIEW_SIGNED_OUT, VIEW_SIGNIN, VIEW_LIBRARY }

## What the page says about Valve's client while it is not here yet, by the word
## the status seam reports. "unknown" doubles as the fallback so no state can
## render this page silent about the one thing it is about.
const INSTALL_LINES := {
	"installed": "Installed",
	"downloading": "Downloading Steam from Flathub -- a few GB, so give it minutes",
	"waiting-network": "Waiting for a network before downloading Steam",
	"no-network": "No network found -- plug in ethernet; the install retries next boot",
	"no-space": "Not enough free space on the drive for Steam",
	"failed": "The Steam install failed -- journalctl -t marwanos-install has the story",
	"unknown": "Checking whether Steam is installed",
}

## The install states that name a problem somebody could act on.
const INSTALL_ALERT_STATES := ["no-network", "no-space", "failed"]

## What the code panel says under the picture, by the sign-in's status word.
## "approved" is deliberately absent: that sentence carries a name and a caveat,
## so _render_signin words it. "" is a request the service has not answered yet,
## which reads the same as starting.
const SIGNIN_LINES := {
	"": "Getting a code from Steam",
	"starting": "Getting a code from Steam",
	"waiting": "Scan the code with the Steam app on your phone, then approve the sign-in there",
	"second": "Approved -- one more scan fills your library. Scan this second code the same way",
	"expired": "That code expired -- A gets a fresh one",
	"failed": "Steam did not answer -- A tries again",
}

## The sign-in states that are a problem rather than progress, and -- not by
## coincidence -- exactly the two where pressing A gets a NEW code rather than
## re-publishing the one already on screen. That is why this list also decides
## whether the panel has anything focusable in it: see _render_signin.
const SIGNIN_RETRY_STATES := ["expired", "failed"]

## What the shelf area says when there is nothing on it, by the seam's state
## word. EVERY ONE OF THESE IS A FIRST-CLASS RENDER -- the wifi screen's lesson,
## applied to something slower and more failure-prone than a radio: a list that
## is still coming, a machine with no network and an account Valve would not
## answer for are three different situations leading three different places, and
## an empty grid says none of them.
const LIBRARY_STATE_LINES := {
	"unknown": "Asking Steam what this account owns",
	"idle": "Asking Steam what this account owns",
	"working": "Asking Steam what this account owns",
	"done": "Steam listed no games for this account",
	"offline": "No network -- the list needs one, and the last one fetched is kept",
	"failed": "Steam did not answer",
}

## The shelf states that name a problem rather than progress.
const LIBRARY_ALERT_STATES := ["offline", "failed"]

## The options menu's rows, per what the game is doing. Written here rather than
## on the seam because they are WORDING and consequences, which is the caller's
## half of list_menu.gd's contract: the menu decides nothing.
const CANCEL_ITEM := {"id": "cancel", "label": "Cancel download", "icon": "close"}
const CLEAR_ITEM := {"id": "cancel", "label": "Clear the failed download", "icon": "close"}
const UNINSTALL_ITEM := {"id": "uninstall", "label": "Uninstall", "icon": "trash"}

## The sentence under the menu's rows. NAMED, not "this cannot be undone":
## removing a game is reversible from this very shelf, and the honest cost is
## the download -- which is what somebody on a domestic line wants warned about.
## Apps.OPTIONS_NOTE makes the same argument about applications and is
## deliberately not shared: that one is about a flatpak and this is about
## tens of gigabytes of game.
const UNINSTALL_NOTE := \
	"Removing frees the disk space. Installing it again means downloading it again."
const CANCEL_NOTE := "What has been downloaded so far is deleted."

## HOW OFTEN THE LIBRARY IS ASKED FOR AGAIN WHILE THE SHELF IS OPEN, and it is
## about ARTWORK rather than about the list. The service fetches pictures for at
## most twenty-four new appids per request -- the contract's bound, so one visit
## cannot spend minutes on a four-hundred-game library -- and each request
## reaches further down. Without this, a big library would show two dozen
## pictures and several hundred washes for the whole session, and the fix would
## look like leaving the screen and coming back.
##
## Asked only while pictures are actually missing, so a fully-drawn shelf costs
## nothing at all.
const ART_REFETCH_SECONDS := 30.0

var _view := VIEW_ABSENT

## Whether the person has asked for a code. Kept separately from the sign-in's
## status word because B has to be able to fold the panel away while the
## service's session is still live -- and that session SHOULD stay live: someone
## who backs out after scanning but before their phone finished asking is still
## mid-sign-in, and the approval landing a moment later is a success rather than
## a surprise.
var _signin_open := false

var _body: VBoxContainer = null
var _prose: Control = null
var _prose_hero: Panel = null
var _prose_title: Label = null
var _prose_tagline: Label = null
var _prose_description: Label = null
var _prose_status: Label = null

var _signin_pane: Control = null
var _signin_wash: Panel = null
var _signin_qr: TextureRect = null
## The square that holds the wash and the code. Hidden outright when no scan is
## live -- see _build_signin.
var _signin_frame: Control = null
var _signin_line: Label = null
var _signin_row: ActionRow = null
## Which published code is on screen, as the `fetched` stamp it arrived with.
## THE PICTURE ROTATES ABOUT EVERY THIRTY SECONDS while a scan is live and the
## file keeps its name, so this stamp is the only thing that says the PNG on
## disk is a different PNG. Comparing it is what stops the panel decoding the
## same image every two seconds and what stops it drawing a dead code.
var _signin_drawn_fetched := -1

var _library: Control = null
var _library_scroll: ScrollContainer = null
var _library_grid: GridContainer = null
var _library_status: Label = null
var _account_line: Label = null

## Every tile in reading order, and the same tiles arranged as rows. The row
## structure is what the focus wiring walks -- see _wire_grid_neighbours for why
## index arithmetic breaks on a short last row.
var _tiles: Array = []
var _tile_rows: Array = []

## What the shelf is currently drawn from, against what the seam now holds. A
## rebuild drops focus, and this screen is fed by a two-second poll, so a
## rebuild per poll would pull the selection out from under a resting thumb
## continuously -- the wifi screen's lesson and its solution.
var _library_signature := ""

var _hints: HBoxContainer = null

var _menu: ListMenu = null
## Which game the open menu is about. The menu carries a title and an id and
## deliberately knows nothing else, so the screen has to remember the subject.
var _menu_item: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The full TV-safe inset, all four edges. Everything on this screen is text,
	# a picture inside a frame, or a control carrying a focus ring; nothing here
	# is background-class furniture with the rail's licence to bleed.
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
	heading.text = "Steam"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	# WHOSE LIBRARY THIS IS, above the shelf rather than below it: it answers a
	# question a person asks before they look at what is on it. A DISPLAY NAME
	# AND NEVER A STEAMID -- the number is in account.json because the service
	# needs it, and there is no reading of this appliance's job that involves
	# printing somebody's account id on a television.
	_account_line = Label.new()
	_account_line.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_account_line.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_account_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_account_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_account_line.visible = false
	column.add_child(_account_line)

	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	column.add_child(_body)

	_prose = _build_prose()
	_body.add_child(_prose)
	_signin_pane = _build_signin()
	_body.add_child(_signin_pane)
	_library = _build_library()
	_body.add_child(_library)

	column.add_child(_build_hints())

	# Both halves of "is Steam here": the status seam narrates the first-boot
	# installer, and the installed seam says whether the application has actually
	# arrived or been removed since. The gate reads the installed seam and the
	# page's line reads the installer, so both are watched.
	SystemStatus.steam_changed.connect(_on_steam_changed)
	Installed.apps_changed.connect(_on_installed_changed)
	Steam.state_changed.connect(_on_state_changed)
	Steam.account_changed.connect(_on_account_changed)
	Steam.library_changed.connect(_on_library_changed)
	Steam.signin_changed.connect(_on_signin_changed)
	Steam.downloads_changed.connect(_on_downloads_changed)
	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)

	# A SCAN ALREADY RUNNING OWNS THE SCREEN. The service's session outlives this
	# node -- it keeps polling Valve after B closes the panel -- so a person who
	# left and came back within the same thirty seconds should find their code
	# where they left it rather than a button offering to start again.
	if Steam.signin_status == "starting" or Steam.signin_status == "waiting":
		_signin_open = true

	# Asked on every visit rather than once per boot: it is one local file read
	# on the root side, it opens no socket, and it is the answer that changes
	# without warning while nobody is looking at this screen.
	Steam.request_account()
	if Steam.account_signed_in:
		Steam.request_library()

	# THE PICTURES, over the whole time the shelf is open. See ART_REFETCH_SECONDS
	# -- and note that it does nothing at all once every tile has its art, which
	# is the steady state on any machine that has had this screen open once.
	var art_timer := Timer.new()
	art_timer.wait_time = ART_REFETCH_SECONDS
	art_timer.autostart = true
	art_timer.timeout.connect(_on_art_timer)
	add_child(art_timer)

	_render()

	ShellLog.info("steam screen up (%s)" % _view_name())


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

## The page for a machine whose Steam is still arriving: a wash standing in for
## key art, the catalogue's own words, and the installer's live line.
##
## THE PROSE IS WRITTEN FOR EXACTLY ONE READER and this is the only place it is
## ever drawn -- somebody looking at a machine that cannot yet do any of what it
## describes. The moment the client is here, this whole pane is gone rather than
## sitting above the shelf as a caption on a photograph of itself.
func _build_prose() -> Control:
	var pane := VBoxContainer.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	pane.visible = false

	_prose_hero = Panel.new()
	_prose_hero.custom_minimum_size = Vector2(0, TvTheme.STORE_PAGE_HERO_HEIGHT)
	_prose_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_prose_hero)

	_prose_title = Label.new()
	_prose_title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	_prose_title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_prose_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_prose_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_prose_title)

	_prose_tagline = Label.new()
	_prose_tagline.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_prose_tagline.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_prose_tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_prose_tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_prose_tagline)

	_prose_description = Label.new()
	_prose_description.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_prose_description.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_prose_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prose_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_prose_description)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(spacer)

	# The one line on this page that changes on its own.
	_prose_status = Label.new()
	_prose_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_prose_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_prose_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prose_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_prose_status)

	return pane


## The sign-in pane: one row, a code, and a sentence.
##
## THE CREDENTIAL BOUNDARY, STATED WHERE A PERSON COULD EXPECT A FORM. This pane
## never asks for anything. No password field will ever be added here: the
## approval happens inside Valve's own app on a phone that already holds the
## session, the token is minted for the Steam CLIENT (which is what makes one
## scan serve both the library and the downloader), and what this machine keeps
## is stored 0600 root-side where the shell cannot read it.
##
## THE ROW IS ONLY THERE WHEN A IS WORTH PRESSING -- see _render_signin. While a
## live code is on screen the next move belongs to somebody's phone, and a
## button that re-publishes the picture already showing would be a control
## offered because a screen felt empty without one.
func _build_signin() -> Control:
	var pane := VBoxContainer.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	pane.visible = false

	# The code, square, at close to the PNG's native size -- see STORE_QR_SIZE,
	# which is worked from what a phone camera across a living room can resolve
	# rather than from what looks balanced. Left-aligned like every heading on
	# this screen rather than centred.
	# HELD IN A MEMBER because the whole frame has to disappear when there is no
	# code coming. It carries the wash as well as the picture, and a wash with
	# nothing on its way is a grey square sitting above the sign-in row looking
	# like an image that failed to load -- which is what the signed-out screen
	# drew until somebody screenshotted it.
	_signin_frame = Control.new()
	var frame := _signin_frame
	frame.custom_minimum_size = Vector2(TvTheme.STORE_QR_SIZE, TvTheme.STORE_QR_SIZE)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(frame)

	# The wash while the code is still coming, for the tile's reason: a rectangle
	# of the right size that the picture lands in, not a layout that jumps.
	_signin_wash = Panel.new()
	_signin_wash.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	_signin_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_signin_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_signin_wash)

	_signin_qr = TextureRect.new()
	_signin_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_signin_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# NEAREST, and it is load-bearing rather than aesthetic: a QR is a grid of
	# hard-edged modules, and bilinear filtering greys every edge -- which is
	# exactly the contrast a camera across a room needs most.
	_signin_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_signin_qr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_signin_qr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_signin_qr.visible = false
	frame.add_child(_signin_qr)

	_signin_line = Label.new()
	_signin_line.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_signin_line.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_signin_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_signin_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_signin_line)

	# ONE ROW SERVES TWO PANES. It is the whole of the signed-out rendering and
	# the retry inside the sign-in one, because it is the same button either way
	# -- "ask Steam for a code" -- and two rows would be two places to keep the
	# same sentence. Its parent is the pane rather than the screen so it travels
	# with the picture it belongs to.
	_signin_row = ActionRow.new()
	_signin_row.setup("Sign in", "Scan a code with the Steam app on your phone", "download")
	_signin_row.activated.connect(_on_signin_row_pressed)
	pane.add_child(_signin_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(spacer)

	return pane


## The shelf. A scrolling grid plus one status line, both children of the same
## container so exactly one of them is ever showing and the pane can never be
## blank.
##
## THE SCROLL CONTAINER FOLLOWS FOCUS, which is the whole of the scrolling
## design: there is no scrollbar to grab on a machine with no pointer, so the
## only thing that may move the view is the selection moving, and Godot does
## that for free. A library of forty games is seven rows against a pane that
## shows one and a half.
func _build_library() -> Control:
	var pane := VBoxContainer.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_theme_constant_override("separation", TvTheme.STORE_SHELF_GAP)
	pane.visible = false

	_library_status = Label.new()
	_library_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_library_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_library_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_library_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_library_status)

	_library_scroll = ScrollContainer.new()
	_library_scroll.follow_focus = true
	_library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The bar is hidden rather than merely unused: nothing on this machine can
	# grab it, and a grey stripe down the edge of the shelf is decoration saying
	# "there is a mouse here".
	_library_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_library_scroll.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	pane.add_child(_library_scroll)

	_library_grid = GridContainer.new()
	_library_grid.columns = TvTheme.STEAM_GRID_COLUMNS
	_library_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_library_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_grid.add_theme_constant_override("h_separation", TvTheme.STORE_GRID_GAP)
	_library_grid.add_theme_constant_override("v_separation", TvTheme.STORE_GRID_GAP)
	_library_scroll.add_child(_library_grid)

	return pane


func _build_hints() -> Control:
	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	return _hints


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

## Which of the four this screen is right now. The order is the order of the
## questions: is the client here, is anybody signed in, did somebody ask for a
## code.
## THE SHELF NEEDS A WEB TOKEN, NOT AN ACCOUNT, and the distinction is the whole
## of this function. `Steam.account_signed_in` is true when EITHER identity
## exists -- our QR token, or merely Valve's client having a session of its own
## -- and only the first can fetch a library. Keying on it sent a machine whose
## client was signed in but which had never had a QR scanned straight to
## VIEW_LIBRARY, where it drew the person's own name above an empty shelf and
## never offered the scan that was the one thing missing (bench, 2026-08-12).
##
## So: a web token draws the shelf, and anything less offers the code. The
## client's own account is still worth knowing -- the sign-in pane says whether
## it will be able to start a DRM'd game once the shelf works -- but it is not
## what this decision is made of. See Steam.account_source.
func _decide_view() -> int:
	if not _client_installed():
		return VIEW_ABSENT
	if Steam.account_has_library_access():
		return VIEW_LIBRARY
	if _signin_open:
		return VIEW_SIGNIN
	return VIEW_SIGNED_OUT


## Is Valve's client actually on the machine? Answered from the INSTALLED seam --
## the same list the rail draws -- rather than from the install state file,
## which says what the first-boot installer last did and goes on saying it after
## somebody removes the application by hand.
func _client_installed() -> bool:
	var app_id := str(Catalogue.stores()[0].get("app_id", ""))
	if app_id.is_empty():
		return false
	for app in Installed.apps:
		if str(app.get("id", "")) == app_id and str(app.get("state", "")) == "installed":
			return true
	return false


func _render() -> void:
	var was := _view
	_view = _decide_view()

	_prose.visible = _view == VIEW_ABSENT
	# The signed-out row and the code panel are one pane in two states -- see
	# _build_signin.
	_signin_pane.visible = _view == VIEW_SIGNED_OUT or _view == VIEW_SIGNIN
	_library.visible = _view == VIEW_LIBRARY

	if _view == VIEW_ABSENT:
		_render_prose()
	elif _view == VIEW_LIBRARY:
		_render_library()
	else:
		_render_signin()

	_render_account_line()
	_refresh_hints()
	_ensure_focus()

	if was != _view:
		ShellLog.info("steam screen: %s" % _view_name())


func _render_prose() -> void:
	var entry: Dictionary = Catalogue.stores()[0]
	_prose_hero.add_theme_stylebox_override(
		"panel", TvTheme.card_art_box(TvTheme.accent(str(entry.get("accent", "")))))
	_prose_title.text = str(entry.get("title", ""))
	_prose_tagline.text = str(entry.get("tagline", ""))
	_prose_description.text = str(entry.get("description", ""))

	var state := SystemStatus.steam
	# The installer's live progress line beats the fixed wording, for the rail's
	# reason: a number that moves is the whole difference between "working" and
	# "hung" to the person watching a multi-gigabyte download.
	if not SystemStatus.steam_detail.is_empty():
		_prose_status.text = "Installing Steam -- %s" % SystemStatus.steam_detail
	else:
		_prose_status.text = str(INSTALL_LINES.get(state, INSTALL_LINES["unknown"]))
	_prose_status.add_theme_color_override("font_color",
		TvTheme.TEXT_ALERT if INSTALL_ALERT_STATES.has(state) else TvTheme.TEXT_SECONDARY)


## The code, the sentence, and whether there is anything to press.
##
## THE PICTURE IS RE-READ WHEN `fetched` MOVES AND NOT OTHERWISE. Valve's
## challenge dies about every thirty seconds and the service publishes a
## replacement under the same filename, with the same status word -- so
## comparing the STAMP is the only way to tell a rotated code from the one
## already on screen, and it is the difference between a panel that decodes a
## PNG twice a second and one that shows a code nobody can scan any more.
func _render_signin() -> void:
	var status := Steam.signin_status

	if _view == VIEW_SIGNED_OUT:
		# Nothing has been asked for yet: the row is the whole pane.
		_signin_frame.visible = false
		_signin_qr.visible = false
		_signin_drawn_fetched = -1
		_signin_row.visible = true
		_signin_row.set_name_text("Sign in")
		_signin_row.set_value("Scan a code with the Steam app on your phone")

		# THE ONE CASE THAT NEEDS A SENTENCE, and it is the case that sent
		# somebody to a shelf they could not fill: the machine plainly knows
		# who they are -- Valve's client has a session, or the first QR phase
		# already stored the downloads token -- and the screen is nevertheless
		# asking them to sign in. Without a word here that reads as the machine
		# having forgotten them. It has not -- it is that neither of those
		# identities can fetch a library, and only the second scanned code can.
		if (Steam.account_client_signed_in or Steam.account_signed_in) \
				and not Steam.account_persona.is_empty():
			_signin_line.text = (
				"Steam is signed in as %s on this machine, but the library"
				+ " needs its own code."
			) % Steam.account_persona
		else:
			_signin_line.text = ""
		return

	# A scan is live (or has just ended): the square comes back, carrying the
	# wash until the picture lands.
	_signin_frame.visible = true

	if Steam.signin_fetched != _signin_drawn_fetched:
		var qr := Steam.qr_path()
		if qr.is_empty():
			_signin_qr.visible = false
		else:
			var image := Image.new()
			if image.load(qr) == OK:
				_signin_qr.texture = ImageTexture.create_from_image(image)
				_signin_qr.visible = true
				_signin_drawn_fetched = Steam.signin_fetched
			else:
				# A half-written PNG caught mid-rotation. The stamp is NOT
				# recorded, so the next poll tries the finished file rather than
				# believing this one was drawn.
				ShellLog.warn("steam: could not load %s" % qr)

	if status == "approved":
		var who := Steam.signin_persona
		var line := ("Signed in as %s" % who) if not who.is_empty() else "Signed in"
		# THE KNOWN LIMIT, said here rather than papered over. "approved" now
		# means BOTH scans landed -- downloads token and library token, see the
		# contract's sign-in section -- but Valve's client keeps its own
		# account, and a game with Steam DRM will not start until the client has
		# signed in once itself. Only said when it applies.
		if not Steam.signin_client_signed_in:
			line += ". The Steam client itself still needs its own one-time sign-in before a game will start."
		_signin_line.text = line
		_signin_line.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	elif Steam.state == "offline" and (status.is_empty() or status == "starting"):
		# The service answers an offline sign-in through the STATE file and leaves
		# signin.json alone -- there is no session to narrate -- so without this
		# the panel would say "Getting a code" forever on a machine with no
		# network. Same first-class-render rule as the shelf.
		_signin_line.text = "No network -- signing in needs one"
		_signin_line.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	else:
		_signin_line.text = str(SIGNIN_LINES.get(status, SIGNIN_LINES[""]))
		_signin_line.add_theme_color_override("font_color",
			TvTheme.TEXT_ALERT if SIGNIN_RETRY_STATES.has(status) else TvTheme.TEXT_SECONDARY)

	# A DEAD CODE COMES OFF THE SCREEN. The picture is still on disk when a
	# challenge expires -- the service replaces the file rather than deleting it
	# -- and leaving it up would invite somebody to walk over with a phone and
	# scan something that cannot work, which is a worse failure than an empty
	# frame because it looks like the machine is fine. The stamp is reset so the
	# next published code is drawn even if the service reuses one.
	if SIGNIN_RETRY_STATES.has(status):
		_signin_qr.visible = false
		_signin_drawn_fetched = -1

	# Focusable only when A would do something new -- see _build_signin. Hidden
	# rather than disabled: a disabled Button is unfocusable in Godot, so the
	# focus would sit on a control the ring is drawn around and nothing else,
	# and hiding is the state this row should actually be in.
	_signin_row.visible = SIGNIN_RETRY_STATES.has(status)
	if _signin_row.visible:
		_signin_row.set_name_text("New code")
		_signin_row.set_value("Ask Steam for another one")

	# WHAT THE PANE ACTUALLY DREW, for the invisible harness -- the status word
	# and whether a code is up, never the persona.
	ShellLog.info("steam sign-in: %s, %s"
		% [status if not status.is_empty() else "starting",
			"code on screen" if _signin_qr.visible else "no code"])


func _render_account_line() -> void:
	# Only where it is a fact about something: on a machine with no client, or
	# with nobody signed in, a line about the account would be a caption on an
	# absence. The sign-in pane says its own sentence.
	_account_line.visible = _view == VIEW_LIBRARY
	if not _account_line.visible:
		return
	_account_line.text = ("Signed in as %s" % Steam.account_persona) \
		if not Steam.account_persona.is_empty() else "Signed in"


func _render_library() -> void:
	if _library_signature != _current_signature():
		_rebuild_grid()

	var have := not _tiles.is_empty()
	_library_scroll.visible = have
	_library_status.visible = not have
	if have:
		return

	var state := Steam.state
	var line := str(LIBRARY_STATE_LINES.get(state, LIBRARY_STATE_LINES["unknown"]))
	# `failed` is the one word whose detail is a REASON rather than the name of
	# the request -- "no token", "sign in again", "no answer" -- and it is the
	# only thing on screen that could tell somebody which of those happened.
	if state == "failed" and not Steam.detail.is_empty():
		line = "%s -- %s" % [line, Steam.detail]
	_library_status.text = line
	_library_status.add_theme_color_override("font_color",
		TvTheme.TEXT_ALERT if LIBRARY_ALERT_STATES.has(state) else TvTheme.TEXT_SECONDARY)


## APPIDS ONLY, and deliberately not the states. A tile updates its own state
## line in place (see steam_tile.refresh_state), so a download's percentage
## moving must NOT change this string -- if it did, the shelf would be rebuilt
## every two seconds for the whole length of a download and the person would
## lose their place every time the number moved.
func _current_signature() -> String:
	var signature := ""
	for item in Steam.library_items():
		signature += "%d," % int(item.get("appid", 0))
	return signature


func _rebuild_grid() -> void:
	_library_signature = _current_signature()

	for tile in _tiles:
		_library_grid.remove_child(tile)
		tile.queue_free()
	_tiles = []
	_tile_rows = []

	var row: Array = []
	for item in Steam.library_items():
		var tile := SteamTile.new()
		tile.setup_item(item)
		tile.opened.connect(_on_tile_opened)
		tile.focus_entered.connect(_refresh_hints)
		_library_grid.add_child(tile)
		_tiles.append(tile)
		row.append(tile)
		if row.size() == TvTheme.STEAM_GRID_COLUMNS:
			_tile_rows.append(row)
			row = []
	if not row.is_empty():
		_tile_rows.append(row)

	_wire_grid_neighbours()
	ShellLog.info("steam library: %d game(s) in %d row(s)" % [_tiles.size(), _tile_rows.size()])


## Rows and columns, hard stops at every edge.
##
## NO DOORWAY, and that is a decision rather than an omission: the storefront's
## grid had one because it sat beside a column of tabs, and there is nothing
## beside this one. Left off the first column points at the tile itself so
## Control's geometric search cannot wander out of the grid into the hint row or
## into whatever a future version puts above it.
func _wire_grid_neighbours() -> void:
	var count := _tile_rows.size()
	for index in count:
		var row: Array = _tile_rows[index]
		var above: Array = _tile_rows[index - 1] if index > 0 else row
		var below: Array = _tile_rows[index + 1] if index + 1 < count else row

		for column in row.size():
			var tile: Control = row[column]
			# Clamped rather than wrapped: a short last row must not send the
			# selection to a column that does not exist there, and landing on the
			# nearest tile is what a person expects from pressing down.
			tile.focus_neighbor_top = tile.get_path_to(above[mini(column, above.size() - 1)])
			tile.focus_neighbor_bottom = tile.get_path_to(below[mini(column, below.size() - 1)])
			tile.focus_neighbor_left = tile.get_path_to(
				row[column - 1] if column > 0 else tile)
			tile.focus_neighbor_right = tile.get_path_to(
				row[column + 1] if column + 1 < row.size() else tile)


## Rebuilt rather than relabelled: TvTheme.hint returns an assembled badge and
## caption and does not hand back the caption to edit, and a row of two or three
## children is cheap enough that reaching into its internals to save a couple of
## node allocations would be the worse trade.
##
## Takes no argument and is connected to every tile's focus_entered as well:
## what A does depends on the tile under the ring, so the row has to follow the
## selection rather than the screen.
func _refresh_hints() -> void:
	if _hints == null:
		return
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()

	match _view:
		VIEW_SIGNED_OUT:
			_hints.add_child(TvTheme.hint("A", "Sign in"))
		VIEW_SIGNIN:
			# Advertised only while the row exists -- while a live code is up the
			# next move is on somebody's phone and the pad's only job is B.
			if _signin_row != null and _signin_row.visible:
				_hints.add_child(TvTheme.hint("A", "New code"))
		VIEW_LIBRARY:
			var tile := _focused_tile()
			if tile != null:
				_hints.add_child(TvTheme.hint("A", _tile_verb(tile)))
				if not _menu_items_for(tile).is_empty():
					_hints.add_child(TvTheme.hint("OPTIONS", "Options"))
		_:
			pass
	_hints.add_child(TvTheme.hint("B", "Back"))


## What A does on the tile under the ring, NAMED rather than called "Select".
## The settings screen uses the vaguer word because its rows do five different
## things and the hint row cannot know which is lit; here it can, and "Play" over
## a game that is installed is worth more than a word that is always true.
func _tile_verb(tile: SteamTile) -> String:
	match Steam.item_state(int(tile.item.get("appid", 0))):
		"installed":
			return "Play"
		"queued", "downloading", "installing":
			return "Options"
		_:
			return "Install"


func _view_name() -> String:
	match _view:
		VIEW_ABSENT:
			return "Steam is not installed yet"
		VIEW_SIGNED_OUT:
			return "not signed in"
		VIEW_SIGNIN:
			return "signing in"
		_:
			return "library"


# ---------------------------------------------------------------------------
# Focus
# ---------------------------------------------------------------------------

## The rail's lesson, and the reason it is a function rather than a line in
## _ready: nothing navigates until something is focused, and this screen changes
## what IS focusable underneath the person -- a code expires and grows a row, a
## library arrives and replaces a status line with a grid.
##
## Deliberately does nothing while something focusable on this screen already
## has the ring: a render happens every two seconds, and a version of this that
## grabbed unconditionally would walk the selection back to the first tile while
## somebody was still moving through the shelf.
func _ensure_focus() -> void:
	# Not `owner`: Node already has a property by that name, and a local
	# shadowing it is the kind of warning that reads as noise until the day
	# somebody writes to it.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused) and focused.is_visible_in_tree():
		return

	if _view == VIEW_LIBRARY and not _tiles.is_empty():
		var first: Control = _tiles[0]
		first.grab_focus()
		return
	if _signin_row != null and _signin_row.is_visible_in_tree():
		_signin_row.grab_focus()
	# Otherwise NOTHING IS FOCUSED, on purpose. The first-boot page and a live
	# code panel have nothing anybody can press, and a ring drawn around a
	# paragraph would be the screen advertising a control it does not have. B
	# still closes: _unhandled_input does not need a focus owner.


## The tile under the ring, or null.
##
## Typed as the SCRIPT rather than as Control, and asked by membership rather
## than by `is`: callers read `tile.item`, and GDScript resolves a member against
## the STATIC type -- a Control-typed variable would fail to parse on `.item`,
## which is the same rule settings_screen.gd's ActionRow-typed fields exist for.
## Membership in _tiles is also the exact question ("is the ring on one of MY
## tiles"), where a type test would answer yes for a tile belonging to a screen
## that had not been torn down yet.
func _focused_tile() -> SteamTile:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _tiles.has(focused):
		return focused as SteamTile
	return null


# ---------------------------------------------------------------------------
# Acting
# ---------------------------------------------------------------------------

func _on_signin_row_pressed() -> void:
	_signin_open = true
	# Safe to press repeatedly by the contract's own guarantee: a `signin`
	# arriving while a job is live re-publishes the current challenge rather than
	# starting a second session.
	Steam.request_signin()
	_render()


## A on a game, and it means three different things because a game is in one of
## three situations. NOTHING HERE IS A DEAD BUTTON -- that is the whole rule this
## function is written to: a press must always be worth making.
##
##   INSTALLED     play it, through the launch seam like every other launch in
##                 this shell.
##   IN FLIGHT     open the menu, whose one row cancels. A press on a download
##                 has nothing to start and something obvious to ask about.
##   ANYTHING ELSE ask for the download. A failed one included: retrying is what
##                 somebody looking at "Download failed" is reaching for.
func _on_tile_opened(item: Dictionary) -> void:
	var appid := int(item.get("appid", 0))
	match Steam.item_state(appid):
		"installed":
			_launch(item)
		"queued", "downloading", "installing":
			_open_menu(item)
		_:
			Steam.request_install(appid)
			# The tile's line follows the seam rather than this press: the
			# service answers within a poll and an optimistic "Downloading" here
			# would be the shell claiming something root has not agreed to yet.
			_refresh_hints()


## Start a game.
##
## THROUGH THE LAUNCH SEAM, and through the INSTALLED SEAM'S OWN ENTRY where
## there is one. marwanos-appscan reads the appmanifest our downloader wrote and
## publishes the same `steam.<appid>` record the home rail launches from, so a
## game started here and the same game started from the rail run the identical
## command line -- and launcher.gd's handoff machinery (which watches the WINDOW
## rather than the pid, because the flatpak wrapper exits in a second) already
## knows what to do with that id.
##
## THE FALLBACK IS A GUESS AND IS MARKED AS ONE. Between our downloader
## finishing and the scanner's next pass there is a window where a game is
## installed and has no record, and a Play button that answered "not yet" for
## those seconds would be the worst kind of wrong -- so the entry is built from
## the contract's own tier-1 command. If the scanner's exec ever diverges from
## it, this is the line that is stale.
func _launch(item: Dictionary) -> void:
	if Launcher.is_busy():
		ShellLog.info("steam: something is already running; ignoring the launch")
		return
	Launcher.launch(_launch_entry(item))


func _launch_entry(item: Dictionary) -> Dictionary:
	var appid := int(item.get("appid", 0))
	var id := "%s%d" % [Steam.INSTALLED_PREFIX, appid]
	for app in Installed.apps:
		if str(app.get("id", "")) == id:
			return app
	ShellLog.warn(("steam: %s is installed and the scanner has no record of it yet;"
		+ " starting it through the client directly") % id)
	return {
		"id": id,
		"title": str(item.get("name", "")),
		"exec": [
			"flatpak", "run", "com.valvesoftware.Steam",
			"-silent", "steam://rungameid/%d" % appid,
		],
	}


## The options menu, over the shelf. The rows depend on what the game is doing,
## and an empty list means the button is not offered at all rather than opening
## a panel with nothing in it.
func _menu_items_for(tile: SteamTile) -> Array:
	match Steam.item_state(int(tile.item.get("appid", 0))):
		"queued", "downloading", "installing":
			return [CANCEL_ITEM]
		"failed":
			return [CLEAR_ITEM]
		"installed":
			return [UNINSTALL_ITEM]
		_:
			return []


func _open_menu(item: Dictionary) -> void:
	if _menu != null or Launcher.is_busy():
		return
	var tile := _focused_tile()
	if tile == null:
		return
	var items := _menu_items_for(tile)
	if items.is_empty():
		ShellLog.info("steam: nothing to offer for %s" % str(item.get("name", "")))
		return

	_menu_item = item
	_menu = ListMenu.new()
	_menu.title_text = str(item.get("name", ""))
	_menu.items = items
	_menu.note_text = UNINSTALL_NOTE if str(items[0]["id"]) == "uninstall" else CANCEL_NOTE
	_menu.chosen.connect(_on_menu_chosen)
	_menu.closed.connect(_on_menu_closed, CONNECT_ONE_SHOT)
	# Deaf while the menu is up: the menu is a later sibling and consumes what it
	# handles, but this screen must not be one reparent away from B doing two
	# things at once.
	set_process_unhandled_input(false)
	get_tree().root.add_child(_menu)


func _on_menu_chosen(id: String) -> void:
	var appid := int(_menu_item.get("appid", 0))
	match id:
		"cancel":
			Steam.request_cancel(appid)
		"uninstall":
			Steam.request_uninstall(appid)
		_:
			ShellLog.error("steam menu item \"%s\" has no action" % id)


func _on_menu_closed() -> void:
	_close_menu.call_deferred()


func _close_menu() -> void:
	if _menu == null:
		return
	var menu := _menu
	_menu = null
	_menu_item = {}
	menu.get_parent().remove_child(menu)
	menu.queue_free()
	set_process_unhandled_input(true)
	# The menu's own row took the focus; without this the shelf comes back
	# ringless and dead-looking.
	_ensure_focus()
	_refresh_hints()


# ---------------------------------------------------------------------------
# Listening
# ---------------------------------------------------------------------------

func _on_steam_changed(_state: String) -> void:
	_render()


func _on_installed_changed(_apps: Array) -> void:
	# The client arriving or leaving changes which of the four this screen is,
	# and a game arriving or leaving changes what A does on its tile.
	_render()
	_refresh_tiles()


func _on_state_changed(_state: String, _detail: String) -> void:
	_render()


func _on_account_changed(_signed_in: bool, _persona: String) -> void:
	_render()


func _on_library_changed(_items: Array) -> void:
	_render()
	# The pictures, for the tiles that already existed: on a cold machine the
	# list lands seconds before the JPEGs, and a tile built in that gap would
	# stay a wash for the rest of the session.
	_refresh_tiles()


func _on_downloads_changed(_items: Array) -> void:
	_refresh_tiles()
	# The A hint names what the focused tile can do, and a download starting or
	# finishing changes that under a resting thumb.
	_refresh_hints()


## The scan moving. Only the panel redraws unless it ended in an approval, in
## which case who is signed in and what they own are both newly askable -- and
## the shelf builds behind the panel, so it is already there when B returns.
func _on_signin_changed(status: String, _persona: String, _client: bool) -> void:
	if _view == VIEW_SIGNIN or _view == VIEW_SIGNED_OUT:
		_render()
	if status == "approved":
		Steam.request_account()
		Steam.request_library()


func _refresh_tiles() -> void:
	for tile in _tiles:
		tile.refresh_state()
		tile.refresh_art()


## Ask for the library again, but only while pictures are still missing. See
## ART_REFETCH_SECONDS: the service pages artwork twenty-four appids at a time,
## so a big library needs several requests to finish drawing and a finished one
## must cost nothing.
func _on_art_timer() -> void:
	if _view != VIEW_LIBRARY or _tiles.is_empty():
		return
	for tile in _tiles:
		if not tile.has_art():
			Steam.request_library()
			return


## Off the screen for as long as something is running on it. See the header for
## why this hides rather than going deaf.
func _on_launch_started(_entry: Dictionary) -> void:
	hide()
	# The second half a hide does not cover: input callbacks are not gated on a
	# Control's visibility, so an invisible screen still hears every button --
	# and B is the press that proves it.
	set_process_unhandled_input(false)


func _on_launch_finished(_entry: Dictionary) -> void:
	show()
	if _menu == null:
		set_process_unhandled_input(true)
	# Nothing is focused after a hide, and a shelf with no focus owner is a shelf
	# the pad cannot move.
	_ensure_focus()
	_refresh_hints()


func _unhandled_input(event: InputEvent) -> void:
	# OPTIONS acts on the game under the ring, so it is offered only where there
	# is one and only where it has something to offer -- a button that opens an
	# empty panel is worse than a button that does nothing.
	if event.is_action_pressed("ui_shell_options"):
		if _view != VIEW_LIBRARY:
			return
		var tile := _focused_tile()
		if tile == null:
			return
		get_viewport().set_input_as_handled()
		_open_menu(tile.item)
		return

	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath -- hidden until the seam restores it --
	# never sees the same press as a second back-out.
	get_viewport().set_input_as_handled()

	# THE CODE PANEL IS A LEVEL OF ITS OWN and B unwinds it to the sign-in row
	# rather than off the screen. The service's session keeps running on purpose:
	# somebody who scans and then backs out is still mid-sign-in, and the
	# approval landing a moment later is a success rather than a surprise -- the
	# account line and this whole screen pick it up through account_changed.
	if _view == VIEW_SIGNIN:
		_signin_open = false
		_render()
		ShellLog.info("steam sign-in panel closed")
		return

	closed.emit()
