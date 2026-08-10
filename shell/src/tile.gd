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

## Emitted whenever this card takes focus, so the root can move the rail and swap
## the hero art. A signal rather than the root connecting to focus_entered
## directly: the root wants the entry, not the node, and this keeps the card's
## data private to the card.
signal selected(entry: Dictionary)

var entry: Dictionary = {}

## How large the card grows when focused. The rail's 340 by default; the store
## grid dials it down before add_child, because a growth that opens up a strip
## along one axis shoves a grid around on two. A variable rather than a second
## card class -- the difference is one number, and everything else about being
## a card (the press semantics especially) must stay identical.
var focused_size: int = TvTheme.CARD_FOCUSED_SIZE

var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat
var _ring: Panel
var _size_tween: Tween


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
	# The wash. Full-bleed inside the card's rounded box rather than inset: it
	# is the card's surface, and a card that frames itself in another colour
	# reads as unfinished. An installed app derives its wash from its id (see
	# TvTheme.accent_for_id); a hand-written entry carries one.
	#
	# A Panel with a rounded stylebox, NOT a ColorRect. A ColorRect draws a hard
	# rectangle whatever is underneath it, so its corners sat outside the rounded
	# ring and the rounded card box -- the art visibly leaking past its own
	# border on the TV. See TvTheme.card_art_box.
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
	_ring = Panel.new()
	_ring.add_theme_stylebox_override("panel", TvTheme.card_focus_ring())
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.visible = false
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)


func _wash() -> Color:
	# A hand-written entry states its accent; an enumerated application has no
	# such thing and derives one from its id instead.
	var stated := str(entry.get("accent", ""))
	if not stated.is_empty():
		return TvTheme.accent(stated)
	return TvTheme.accent_for_id(str(entry.get("id", "")))


## The application's real icon, loaded from the absolute path marwanos-appscan
## resolved out of the icon theme.
##
## LOADED HERE RATHER THAN PRELOADED, and that is forced rather than chosen:
## these files live on the running system (/usr/share/icons, and the flatpak
## exports that only exist after an install), not in the export pack, so
## `preload` cannot see them and `load()` would look under res://. Image plus
## ImageTexture is the runtime path for a file on disk.
##
## A missing, unreadable or corrupt icon is not an error worth a black card:
## the wash underneath is exactly what a card with no icon has always drawn, so
## every failure here falls back to it silently. appscan already guarantees the
## path is a PNG that existed at scan time; this handles the file disappearing
## between the scan and the frame.
func _build_icon() -> void:
	var path := str(entry.get("icon", ""))
	if path.is_empty():
		# No file on disk to draw, but the entry may name a Phosphor glyph --
		# the shell's built-in surfaces (the Files card) have no flatpak
		# export and no storeart cache entry, and a card that is only its
		# accent wash reads as a loading failure next to neighbours with real
		# logos. The glyph is the card's icon the same way the wash is its
		# art: sized to the same inset the PNG icons respect, so the two card
		# kinds read as one family. It does not grow with the focus tween the
		# way a texture does -- a Label's font size is fixed -- which is a
		# known, minor asymmetry and cheaper than re-rendering type per frame.
		var glyph_name := str(entry.get("glyph", ""))
		if glyph_name.is_empty():
			return
		var glyph := Icons.label(glyph_name,
			TvTheme.CARD_SIZE - 2 * TvTheme.CARD_ICON_INSET, TvTheme.TEXT_PRIMARY)
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(glyph)
		return

	var image := load_icon_image(path)
	if image == null:
		ShellLog.warn("could not load icon %s for %s" % [path, str(entry.get("id", ""))])
		return

	var icon := TextureRect.new()
	icon.texture = ImageTexture.create_from_image(image)
	# KEEP_ASPECT_CENTERED so a non-square icon is letterboxed inside the card
	# rather than stretched -- a distorted logo is more obviously wrong than a
	# small one. IGNORE_SIZE lets the rect shrink below the texture's own size,
	# which it must: these are 256 px icons inside a 200 px card at rest.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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


func _on_pressed() -> void:
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
	# A SURFACE CARD OPENS A SEAM, NOT A PROCESS. The shell's own screens wear
	# cards too (the Files card), and their press is a screen swap through the
	# surface's seam -- the same call the top bar's gear makes for settings.
	# Routed here, before the state ladder, because a surface entry says
	# "installed" truthfully and must still never reach Launcher.launch: there
	# is no process to spawn, and the placeholder branch claiming one would be
	# the exact lie the state checks below exist to prevent.
	var surface := str(entry.get("surface", ""))
	if not surface.is_empty():
		match surface:
			"files":
				Files.open()
			_:
				ShellLog.error("card \"%s\" names surface \"%s\", which no seam answers"
					% [str(entry.get("title", "")), surface])
		return

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
