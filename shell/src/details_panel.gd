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
## The catalogue is not preloaded here any more: every question this panel used
## to ask it -- the Steam description, the hand-written tagline -- is now one
## source among several inside GameMeta, which is the file that knows the order
## they go in.
const GameMeta = preload("res://src/gamemeta.gd")
const ActionRow = preload("res://src/action_row.gd")

## Same prefix, same meaning as tile.gd's and shell_root's.
const STEAM_PREFIX := "steam."

## HOW MANY OF A REPEATING FIELD REACH THE FACT ROW. Genres and developers are
## arrays and Valve puts no ceiling on either -- a compilation can carry six
## genres and four studios, which at SIZE_SUPPLEMENTAL is a row wider than the
## output. The row squeezes its labels when that happens rather than wrapping,
## so every fact gets shorter to make room for one nobody needed. Three genres
## and two studios is the point where the row still says the useful thing.
const MAX_GENRES := 3
const MAX_DEVELOPERS := 2

## What sits between two facts on the row. Four spaces rather than a separator
## character -- see the fact row's own comment in _build for why this shell
## spends no codepoints it has not seen render.
const FACT_SEPARATOR := "    "

## THE FEATURES WORTH A TEN-FOOT SCREEN, out of the twenty-odd Steam publishes
## as categories. gamemeta hands the list over whole and deliberately does not
## choose (see its `features` branch); this is where the choosing happens,
## because it is a question about a panel rather than about a game.
##
## CONTROLLER SUPPORT AND NOTHING ELSE, which is a short list with a long
## reason. This appliance's entire premise is that the only input is a pad --
## the acceptance criterion for the whole store milestone is "keyboard
## unplugged" -- so "Full controller support" is the one category that changes
## what happens when the person presses Play. "Steam Cloud", "Steam
## Achievements", "Remote Play on TV" and the rest are true, and are noise on a
## screen whose job is to say what a game is.
##
## Matched exactly against Valve's own strings rather than by substring: the two
## live entries differ by one word, and "Partial Controller Support" contains
## neither more nor less truth than a `contains("Controller")` would find in a
## future category nobody has read.
const SHOWN_FEATURES := [
	"Full controller support",
	"Partial Controller Support",
]

var entry: Dictionary = {}

## The merged metadata record for `entry`, resolved once in _build and read by
## the three functions that draw from it. Resolving per-drawer would re-open and
## re-parse Steam's cached document once per line on the screen.
var _meta: Dictionary = {}

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
	# Before anything is drawn, because the title, the description and the fact
	# row all read from it. See GameMeta for what "resolve" means here -- it is
	# a walk over a table of fields, not a fetch.
	_meta = GameMeta.resolve(entry)

	# THE WHOLE RESOLUTION IN ONE LINE, for the reason _description's own log
	# line exists and generalised to every field at once: on this machine a
	# panel with no fact row and a panel whose fact row failed to draw are the
	# same photograph, and the sources map is the only thing that can tell them
	# apart afterwards. It is one line per panel open, which is one line per
	# deliberate button press.
	ShellLog.info("details: %s resolved %s"
		% [str(entry.get("id", "")), str(_meta.get("sources", {}))])

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
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(description)

	# WHAT THE THING IS, in the fields Playnite would have downloaded. Added
	# only when something answered: a game whose metadata has not been fetched
	# yet, and every application that has no store page at all, draw the panel
	# exactly as it was before this row existed rather than an empty band where
	# a row would be.
	#
	# ONE LABEL, NOT A ROW OF THEM, and it was the other way round until the
	# harness drew it. The obvious build is an HBoxContainer with a Label per
	# fact and HINT_GAP between them -- the shape the hint row below already
	# uses -- and it renders NOTHING. A Label that is allowed to trim reports a
	# minimum width of zero, because being shrinkable is the whole point of
	# trimming; five such Labels in a row with no expand flag are five controls
	# the container is free to give zero width to, and it does. The facts were
	# all there and all resolved, and the panel had an invisible band where they
	# should have been -- which is exactly the failure this file's logging
	# philosophy exists to catch, and it took a screenshot to catch it.
	#
	# A single Label fills the column's width, so trimming has something to trim
	# against and the ellipsis lands at the end of the line instead of at the
	# start of every field.
	#
	# SEPARATED BY SPACES RATHER THAN A GLYPH. The natural separator is a middle
	# dot and this shell has no non-ASCII character anywhere in it -- the Play
	# button a few lines below goes without an icon for exactly this reason,
	# because a codepoint the font does not carry renders as a tofu box on the
	# one screen nobody can inspect. The gap is wider than a word space so it
	# cannot be read as one, and the commas inside a field (genres, studios) are
	# what keep the two levels apart.
	var facts := _fact_texts()
	if not facts.is_empty():
		var fact_row := Label.new()
		fact_row.text = FACT_SEPARATOR.join(facts)
		fact_row.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
		fact_row.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		fact_row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		fact_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(fact_row)

	# THE SLACK LIVES HERE NOW, and it used to live on the description. Giving
	# the description SIZE_EXPAND_FILL made its BOX absorb the column's spare
	# height while its text stayed at the top of that box -- invisible when the
	# description was the last thing above the button, and wrong the moment a
	# fact row followed it, because the row got pushed to the bottom of the
	# sheet and read as belonging to the Play button rather than to the sentence
	# it qualifies. An empty Control taking the slack puts the two halves of
	# "what this is" together and leaves Play where it has always been.
	#
	# With no fact row this draws exactly what it drew before: text at the top,
	# button at the bottom, one expanding thing between them either way.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

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
## THE THREE-TIER CHAIN THIS FUNCTION USED TO BE IS NOW A ROW IN A TABLE, and
## nothing about which source wins has changed -- Steam's short_description,
## then the catalogue's hand-written tagline, then the record's own subtitle.
## See GameMeta.FIELDS, where that order is now written down next to the order
## for every other field, and GameMeta's header for why a per-field chain is the
## thing worth copying from Playnite.
##
## An entry no source could answer gets a stated sentence rather than a blank
## space, because a panel that is a title and a button with a hole between them
## reads as a screen that failed to load. That sentence stays here rather than
## moving with the chain: it is display copy for an empty screen, not a fact
## about the game, and a resolver that invented one would be lying to every
## other caller.
##
## WHICH SOURCE ANSWERED IS SAID IN THE JOURNAL, because on this machine the
## difference between "Steam's metadata has not been fetched for this game" and
## "the panel is not reading it" is otherwise a thing you can only photograph --
## and both of them look like a card's own subtitle on the TV. It is the
## resolver's sources map that is being read out now, so the line names the
## source that won by the same name the table uses.
func _description() -> String:
	var id := str(entry.get("id", ""))

	if _meta.has("description"):
		var sources: Dictionary = _meta.get("sources", {})
		ShellLog.info("details: description for %s from %s"
			% [id, str(sources.get("description", "?"))])
		return str(_meta["description"])

	ShellLog.info("details: nothing describes %s" % id)
	return "No description for this one yet."


## The fact row's contents, in order, already trimmed to what fits.
##
## ORDER IS PRIORITY, because the row squeezes rather than wraps: an
## HBoxContainer whose children do not fit shrinks them all, and each label
## ellipsises what it cannot show. So the fields go in descending order of how
## much they say about a game somebody is deciding whether to start, and the
## ones that lose characters first are the ones at the end.
##
## EVERY ENTRY IS CONDITIONAL, and a game with no cached metadata produces an
## empty array -- which is what makes the row disappear in _build rather than
## drawing a band of nothing.
func _fact_texts() -> Array:
	var texts: Array = []

	var genres: Array = _meta.get("genres", [])
	if not genres.is_empty():
		texts.append(", ".join(genres.slice(0, MAX_GENRES)))

	var released := str(_meta.get("release_date", ""))
	if not released.is_empty():
		texts.append(released)

	var developers: Array = _meta.get("developers", [])
	if not developers.is_empty():
		texts.append(", ".join(developers.slice(0, MAX_DEVELOPERS)))

	# PUBLISHERS ONLY WHEN THEY ARE SOMEBODY ELSE. Self-published games are most
	# of an indie library and Valve lists the same studio in both arrays, so an
	# unconditional publisher field would print "Team Cherry" twice in one row
	# and look like a rendering fault rather than a fact.
	var publishers: Array = _meta.get("publishers", [])
	if not publishers.is_empty() and publishers != developers:
		texts.append(", ".join(publishers.slice(0, MAX_DEVELOPERS)))

	# Named rather than bare, because a lone "90" in a row of prose is not
	# self-describing at three metres.
	var score := int(_meta.get("critic_score", 0))
	if score > 0:
		texts.append("Metacritic %d" % score)

	for feature in _meta.get("features", []):
		if SHOWN_FEATURES.has(str(feature)):
			texts.append(str(feature))

	return texts


## ELLIPSISED RATHER THAN WRAPPED, unlike the description above it and for the
## opposite reason: the facts are one line, and a row that wrapped would be two
## lines tall and push the Play button off the bottom of a sheet whose height is
## fixed (TvTheme.DETAILS_PANEL_HEIGHT). That is why the row is built with the
## Label defaults for autowrap and an explicit overrun behaviour, and it is the
## one line of that block worth finding again.


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
