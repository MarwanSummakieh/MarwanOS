extends Button

## The background services, as a row of small icons in the top bar.
##
## One icon per service that is installed: lit when it is running, dark when it
## is not. It is the answer to "is Steam actually up" without opening anything --
## the question the owner had no way to ask on 2026-08-11, when a game launch
## cold-started the client because nothing on screen said it was not running.
##
## A Button for icon_button.gd's reason: FOCUS_ALL and ui_accept-to-pressed come
## free. It sits in the bar's focus chain next to the store and the gear, and A
## opens the menu that can start and stop things -- see service_menu.gd.
##
## THE ICONS ARE THE APPLICATIONS' OWN, not glyphs from the icon font. Phosphor
## has no Steam mark and inventing one would be a drawn approximation of somebody
## else's logo; marwanos-appscan already resolves a real icon path for everything
## installed, which is the same picture the rail's card draws. A service whose
## icon has not resolved yet falls back to the first letter of its name, which is
## legible and honest rather than an empty gap.
##
## GREY IS THE WHOLE POINT and it is done with modulate rather than a second
## asset: a stopped service is the same picture at a third of its brightness,
## which reads as "off" at three metres without needing a second thing to look
## at. A service this shell has ASKED to change is drawn between the two, so a
## press is visibly acknowledged during the couple of seconds the supervisor
## takes to notice.

const TvTheme = preload("res://src/tv_theme.gd")

signal activated()

## Brightness of a service's icon by what it is doing. Running is full; stopped
## is dark enough to read as off at a glance but not so dark it looks like a
## rendering failure; pending sits between them because it is between them.
const MODULATE_RUNNING := Color(1, 1, 1, 1)
const MODULATE_STOPPED := Color(1, 1, 1, 0.30)
const MODULATE_PENDING := Color(1, 1, 1, 0.65)

const ICON_SIZE := 34

var _row: HBoxContainer = null
var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat

## Cached textures by icon path, so a two-second poll does not re-decode a PNG
## off the disk for every service on every tick.
var _textures: Dictionary = {}


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	# THE BAR'S OWN BOXES, taken from icon_button rather than from the card set,
	# so this reads as a sibling of the store and the gear rather than as a
	# differently-styled thing that happens to sit near them. Same four
	# overrides, same focus ring, and the same lit-while-focused swap below.
	_idle_box = TvTheme.topbar_circle_box(false)
	_focus_box = TvTheme.topbar_circle_box(true)
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", TvTheme.topbar_circle_box(true))
	add_theme_stylebox_override("disabled", _idle_box)
	add_theme_stylebox_override("focus", TvTheme.topbar_circle_ring())
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	add_child(pad)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 10)
	pad.add_child(_row)

	pressed.connect(_on_pressed)
	Services.services_changed.connect(refresh)
	# The icon path comes from the installed seam, which fills in seconds after
	# boot -- so the tray has to rebuild when it does or it draws letters forever.
	Installed.apps_changed.connect(_on_installed_changed)
	refresh()


func _on_installed_changed(_apps: Array) -> void:
	refresh()


## Rebuild the row from the seam. Cheap enough to do on every change: it is at
## most a handful of children, and the alternative is diffing a list of two.
func refresh() -> void:
	if _row == null:
		return
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()

	var services: Array = Services.visible_services()
	# NOTHING INSTALLED IS NOT AN EMPTY BOX. A focusable rectangle with no
	# content is a control the pad can land on that says nothing and does
	# nothing; hiding it takes it out of the neighbour chain as well, which is
	# what shell_root's wiring already handles for the terminal button.
	visible = not services.is_empty()
	if not visible:
		return

	for service in services:
		_row.add_child(_icon_for(service))
	custom_minimum_size = Vector2(
		services.size() * (ICON_SIZE + 10) + 14, TvTheme.SIZE_TOPBAR + 18)


func _icon_for(service: Dictionary) -> Control:
	var id := str(service.get("id", ""))
	var state := str(service.get("state", ""))
	var tint := MODULATE_STOPPED
	if not Services.pending_of(id).is_empty():
		tint = MODULATE_PENDING
	elif state == "running":
		tint = MODULATE_RUNNING

	var path := _icon_path(str(service.get("app_id", "")))
	if not path.is_empty():
		var texture := _texture(path)
		if texture != null:
			var art := TextureRect.new()
			art.texture = texture
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			art.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			art.modulate = tint
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return art

	# The fallback: the service's initial, at the same size and the same tint.
	# A letter is a worse picture than a logo and a much better one than a gap.
	var letter := Label.new()
	letter.text = str(service.get("label", "?")).substr(0, 1).to_upper()
	letter.add_theme_font_size_override("font_size", TvTheme.SIZE_TOPBAR)
	letter.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	letter.modulate = tint
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return letter


func _icon_path(app_id: String) -> String:
	if app_id.is_empty():
		return ""
	for app in Installed.apps:
		if str(app.get("id", "")) == app_id:
			return str(app.get("icon", ""))
	return ""


func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var image := Image.new()
	if image.load(path) != OK:
		# Warned once per path and remembered as null, so a bad file is not
		# re-read every two seconds for the life of the session.
		ShellLog.warn("services: could not load icon %s" % path)
		_textures[path] = null
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


## The lit-while-focused swap, matching icon_button exactly: the ring alone is
## not enough separation on a bar this dark, so the plate lights too.
func _on_focus_entered() -> void:
	add_theme_stylebox_override("normal", _focus_box)
	add_theme_stylebox_override("hover", _focus_box)


func _on_focus_exited() -> void:
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)


func _on_pressed() -> void:
	activated.emit()
