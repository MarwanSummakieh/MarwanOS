extends Control

## The home screen -- everything the appliance shows when nothing is launched.
##
## A console-style home: the selected entry's own artwork as the FULL-BLEED
## background, behind a top status bar, the selected entry's title, and a
## horizontal rail of cards with one enlarged selection. It replaced a 4x3 grid,
## and the reason is navigational rather than cosmetic.
##
## THE BACKGROUND IS THE SELECTION. Moving the cursor repaints the entire
## surface with that entry's picture, not a strip of it and not an accent tint --
## the Playnite and PS5 shape, and the thing that makes a screen of cards read as
## a library. See _build_art_layer for the stack and why every layer in it is
## there; the accent wash stays underneath as the base and as the whole answer
## for an entry that ships no picture. A grid has two axes, so "what does right do at the end of a row"
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
const DetailsPanel = preload("res://src/details_panel.gd")
const Glyphs = preload("res://src/glyphs.gd")
const ErrorScreen = preload("res://src/error_screen.gd")

## Same prefix, same meaning as tile.gd's: an entry whose id starts with it is a
## Steam library game rather than an application, which is what makes it the one
## kind of entry with a background of its own.
const STEAM_PREFIX := "steam."

var _hero: ColorRect = null
## The key-art layer and its two stacked pictures. See _build_art_layer.
var _art_layer: Control = null
var _art_back: TextureRect = null
var _art_front: TextureRect = null
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
## The details panel, and the card it was opened from. The card is kept because
## the panel's Play button asks that card to act (see Tile.activate) rather than
## reaching into the launch seam on its own.
var _details: DetailsPanel = null
var _details_tile: Control = null
## The rail entry the cursor is on, kept because the card menu is opened from
## input handling rather than from the card itself.
var _selected_entry: Dictionary = {}
var _wifi: Glyphs = null
## The bar's focusable cluster, in the order they sit. Kept as one array as
## well as four members because every wiring loop below wants "all of them" --
## and a fifth icon arriving should not be a fifth line in four places.
var _bar_buttons: Array = []
var _store_button: IconButton = null
var _files_button: IconButton = null
var _gear_button: IconButton = null
var _power_button: IconButton = null

var _tiles: Array = []
var _last_focused: Control = null
var _rail_tween: Tween = null
var _hero_tween: Tween = null
var _art_tween: Tween = null

## The debounce between "the selection moved" and "load that picture", and the
## path it is waiting to load. See TvTheme.HERO_ART_DEBOUNCE_SECONDS.
var _art_timer: Timer = null
var _art_pending_path := ""
## Whether the pending picture is to be softened. A portrait or a logo is, a
## game's hero background is not -- see _on_card_selected.
var _art_pending_soften := true
## What is actually on the screen, so re-selecting the same card is a no-op
## rather than a crossfade from a picture to itself.
var _art_shown_path := ""

## path -> ImageTexture of already-softened backdrops, with the insertion order
## kept alongside so the oldest can be dropped at the cap. A Dictionary has no
## ordering to evict by, and the alternative -- letting it grow -- is a leak on
## a machine that never reboots.
var _art_cache: Dictionary = {}
var _art_cache_order: Array = []


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
	Files.files_opened.connect(_on_surface_opened)
	Files.files_closed.connect(_on_surface_closed)
	PlayerOne.player_one_present.connect(_on_player_one_present)
	PlayerOne.player_one_absent.connect(_on_player_one_absent)
	SystemStatus.network_changed.connect(_on_network_changed)
	Installed.apps_changed.connect(_on_apps_changed)
	# ARTWORK ARRIVING IS A RAIL REBUILD, through the same door an install is.
	# A card's picture is chosen when the card is built (tile._art_candidates),
	# so a cache that warms after boot only reaches the screen if the cards are
	# built again -- and doing that through _on_apps_changed rather than through
	# a second, artwork-shaped path is what stops the two rebuilds racing each
	# other for the focused card. See _on_gameart_changed.
	GameArt.changed.connect(_on_gameart_changed)
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
	# is the BASE of the background and the whole of it for an entry with no
	# picture -- which is a normal card, not a broken one: the Files surface has
	# no export to take an icon from, and neither does an app whose flatpak
	# shipped none. It deliberately bleeds past the TV-safe inset -- background
	# may overscan, text may not.
	_hero = ColorRect.new()
	_hero.color = TvTheme.BACKGROUND
	_hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)

	# The selected entry's own picture, over the wash and under everything else.
	_build_art_layer()

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


## THE WHOLE BACKGROUND IS THE SELECTED ENTRY'S ART, which is the difference
## between a library and a menu -- Playnite and the PS5 both repaint the entire
## surface as the cursor moves, and an accent wash alone never reads as "this
## screen is about that thing".
##
## Four children, in the order they paint, and every one of them is load-bearing:
##
##   _art_back    the picture currently up
##   _art_front   the picture fading in over it, alpha 0 at rest
##   a flat scrim TvTheme.HERO_ART_SCRIM over both, so text has a floor to stand
##                on whatever the art is
##   a top band   the mirror of the bottom gradient, for the top bar
##
## Two rects rather than one because a crossfade needs both frames alive at once;
## _settle_front collapses them back to one as soon as the fade lands, so the
## resting cost is one texture.
##
## ANCHORED TO THE FULL CONTROL RECT, NOT TO 1920x1080. The design surface is
## 1920 wide and canvas_items scales it, but project.godot's stretch is
## aspect=expand, which hands a wider panel the extra width instead of black
## bars -- so on the 3440x1440 ultrawide this Control is ~2580 units across, and
## a layer sized to BASE_WIDTH would leave a strip of bare wash down one side.
## PRESET_FULL_RECT is the only correct answer, and it is why no number in here
## is a width.
##
## The whole layer is transparent when there is no art, so an entry without a
## picture costs nothing and shows the wash exactly as it always did -- INCLUDING
## the scrim and the top band, which are children and go with it. A scrim that
## stayed up over the wash would darken a screen that has nothing needing to be
## darkened.
func _build_art_layer() -> void:
	_art_layer = Control.new()
	_art_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.modulate.a = 0.0
	add_child(_art_layer)

	_art_back = _build_art_rect()
	_art_layer.add_child(_art_back)

	_art_front = _build_art_rect()
	_art_front.modulate.a = 0.0
	_art_layer.add_child(_art_front)

	var scrim := ColorRect.new()
	scrim.color = TvTheme.hero_scrim_color()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(scrim)

	var top_band := TextureRect.new()
	top_band.texture = TvTheme.hero_top_gradient()
	top_band.stretch_mode = TextureRect.STRETCH_SCALE
	# Full rect first and then one anchor moved, rather than PRESET_TOP_WIDE:
	# set_anchors_and_offsets_preset is the form that zeroes the offsets, and a
	# preset that only moves anchors leaves whatever offsets the node was built
	# with to be interpreted against the new ones.
	top_band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_band.anchor_bottom = TvTheme.HERO_ART_TOP_FRACTION
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(top_band)


## One of the two stacked pictures.
##
## KEEP_ASPECT_COVERED is the cover fit: the image is scaled until it fills the
## rect on both axes and the overflow is cropped by the draw itself, so nothing
## is ever stretched out of shape -- which a 600x900 portrait across a 2580-wide
## panel very visibly would be. EXPAND_IGNORE_SIZE is what lets the rect be
## whatever the anchors say instead of at least as large as its texture; it
## matters in the other direction too, since these textures are deliberately
## tiny (see TvTheme.HERO_ART_BLUR_DIVISOR).
##
## TEXTURE_FILTER_LINEAR is stated rather than inherited, because it IS the
## blur. A backdrop resized down to 50 px and then drawn with nearest-neighbour
## filtering is not a soft picture, it is a grid of enormous squares -- so the
## one property the whole softening trick depends on does not get to be a
## project-settings default that someone changes for an unrelated reason.
func _build_art_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


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

	# The bar's icon cluster, PS5-fashion (ADR 0006, third amendment): these are
	# the FOCUSABLE things outside the rail -- up from any card lands on the
	# store -- and the wifi glyph and clock after them are indicators, not
	# controls. The order keeps them adjacent so left/right between them never
	# crosses a non-focusable.
	#
	# FILES IS ONE OF THEM NOW, at the owner's request, and it stopped being a
	# rail card in the same move. The rail is the library -- the applications
	# this machine has -- and the file manager is a shell surface exactly like
	# settings and power: a screen the binary draws, not a thing you install or
	# remove. It had a card because "an app in the person's mental model" was a
	# defensible reading; sitting next to the gear is the better one, and it
	# frees the rail's first card to be something the person actually put there.
	# One thing, one home (ADR 0006) is what forbids it being in both places.
	_store_button = _bar_button("store", "Store", Stores.open)
	_files_button = _bar_button("folder", "Files", Files.open)
	_gear_button = _bar_button("gear", "Settings", Settings.open)
	# The power menu, asked for by name: off, restart, sleep, next to the
	# others. Last of the focusables so a thumb overshooting the gear lands on
	# it rather than on nothing.
	_power_button = _bar_button("power", "Power", Power.open)

	for button in _bar_buttons:
		bar.add_child(button)
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


## One icon in the bar's cluster, built and remembered. The registration into
## _bar_buttons is the point: the neighbour tables below walk that array, so an
## icon that is built is an icon that is wired, and the two cannot drift.
func _bar_button(kind: String, label_text: String, action: Callable) -> IconButton:
	var button := IconButton.new()
	button.setup(kind, label_text)
	button.activated.connect(action)
	_bar_buttons.append(button)
	return button


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
	# OPTIONS is the only route to removing an application on a machine with no
	# terminal, so it is advertised rather than left to be discovered. Hidden
	# with the A hint when the rail is empty -- there is nothing to have options
	# about -- which is why it is a member too.
	_options_hint = TvTheme.hint("OPTIONS", "Options")
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

	# THE RAIL IS APPLICATIONS ONLY. The Files card used to ride in front of the
	# installed list; the file manager is a top-bar icon now, next to the gear
	# and the power button, so a card for it here would be the same surface with
	# two homes. See _build_topbar.
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
		# Bound rather than looked up from the focus owner when it fires: the
		# panel's Play button asks THIS card to act, and "whatever has focus" is
		# a different thing the moment anything else grabs it.
		tile.details_requested.connect(_on_details_requested.bind(tile))
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

	# The bar is the rail's argument on its own row: one axis, hard stops at both
	# ends, up pointed at self so nothing above it can be found geometrically.
	var bar_count := _bar_buttons.size()
	for index in bar_count:
		var button: Control = _bar_buttons[index]
		var previous := index - 1 if index > 0 else index
		var next := index + 1 if index + 1 < bar_count else index

		button.focus_neighbor_left = button.get_path_to(_bar_buttons[previous])
		button.focus_neighbor_right = button.get_path_to(_bar_buttons[next])
		button.focus_neighbor_top = button.get_path_to(button)
		# Nothing below the bar on an empty rail. Pointed at self rather than
		# left unset, so Control's geometric search cannot find the hint row.
		var below: Control = _tiles[0] if count > 0 else button
		button.focus_neighbor_bottom = button.get_path_to(below)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_card_selected(entry: Dictionary) -> void:
	# Remembered for the card menu, which is opened from _unhandled_input and
	# therefore has no card to ask.
	_selected_entry = entry
	# OPTIONS IS ONLY OFFERED WHERE IT DOES SOMETHING. The menu's one entry is
	# Uninstall, and an application that is not on the machine cannot be
	# removed -- so on an available card the hint would advertise a button
	# whose press is correctly ignored, which is the exact shape of "broken
	# input" on a machine with no other feedback. A Steam game's card hides it
	# too -- removal belongs to Steam itself.
	if _options_hint != null:
		_options_hint.visible = str(entry.get("state", "")) == "installed" \
			and not str(entry.get("id", "")).begins_with("steam.")
	_title.text = str(entry.get("title", ""))
	_subtitle.text = str(entry.get("subtitle", ""))
	_fade_hero_to(TvTheme.accent(str(entry.get("accent", ""))))
	# The wash changes NOW and the picture changes in a moment: the accent is a
	# colour already in hand, and the picture is a file on disk. Splitting them
	# is what makes a fast scroll cost one decode instead of ten -- see
	# _request_hero_art.
	#
	# A GAME'S HERO ART IS SHOWN SHARP, and it is the only picture on this screen
	# that is. Everything else the rail can hand the background is a logo or a box
	# shot -- a picture of a THING, at the wrong shape for a wall, which is why it
	# is resized down to a smear (see TvTheme.HERO_ART_BLUR_DIVISOR). A Steam hero
	# is not that: it is a wide, deliberately empty-in-the-middle image that Steam
	# itself draws edge to edge behind its own library, drawn by the people who
	# made the game to be a background. Softening one would be throwing away the
	# only artwork the machine ever gets that was designed for this exact job.
	#
	# The scrim and both gradients stay exactly as they are over it -- see
	# TvTheme.HERO_ART_SCRIM, which is derived from the worst-case LUMINANCE the
	# background can have and therefore says nothing about sharpness.
	var id := str(entry.get("id", ""))
	var hero := GameArt.hero_for(id) if id.begins_with(STEAM_PREFIX) else ""
	if hero.is_empty():
		_request_hero_art(str(entry.get("icon", "")), true)
	else:
		_request_hero_art(hero, false)
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


# ---------------------------------------------------------------------------
# The hero art
# ---------------------------------------------------------------------------

## Asks for a picture, eventually.
##
## THE DEBOUNCE IS THE WHOLE FUNCTION. Holding right across ten cards emits ten
## selections in about a second; every one of them lands here, and every one of
## them restarts the same one-shot timer, so nine of them never touch the disk.
## Only the card the thumb settles on is loaded and only one fade is ever in
## flight. The alternative was measured in the shape of the problem rather than
## on a stopwatch: a Steam portrait is a JPEG decode on a CPU renderer, and ten
## of them queued behind ten crossfades is a rail that stops answering the pad
## while it catches up -- the exact failure the rail's anchored selection exists
## to avoid.
##
## An empty path is a real request, not a skipped one: it is how a card with no
## picture takes the screen BACK from the last card that had one.
##
## `soften` rides along with the path rather than being decided at load time,
## because it is a property of what the picture IS FOR -- a background versus a
## logo standing in for one -- and only the selection handler knows that. See
## _on_card_selected and _backdrop_texture.
func _request_hero_art(path: String, soften: bool) -> void:
	_art_pending_path = path
	_art_pending_soften = soften

	if _art_timer == null:
		_art_timer = Timer.new()
		_art_timer.one_shot = true
		_art_timer.timeout.connect(_on_art_settled)
		add_child(_art_timer)

	# start() on a running one-shot restarts it, which is the debounce.
	_art_timer.start(TvTheme.HERO_ART_DEBOUNCE_SECONDS)


func _on_art_settled() -> void:
	var path := _art_pending_path

	if path.is_empty():
		# Said out loud rather than done silently, because on this machine the
		# journal is the only place to tell "that entry ships no artwork" apart
		# from "the loader fell over".
		ShellLog.info("hero art: none, wash only")
		_art_shown_path = ""
		_clear_hero_art()
		return

	if path == _art_shown_path:
		ShellLog.info("hero art: %s (already up)" % path)
		return

	var texture := _backdrop_texture(path, _art_pending_soften)
	if texture == null:
		# Same policy as the card's own icon: a picture that will not decode is
		# not worth a black screen, and the wash underneath is a complete answer.
		ShellLog.warn("hero art: %s would not decode; wash only" % path)
		_art_shown_path = ""
		_clear_hero_art()
		return

	_art_shown_path = path
	_show_hero_art(texture)


## Crossfades to a picture.
##
## The two rects and the layer's own alpha do two different jobs and both are
## needed. Fading _art_front in handles picture-to-picture. Fading the LAYER in
## handles wash-to-picture, where there is no outgoing frame to cross from
## because the outgoing frame is the accent wash sitting underneath. They run in
## parallel so an interrupted fade-out -- selection moving back onto a card with
## art while the layer is still on its way down -- is recovered by the same
## tween that does the crossfade, rather than leaving the art stranded at 40%.
##
## The in-flight tween is killed first, always. Ten queued fades would each be
## drawing a full-screen texture, and the last one to finish would win by luck
## rather than by being the current selection.
func _show_hero_art(texture: ImageTexture) -> void:
	_settle_front()
	_kill_art_tween()

	_art_tween = create_tween()
	_art_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_art_tween.set_parallel(true)

	if _art_back.texture == null:
		_art_back.texture = texture
	else:
		_art_front.texture = texture
		_art_front.modulate.a = 0.0
		_art_tween.tween_property(
			_art_front, "modulate:a", 1.0, TvTheme.HERO_ART_FADE_SECONDS)

	_art_tween.tween_property(
		_art_layer, "modulate:a", 1.0, TvTheme.HERO_ART_FADE_SECONDS)
	_art_tween.chain().tween_callback(_settle_front)


## Fades the art off, leaving the wash.
func _clear_hero_art() -> void:
	if _art_back.texture == null and _art_front.texture == null:
		return

	_kill_art_tween()
	_art_tween = create_tween()
	_art_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_art_tween.tween_property(
		_art_layer, "modulate:a", 0.0, TvTheme.HERO_ART_FADE_SECONDS)
	_art_tween.tween_callback(_drop_art)


## Collapses the two pictures back to one, so the resting state is always a
## single texture and the next crossfade has a clean frame to cross FROM.
##
## Called at the end of a fade, where the front is fully opaque and simply
## becomes the back -- and called again at the START of the next one, which is
## the case that matters: a fade cut short by a faster thumb leaves the front
## half shown, and the half-shown picture is what the person is looking at. Past
## the midpoint it is promoted, before it, dropped. Either way the front is empty
## afterwards, which is the invariant _show_hero_art relies on.
func _settle_front() -> void:
	if _art_front.texture == null:
		return
	if _art_front.modulate.a >= 0.5:
		_art_back.texture = _art_front.texture
	_art_front.texture = null
	_art_front.modulate.a = 0.0


func _drop_art() -> void:
	_art_back.texture = null
	_art_front.texture = null
	_art_front.modulate.a = 0.0


func _kill_art_tween() -> void:
	if _art_tween != null and _art_tween.is_valid():
		_art_tween.kill()
	_art_tween = null


## An entry's icon file, decoded once and softened into a backdrop.
##
## CACHED BY PATH, because the rail is walked back and forth: left, right and
## left again over three cards would otherwise be three decodes of the same
## JPEG, and revisiting a card is the single most common thing anyone does here.
## The cache holds the SOFTENED texture rather than the source image, so a hit
## costs a dictionary lookup and nothing else -- no resize, no upload.
##
## The decode itself is tile.gd's loader, unchanged and not reimplemented: it is
## where PNG, JPG and the SVG two-pass were all paid for, and a second copy of
## that reasoning would drift the first time one of them learned something.
##
## THE SOFTENING IS A RESIZE, and that is the entire trick -- see
## TvTheme.HERO_ART_BLUR_DIVISOR for why a blur is not affordable here and why
## an icon is taken further down than a portrait.
##
## `soften` false is the game-hero case and skips all of that: the file is
## decoded and uploaded as it is. It costs more texture memory than a 50 px
## smear and nothing per frame, which is the budget that matters here -- the
## cache is capped either way.
func _backdrop_texture(path: String, soften: bool) -> ImageTexture:
	# KEYED ON THE TREATMENT AS WELL AS THE PATH. Nothing today can ask for one
	# file both ways -- heroes and portraits are different files -- but a cache
	# that answered a sharp request with a softened texture would be a bug whose
	# only symptom is a blurry background, which is precisely the thing this
	# change exists to remove and would be read as "the feature did not land".
	var key := "%s|%s" % [path, "soft" if soften else "sharp"]
	if _art_cache.has(key):
		ShellLog.info("hero art: %s (cached)" % path)
		return _art_cache[key]

	var image := Tile.load_icon_image(path)
	if image == null:
		return null

	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return null

	if not soften:
		var sharp := ImageTexture.create_from_image(image)
		_remember_backdrop(key, sharp)
		ShellLog.info("hero art: %s (%dx%d, unblurred background)" % [path, width, height])
		return sharp

	# A logo is square-ish; key art is not. The test is on the pixels rather than
	# on the entry's id, because "steam.<appid>" is only today's source of
	# portraits and the next one will not announce itself in the id.
	var squareish := absf(1.0 - float(width) / float(height)) <= TvTheme.HERO_ART_SQUARE_TOLERANCE
	var divisor := TvTheme.HERO_ART_BLUR_DIVISOR_SQUARE if squareish \
		else TvTheme.HERO_ART_BLUR_DIVISOR

	var small_w := maxi(TvTheme.HERO_ART_BLUR_MIN, width / divisor)
	var small_h := maxi(TvTheme.HERO_ART_BLUR_MIN,
		int(round(float(small_w) * float(height) / float(width))))
	image.resize(small_w, small_h, Image.INTERPOLATE_BILINEAR)

	var texture := ImageTexture.create_from_image(image)
	_remember_backdrop(key, texture)

	ShellLog.info("hero art: %s (%dx%d softened to %dx%d)"
		% [path, width, height, small_w, small_h])
	return texture


## The cache insert and the eviction that goes with it, in one place because the
## two must not drift: an insert that forgot the order list would be a dictionary
## that grows forever on a machine that never reboots.
func _remember_backdrop(key: String, texture: ImageTexture) -> void:
	_art_cache[key] = texture
	_art_cache_order.append(key)
	while _art_cache_order.size() > TvTheme.HERO_ART_CACHE_MAX:
		_art_cache.erase(_art_cache_order.pop_front())


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
	for button in _bar_buttons:
		button.focus_neighbor_bottom = button.get_path_to(selected)


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
		# Nothing selected means nothing to show a picture OF, and the last card
		# to be removed must not leave its backdrop behind on a screen that now
		# says the machine is empty.
		_request_hero_art("", true)

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
	# The panel is ABOUT one of the cards that is about to be freed, and after a
	# rescan the entry behind it may not exist any more. Closing it is the honest
	# response and the cheap one -- the list changing is rare (an install, a
	# removal, a picture arriving), and a panel that survived would be describing
	# a dictionary nothing on screen refers to.
	_close_details()

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


## A game's artwork landed (or changed, or went away).
##
## THE SAME REBUILD, ON PURPOSE. A card chooses its picture when it is built, so
## the only way new art reaches the screen is to build the cards again -- and
## _on_apps_changed is already the function that does that correctly: it frees
## the strip, repopulates it, rewires the neighbour table and puts focus back on
## the app the person was on BY ID. A second rebuild path would be a second copy
## of that focus restoration, and the two would drift the first time one of them
## learned something. The list it is handed is the current installed list rather
## than a new one, because nothing about what is installed has changed -- only
## what it looks like.
func _on_gameart_changed() -> void:
	_on_apps_changed(Installed.apps)


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
	# While the overlay is up the pad belongs to the overlay. Without this a
	# bridged application (Dolphin) receives an arrow for every menu move and a
	# BackSpace for the B that closes the menu -- input delivered twice, acted
	# on twice, visible once.
	#
	# IT STAYS PAUSED THROUGH THE KEYBOARD TOO, and that is why this is paired
	# with the overlay's lifetime rather than with the menu panel's. The menu's
	# Type entry swaps the panel for the on-screen keyboard on the same node
	# (see app_overlay.gd) -- so nothing here fires in between, and a stick
	# crossing a 5x10 grid cannot also be arrowing around the application
	# behind it. The bridge resumes in _close_overlay, once.
	Launcher.set_pad_keys_paused(true)
	# The launch splash stands down for the same span. It is only ever still up
	# when the application has not drawn yet -- which is precisely when someone
	# presses home to ask what is going on -- and its input eating would swallow
	# the A that chooses a menu entry. See launch_splash.gd.
	Launcher.set_splash_paused(true)


func _on_overlay_closed() -> void:
	_close_overlay.call_deferred()


## The overlay's single teardown, and it is single on purpose: the keyboard the
## Type entry puts up is a CHILD of the overlay, not a surface of its own, so
## freeing the overlay frees it too. That is what makes the awkward path safe --
## the application exiting while someone is mid-word arrives at
## _on_launch_finished, which calls this, and the keys go with the menu, the
## gamescope overlay flag and the pad-bridge pause. A sibling screen would have
## needed its own branch here and would have been the branch that got missed.
func _close_overlay() -> void:
	if _overlay == null:
		return
	var overlay := _overlay
	_overlay = null
	overlay.get_parent().remove_child(overlay)
	overlay.queue_free()
	Kiosk.set_overlay(false)
	Launcher.set_pad_keys_paused(false)
	Launcher.set_splash_paused(false)


## ---------------------------------------------------------------------------
## The details panel
## ---------------------------------------------------------------------------

## DOWN on a focused card, which was a dead axis until now -- see Tile._gui_input
## for why the press is caught on the card and not here.
##
## THE PANEL IS ADDITIVE, NOT A GATE. A on a card still launches it directly and
## nothing about that press changed; the panel is the second, slower route for
## the person who wants to know what a thing is before starting it, and it is
## where a game's description finally has somewhere to be. Anyone who never
## presses down sees exactly the shell they saw before.
##
## Guarded the way the card menu is, and for the same reason: each of these is a
## state in which the panel would be about something that is not on the screen.
func _on_details_requested(tile: Control) -> void:
	if _details != null:
		# A second press is the hold-repeat (FocusRepeat sends eight a second) or
		# a bounced button, not a request for two panels.
		return
	if Settings.is_open() or Stores.is_open() or Power.is_open() or Files.is_open() \
			or Launcher.is_busy():
		return
	if not is_instance_valid(tile) or not _tiles.has(tile):
		return

	_details_tile = tile
	_details = DetailsPanel.new()
	_details.entry = tile.entry
	_details.play_requested.connect(_on_details_play)
	_details.closed.connect(_on_details_closed)
	# A CHILD OF THE RAIL, unlike the card menu and the app overlay, which are
	# children of the tree root. Those two cover the shell; this one is part of
	# it -- the top half of the screen stays the selected game's background, and
	# the panel slides over the bottom half where the rail is. Last child, so it
	# paints over the rail it is covering.
	add_child(_details)


## Play: exactly the press the card already answers, asked of the card itself.
##
## The panel closes FIRST. The launch seam hides this whole surface a moment
## later (_hand_screen_over), and a panel still in the tree at that point would
## be what focus was remembered on -- so the rail would come back with the
## cursor on a button belonging to a screen the person had left.
func _on_details_play() -> void:
	var tile := _details_tile
	_close_details()
	if is_instance_valid(tile):
		tile.activate()


func _on_details_closed() -> void:
	_close_details.call_deferred()


## The panel's single teardown. Focus goes back to the card it was opened from,
## by identity: the rail never lost its shape while the panel was up, so the card
## is still there and is where the person was.
func _close_details() -> void:
	if _details == null:
		return
	var panel := _details
	var tile := _details_tile
	_details = null
	_details_tile = null
	panel.get_parent().remove_child(panel)
	panel.queue_free()
	# Only when the rail is what is on screen. A launch started from the panel
	# hides this surface between the two, and grabbing focus into a hidden
	# control would strand it there.
	if visible and is_instance_valid(tile) and _tiles.has(tile):
		tile.grab_focus()


## The options menu for the selected card. Guarded rather than always available,
## and every guard is a state in which the menu would be about the wrong thing.
func _open_card_menu() -> void:
	if _details != null:
		# The panel owns the screen and the pad while it is up. OPTIONS is about
		# the SELECTED CARD, and the selected card is behind a panel.
		return
	if _card_menu != null:
		# A second press while it is up is a bounced button, not a request for
		# two -- the same rule the other surfaces enforce.
		return
	if Settings.is_open() or Stores.is_open() or Power.is_open() or Files.is_open() \
			or Launcher.is_busy():
		# The rail is not what is on screen, so the selected card is not what the
		# person is looking at.
		return
	if _selected_entry.is_empty():
		ShellLog.info("OPTIONS at the rail with nothing selected; nothing to offer")
		return
	if str(_selected_entry.get("state", "")) != "installed":
		# A card for an application that is still downloading has nothing to
		# uninstall, and offering it would race the installer for the same
		# flatpak. The installer's own states say what is happening instead.
		ShellLog.info("OPTIONS on a card that is not installed yet; nothing to offer")
		return
	if str(_selected_entry.get("id", "")).begins_with("steam."):
		# A Steam game's install lives inside Steam's own library, and appctl
		# would rightly refuse its id. Removing one is Steam's job -- the menu
		# not opening is more honest than a menu whose one entry is refused.
		ShellLog.info("OPTIONS on a Steam game; removal belongs to Steam itself")
		return
	if Apps.is_busy():
		ShellLog.info("OPTIONS while another install or removal is in flight; ignoring")
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
	# WHILE THE PANEL IS UP, THE RAIL IS NOT LISTENING. The panel is a later
	# child and so is offered unhandled input first, and it consumes B -- but
	# relying on dispatch order for "B does not do two things at once" is the
	# assumption _hand_screen_over already refuses to make, and OPTIONS is not
	# consumed by anything.
	if _details != null:
		return

	# OPTIONS OPENS THE CARD'S OPTIONS. It is checked before B because it is the
	# only way to remove an application on a machine with no terminal, and it is
	# on the pad's own OPTIONS button rather than on a long-press of A because a
	# hold that means something different from a press is exactly the
	# interaction a person on a sofa discovers by accident and cannot undo.
	if InputMap.has_action("ui_shell_options") and event.is_action_pressed("ui_shell_options"):
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
