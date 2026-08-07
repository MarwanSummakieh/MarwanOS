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

## Emitted whenever this card takes focus, so the root can move the rail and swap
## the hero art. A signal rather than the root connecting to focus_entered
## directly: the root wants the entry, not the node, and this keeps the card's
## data private to the card.
signal selected(entry: Dictionary)

var entry: Dictionary = {}

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
		return

	var image := Image.load_from_file(path)
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


## Grows or shrinks the card in the layout. See the class header for why this is
## custom_minimum_size and not scale.
func set_selected_size(is_selected: bool) -> void:
	var target := float(TvTheme.CARD_FOCUSED_SIZE if is_selected else TvTheme.CARD_SIZE)

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
	if str(entry.get("state", "installed")) != "installed":
		ShellLog.info("\"%s\" is not installed yet (%s); not launching"
			% [str(entry.get("title", "")), str(entry.get("state", ""))])
		return

	# The only call into the launch seam anywhere in the project.
	Launcher.launch(entry)
