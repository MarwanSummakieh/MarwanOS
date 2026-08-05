extends Button

## One tile in the grid.
##
## Built as a Button rather than a Panel because Button already is what a tile
## needs to be: focus_mode defaults to FOCUS_ALL, and it turns a `ui_accept` press
## on the focused control into a `pressed` signal without any of that having to be
## written here. A tile built on Panel or TextureRect would default to FOCUS_NONE
## and never be reachable at all -- one of the quieter ways a grid ends up
## un-navigable.
##
## The look is entirely theme overrides rather than a .tres theme resource. Godot
## serialises a theme as a resource the editor owns, and this repo would rather
## have twenty reviewable lines in a file than a binary-shaped one; it also means
## the whole appearance is one grep away from the constants that justify it.

const TvTheme = preload("res://src/tv_theme.gd")

var entry: Dictionary = {}

var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat
var _scale_tween: Tween


func setup(new_entry: Dictionary) -> void:
	entry = new_entry


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, TvTheme.TILE_MIN_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Button draws its own text centred, which is not the layout wanted here; the
	# labels are children instead.
	text = ""

	_idle_box = TvTheme.tile_idle_box()
	_focus_box = TvTheme.tile_focus_box()

	# Button draws one of normal/hover/pressed and then the focus box over it.
	# Hover is bound to the same box as normal because there is no pointer on this
	# machine and a mouse that wandered in should not light a tile up as if it
	# were focused.
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", _focus_box)
	add_theme_stylebox_override("disabled", _idle_box)
	add_theme_stylebox_override("focus", TvTheme.tile_focus_ring())

	_build_contents()

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)
	resized.connect(_recentre_pivot)
	_recentre_pivot()


func _build_contents() -> void:
	var padding := MarginContainer.new()
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", TvTheme.TILE_PADDING)
	padding.add_theme_constant_override("margin_right", TvTheme.TILE_PADDING)
	padding.add_theme_constant_override("margin_top", TvTheme.TILE_PADDING)
	padding.add_theme_constant_override("margin_bottom", TvTheme.TILE_PADDING)
	add_child(padding)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	padding.add_child(column)

	# Stands in for the icon Phase 1 loads from the daemon's cache. It expands, so
	# it absorbs whatever height the grid gives the tile and the two text lines
	# stay put at the bottom.
	var art := ColorRect.new()
	art.color = TvTheme.accent(str(entry.get("accent", "")))
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art)

	column.add_child(_label(
		str(entry.get("title", "")),
		TvTheme.SIZE_TILE_TITLE,
		TvTheme.TEXT_PRIMARY))
	column.add_child(_label(
		str(entry.get("subtitle", "")),
		TvTheme.SIZE_SUPPLEMENTAL,
		TvTheme.TEXT_SECONDARY))


func _label(value: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	# Ellipsis rather than wrapping: a tile that grows a second line pushes the
	# art around and makes the grid ragged. Real application names are long.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Scale is applied about the tile's own centre, so it grows in place instead of
## sliding towards the top-left. The container resizes the tile whenever the
## window does, hence the reconnect on `resized` rather than a one-off in _ready.
func _recentre_pivot() -> void:
	pivot_offset = size * 0.5


func _on_focus_entered() -> void:
	# Channel two of three: a brighter surface under the ring. See TvTheme's
	# header for why one channel is not enough on a television.
	add_theme_stylebox_override("normal", _focus_box)
	add_theme_stylebox_override("hover", _focus_box)
	# Above its neighbours, so the scaled edges and the ring are never clipped by
	# the tile drawn after it.
	z_index = 1
	_scale_to(TvTheme.FOCUS_SCALE)


func _on_focus_exited() -> void:
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	z_index = 0
	_scale_to(1.0)


func _scale_to(factor: float) -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2(factor, factor), TvTheme.FOCUS_TWEEN_SECONDS)


func _on_pressed() -> void:
	# The only call into the launch seam anywhere in the project.
	Launcher.launch(entry)
