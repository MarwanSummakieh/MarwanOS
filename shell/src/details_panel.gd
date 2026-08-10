extends Control

## What a card IS, and one button that starts it.
##
## DOWN from a focused rail card slides this sheet up over the lower part of the
## home screen. It exists because the rail can only ever say two lines about an
## entry -- a title and a subtitle that is really a state -- and a library of
## games in which nothing describes the games is a wall of pictures. The
## description is the whole point of the panel; the Play button is there because
## a screen about a thing that cannot start the thing sends the person back to
## the card to press A, which is a worse flow than the one they already had.
##
## THE TOP OF THE SURFACE IS LEFT ALONE, on purpose. What is up there is the
## game's own background art (see shell_root._on_card_selected), which is the
## thing pressing down was in aid of; a fullscreen panel would cover the answer
## with the question. What the sheet DOES cover is everything the home screen was
## already saying -- the title block, the rail and the hint row -- because a
## panel that restates a title with half of the old one still showing above it
## reads as a broken draw rather than as a panel; see
## TvTheme.DETAILS_PANEL_HEIGHT, which is set by exactly that. It is also why
## this is a child of the home screen rather than a surface of its own like the
## stores or settings screens: nothing was handed over, the rail is simply
## covered.
##
## PLAY IS THE ONLY BUTTON, and "Store page" was considered and left out. It
## would have been the second item in a family whose entire navigation argument
## is that a rail has one axis, on a panel opened by a person who is looking at
## a game they own and pressed down to read about it; steam://url/StoreAppPage
## reaches the storefront for something already installed, which is the least
## likely thing to be wanted here. One button also means one focusable, which is
## why the neighbour table below is four hard stops and nothing else. If a second
## button ever earns its place, it goes in _build's row and gets a real left and
## right -- the panel is a column of one row today, not a design that forbids
## two.
##
## THE PRESS IS THE CARD'S, NOT THIS PANEL'S. Play asks shell_root to activate
## the card it was opened from (Tile.activate), so the policy about what an A
## press means -- refuse a pending app, install an available one, launch an
## installed one -- stays in the one file that has always owned it.

## Play was chosen. The panel does not launch anything itself; see the header.
signal play_requested()

## B, or UP: the panel is done and the rail should come back.
signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Catalogue = preload("res://src/catalogue.gd")
const ActionRow = preload("res://src/action_row.gd")

## Same prefix, same meaning as tile.gd's and shell_root's.
const STEAM_PREFIX := "steam."

var entry: Dictionary = {}

var _sheet: PanelContainer = null
var _play: ActionRow = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build()
	_wire_focus_neighbours()
	_slide_in()

	# Focused immediately rather than when the slide lands: the sheet is moving
	# for a quarter of a second and a person who pressed down and then A must not
	# have the A go somewhere else. The ring rides up with the button.
	if _play != null:
		_play.grab_focus()

	ShellLog.info("details panel up for %s" % str(entry.get("title", "<unknown>")))


func _build() -> void:
	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", TvTheme.details_sheet_box())
	# Bottom-wide by hand rather than by preset, so the offsets are the ones
	# stated here: the sheet is anchored to the BOTTOM edge and given a fixed
	# height, which is what makes _slide_in a single position tween.
	_sheet.anchor_left = 0.0
	_sheet.anchor_right = 1.0
	_sheet.anchor_top = 1.0
	_sheet.anchor_bottom = 1.0
	_sheet.offset_top = -TvTheme.DETAILS_PANEL_HEIGHT
	_sheet.offset_bottom = 0.0
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sheet)

	# The horizontal inset is the TV-safe margin, not the panel padding the card
	# menu uses: this sheet spans the whole output, so its text is subject to the
	# same overscan as the title block it slides over -- and lining up with that
	# block is what makes the panel read as the same screen rather than a dialog.
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	pad.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_PAGE_PAD)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_PAGE_PAD)
	_sheet.add_child(pad)

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

	# Wrapped rather than ellipsised, unlike every other line in this shell: this
	# is the one place a paragraph is the content. Steam's short_description runs
	# to two or three lines at SIZE_BODY across the safe width, and the sheet was
	# sized with room for four.
	var description := Label.new()
	description.text = _description()
	description.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	description.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(description)

	# The button lives in a row with the slack after it, so it takes a stated
	# width instead of the sheet's -- see TvTheme.DETAILS_BUTTON_WIDTH.
	var actions := HBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	column.add_child(actions)

	_play = ActionRow.new()
	# NO ICON. The row family takes one and the diagnostic rows already go
	# without; the alternative here is a Phosphor codepoint chosen by eye, and a
	# wrong codepoint renders as a tofu box on the one button of the panel.
	_play.setup(_play_label(), "")
	_play.activated.connect(_on_play)
	actions.add_child(_play)
	# AFTER add_child, because settings_row's own _ready sets both of these for a
	# full-width column of rows and _ready runs on entering the tree.
	_play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_play.custom_minimum_size = Vector2(
		TvTheme.DETAILS_BUTTON_WIDTH, TvTheme.SETTINGS_ROW_HEIGHT)

	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", _play_label()))
	hints.add_child(TvTheme.hint("B", "Back"))
	column.add_child(hints)


## PLAY for a game, OPEN for everything else.
##
## The rail is a library and most of it is games, but it also holds Kodi and a
## browser, and "Play" on a browser is the shell using a word it borrowed from a
## console without checking what it was pointing at. The hint row already says
## "Open" for the same press on a card, so this is the panel agreeing with the
## screen it slid over.
func _play_label() -> String:
	return "Play" if str(entry.get("id", "")).begins_with(STEAM_PREFIX) else "Open"


## WHAT THE THING IS, from the best source that has an answer.
##
##   1. Steam's own words for a game. short_description is the sentence on the
##      store page under the title -- written to say what a game is to somebody
##      who has not played it, which is exactly this panel's question.
##   2. The catalogue's tagline for a shipped flatpak. Hand-written, one line,
##      and the only description this project has ever had for Kodi or a browser.
##   3. The record's own subtitle, last. For an installed application that is the
##      desktop entry's Comment field, which ranges from a useful sentence to the
##      application's own name again -- true, occasionally useless, and better
##      than an empty panel.
##
## An entry with none of the three gets a stated sentence rather than a blank
## space, because a panel that is a title and a button with a hole between them
## reads as a screen that failed to load.
## WHICH SOURCE ANSWERED IS SAID IN THE JOURNAL, because on this machine the
## difference between "Steam's metadata has not been fetched for this game" and
## "the panel is not reading it" is otherwise a thing you can only photograph --
## and both of them look like a card's own subtitle on the TV.
func _description() -> String:
	var id := str(entry.get("id", ""))

	var steam := Catalogue.steam_description(id)
	if not steam.is_empty():
		ShellLog.info("details: description for %s from steam metadata" % id)
		return steam

	var tagline := Catalogue.tagline_for(id)
	if not tagline.is_empty():
		ShellLog.info("details: description for %s from the catalogue tagline" % id)
		return tagline

	var subtitle := str(entry.get("subtitle", ""))
	if not subtitle.is_empty():
		ShellLog.info("details: description for %s from the record's own comment" % id)
		return subtitle

	ShellLog.info("details: nothing describes %s" % id)
	return "No description for this one yet."


## ONE FOCUSABLE, FOUR HARD STOPS. Every direction points the button at itself,
## so the viewport's geometric search can never find the rail underneath the
## sheet -- which is drawn behind the panel and would take the focus ring with it
## if left findable. UP is not a neighbour either: it CLOSES, and _input is where
## that is caught, for the reason given there.
func _wire_focus_neighbours() -> void:
	if _play == null:
		return
	_play.focus_neighbor_top = _play.get_path_to(_play)
	_play.focus_neighbor_bottom = _play.get_path_to(_play)
	_play.focus_neighbor_left = _play.get_path_to(_play)
	_play.focus_neighbor_right = _play.get_path_to(_play)


## Slides the sheet up from below the screen.
##
## The tween is on `position`, which for an anchored control moves both offsets
## and leaves the size alone -- so the sheet keeps the height _build gave it and
## simply starts a sheet's height lower, which is off the bottom of the output.
func _slide_in() -> void:
	var rest := _sheet.position.y
	_sheet.position.y = rest + TvTheme.DETAILS_PANEL_HEIGHT

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sheet, "position:y", rest, TvTheme.DETAILS_SLIDE_SECONDS)


func _on_play() -> void:
	ShellLog.info("details panel: %s for %s"
		% [_play_label().to_lower(), str(entry.get("id", ""))])
	play_requested.emit()


## UP CLOSES, AND IT HAS TO BE CAUGHT HERE RATHER THAN IN _unhandled_input.
##
## The panel's one button is a hard stop on all four sides, and a hard stop is
## not an ignored press: the viewport resolves the neighbour to the button
## itself, grabs focus on it and marks the event handled, several steps before
## any _unhandled_input runs. That is the same rule that made DOWN look dead on
## the rail (see tile.gd). `_input` is the hook that runs BEFORE the viewport's
## GUI phase, so it is the only place the press is still available -- and it is
## made specific to this action so nothing else about input changes while the
## panel is up.
##
## Symmetry is the point: down opened it, up closes it, and the panel goes back
## the way it came.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_up"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	closed.emit()
