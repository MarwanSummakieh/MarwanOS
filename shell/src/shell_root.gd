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
const SettingsTile = preload("res://src/settings_tile.gd")
const ErrorScreen = preload("res://src/error_screen.gd")

var _hero: ColorRect = null
var _title: Label = null
var _subtitle: Label = null
var _clock: Label = null
var _rail_viewport: Control = null
var _rail: HBoxContainer = null
var _status: Label = null

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

	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)
	Settings.settings_opened.connect(_on_settings_opened)
	Settings.settings_closed.connect(_on_settings_closed)
	PlayerOne.player_one_present.connect(_on_player_one_present)
	PlayerOne.player_one_absent.connect(_on_player_one_absent)
	_refresh_status()

	_start_clock()

	# Nothing navigates until something is focused: the viewport's directional
	# navigation starts from the current focus owner, and with none there is no
	# origin to move from. This is the single most common way a gamepad UI ships
	# looking dead.
	_ensure_focus()

	ShellLog.info("home rail ready with %d cards" % _tiles.size())
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
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_status)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(TvTheme.SECTION_GAP, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(gap)

	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	_clock.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_clock)

	return bar


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
	# Start where the first selection will settle, so the opening frame is
	# already right. _scroll_to_selected waits a frame before it can measure, and
	# without this the rail would draw once hard against the screen edge and then
	# jump inwards -- a flinch on the very first frame the appliance ever shows.
	_rail.position.x = TvTheme.SAFE_MARGIN_X
	_rail_viewport.add_child(_rail)

	return _rail_viewport


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	hints.add_child(TvTheme.hint("A", "Open"))
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


func _populate() -> void:
	for entry in Catalogue.entries():
		var tile := Tile.new()
		tile.setup(entry)
		tile.selected.connect(_on_card_selected)
		_rail.add_child(tile)
		_tiles.append(tile)

	# The settings card rides at the end of the rail rather than living in the
	# catalogue: it is shell furniture, and the catalogue file is deleted whole
	# in Phase 1. Last and not first because the rail opens on the library --
	# the thing the machine is for -- and settings is somewhere you go on
	# purpose, not somewhere you land.
	var settings_card := SettingsTile.new()
	settings_card.setup({
		"id": "shell.settings",
		"title": "Settings",
		"subtitle": "What this machine is running",
		"accent": TvTheme.SETTINGS_CARD_ACCENT,
	})
	settings_card.selected.connect(_on_card_selected)
	_rail.add_child(settings_card)
	_tiles.append(settings_card)


## One axis, and the ends are hard stops. A card at either end points that
## neighbour at itself, so pushing further does nothing rather than wrapping.
## Wrapping is a defensible choice and this is not it -- a selection that
## teleports from one end of the rail to the other when you lean on the stick
## reads as a glitch.
##
## Up and down are pointed at self as well. There is nothing above or below the
## rail to reach yet, and leaving them empty would let Control's geometric focus
## search find the hint row or the top bar, neither of which is focusable but both
## of which could become so later. Explicit is a table someone can read.
func _wire_focus_neighbours() -> void:
	var count := _tiles.size()
	for index in count:
		var tile: Control = _tiles[index]
		var left := index - 1 if index > 0 else index
		var right := index + 1 if index + 1 < count else index

		tile.focus_neighbor_left = tile.get_path_to(_tiles[left])
		tile.focus_neighbor_right = tile.get_path_to(_tiles[right])
		tile.focus_neighbor_top = tile.get_path_to(tile)
		tile.focus_neighbor_bottom = tile.get_path_to(tile)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_card_selected(entry: Dictionary) -> void:
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
## Deferred by one frame because the card that just took focus is mid-tween to
## its larger size, and the HBoxContainer has not re-flowed yet -- reading
## position now would scroll to where the card was about to stop being.
func _scroll_to_selected() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_rail):
		return

	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _tiles.has(focused):
		return

	var target_x := TvTheme.SAFE_MARGIN_X - focused.position.x

	if _rail_tween != null and _rail_tween.is_valid():
		_rail_tween.kill()
	_rail_tween = create_tween()
	_rail_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rail_tween.tween_property(_rail, "position:x", target_x, TvTheme.RAIL_TWEEN_SECONDS)


func _ensure_focus() -> void:
	if _tiles.is_empty():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	if is_instance_valid(_last_focused):
		_last_focused.grab_focus()
	else:
		var first: Control = _tiles[0]
		first.grab_focus()


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
	_take_screen_back()


func _on_settings_opened() -> void:
	_hand_screen_over()


func _on_settings_closed() -> void:
	_take_screen_back()


## Shared by the launch seam and the settings seam: from the rail's point of
## view "something fullscreen is up" is one state, however it was reached, and
## having one implementation is what guarantees the two seams cannot drift
## apart in how they give the screen back.
func _hand_screen_over() -> void:
	# Captured before hiding: hiding a Control releases focus, so asking
	# afterwards would always answer null.
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


func _refresh_status() -> void:
	if _status == null:
		return
	if PlayerOne.has_controller():
		_status.text = "Player 1  %s" % PlayerOne.pad_name
		_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	else:
		_status.text = "Reconnect the controller"
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# The home rail is the root of the shell, so there is nowhere to back out to
	# and nothing here quits. Exiting would be a client exit as far as
	# marwanos-session is concerned: the supervision loop would count it as a
	# crash, restart it, and five of those inside sixty seconds would trip the
	# guard and draw the error screen. B is inert here on purpose.
	ShellLog.info("back pressed at the home rail; nothing above this")
