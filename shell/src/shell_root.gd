extends Control

## The home screen -- everything the appliance shows when nothing is launched.
##
## A console-style home: a full-bleed hero wash behind a top status bar, the
## selected entry's title, and a horizontal rail of cards with one enlarged
## selection. It replaced a 4x3 grid, and the reason is navigational rather than
## cosmetic. A grid has two axes, so "what does right do at the end of a row"
## has no answer a person can predict, and the previous version needed an
## explicit twelve-entry neighbour table to make it defensible. A rail has one
## axis: left and right are the only moves, the ends are hard stops, and there is
## nothing left to tabulate.
##
## THE SELECTION IS ANCHORED, NOT THE STRIP. The selected card sits at a fixed x
## and the rail slides underneath it. That is the property that stops the eye
## re-finding the cursor after every press, and it is why _scroll_to_selected
## moves the strip rather than moving a highlight.
##
## The whole layout is built in code rather than in a .tscn. Two reasons, both
## specific to this repo: a scene file is authored by a GUI tool that rewrites it
## on its own schedule (which is how CRLF and unreviewable diffs get into a repo
## that has spent real days on both), and Phase 1 M2 replaces this catalogue with
## a live list from marwand that has to be built at runtime anyway.

const TvTheme = preload("res://src/tv_theme.gd")
const Catalogue = preload("res://src/catalogue.gd")
const Tile = preload("res://src/tile.gd")
const IconButton = preload("res://src/icon_button.gd")
const AppOverlay = preload("res://src/app_overlay.gd")
const CardMenu = preload("res://src/card_menu.gd")
const Glyphs = preload("res://src/glyphs.gd")
const ErrorScreen = preload("res://src/error_screen.gd")

var _hero: ColorRect = null
var _title: Label = null
var _subtitle: Label = null
var _clock: Label = null
var _rail_viewport: Control = null
var _rail: HBoxContainer = null
var _status: Label = null
var _app_alert: Label = null
var _app_alert_timer: Timer = null
var _open_hint: Control = null
var _options_hint: Control = null
var _overlay: AppOverlay = null
var _card_menu: CardMenu = null
## The rail entry the cursor is on, kept because the card menu is opened from
## input handling rather than from the card itself.
var _selected_entry: Dictionary = {}
var _wifi: Glyphs = null
var _store_button: IconButton = null
var _gear_button: IconButton = null
var _power_button: IconButton = null

var _tiles: Array = []
var _last_focused: Control = null
var _rail_tween: Tween = null
var _hero_tween: Tween = null


func _ready() -> void:
	# The error mode branches before anything else in this file runs, and that
	# ordering is the whole point rather than a style choice. marwanos-session
	# starts this binary in error mode precisely because the normal path crashed
	# five times in sixty seconds -- so the frame it draws must not touch the
	# catalogue, the cards, the launcher or the rail, any one of which could be
	# what crashed. See error_screen.gd for what this does and does not protect
	# against.
	if ErrorScreen.requested():
		ShellLog.error("starting in ERROR SCREEN mode: the supervision loop gave up on the shell")
		add_child(ErrorScreen.build())
		return

	_build()
	_populate()
	_wire_focus_neighbours()
	_refresh_empty_state()

	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)
	Settings.settings_opened.connect(_on_surface_opened)
	Settings.settings_closed.connect(_on_surface_closed)
	Stores.stores_opened.connect(_on_surface_opened)
	Stores.stores_closed.connect(_on_surface_closed)
	Power.power_opened.connect(_on_surface_opened)
	Power.power_closed.connect(_on_surface_closed)
	PlayerOne.player_one_present.connect(_on_player_one_present)
	PlayerOne.player_one_absent.connect(_on_player_one_absent)
	SystemStatus.network_changed.connect(_on_network_changed)
	Installed.apps_changed.connect(_on_apps_changed)
	Apps.state_changed.connect(_on_apps_state_changed)
	_refresh_status()
	# SystemStatus polled once in its own _ready, which ran before this one, so
	# this is the current answer rather than a default -- the first frame the
	# TV shows already carries the wifi glyph if the machine has said Offline.
	_on_network_changed(SystemStatus.network)

	_start_clock()

	# Nothing navigates until something is focused: the viewport's directional
	# navigation starts from the current focus owner, and with none there is no
	# origin to move from. This is the single most common way a gamepad UI ships
	# looking dead.
	_ensure_focus()

	_log_rail_geometry()


## Says where the rail actually ended up, for the same reason Kiosk logs the
## window and screen geometry: this appliance has no console, so a layout that
## lands in the wrong place is otherwise a thing you can only photograph.
##
## The two numbers that matter are the rail band, which should span the whole
## output because the strip is full-bleed, and the selected card's left edge,
## which should sit on SAFE_MARGIN_X. They are different numbers on purpose --
## conflating them is exactly the bug this logging was added alongside, where the
## strip was clipped to the safe area and cards were cut off at an invisible
## interior line.
func _log_rail_geometry() -> void:
	# Deferred: containers have not laid out on the frame they are built, so
	# every rect read here would be zero.
	await get_tree().process_frame
	if not is_instance_valid(_rail_viewport) or _tiles.is_empty():
		return

	var band := _rail_viewport.get_global_rect()
	ShellLog.info("rail band: x %.0f..%.0f (width %.0f), height %.0f"
		% [band.position.x, band.end.x, band.size.x, band.size.y])

	var first: Control = _tiles[0]
	ShellLog.info("first card rests at x %.0f (safe margin is %d)"
		% [first.get_global_rect().position.x, TvTheme.SAFE_MARGIN_X])


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The hero wash: the selected entry's accent, full bleed, heavily dimmed. It
	# stands in for the key art Phase 1 will load, and it deliberately bleeds past
	# the TV-safe inset -- background may overscan, text may not.
	_hero = ColorRect.new()
	_hero.color = TvTheme.BACKGROUND
	_hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)

	# Darkens the lower part of the surface so the title and rail keep their
	# contrast whatever the accent is. Anchored to the bottom and given a
	# fraction of the height rather than a pixel count, so it scales with the
	# output the same way every other measurement here does.
	var scrim := TextureRect.new()
	scrim.texture = TvTheme.hero_gradient()
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.anchor_top = 1.0 - TvTheme.HERO_GRADIENT_FRACTION
	scrim.offset_top = 0.0
	scrim.offset_bottom = 0.0
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# THE VERTICAL TV-SAFE INSET ONLY. The horizontal one is applied per row by
	# _inset(), and the rail is deliberately the one row that does not get it.
	#
	# It used to be applied here, to everything at once, and that produced the
	# defect this structure exists to fix: the rail's clip_contents clipped to
	# this container's rect, so cards were guillotined at an invisible line 96 px
	# in from each screen edge with empty background beyond it. A card has to
	# leave the screen at the SCREEN's edge or the eye reads the cut as damage.
	#
	# The rail is background-class furniture, like the hero and the scrim above
	# it: it may bleed. What must stay inside the safe area is the SELECTED card
	# -- which is where the focus ring is and the only card anyone is reading --
	# and that is handled by resting the selection at SAFE_MARGIN_X in
	# _scroll_to_selected rather than by clipping the strip it sits on.
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)

	column.add_child(_inset(_build_topbar()))

	# Pushes everything below it to the bottom of the surface. The rail sitting
	# low is not a style choice: the hero art it is drawn over is the thing being
	# selected, and covering the middle of it with cards would hide what the
	# selection is for.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	column.add_child(_inset(_build_title_block()))
	column.add_child(_build_rail())
	column.add_child(_inset(_build_hints()))


## Wraps a row in the horizontal TV-safe inset.
##
## Everything that is text or carries a focus ring goes through this. The rail
## deliberately does not -- see the comment in _build().
func _inset(control: Control) -> Control:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	margin.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	margin.add_child(control)
	return margin


func _build_topbar() -> Control:
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Explicit, because the bar's right-hand end is a run of independent items --
	# the app alert, the controller line, three icons and the clock -- and at the
	# container default the alert ran straight into "Reconnect the controller"
	# with no gap, reading as one impossible sentence. Caught on the Xvfb run.
	bar.add_theme_constant_override("separation", TvTheme.HINT_GAP)

	var wordmark := Label.new()
	wordmark.text = "MarwanOS"
	wordmark.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	wordmark.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(wordmark)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	# Controller state lives in the bar rather than in a modal overlay. A pad that
	# has been unplugged should not also take the home screen away -- the person
	# is reaching for a cable, and the UI they come back to should be the one they
	# left, with the selection where it was.
	# THE APP ALERT, and it is a separate label from the controller line rather
	# than a second thing that line can say. An install failing and a pad
	# falling off the air are independent -- both can be true at once -- and a
	# single label would have to pick one and silently drop the other.
	#
	# Empty and invisible almost always. It exists because an uninstall is
	# started from the rail and finishes somewhere the person is not looking:
	# without this the only report of a failure was the journal, on a machine
	# with no terminal to read it from.
	_app_alert = Label.new()
	_app_alert.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_app_alert.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	_app_alert.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_app_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app_alert.visible = false
	bar.add_child(_app_alert)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_status)

	bar.add_child(_bar_gap())

	# The bar's icon cluster, PS5-fashion (ADR 0006, third amendment): the
	# store and the gear are the two FOCUSABLE things outside the rail -- up
	# from any card lands on the store -- and the wifi glyph and clock after
	# them are indicators, not controls. The order puts the two buttons
	# together so left/right between them never crosses a non-focusable.
	_store_button = IconButton.new()
	_store_button.setup("store", "Store")
	_store_button.activated.connect(Stores.open)
	bar.add_child(_store_button)

	bar.add_child(_bar_gap())

	_gear_button = IconButton.new()
	_gear_button.setup("gear", "Settings")
	_gear_button.activated.connect(Settings.open)
	bar.add_child(_gear_button)

	bar.add_child(_bar_gap())

	# The power menu, asked for by name: off, restart, sleep, next to the other
	# two. Last of the three focusables so a thumb overshooting the gear lands
	# on it rather than on nothing.
	_power_button = IconButton.new()
	_power_button.setup("power", "Power")
	_power_button.activated.connect(Power.open)
	bar.add_child(_power_button)

	bar.add_child(_bar_gap())

	# The network's answer as a glyph next to the time, from SystemStatus. In
	# the bar for the same reason the controller state is: connectivity coming
	# and going should never take the home screen away, only annotate it.
	# Hidden when the system has made no claim -- a desk run, or a boot too
	# early for netcheck to have answered -- because drawing a struck wifi fan
	# on a machine that merely has not said yet would be the indicator lying in
	# the direction that causes cable-wiggling.
	_wifi = Glyphs.new()
	_wifi.custom_minimum_size = Vector2(TvTheme.SIZE_TOPBAR + 10, TvTheme.SIZE_TOPBAR + 10)
	_wifi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wifi.visible = false
	_wifi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_wifi)

	bar.add_child(_bar_gap())

	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_clock.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_clock)

	return bar


func _bar_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(TvTheme.SECTION_GAP, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _build_title_block() -> Control:
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", 4)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TvTheme.SIZE_HERO_TITLE)
	_title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	# Ellipsis rather than wrapping: a title that grows a second line shoves the
	# rail down, and the rail's vertical position is supposed to be a constant.
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_subtitle.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(_subtitle)

	return block


func _build_rail() -> Control:
	# A fixed-height window onto a strip that is wider than the screen, spanning
	# the FULL width of the output rather than the safe area. clip_contents is
	# what makes a card vanish as it crosses the screen edge instead of drawing
	# past it; without it the strip is simply a very wide row. Because this
	# viewport now reaches the physical edges, that clip happens where the panel
	# ends, which is the only place a cut is invisible.
	_rail_viewport = Control.new()
	_rail_viewport.custom_minimum_size = Vector2(0, TvTheme.CARD_FOCUSED_SIZE)
	_rail_viewport.clip_contents = true
	_rail_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_rail = HBoxContainer.new()
	_rail.add_theme_constant_override("separation", TvTheme.CARD_GAP)
	_rail.alignment = BoxContainer.ALIGNMENT_BEGIN
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Vertically centred in the window so a card growing from CARD_SIZE to
	# CARD_FOCUSED_SIZE opens in both directions rather than pushing downwards.
	_rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_rail.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Start where the first selection rests, so the opening frame is already
	# right. _scroll_to_selected tweens the strip to this same x when the first
	# card takes focus; starting at the destination makes that opening tween a
	# hold rather than a slide in from the screen edge -- a flinch on the very
	# first frame the appliance ever shows.
	_rail.position.x = TvTheme.SAFE_MARGIN_X
	_rail_viewport.add_child(_rail)

	return _rail_viewport


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	# Kept as a member because it is hidden when the rail is empty -- see
	# _refresh_empty_state. B stays: it is inert at the rail but the glyph is
	# how a person learns that, and the top bar's icons still take an A.
	_open_hint = TvTheme.hint("A", "Open")
	hints.add_child(_open_hint)
	# Y is the only route to removing an application on a machine with no
	# terminal, so it is advertised rather than left to be discovered. Hidden
	# with the A hint when the rail is empty -- there is nothing to have options
	# about -- which is why it is a member too.
	_options_hint = TvTheme.hint("Y", "Options")
	hints.add_child(_options_hint)
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


## Builds the rail from what is installed, plus what this image ships and is
## not.
##
## No shell furniture and no placeholders: the settings card became the top
## bar's gear and the twelve placeholder entries are deleted (ADR 0006, third
## and fourth amendments). The `available` cards appended here are NOT a return
## of those -- a placeholder named an application that did not exist anywhere,
## and these name applications the image ships and can fetch on a button press.
## They exist because removal exists: without them, uninstalling Kodi was a
## one-way door, since the stores screen only ever offered stores back.
##
## Installed first, available after. The rail is a library, and something you
## own outranks something you could have.
func _populate() -> void:
	# One thing, one home (ADR 0006): a store's application lives on the
	# stores screen and must not also be a rail card -- installed, pending or
	# available, which is why the filter sits below where all three kinds meet.
	# Filtered HERE rather than omitted by the scanner: apps.tsv is the truth
	# about the machine, and the stores screen answers "is Steam actually
	# here" and finds its real icon from that same list, which it cannot do if
	# the scanner pretends Steam does not exist.
	var store_ids: Array = Catalogue.store_app_ids()

	var known_ids: Array = []
	for entry in Installed.apps:
		known_ids.append(str(entry.get("id", "")))

	var entries: Array = Installed.apps.duplicate()
	entries.append_array(Catalogue.available(known_ids))

	for entry in entries:
		if store_ids.has(str(entry.get("id", ""))):
			continue
		var tile := Tile.new()
		# duplicate() so a tile can never write back into the list the seam
		# hands out -- Installed rebuilds that list on every rescan, and a tile
		# holding a reference into it would be reading a dictionary that the
		# next scan replaced underneath it.
		tile.setup(entry.duplicate())
		tile.selected.connect(_on_card_selected)
		_rail.add_child(tile)
		_tiles.append(tile)

	# Logged HERE rather than in _ready, so a rail rebuilt by a rescan says so
	# too. It used to be logged once at startup, which meant the journal of a
	# machine where an install had landed still described the rail as it was at
	# boot -- and this line is the shell's primary "the rail exists and has
	# this much on it" assertion, both for a person reading journalctl and for
	# the Xvfb harness.
	ShellLog.info("home rail ready with %d cards" % _tiles.size())


## The rail keeps its one-axis argument -- left and right between cards, hard
## stops at the ends, no wrapping (a selection that teleports across the rail
## when you lean on the stick reads as a glitch). What the third amendment
## added is ONE move off that axis: up, from any card, lands on the store icon
## -- the PS5 shape, where the bar is a second row rather than decoration. Down
## from the bar returns to the rail; _scroll_to_selected keeps the buttons'
## down-neighbour pointed at the selected card, so the round trip up-and-down
## lands where the person left rather than at the rail's start.
##
## Everything is still an explicit table someone can read. Down from a card and
## up from the bar stay pointed at self, so Control's geometric search can
## never wander into the hint row.
func _wire_focus_neighbours() -> void:
	var count := _tiles.size()
	for index in count:
		var tile: Control = _tiles[index]
		var left := index - 1 if index > 0 else index
		var right := index + 1 if index + 1 < count else index

		tile.focus_neighbor_left = tile.get_path_to(_tiles[left])
		tile.focus_neighbor_right = tile.get_path_to(_tiles[right])
		tile.focus_neighbor_top = tile.get_path_to(_store_button)
		tile.focus_neighbor_bottom = tile.get_path_to(tile)

	_store_button.focus_neighbor_left = _store_button.get_path_to(_store_button)
	_store_button.focus_neighbor_right = _store_button.get_path_to(_gear_button)
	_store_button.focus_neighbor_top = _store_button.get_path_to(_store_button)

	_gear_button.focus_neighbor_left = _gear_button.get_path_to(_store_button)
	_gear_button.focus_neighbor_right = _gear_button.get_path_to(_power_button)
	_gear_button.focus_neighbor_top = _gear_button.get_path_to(_gear_button)

	_power_button.focus_neighbor_left = _power_button.get_path_to(_gear_button)
	_power_button.focus_neighbor_right = _power_button.get_path_to(_power_button)
	_power_button.focus_neighbor_top = _power_button.get_path_to(_power_button)

	if count > 0:
		_store_button.focus_neighbor_bottom = _store_button.get_path_to(_tiles[0])
		_gear_button.focus_neighbor_bottom = _gear_button.get_path_to(_tiles[0])
		_power_button.focus_neighbor_bottom = _power_button.get_path_to(_tiles[0])
	else:
		# Nothing below the bar on an empty rail. Pointed at self rather than
		# left unset, so Control's geometric search cannot find the hint row.
		_store_button.focus_neighbor_bottom = _store_button.get_path_to(_store_button)
		_gear_button.focus_neighbor_bottom = _gear_button.get_path_to(_gear_button)
		_power_button.focus_neighbor_bottom = _power_button.get_path_to(_power_button)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_card_selected(entry: Dictionary) -> void:
	# Remembered for the card menu, which is opened from _unhandled_input and
	# therefore has no card to ask.
	_selected_entry = entry
	# Y IS ONLY OFFERED WHERE IT DOES SOMETHING. The menu's one entry is
	# Uninstall, and an application that is not on the machine cannot be
	# removed -- so on an available card the hint would advertise a button
	# whose press is correctly ignored, which is the exact shape of "broken
	# input" on a machine with no other feedback.
	if _options_hint != null:
		_options_hint.visible = str(entry.get("state", "")) == "installed"
	_title.text = str(entry.get("title", ""))
	_subtitle.text = str(entry.get("subtitle", ""))
	_fade_hero_to(TvTheme.accent(str(entry.get("accent", ""))))
	_scroll_to_selected()


## Cross-fades the wash rather than cutting to it. A hard cut on every press is
## the single most fatiguing thing a full-screen colour change can do, and the
## rail is meant to be held down.
func _fade_hero_to(accent: Color) -> void:
	var target := Color(
		accent.r * TvTheme.HERO_DIM + TvTheme.BACKGROUND.r * (1.0 - TvTheme.HERO_DIM),
		accent.g * TvTheme.HERO_DIM + TvTheme.BACKGROUND.g * (1.0 - TvTheme.HERO_DIM),
		accent.b * TvTheme.HERO_DIM + TvTheme.BACKGROUND.b * (1.0 - TvTheme.HERO_DIM),
		1.0)

	if _hero_tween != null and _hero_tween.is_valid():
		_hero_tween.kill()
	_hero_tween = create_tween()
	_hero_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hero_tween.tween_property(_hero, "color", target, TvTheme.RAIL_TWEEN_SECONDS)


## Slides the strip so the selected card's left edge rests on the TV-safe margin.
## See the class header: the selection is what stays put.
##
## SAFE_MARGIN_X, not zero, and that is what keeps the selection inside the safe
## area now that the strip itself spans the full output. The viewport's left edge
## is the screen's left edge; resting the selection there would push the focus
## ring into the region a TV is allowed to overscan away.
##
## THE RESTING X IS ARITHMETIC, NOT MEASURED. When focus moves, the card that
## just lost it is still tweening back down from CARD_FOCUSED_SIZE, so for the
## whole RAIL_TWEEN_SECONDS the HBoxContainer's layout is in flight and any
## position read off it -- this frame, next frame -- is a snapshot of a rail
## that is still changing shape. Reading one frame in measured every card with a
## shrinking neighbour on its left 140 px too far right, and the rail overshot
## until the selection sat clipped at the screen edge. The settled layout needs
## no measuring at all: once the tweens finish, every card left of the selection
## is back at CARD_SIZE, so card N's left edge inside the strip is
## N * (CARD_SIZE + CARD_GAP) -- known before the animation starts, which also
## lets the rail slide and the card grow in the same frame instead of a frame
## apart.
func _scroll_to_selected() -> void:
	if not is_instance_valid(_rail):
		return

	var index := _tiles.find(get_viewport().gui_get_focus_owner())
	if index == -1:
		return

	var target_x := float(TvTheme.SAFE_MARGIN_X - index * (TvTheme.CARD_SIZE + TvTheme.CARD_GAP))

	if _rail_tween != null and _rail_tween.is_valid():
		_rail_tween.kill()
	_rail_tween = create_tween()
	_rail_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rail_tween.tween_property(_rail, "position:x", target_x, TvTheme.RAIL_TWEEN_SECONDS)

	# Keep the bar's way back pointed at the selection, so up-then-down is a
	# round trip rather than a teleport to the rail's start.
	var selected: Control = _tiles[index]
	_store_button.focus_neighbor_bottom = _store_button.get_path_to(selected)
	_gear_button.focus_neighbor_bottom = _gear_button.get_path_to(selected)
	_power_button.focus_neighbor_bottom = _power_button.get_path_to(selected)


func _ensure_focus() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	if is_instance_valid(_last_focused):
		_last_focused.grab_focus()
	elif not _tiles.is_empty():
		var first: Control = _tiles[0]
		first.grab_focus()
	elif _store_button != null:
		# An empty rail is the normal state of a fresh machine, and it must not
		# be a dead end: with no card to focus, the store icon is both the only
		# focusable thing left and exactly where someone with nothing installed
		# needs to go.
		_store_button.grab_focus()


## The rail's two moods: a library, or a machine with nothing on it yet.
##
## The empty state is not an error screen and deliberately does not look like
## one. A fresh stick has nothing installed, which is a correct and expected
## condition -- so the title block says what is true and points at the way out,
## and the hint row stops promising an A press that has no card to land on.
## NEARLY UNREACHABLE NOW, and deliberately kept. Since _populate appends a card
## for every shipped application that is not installed, a fresh stick shows
## three "press A to download it" cards rather than this -- which is a better
## first screen than an empty rail pointing at a store that only has Steam in
## it. The branch survives for the one case that still produces nothing:
## Catalogue.AVAILABLE_APPS being emptied, which Phase 1 will do when marwand
## takes over the shipped set and may briefly serve nothing.
func _refresh_empty_state() -> void:
	var empty := _tiles.is_empty()

	if empty:
		_title.text = "No apps installed"
		_subtitle.text = "Open the Store above to install something"
		_fade_hero_to(TvTheme.ACCENT_FALLBACK)

	if _open_hint != null:
		_open_hint.visible = not empty
	if _options_hint != null:
		_options_hint.visible = not empty


# ---------------------------------------------------------------------------
# Status, clock, launch
# ---------------------------------------------------------------------------

## Ticks every 30 s (so the displayed minute is never more than half a minute
## stale), on a Timer rather than in _process: the clock shows hours and minutes,
## and redrawing it sixty times a second would be sixty thousand pointless string
## builds an hour on a machine that is rendering nothing else.
func _start_clock() -> void:
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(_refresh_clock)
	add_child(timer)
	_refresh_clock()


func _refresh_clock() -> void:
	if _clock == null:
		return
	var now := Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0))]


func _on_launch_started(_entry: Dictionary) -> void:
	_hand_screen_over()


func _on_launch_finished(_entry: Dictionary) -> void:
	# The app went away -- via the overlay's Close, or on its own. Either way
	# the overlay is now framing nothing, so it goes first.
	_close_overlay()
	# A launch can start FROM the stores screen, in which case that screen is
	# what the person should land back on when the app quits -- not the rail
	# grabbing focus to a card that is drawn underneath an open surface. The
	# surface's own close is what restores the rail.
	if Stores.is_open() or Settings.is_open():
		return
	_take_screen_back()


func _on_surface_opened() -> void:
	_hand_screen_over()


func _on_surface_closed() -> void:
	_take_screen_back()


## Shared by the launch seam and both shell surfaces: from the rail's point of
## view "something fullscreen is up" is one state, however it was reached, and
## having one implementation is what guarantees the seams cannot drift apart
## in how they give the screen back.
func _hand_screen_over() -> void:
	# Captured before hiding: hiding a Control releases focus, so asking
	# afterwards would always answer null. Captured only while VISIBLE: a
	# launch that starts from inside the stores screen arrives here with the
	# rail already hidden, and overwriting the remembered card with a store
	# tab would strand focus on a freed control when the rail finally returns.
	if visible:
		_last_focused = get_viewport().gui_get_focus_owner()
	hide()
	# Hiding a Control stops it drawing and stops it receiving GUI input, but
	# _unhandled_input keeps arriving regardless. The covering screen is a later
	# sibling and so is called first, and it consumes the press -- but relying on
	# dispatch order for "B does not do two things at once" is the kind of
	# assumption that breaks silently when a node is reparented.
	set_process_unhandled_input(false)


func _take_screen_back() -> void:
	show()
	set_process_unhandled_input(true)
	_ensure_focus()


func _on_player_one_present(_device: int, _pad_name: String) -> void:
	_refresh_status()
	# A controller arriving is also the moment a shell that came up with nothing
	# focused becomes usable, so take the opportunity.
	_ensure_focus()


func _on_player_one_absent() -> void:
	_refresh_status()


## How long a failure stays in the top bar. It has to outlast someone looking
## away -- a removal is started and then watched for on the rail -- and it must
## not become permanent furniture, because appctl's state file keeps saying
## "failed" until the next request and a line that never leaves stops being
## read. Cleared early by any state change, which is the normal way it goes.
const APP_ALERT_SECONDS := 20.0


## An install or removal reported something worth interrupting for.
##
## ONLY FAILURES SURFACE HERE. Progress does not: the rail already shows a
## pending card for an arriving application and simply drops the card for a
## removed one, so a top-bar line narrating the happy path would be a third
## account of something already on screen twice.
func _on_apps_state_changed(state: String, app: String, detail: String) -> void:
	if _app_alert == null:
		return

	if state != "failed" and state != "refused":
		_app_alert.visible = false
		_app_alert.text = ""
		if _app_alert_timer != null:
			_app_alert_timer.stop()
		return

	# The application's TITLE, because "Steam" is what the person pressed a
	# button about and "com.valvesoftware.Steam" is not a name to put on a
	# television.
	#
	# TWO SOURCES, AND THE SECOND IS THE ONE THAT MATTERS. The installed seam
	# knows the title of everything on the machine -- but the two failures worth
	# reporting are an install that did not happen and a removal of something
	# now gone, and in both the application is absent from that list precisely
	# when its name is needed. So the catalogue answers second. The raw id is
	# the last resort: ugly, and true.
	var name := _title_for_app(app)

	var said := detail if not detail.is_empty() else "Something went wrong"
	_app_alert.text = "%s: %s" % [name, said] if not name.is_empty() else said
	_app_alert.visible = true

	if _app_alert_timer == null:
		_app_alert_timer = Timer.new()
		_app_alert_timer.one_shot = true
		_app_alert_timer.timeout.connect(_on_app_alert_expired)
		add_child(_app_alert_timer)
	_app_alert_timer.start(APP_ALERT_SECONDS)


## A human name for an application id -- see _on_apps_state_changed for why the
## installed seam alone is not enough.
func _title_for_app(app: String) -> String:
	if app.is_empty():
		return ""
	for entry in Installed.apps:
		if str(entry.get("id", "")) == app:
			return str(entry.get("title", app))
	for store in Catalogue.stores():
		if str(store.get("app_id", "")) == app:
			return str(store.get("title", app))
	# The shipped list is the one that actually answers for a failed install:
	# the stores list holds only Steam, so without this an install of Kodi that
	# failed reported itself as "tv.kodi.Kodi", which is what the Xvfb run
	# showed on the TV.
	for shipped in Catalogue.AVAILABLE_APPS:
		if str(shipped.get("id", "")) == app:
			return str(shipped.get("title", app))
	return app


func _on_app_alert_expired() -> void:
	if _app_alert != null:
		_app_alert.visible = false
		_app_alert.text = ""


func _refresh_status() -> void:
	if _status == null:
		return
	if PlayerOne.has_controller():
		_status.text = "Player 1  %s" % PlayerOne.pad_name
		_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	else:
		_status.text = "Reconnect the controller"
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)


## An install or a removal landed while the rail was on screen. Rebuilding is
## the whole response: the rail is a rendering of the list, so the list
## changing means it is redrawn rather than patched.
##
## FOCUS IS RE-ESTABLISHED BY IDENTITY, NOT BY INDEX. The tiles about to be
## freed include the focused one, and the replacement list may be longer,
## shorter or reordered -- so the card the person was on is looked up again by
## its app id. Only when that app is genuinely gone does focus fall back to the
## start of the rail. Keeping the index instead would silently move the
## selection to a different app whenever one was installed ahead of it.
func _on_apps_changed(_apps: Array) -> void:
	var focused_id := ""
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and _tiles.has(owner):
		focused_id = str(owner.entry.get("id", ""))

	for tile in _tiles:
		_rail.remove_child(tile)
		tile.queue_free()
	_tiles.clear()
	# The remembered card is one of the tiles just freed; leaving it set would
	# have _ensure_focus grab a freed node.
	_last_focused = null

	_populate()
	_wire_focus_neighbours()
	_refresh_empty_state()

	# Only touch focus if the rail is the surface on screen. A rescan while the
	# stores screen is up must not pull focus out from under it.
	if not visible:
		return

	# Nor may it pull focus off the TOP BAR. An install landing while someone
	# is sitting on the store or gear icon -- which is exactly where they are
	# after closing the stores screen, and exactly when an install is likely to
	# finish -- must not yank the selection down into the rail mid-press.
	# `focused_id` is empty precisely when focus was not on a card, so it is
	# also the test for "leave it alone".
	if focused_id.is_empty():
		if get_viewport().gui_get_focus_owner() == null:
			_ensure_focus()
		return

	var restored: Control = null
	for tile in _tiles:
		if str(tile.entry.get("id", "")) == focused_id:
			restored = tile
			break
	if restored == null and not _tiles.is_empty():
		restored = _tiles[0]

	if restored != null:
		restored.grab_focus()
	else:
		# The rail emptied out from under the selection -- the last app was
		# removed. _ensure_focus sends focus up to the store icon, which is
		# where someone with nothing installed needs to be anyway.
		_ensure_focus()


func _on_network_changed(state: String) -> void:
	if _wifi == null:
		return
	match state:
		"online":
			_wifi.visible = true
			_wifi.kind = "wifi"
			_wifi.color = TvTheme.TEXT_SECONDARY
		"offline":
			_wifi.visible = true
			_wifi.kind = "wifi-off"
			_wifi.color = TvTheme.TEXT_ALERT
		_:
			# No claim from the system, no glyph on the screen. See _build_topbar.
			_wifi.visible = false


## THE HOME BUTTON IS HANDLED IN _input, NOT _unhandled_input, and that is the
## only place it could go. `_hand_screen_over` turns unhandled input off for
## the whole time an application is running -- which is exactly when the home
## button has to work. `_input` keeps arriving on a Node regardless of whether
## the Control is visible, so this is the one hook still alive while the rail
## is hidden behind a launch.
##
## Everything else is left alone: this consumes nothing unless there is a
## running application and the press is the home button.
func _input(event: InputEvent) -> void:
	if not InputMap.has_action("ui_shell_home"):
		return
	if not event.is_action_pressed("ui_shell_home"):
		return
	if not Launcher.is_busy() or not Launcher.can_close():
		# No process to offer anything about. The placeholder branch has no pid
		# and is dismissed with B, and at the rail the button means nothing.
		return
	if _overlay != null:
		return
	get_viewport().set_input_as_handled()
	_open_overlay()


func _open_overlay() -> void:
	_overlay = AppOverlay.new()
	_overlay.entry = Launcher.current_entry()
	_overlay.closed.connect(_on_overlay_closed, CONNECT_ONE_SHOT)
	# Added to the root rather than to this node: the rail is hidden while an
	# app runs, and a child of a hidden Control does not draw.
	get_tree().root.add_child(_overlay)
	# Ask gamescope to composite us over the application rather than instead of
	# it. See Kiosk.set_overlay -- if this does not take, the overlay still
	# works, it just covers the app.
	Kiosk.set_overlay(true)


func _on_overlay_closed() -> void:
	_close_overlay.call_deferred()


func _close_overlay() -> void:
	if _overlay == null:
		return
	var overlay := _overlay
	_overlay = null
	overlay.get_parent().remove_child(overlay)
	overlay.queue_free()
	Kiosk.set_overlay(false)


## The options menu for the selected card. Guarded rather than always available,
## and every guard is a state in which the menu would be about the wrong thing.
func _open_card_menu() -> void:
	if _card_menu != null:
		# A second press while it is up is a bounced button, not a request for
		# two -- the same rule the other surfaces enforce.
		return
	if Settings.is_open() or Stores.is_open() or Power.is_open() or Launcher.is_busy():
		# The rail is not what is on screen, so the selected card is not what the
		# person is looking at.
		return
	if _selected_entry.is_empty():
		ShellLog.info("Y at the rail with nothing selected; nothing to offer")
		return
	if str(_selected_entry.get("state", "")) != "installed":
		# A card for an application that is still downloading has nothing to
		# uninstall, and offering it would race the installer for the same
		# flatpak. The installer's own states say what is happening instead.
		ShellLog.info("Y on a card that is not installed yet; nothing to offer")
		return
	if Apps.is_busy():
		ShellLog.info("Y while another install or removal is in flight; ignoring")
		return

	_card_menu = CardMenu.new()
	_card_menu.entry = _selected_entry
	_card_menu.closed.connect(_on_card_menu_closed, CONNECT_ONE_SHOT)
	# Focus is saved and restored the way the other surfaces do it: the rail is
	# still in the tree underneath, so without this the card loses its ring when
	# the menu closes.
	_hand_screen_over()
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
	_take_screen_back()


func _unhandled_input(event: InputEvent) -> void:
	# Y OPENS THE CARD'S OPTIONS. It is checked before B because it is the only
	# way to remove an application on a machine with no terminal, and it is on Y
	# rather than on a long-press of A because a hold that means something
	# different from a press is exactly the interaction a person on a sofa
	# discovers by accident and cannot undo.
	if InputMap.has_action("ui_shell_y") and event.is_action_pressed("ui_shell_y"):
		get_viewport().set_input_as_handled()
		_open_card_menu()
		return

	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# The home rail is the root of the shell, so there is nowhere to back out to
	# and nothing here quits. Exiting would be a client exit as far as
	# marwanos-session is concerned: the supervision loop would count it as a
	# crash, restart it, and five of those inside sixty seconds would trip the
	# guard and draw the error screen. B is inert here on purpose.
	ShellLog.info("back pressed at the home rail; nothing above this")
