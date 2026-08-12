extends "res://src/settings_row.gd"

## One game the account owns: its picture, its name, and what this machine has
## done about it.
##
## It extends the settings row for the same reason every focusable rectangle in
## this shell does -- tabs, rows, menu items, cards and shelf tiles are ONE kind
## of object with ONE focus look, so a person who has learned what a lit
## rectangle means on the settings screen has learned it here. What is
## overridden is the row's CONTENTS and its shape: a settings row is a wide strip
## with a name on the left and a value on the right, and this is a portrait tile
## with a picture on top of two lines. Both overrides work because the base class
## connects its own method NAMES and GDScript resolves those on the instance.
##
## THE PICTURE IS PORTRAIT AND THE BOX IS CUT FOR IT. The client contract says a
## library image is library_600x900, which is 2:3 -- so this tile is not the
## deleted storefront's, whose box was cut for a 616x353 capsule. Feeding one
## into the other is not a layout nit: it is a black pillar down each side of
## every game on the screen.
##
## A TILE WITH NO PICTURE YET IS A NORMAL TILE, not a broken one. Artwork is
## fetched twenty-four appids at a time and lands minutes after the names on a
## cold machine, so the wash under the picture is the honest rendering of "the
## list arrived and this one's art has not" -- and because the wash is a
## rectangle of the right size, nothing reflows when the JPEG turns up.
##
## NOTHING HERE DECIDES ANYTHING. The tile draws a state word it is handed and
## emits when it is pressed; whether A installs, plays or opens a menu is the
## screen's call, because the screen is what knows about the launch seam and the
## menu. See steam_screen.gd.

signal opened(item: Dictionary)

# TvTheme and Icons are NOT re-declared: settings_row.gd already preloads both,
# GDScript inherits class constants, and re-declaring one is an error rather
# than a shadow.

## What the line under the name says, by the state word Steam.item_state gives.
## "" is a game that is simply not on the disk, which is the majority of any
## real library and is not a failure.
##
## THE WORDS ARE THE SHELL'S AND THE STATE IS THE SYSTEM'S, which is this
## project's standing division of labour (installed.gd's PENDING_SUBTITLES says
## it first): the service reports what is true, the shell decides how that reads
## on a television. `downloading` is deliberately absent -- it carries a number,
## so _state_line words it.
const STATE_LINES := {
	"": "Not installed",
	"queued": "Waiting to download",
	"installing": "Installing",
	"failed": "Download failed",
	"installed": "Installed",
}

## The states that name a problem rather than progress.
const STATE_ALERT := ["failed"]

var item: Dictionary = {}

var _art: TextureRect = null
var _wash: Panel = null
var _state: Label = null


func setup_item(new_item: Dictionary) -> void:
	item = new_item
	# The base still wants a name -- it is what the row logs and what an
	# accessibility pass would read. Here it is also drawn, by _build_contents.
	setup(str(item.get("name", "")), "")


func _ready() -> void:
	super._ready()

	# A fixed rectangle that neither expands nor stretches: the grid places
	# these, and a tile that filled its cell would make the last row's tiles a
	# different size from every other row's whenever a library did not divide by
	# the column count.
	custom_minimum_size = Vector2(TvTheme.STEAM_TILE_WIDTH, TvTheme.STEAM_TILE_HEIGHT)
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

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0, TvTheme.STEAM_TILE_ART_HEIGHT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(frame)

	# The wash sits UNDER the picture rather than instead of it -- see the
	# header. A StyleBoxFlat on a Panel and not a ColorRect, for tv_theme's
	# card_art_box reason: a ColorRect's four square corners draw outside the
	# tile's rounded ones.
	_wash = Panel.new()
	_wash.add_theme_stylebox_override("panel",
		TvTheme.card_art_box(TvTheme.accent_for_id(str(item.get("appid", "")))))
	_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_wash)

	_art = TextureRect.new()
	# COVERED rather than letterboxed: the box is cut to the library image's own
	# 2:3, so covering fills it edge to edge and the only thing ever cropped is a
	# pixel row from a picture Valve served slightly off-ratio. A game whose art
	# fell back to header.jpg (which is landscape) is the case this crops rather
	# than pillarboxes, and a cropped header still reads as the game.
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
	# tile that grew a second line would push the state line out of the rectangle
	# the grid reserved for it -- see STEAM_TILE_HEIGHT, which is a sum.
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	# ALWAYS PRESENT AS A NODE, whatever it says, so an installed game and one
	# that is not here are the same height and the shelf does not ripple as a
	# download finishes.
	_state = Label.new()
	_state.add_theme_font_size_override("font_size", TvTheme.STORE_ITEM_WAS_SIZE)
	_state.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_state)

	refresh_state()
	refresh_art()


## Redraw the line under the name. Called by the screen on every downloads
## arrival -- which is every two seconds while something is being fetched.
##
## IN PLACE RATHER THAN BY REBUILDING THE TILE, and that is the whole reason
## this function exists: a percentage that moves every two seconds would
## otherwise destroy and recreate the node the person's thumb is resting on,
## dropping focus into whatever Godot found next.
func refresh_state() -> void:
	if _state == null:
		return
	var appid := int(item.get("appid", 0))
	var word := Steam.item_state(appid)
	_state.text = _state_line(appid, word)
	_state.add_theme_color_override("font_color",
		TvTheme.TEXT_ALERT if STATE_ALERT.has(word) else TvTheme.TEXT_SECONDARY)


## THE PERCENTAGE IS THE POINT of the downloading case having no table entry. A
## screen that says the same sentence for forty minutes reads as a hung machine
## even while a multi-gigabyte download is going perfectly -- installed.gd made
## the same argument about the rail's cards, and a Steam download is the longest
## thing this appliance ever does.
func _state_line(appid: int, word: String) -> String:
	if word != "downloading":
		return str(STATE_LINES.get(word, STATE_LINES[""]))
	var download := Steam.download_for(appid)
	var percent := int(download.get("percent", 0))
	if percent > 0:
		return "Downloading %d%%" % percent
	# A download the service has started but not yet counted. "Downloading"
	# alone is true and says more than "0%", which reads as stuck.
	return "Downloading"


## Load the picture if it is on disk. Called again by the screen on every
## library arrival, because the JSON lands before the JPEGs on a cold machine
## and a tile built in that gap would stay a wash for the rest of the session.
func refresh_art() -> void:
	if _art == null:
		return
	if _art.texture != null:
		return
	var path := Steam.art_path(int(item.get("appid", 0)))
	if path.is_empty():
		return
	var image := Image.new()
	if image.load(path) != OK:
		# Warned, not fatal, and the wash stays showing -- the same contract as
		# every other art load in this shell. A half-written JPEG is the
		# realistic cause and the next refresh picks up the finished one.
		ShellLog.warn("steam: could not load %s" % path)
		return
	_art.texture = ImageTexture.create_from_image(image)
	_art.visible = true


## Has this tile got its picture yet? Asked by the screen, which re-asks the
## service for the library while any tile is still a wash -- artwork is fetched
## a bounded page at a time, so a large library is drawn over several requests
## and a fully drawn one must stop asking. See steam_screen's ART_REFETCH_SECONDS.
func has_art() -> bool:
	return _art != null and _art.texture != null


func _on_pressed() -> void:
	opened.emit(item)
