extends "res://src/settings_row.gd"

## One tab in the stores screen's side column: the store's own icon, and
## nothing else.
##
## It still extends the settings row so tabs, rows, menu items and cards stay
## one family of focusable rectangles with one focus look. What it overrides is
## the row's CONTENTS and its shape -- a settings row is a wide strip with a
## name on the left and a value on the right, and this is a square carrying one
## mark. Both overrides work for the same reason `_on_pressed` does: the base
## class calls its own method names, and GDScript resolves those calls on the
## instance.
##
## WHY THE NAME IS GONE. There is one store, its icon is the most recognisable
## thing about it, and the page to the right already says "Steam" at
## SIZE_HERO_TITLE the moment the tab takes focus -- so the word in the tab was
## the same word twice, and it set the column's width at 420 px to hold it. A
## column of marks is also what the shape is copied from: the PS Store's rail,
## and every other side rail on a TV, is icons.
##
## THE ICON IS THE REAL ONE, NOT A GLYPH, when there is one to have. It comes
## from the installed seam -- marwanos-appscan already resolved an absolute path
## out of the icon theme for every installed app, which is the same path the
## rail's cards draw (see tile.gd). A store whose application is not installed
## yet has no icon on disk at all, and that is the usual state of a fresh stick,
## so the Phosphor storefront mark stands in until the install lands and the
## seam reports a path. Nothing here walks a directory.

signal opened(entry: Dictionary)

# TvTheme and Icons are NOT re-declared here: settings_row.gd already preloads
# both, GDScript inherits class constants, and re-declaring one is an error
# ("already exists in parent class") rather than a shadow.

## The mark shown before the application is installed and has a real icon.
const FALLBACK_ICON := "store"

var entry: Dictionary = {}

var _art: TextureRect = null
var _fallback: Label = null


func setup_store(new_entry: Dictionary) -> void:
	entry = new_entry
	# The base still wants a name; it is what the row logs and what a future
	# tooltip or accessibility pass would read. It is simply not drawn.
	setup(str(entry.get("title", "")), "")


func _ready() -> void:
	super._ready()

	# Square, and shrinking rather than filling. The base row expands to the
	# width of its container and stands SETTINGS_ROW_HEIGHT tall, which is the
	# right shape for a settings list and the wrong one for a mark.
	custom_minimum_size = Vector2(TvTheme.STORE_TAB_SIZE, TvTheme.STORE_TAB_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# The icon can arrive long after the tab does: on a fresh stick Steam is
	# still downloading when this screen first opens, and the path only exists
	# once the install lands and the scanner sees the desktop entry.
	Installed.apps_changed.connect(_on_apps_changed)


## Replaces the base's name/value row entirely -- there is no HBox, no label and
## no ellipsis to configure, because there is nothing but the mark.
func _build_contents() -> void:
	_fallback = Icons.label(FALLBACK_ICON, TvTheme.STORE_TAB_GLYPH_SIZE, TvTheme.TEXT_PRIMARY)
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fallback)

	_art = TextureRect.new()
	# KEEP_ASPECT_CENTERED and IGNORE_SIZE for tile.gd's reason: these are
	# 256 px PNGs being drawn into a smaller square, and a non-square icon
	# should letterbox rather than stretch.
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.offset_left = TvTheme.STORE_TAB_ICON_INSET
	_art.offset_top = TvTheme.STORE_TAB_ICON_INSET
	_art.offset_right = -TvTheme.STORE_TAB_ICON_INSET
	_art.offset_bottom = -TvTheme.STORE_TAB_ICON_INSET
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	add_child(_art)

	_refresh_icon()


func _on_apps_changed(_apps: Array) -> void:
	_refresh_icon()


## Swap the glyph for the application's own icon once the installed seam has a
## path for it. One direction only in practice -- an app does not un-install
## itself on this machine -- but written as a straight rebuild from the current
## list rather than a latch, so a removal that does happen is not a stale icon.
func _refresh_icon() -> void:
	if _art == null or _fallback == null:
		return

	var texture := _load_icon(_icon_path())
	_art.texture = texture
	_art.visible = texture != null
	_fallback.visible = texture == null


## The absolute path the scanner resolved for this store's application, or
## empty. Matched on the app id the catalogue carries rather than on the store's
## own id: "store.steam" is the shell's name for a tab, and
## "com.valvesoftware.Steam" is what the desktop entry on disk is called.
func _icon_path() -> String:
	var app_id := str(entry.get("app_id", ""))
	if app_id.is_empty():
		return ""
	for app in Installed.apps:
		if str(app.get("id", "")) == app_id:
			return str(app.get("icon", ""))
	return ""


## A missing, unreadable or corrupt icon is not an error worth an empty tab --
## the glyph underneath is exactly what a tab with no icon has always drawn, so
## this warns and leaves it showing. Same contract as tile.gd's.
func _load_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var image := Image.new()
	if image.load(path) != OK:
		ShellLog.warn("could not load icon %s for %s" % [path, str(entry.get("id", ""))])
		return null
	return ImageTexture.create_from_image(image)


func _on_pressed() -> void:
	opened.emit(entry)
