extends Button

## The notification bell in the top bar, and the door to the service menu.
##
## IT USED TO BE A ROW OF APPLICATION ICONS -- one per background service, lit
## when running and grey when not. The owner asked for a notification icon
## instead (2026-08-11): one bell, the same mark whatever is installed, with
## the services' state carried as a badge rather than as a strip that grows a
## logo per service. The menu behind it (service_menu.gd) keeps the start/stop
## rows and is where notifications will land when the shell has any to show --
## the bell is the surface's name as much as its button.
##
## A Button for icon_button.gd's reason: FOCUS_ALL and ui_accept-to-pressed come
## free. It sits in the bar's focus chain next to the store and the gear, and A
## opens the menu.
##
## THE BELL DOES NOT DIM. The old tray said "stopped" by drawing the service's
## icon at a third of its brightness, which worked because the icon WAS the
## service. The bell is a control, and a control drawn dim reads as disabled --
## the exact lie a focusable thing must not tell. State moved into the dot:
##
##   no dot        every service is running; nothing needs attention
##   grey dot      this shell asked for a change and the supervisor has not
##                 confirmed it yet -- the press's acknowledgement, same job
##                 the old tray's in-between brightness did
##   amber dot     something is stopped or unreported; worth opening the menu
##
## Pending outranks stopped, because acknowledging the person's own press
## matters more than restating the state they just acted on.

const TvTheme = preload("res://src/tv_theme.gd")
const Glyphs = preload("res://src/glyphs.gd")

signal activated()

## The badge dot's geometry, in design px against the TOPBAR_ICON_SIZE plate.
## Inset keeps the dot on the plate's face rather than clipped by its circular
## edge; the radius is the smallest that still reads as a deliberate mark at
## three metres rather than as a dead pixel.
const BADGE_RADIUS := 7.0
const BADGE_INSET := 16.0

## Transparent alpha means no badge; _draw tests it rather than a second flag,
## so the colour and the decision to draw cannot disagree.
var _badge := Color(0, 0, 0, 0)

var _idle_box: StyleBoxFlat
var _focus_box: StyleBoxFlat


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	# The same circle as the store and the gear, now that the content is one
	# glyph rather than a row: the bell is a sibling of the other bar icons in
	# size as well as in style.
	custom_minimum_size = Vector2(TvTheme.TOPBAR_ICON_SIZE, TvTheme.TOPBAR_ICON_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text = ""

	_idle_box = TvTheme.topbar_circle_box(false)
	_focus_box = TvTheme.topbar_circle_box(true)
	add_theme_stylebox_override("normal", _idle_box)
	add_theme_stylebox_override("hover", _idle_box)
	add_theme_stylebox_override("pressed", TvTheme.topbar_circle_box(true))
	add_theme_stylebox_override("disabled", _idle_box)
	add_theme_stylebox_override("focus", TvTheme.topbar_circle_ring())
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)

	var glyph := Glyphs.new()
	glyph.kind = "bell"
	glyph.color = TvTheme.TEXT_PRIMARY
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = TvTheme.TOPBAR_ICON_PAD
	glyph.offset_top = TvTheme.TOPBAR_ICON_PAD
	glyph.offset_right = -TvTheme.TOPBAR_ICON_PAD
	glyph.offset_bottom = -TvTheme.TOPBAR_ICON_PAD
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glyph)

	pressed.connect(_on_pressed)
	Services.services_changed.connect(refresh)
	# Visibility depends on what is installed -- see refresh -- so the bell has
	# to re-answer when the installed list does, same as the old tray did.
	Installed.apps_changed.connect(_on_installed_changed)
	refresh()


func _on_installed_changed(_apps: Array) -> void:
	refresh()


## Re-answer visibility and the badge from the seam. Cheap on every change:
## it is one loop over a list of one, and the redraw is a dot.
func refresh() -> void:
	var services: Array = Services.visible_services()
	# NOTHING INSTALLED IS NOT AN EMPTY BELL. A bell over zero services would
	# ring about nothing; hiding it also takes it out of the neighbour chain,
	# which shell_root's tray-membership wiring already handles.
	visible = not services.is_empty()
	if not visible:
		return

	var any_pending := false
	var any_down := false
	for service in services:
		if not Services.pending_of(str(service.get("id", ""))).is_empty():
			any_pending = true
		elif str(service.get("state", "")) != "running":
			any_down = true

	if any_pending:
		_badge = TvTheme.TEXT_SECONDARY
	elif any_down:
		_badge = TvTheme.TEXT_ALERT
	else:
		_badge = Color(0, 0, 0, 0)
	queue_redraw()


## The badge dot, over the bell's top-right shoulder. Drawn here rather than as
## a child node because it is one circle whose only property is a colour --
## a node would be scene-tree bookkeeping for a single draw call.
func _draw() -> void:
	if _badge.a <= 0.0:
		return
	draw_circle(Vector2(size.x - BADGE_INSET, BADGE_INSET), BADGE_RADIUS, _badge)


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
