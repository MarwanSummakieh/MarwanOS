extends Button

## One card on the home rail.
##
## Still called tile.gd because the plan, ADR 0006 and the session notes all use
## that word for "the thing in the shell you move focus between"; renaming the
## file would break more prose than it fixes.
##
## Built as a Button rather than a Panel because Button already is what a card
## needs to be: focus_mode defaults to FOCUS_ALL, and it turns a `ui_accept` press
## on the focused control into a `pressed` signal without any of that having to be
## written here. A card built on Panel or TextureRect would default to FOCUS_NONE
## and never be reachable at all -- one of the quieter ways a console UI ships
## looking dead.
##
## SIZE IS THE SELECTION CHANNEL, NOT SCALE, and that is the substantive change
## from the grid version. Scaling a control leaves its layout box the old size, so
## a scaled card overlaps its neighbours instead of moving them. On a rail the
## neighbours moving IS the effect -- the strip opens up around the selection --
## so the card animates custom_minimum_size and lets the HBoxContainer re-flow.
## The cost is a real layout pass per frame during the tween, which is nothing for
## a dozen controls and is why this is affordable here and would not be in a list
## of hundreds.
##
## The look is entirely theme overrides rather than a .tres theme resource. Godot
## serialises a theme as a resource the editor owns, and this repo would rather
## have twenty reviewable lines in a file than a binary-shaped one; it also means
## the whole appearance is one grep away from the constants that justify it.

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

## The id prefix marwanos-appscan gives a Steam library entry, and the one thing
## in this file that knows a card can be a GAME rather than an application. It is
## the key into the artwork seam (GameArt) as well as the id of the record, which
## is why the test is a prefix on the id rather than a column of its own.
const STEAM_PREFIX := "steam."

## Emitted whenever this card takes focus, so the root can move the rail and swap
## the hero art. A signal rather than the root connecting to focus_entered
## directly: the root wants the entry, not the node, and this keeps the card's
## data private to the card.
signal selected(entry: Dictionary)

## Emitted when DOWN is pressed on this card: the request for the details panel.
## See _gui_input for why the press is caught here rather than in shell_root's
## _unhandled_input, which never sees it.
signal details_requested()

var entry: Dictionary = {}

## How large the card grows when focused. The rail's 340 by default; the store
## grid dials it down before add_child, because a growth that opens up a strip
## along one axis shoves a grid around on two. A variable rather than a second
## card class -- the difference is one number, and everything else about being
## a card (the press semantics especially) must stay identical.
var focused_size: int = TvTheme.CARD_FOCUSED_SIZE

## Typed StyleBox rather than StyleBoxFlat: a chromeless card's boxes are
## StyleBoxEmpty, which is a sibling of StyleBoxFlat and not a subclass of it.
var _idle_box: StyleBox
var _focus_box: StyleBox
var _ring: Panel
var _size_tween: Tween

## The picture this card draws, decoded once in _ready before anything is built.
##
## RESOLVED BEFORE THE CHROME RATHER THAN DURING IT, which is the whole reason
## the load moved out of _build_icon. Whether this card has a plate behind it
## depends on whether it has art to put there instead -- so the answer has to
## exist before the first stylebox is chosen, and "the file is named in the
## record" is not that answer. A path can name a file that was deleted between
## appscan's poll and this frame, or a PNG that does not decode; deciding on the
## path and then failing to load would leave a card with no plate AND no
## picture, which is a hole in the rail.
var _art: Image = null

## Whether this card is its own artwork, edge to edge, with no plate under it
## and no inset around it. See _wants_full_bleed.
var _full_bleed := false


func setup(new_entry: Dictionary) -> void:
	entry = new_entry


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(TvTheme.CARD_SIZE, TvTheme.CARD_SIZE)

	# Cards do not stretch. The rail is a fixed-size strip that slides; a card
	# that expanded would make its width depend on how many entries exist, and the
	# selected card's on-screen position is supposed to be a constant.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Button draws its own text centred, which is not the layout wanted here; the
	# card is art only, and the title lives in the hero block above the rail.
	text = ""

	# Both of these come before the styleboxes because the styleboxes depend on
	# them: a card that is its own artwork has no surface to tint.
	_art = _load_art()
	_full_bleed = _wants_full_bleed()

	if _full_bleed:
		# NO SURFACE AT ALL, in any state. The idle box is the plate this card
		# is doing without, and the focus box is that plate lit up -- neither
		# has anything to say about a tile that is entirely covered by its own
		# picture, and a lit surface behind an opaque image is a colour nobody
		# can see being tweened for nothing. Selection is still carried by size
		# and by the ring, which is two of the three channels the theme's
		# FOCUS_RING_WIDTH note names; the third was the surface, and a game's
		# key art is a better answer than a shade of grey.
		_idle_box = StyleBoxEmpty.new()
		_focus_box = StyleBoxEmpty.new()
	else:
		_idle_box = TvTheme.card_idle_box()
		_focus_box = TvTheme.card_focus_box()

	# Hover is bound to the same box as normal because there is no pointer on this
	# machine and a mouse that wandered in should not light a card up as if it
	# were focused.
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", _focus_box)
	add_theme_stylebox_override("disabled", _idle_box)
	# NOT the ring. Button paints its focus stylebox in its own draw pass, and
	# children paint after their parent -- so the full-bleed art in
	# _build_contents would cover every pixel of a ring drawn here. The ring is
	# the overlay child built after the art instead; this override only stops
	# Button drawing its default focus box invisibly underneath it.
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_build_contents()

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)


func _build_contents() -> void:
	# The wash, and a chromeless card does not get one. It is the card's
	# surface, and this card's surface is the game's own picture -- a wash
	# behind an image that covers every pixel of it is a colour nobody can see.
	#
	# Where it IS built it is unchanged: full-bleed inside the card's rounded
	# box rather than inset, because a card that frames itself in another colour
	# reads as unfinished. An installed app derives its wash from its id (see
	# TvTheme.accent_for_id); a hand-written entry carries one.
	#
	# A Panel with a rounded stylebox, NOT a ColorRect. A ColorRect draws a hard
	# rectangle whatever is underneath it, so its corners sat outside the rounded
	# ring and the rounded card box -- the art visibly leaking past its own
	# border on the TV. See TvTheme.card_art_box.
	if not _full_bleed:
		var art := Panel.new()
		art.add_theme_stylebox_override("panel", TvTheme.card_art_box(_wash()))
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)

	_build_icon()

	# The ring rides above the art AND the icon as the last child, because
	# siblings paint in tree order and the art is full-bleed: anything drawn
	# before it -- including the Button's own focus stylebox -- is entirely
	# behind an opaque rectangle. Toggled by the focus handlers below, since a
	# plain child knows nothing of the theme system's focus state.
	#
	# SQUARE ON A CHROMELESS CARD. There is no rounded plate under the picture
	# to follow any more, so a rounded ring would cut the corners off a square
	# image and let them poke out past it -- the same leak card_art_box's
	# comment describes, arriving from the other side.
	_ring = Panel.new()
	_ring.add_theme_stylebox_override("panel",
		TvTheme.card_focus_ring(0 if _full_bleed else TvTheme.CARD_CORNER_RADIUS))
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.visible = false
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)


## Whether this card should be its own picture, edge to edge, with no plate.
##
## THE ASK WAS "NO CARDS AROUND THE GAME ICONS", and the word doing the work is
## GAME. A game's tile is key art: a picture drawn to be looked at, already the
## right shape, and the thing a console home screen is made of -- a plate around
## it and a 34 px gutter inside that plate turns it into a stamp on a coloured
## square, which is the PS5 look inverted. An application's icon is the opposite
## kind of picture: a logo with transparency around it, drawn to sit ON
## something, at whatever aspect its author chose. Blown up to the full tile it
## is a cropped logo on the desktop background, which is worse than the plate it
## replaced, so applications keep theirs.
##
## ART IS REQUIRED, not merely expected. A game whose picture has not been
## fetched yet -- installed minutes ago, storeart's timer not yet around, Steam's
## own cache still cold -- has nothing to fill a tile with, and a chromeless card
## with no picture is not a card at all, it is a gap in the rail where a game
## should be. Those keep the plate and the accent wash until the file lands, and
## the next rebuild (shell_root._on_gameart_changed) promotes them silently.
func _wants_full_bleed() -> bool:
	if _art == null:
		return false
	return str(entry.get("id", "")).begins_with(STEAM_PREFIX)


func _wash() -> Color:
	# A hand-written entry states its accent; an enumerated application has no
	# such thing and derives one from its id instead.
	var stated := str(entry.get("accent", ""))
	if not stated.is_empty():
		return TvTheme.accent(stated)
	return TvTheme.accent_for_id(str(entry.get("id", "")))


## The pictures this card would like to draw, best first.
##
## A GAME PREFERS ITS SQUARE ICON TO ITS PORTRAIT, and that is the whole of this
## function. appscan puts Steam's library_600x900 portrait in the record's icon
## column because it is the one picture every game has -- but a 2:3 portrait
## letterboxed inside a square card is a thin strip of art with two bands of wash
## either side, which is exactly what the rail looked like before the artwork
## seam existed. The square icon Steam also caches fills the card the way an
## application's logo does, so the rail reads as one family of cards instead of
## two.
##
## THE PORTRAIT STAYS AS THE FALLBACK rather than being replaced: the icon
## arrives when Steam's cache warms, which is minutes-to-never after a fresh
## install, and a card that waited for it would be a wash with nothing on it in
## the meantime. Ordered, not chosen, so a file that has gone missing between the
## scan and this frame falls through to the next candidate instead of leaving a
## blank card -- see the loop in _load_art.
func _art_candidates() -> Array:
	var candidates: Array = []

	var id := str(entry.get("id", ""))
	if id.begins_with(STEAM_PREFIX):
		var square := GameArt.icon_for(id)
		if not square.is_empty():
			candidates.append(square)

	var stated := str(entry.get("icon", ""))
	if not stated.is_empty():
		candidates.append(stated)

	return candidates


## The best candidate that actually decodes, or null.
##
## SPLIT OUT OF _build_icon SO THE ANSWER EXISTS BEFORE THE CHROME DOES -- see
## the _art field. Nothing about which file wins changed: the candidates are
## still in _art_candidates' order, still tried in order so a file that went
## missing between the scan and this frame falls through to the next, and the
## journal still says so only when the game's own icon is what won.
##
## LOADED AT RUNTIME RATHER THAN PRELOADED, and that is forced rather than
## chosen: these files live on the running system (/usr/share/icons, and the
## flatpak exports that only exist after an install), not in the export pack, so
## `preload` cannot see them and `load()` would look under res://. Image plus
## ImageTexture is the runtime path for a file on disk.
##
## A missing, unreadable or corrupt icon is not an error worth a black card: the
## wash is exactly what a card with no icon has always drawn, so every failure
## here falls back to it silently -- and now also decides the card keeps its
## plate, which is the same fallback said twice. appscan already guarantees the
## path existed at scan time; this handles the file disappearing between the
## scan and the frame.
func _load_art() -> Image:
	for path in _art_candidates():
		var image := load_icon_image(str(path))
		if image != null:
			# Said out loud only when the game's own icon won, because that is the
			# line that distinguishes "the artwork cache has warmed" from "the
			# portrait is still all there is" on a machine with no screen to look
			# at. The ordinary case -- an application drawing the icon appscan
			# found -- stays silent, as it always has.
			if str(path) != str(entry.get("icon", "")):
				ShellLog.info("card art: %s uses %s" % [str(entry.get("id", "")), path])
			return image
		ShellLog.warn("could not load icon %s for %s" % [path, str(entry.get("id", ""))])
	return null


func _build_icon() -> void:
	if _art == null:
		# No file on disk to draw, but the entry may name a Phosphor glyph. A
		# card that is only its accent wash reads as a loading failure next to
		# neighbours with real logos, and an application whose flatpak exports
		# no icon and whose Flathub art has not been fetched yet is exactly
		# that card. The glyph is the card's icon the same way the wash is its
		# art: sized to the same inset the PNG icons respect, so the two card
		# kinds read as one family. It does not grow with the focus tween the
		# way a texture does -- a Label's font size is fixed -- which is a
		# known, minor asymmetry and cheaper than re-rendering type per frame.
		#
		# NO ENTRY NAMES ONE TODAY: the Files card was the only "glyph" in the
		# catalogue and it is a top-bar icon now. Kept because appscan's
		# records are the source of every other card and it cannot promise an
		# icon path -- this is the fallback for the day one of them arrives
		# bare, and it is nine lines.
		var glyph_name := str(entry.get("glyph", ""))
		if glyph_name.is_empty():
			return
		var glyph := Icons.label(glyph_name,
			TvTheme.CARD_SIZE - 2 * TvTheme.CARD_ICON_INSET, TvTheme.TEXT_PRIMARY)
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(glyph)
		return

	var icon := TextureRect.new()
	icon.texture = ImageTexture.create_from_image(_art)
	# IGNORE_SIZE lets the rect shrink below the texture's own size, which it
	# must: these are 256 px icons and 600x900 portraits inside a 200 px card at
	# rest.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if _full_bleed:
		# COVERED, NOT CENTERED, and it is the only stretch mode that can honour
		# "no card". Centered fits the picture INSIDE the tile, so anything that
		# is not square leaves bars down two sides -- and with the plate gone
		# those bars are not a wash any more, they are whatever the home screen
		# is drawing behind the rail. Covered fills the tile and crops the
		# overflow instead.
		#
		# What gets cropped is nearly always nothing. _art_candidates prefers
		# Steam's square library icon, which is already the tile's aspect, so
		# this is a no-op in the warm case. The one shape it does cut is the
		# 600x900 portrait standing in until that icon arrives, and taking the
		# middle square of a portrait is what every console library does with
		# one.
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		# KEEP_ASPECT_CENTERED so a non-square icon is letterboxed inside the card
		# rather than stretched -- a distorted logo is more obviously wrong than a
		# small one.
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.offset_left = TvTheme.CARD_ICON_INSET
		icon.offset_top = TvTheme.CARD_ICON_INSET
		icon.offset_right = -TvTheme.CARD_ICON_INSET
		icon.offset_bottom = -TvTheme.CARD_ICON_INSET

	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)


## What a rasterised SVG is rendered at, in pixels on the long edge.
##
## Comfortably above CARD_FOCUSED_SIZE rather than equal to it: the card grows
## when focused and the texture is not re-rendered, so rasterising at exactly
## the resting size would leave every selected card soft -- which is the state
## the card spends its time in when someone is actually looking at it.
const ICON_RASTER_PX := 512


## An Image for an icon path, PNG or SVG.
##
## SVG IS WHY ZEN'S CARD WAS A COLOURED RECTANGLE. Its flatpak exports exactly
## one icon and it is scalable, so appscan -- PNG-only until now -- found
## nothing and the card fell back to its accent wash. That is not a rare shape:
## a lot of modern applications ship only an SVG.
##
## RENDERED TWICE, ON PURPOSE. load_svg_from_buffer's scale multiplies the
## drawing's intrinsic size, and an app icon's intrinsic size is anywhere from
## 16 to 512 depending on who drew it -- so a fixed scale would rasterise some
## icons at 64 px and others at 4096. The first pass measures, the second
## renders at a known size. Both are cheap and this runs once per card.
##
## A build without the SVG module returns an error rather than crashing, and
## the caller falls back to the wash -- which is the behaviour appscan's old
## comment was protecting, kept, but decided here where it can be detected
## instead of assumed.
##
## STATIC AND SHARED, not private: launch_splash.gd draws the same icon the
## card carried, and two copies of the SVG two-pass would drift the first time
## one of them learned something the other did not. It lives here rather than
## in a module of its own because the card is where every rule above was paid
## for, and Phase 1's key-art pass replaces both call sites at once.
static func load_icon_image(path: String) -> Image:
	if path.get_extension().to_lower() != "svg":
		return Image.load_from_file(path)

	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null

	var probe := Image.new()
	if probe.load_svg_from_buffer(bytes, 1.0) != OK:
		return null
	var longest := maxi(probe.get_width(), probe.get_height())
	if longest <= 0:
		return null
	if longest >= ICON_RASTER_PX:
		return probe

	var full := Image.new()
	if full.load_svg_from_buffer(bytes, float(ICON_RASTER_PX) / float(longest)) != OK:
		# The measured pass already succeeded, so something small is better than
		# a card with no logo on it.
		return probe
	return full


## Grows or shrinks the card in the layout. See the class header for why this is
## custom_minimum_size and not scale.
func set_selected_size(is_selected: bool) -> void:
	var target := float(focused_size if is_selected else TvTheme.CARD_SIZE)

	if _size_tween != null and _size_tween.is_valid():
		_size_tween.kill()
	_size_tween = create_tween()
	_size_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_size_tween.tween_property(
		self, "custom_minimum_size", Vector2(target, target), TvTheme.RAIL_TWEEN_SECONDS)


func _on_focus_entered() -> void:
	add_theme_stylebox_override("normal", _focus_box)
	add_theme_stylebox_override("hover", _focus_box)
	_ring.visible = true
	set_selected_size(true)
	selected.emit(entry)


func _on_focus_exited() -> void:
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	_ring.visible = false
	set_selected_size(false)


## DOWN OPENS THE DETAILS PANEL, and it is caught here rather than in
## shell_root's _unhandled_input because _unhandled_input never sees it.
##
## The rail's cards point focus_neighbor_bottom at THEMSELVES (see
## shell_root._wire_focus_neighbours), which is the hard stop that keeps the
## viewport's geometric search out of the hint row. But a hard stop is not a
## discarded press: the viewport resolves the neighbour to this same card, grabs
## focus on it, and calls set_input_as_handled -- so the event is consumed
## several steps before any _unhandled_input handler runs. That is why DOWN has
## looked like a dead axis, and it is dead in exactly the way that hides the
## press from everything downstream.
##
## A focused Control's _gui_input runs BEFORE that navigation block, and only
## for the control that holds focus -- which is the card the person is looking
## at. accept_event() stops the navigation, so the hard stop is preserved for
## every card that does not open a panel.
##
## ONLY AN INSTALLED CARD HAS DETAILS, the same policy _on_pressed applies and
## for the same reason: the panel's one button launches, an application that is
## not on the machine cannot be launched, and a panel whose button is correctly
## refused is the shape of broken input on a machine with no other feedback. The
## card's own subtitle already says what state it is in.
func _gui_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_down"):
		return
	accept_event()

	var state := str(entry.get("state", "installed"))
	if state != "installed":
		ShellLog.info("no details for \"%s\": %s"
			% [str(entry.get("title", "")), state])
		return

	details_requested.emit()


func _on_pressed() -> void:
	activate()


## The card's press, callable from somewhere that is not the card.
##
## SPLIT OUT FOR THE DETAILS PANEL'S PLAY BUTTON, which must do exactly what
## pressing the card does -- including the two refusals below, which are policy
## the panel has no business restating. The panel asks the card to act rather
## than reaching for the launch seam itself, so there stays exactly one place
## that decides what an A press on an entry means.
func activate() -> void:
	# An app that is still downloading has no exec yet, and handing an entry
	# with an empty exec to the launch seam would take the placeholder branch
	# -- a fullscreen scene claiming to have launched something that does not
	# exist on the machine. Refusing here, at the one place that knows the
	# card's state, keeps the seam itself free of policy: Launcher.launch is
	# still the only call into the launch path, and it still does exactly one
	# thing to everything it is given.
	#
	# It logs rather than doing nothing silently, for settings_row.gd's reason:
	# on this machine a press that vanishes is indistinguishable from broken
	# input, and the card's own subtitle already says why it will not open.
	#
	# EVERY CARD IS AN APPLICATION. A "surface" branch used to sit above this,
	# routing the Files card's press to Files.open instead of to the launch
	# seam; the file manager is a top-bar icon now (see catalogue.gd) and the
	# branch went with its only entry. A shell surface reached from the bar
	# calls its seam directly, which is what the gear and the power button
	# always did.
	var state := str(entry.get("state", "installed"))

	# AN AVAILABLE CARD DOWNLOADS ITSELF. These are the applications the image
	# ships that are not on the machine -- never installed, or removed on
	# purpose -- and before they existed the only way back from an uninstall was
	# the stores screen, which covers stores and therefore never covered Kodi.
	# The card IS the install button, which is what a person expects from a
	# thing that looks like an app and says it is not installed.
	if state == "available":
		if Apps.is_busy():
			ShellLog.info("install requested while another request is in flight; ignoring")
			return
		Apps.request_install(str(entry.get("id", "")))
		return

	# An app that is still downloading has no exec yet, and handing an entry
	# with an empty exec to the launch seam would take the placeholder branch.
	if state != "installed":
		ShellLog.info("\"%s\" is not installed yet (%s); not launching"
			% [str(entry.get("title", "")), state])
		return

	# The only call into the launch seam anywhere in the project.
	Launcher.launch(entry)
