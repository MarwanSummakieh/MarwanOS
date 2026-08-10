extends "res://src/settings_row.gd"

## One game on the storefront grid: its capsule, its name, and what it costs.
##
## It extends the settings row for store_tab.gd's reason, and the reason is
## worth repeating because this is the third member of the family: tabs, rows,
## menu items, cards and now shelf tiles are ONE kind of focusable rectangle
## with ONE focus look, so a person who has learned what a lit rectangle means
## on the settings screen has learned it here too. What this overrides is the
## row's CONTENTS and its shape -- a settings row is a wide strip with a name on
## the left and a value on the right; this is a portrait-ish tile with a picture
## on top. Both overrides work because the base class calls its own method
## names and GDScript resolves those on the instance.
##
## THE PICTURE IS THE REAL CAPSULE, fetched by marwanos-steamfront and read off
## disk like every other image in this shell. A tile with no picture yet draws
## the accent wash and its name, which is the same fallback the rail's cards and
## the store tabs have always had -- and on this screen it is also the honest
## rendering of "the JSON arrived and the art has not", which happens for a
## second or two on a cold machine.
##
## NOTHING HERE CAN SPEND MONEY. A tile shows a price because a storefront that
## hides prices is a worse storefront; pressing it opens a page, and the only
## button on that page hands the game to Steam. See stores_screen.gd.

signal opened(item: Dictionary)

# TvTheme and Icons are NOT re-declared: settings_row.gd already preloads both,
# GDScript inherits class constants, and re-declaring one is an error rather
# than a shadow.

var item: Dictionary = {}

## Which picture this tile is for. A shelf tile has a 616x353 capsule waiting for
## it; a SEARCH RESULT has whatever `storesearch` returned, which is a 231x87
## one. Set before add_child, like every other configuration in this tree.
##
## It is a flag rather than two tile classes because the difference really is one
## path lookup: the same rectangle, the same focus look, the same price line, the
## same detail page behind it. See Steamfront.search_art_path, which prefers the
## big capsule anyway when the game also happens to be on a shelf -- so a search
## for something the front page is already showing draws at full fidelity and
## only a game the shell has never fetched draws soft.
var small_art: bool = false

var _art: TextureRect = null
var _wash: Panel = null


func setup_item(new_item: Dictionary) -> void:
	item = new_item
	# The base still wants a name -- it is what the row logs and what an
	# accessibility pass would read. Here it is also drawn, by _build_contents.
	setup(str(item.get("name", "")), "")


func _ready() -> void:
	super._ready()

	# A fixed rectangle that neither expands nor stretches: the grid places
	# these, and a tile that filled its cell would make one shelf's tiles a
	# different size from another's whenever a row was short.
	custom_minimum_size = Vector2(TvTheme.STORE_ITEM_WIDTH, TvTheme.STORE_ITEM_HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## Replaces the base's name/value strip entirely.
func _build_contents() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", TvTheme.STORE_ITEM_PAD)
	pad.add_theme_constant_override("margin_right", TvTheme.STORE_ITEM_PAD)
	pad.add_theme_constant_override("margin_top", TvTheme.STORE_ITEM_PAD)
	pad.add_theme_constant_override("margin_bottom", TvTheme.STORE_ITEM_PAD)
	add_child(pad)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.STORE_ITEM_PAD / 2)
	pad.add_child(column)

	# The wash sits UNDER the picture rather than instead of it, so a tile whose
	# art has not landed yet is a coloured rectangle of the right size instead
	# of a collapsed row -- and so the moment art arrives nothing reflows. A
	# StyleBoxFlat on a Panel, not a ColorRect, for tv_theme's card_art_box
	# reason: a ColorRect's square corners draw outside the rounded tile.
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0, TvTheme.STORE_ITEM_ART_HEIGHT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(frame)

	_wash = Panel.new()
	_wash.add_theme_stylebox_override("panel",
		TvTheme.card_art_box(TvTheme.accent_for_id(str(item.get("appid", "")))))
	_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_wash)

	_art = TextureRect.new()
	# KEEP_ASPECT_COVERED, unlike the rail's cards and the store tabs, and the
	# difference is what the picture IS. Those draw square icons into square
	# boxes and letterbox anything else; this box is cut to the capsule's own
	# aspect, so covering fills it edge to edge and the only thing ever cropped
	# is a pixel row from a capsule Valve served slightly off-ratio.
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	frame.add_child(_art)

	var name_label := Label.new()
	name_label.text = str(item.get("name", ""))
	name_label.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	name_label.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	# One line with an ellipsis rather than wrapping: game names run long, and a
	# tile that grew a second line would push the price out of the rectangle the
	# grid reserved for it.
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var prices: Array = Steamfront.price_lines(item)
	var price_label := Label.new()
	price_label.text = str(prices[0])
	price_label.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	price_label.add_theme_color_override("font_color",
		TvTheme.TEXT_DISCOUNT if not str(prices[1]).is_empty() else TvTheme.TEXT_PRIMARY)
	price_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(price_label)

	# The old price is a SECOND LINE and always present as a node, so a
	# discounted tile and an undiscounted one are the same height. See
	# Steamfront.price_lines for why it is worded rather than struck through.
	var was_label := Label.new()
	was_label.text = str(prices[1])
	was_label.add_theme_font_size_override("font_size", TvTheme.STORE_ITEM_WAS_SIZE)
	was_label.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	was_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	was_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(was_label)

	refresh_art()


## Load the capsule if it is on disk. Called again by the screen when the seam
## reports new results, because on a cold machine the JSON lands a second or two
## before the pictures do and a tile built in that gap would stay a wash
## forever otherwise.
func refresh_art() -> void:
	if _art == null:
		return
	if _art.texture != null:
		return
	var appid := int(item.get("appid", 0))
	var path := Steamfront.search_art_path(appid) if small_art else Steamfront.art_path(appid)
	if path.is_empty():
		return
	var image := Image.new()
	if image.load(path) != OK:
		# Warned, not fatal, and the wash stays showing -- the same contract as
		# tile.gd's and store_tab.gd's icon loads. A half-written JPEG is the
		# realistic cause and the next refresh picks up the finished one.
		ShellLog.warn("steamfront: could not load %s" % path)
		return
	_art.texture = ImageTexture.create_from_image(image)
	_art.visible = true


func _on_pressed() -> void:
	opened.emit(item)
