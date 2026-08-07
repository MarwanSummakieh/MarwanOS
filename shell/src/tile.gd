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
	# Stands in for the icon Phase 1 loads from the daemon's cache. Full-bleed
	# inside the card's rounded box rather than inset: real key art has no margin,
	# and a card that frames its art in surface colour looks like a placeholder
	# even once the art is real.
	var art := ColorRect.new()
	art.color = TvTheme.accent(str(entry.get("accent", "")))
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	# The ring rides above the art as the last child, because siblings paint in
	# tree order and the art is full-bleed: anything drawn before it -- including
	# the Button's own focus stylebox -- is entirely behind an opaque rectangle.
	# Toggled by the focus handlers below, since a plain child knows nothing of
	# the theme system's focus state.
	_ring = Panel.new()
	_ring.add_theme_stylebox_override("panel", TvTheme.card_focus_ring())
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.visible = false
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)


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
	# The only call into the launch seam anywhere in the project.
	Launcher.launch(entry)
