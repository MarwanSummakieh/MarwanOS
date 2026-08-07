extends Control

## The home-button overlay: what you get while an application is running.
##
## THE APP IS THE CARD, AND IT IS THE REAL APP. This draws nothing behind its
## own controls -- the background is transparent, gamescope composites this
## window on top of the running application, and what shows through the middle
## is the application itself, live. There is no screenshot, no thumbnail and no
## capture: the "card" is a frame drawn around a hole.
##
## That is possible because of one X property. gamescope reads
## GAMESCOPE_EXTERNAL_OVERLAY on a window and, when set, composites that window
## over the focused application instead of replacing it -- the same mechanism
## Steam's overlay uses on a Deck. Kiosk.set_overlay() sets and clears it; see
## there for how, and for what happens if it does not take.
##
## TWO CONTROLS, AND THEY ARE DELIBERATELY NOT SYMMETRIC.
##
##   Close (X)      stops the application. Certain: the launch seam owns the
##                  pid and, for a flatpak, the app id.
##   Minimize (-)   leaves it running and shows the rail. HONEST CAVEAT: this
##                  depends on gamescope handing focus back to the shell, which
##                  is the compositor's decision and not something a client can
##                  insist on. It is wired, it is logged, and if the bench shows
##                  it does not work the button says so rather than pretending.
##
## Navigation is the rail's, rotated: left and right between the two controls,
## hard stops, B closes the overlay and returns to the application.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Glyphs = preload("res://src/glyphs.gd")

## Diameter of the two control circles. Well above the interactive floor in
## tv_theme's header, and sized so the pair reads as buttons rather than as
## decoration from three metres.
const CIRCLE_SIZE := 132

## Gap between the two circles.
const CIRCLE_GAP := 72

## How much of the screen the app "card" frame leaves visible. The frame is
## drawn just inside the TV-safe area, and the controls sit BELOW it -- so the
## application is never covered by the thing that offers to close it.
const CARD_BOTTOM_FRACTION := 0.72

var entry: Dictionary = {}

var _title: Label = null
var _hint: Label = null
var _buttons: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Nothing is drawn behind the controls. The scrim below is a partial dim so
	# the overlay reads as a layer rather than as the app having changed, and
	# it deliberately stops short of the card area.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build()
	_wire_focus_neighbours()

	if not _buttons.is_empty():
		# Opens on Close, because that is what the button was pressed for in
		# the overwhelming majority of cases -- the application is finished
		# with. Minimize is the deliberate second choice.
		var first: Control = _buttons[0]
		first.grab_focus()

	ShellLog.info("app overlay up for %s" % str(entry.get("title", "<unknown>")))


func _build() -> void:
	# The frame around the live application. draw_center off: this is an
	# outline, and every pixel inside it is the app showing through.
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", TvTheme.overlay_card_frame())
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_left = TvTheme.SAFE_MARGIN_X
	card.offset_right = -TvTheme.SAFE_MARGIN_X
	card.offset_top = TvTheme.SAFE_MARGIN_Y
	card.offset_bottom = -(1.0 - CARD_BOTTOM_FRACTION) * TvTheme.BASE_HEIGHT
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)

	# The strip under the card, where the controls live. This IS dimmed --
	# unlike the card, there is nothing behind it worth seeing, and the
	# contrast is what makes the circles legible over whatever the app is
	# rendering.
	var strip := ColorRect.new()
	strip.color = Color(TvTheme.BACKGROUND.r, TvTheme.BACKGROUND.g, TvTheme.BACKGROUND.b, 0.88)
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.anchor_top = CARD_BOTTOM_FRACTION
	strip.offset_top = 0.0
	strip.offset_bottom = 0.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	column.anchor_top = CARD_BOTTOM_FRACTION
	column.offset_top = TvTheme.SECTION_GAP
	column.offset_bottom = 0.0
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_title = Label.new()
	_title.text = str(entry.get("title", ""))
	_title.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	_title.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", CIRCLE_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)

	var close_button := _circle("close", "Close")
	close_button.pressed.connect(_on_close_pressed)
	row.add_child(close_button)
	_buttons.append(close_button)

	var minimize_button := _circle("minimize", "Minimize")
	minimize_button.pressed.connect(_on_minimize_pressed)
	row.add_child(minimize_button)
	_buttons.append(minimize_button)

	_hint = Label.new()
	_hint.text = "Close  |  Minimize        B returns to the app"
	_hint.add_theme_font_size_override("font_size", TvTheme.SIZE_SUPPLEMENTAL)
	_hint.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hint)


## A round button carrying one glyph. Round because the request was circles,
## and because a circle is the one shape nothing else in this shell uses -- the
## rail, the rows and the keys are all rounded rectangles, so these read as a
## different KIND of control rather than as more of the same.
func _circle(kind: String, label: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(CIRCLE_SIZE, CIRCLE_SIZE)
	button.focus_mode = Control.FOCUS_ALL
	button.text = ""
	button.tooltip_text = label
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	button.add_theme_stylebox_override("normal", TvTheme.circle_box(false))
	button.add_theme_stylebox_override("hover", TvTheme.circle_box(false))
	button.add_theme_stylebox_override("pressed", TvTheme.circle_box(true))
	button.add_theme_stylebox_override("focus", TvTheme.circle_ring())

	var glyph := Glyphs.new()
	glyph.kind = kind
	glyph.color = TvTheme.TEXT_PRIMARY
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = TvTheme.TOPBAR_ICON_PAD * 2
	glyph.offset_top = TvTheme.TOPBAR_ICON_PAD * 2
	glyph.offset_right = -TvTheme.TOPBAR_ICON_PAD * 2
	glyph.offset_bottom = -TvTheme.TOPBAR_ICON_PAD * 2
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(glyph)

	button.focus_entered.connect(_on_button_focus.bind(button, true))
	button.focus_exited.connect(_on_button_focus.bind(button, false))
	return button


func _on_button_focus(button: Button, focused: bool) -> void:
	var box := TvTheme.circle_box_focused() if focused else TvTheme.circle_box(false)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)


func _wire_focus_neighbours() -> void:
	var count := _buttons.size()
	for index in count:
		var button: Control = _buttons[index]
		var left := index - 1 if index > 0 else index
		var right := index + 1 if index + 1 < count else index
		button.focus_neighbor_left = button.get_path_to(_buttons[left])
		button.focus_neighbor_right = button.get_path_to(_buttons[right])
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)


func _on_close_pressed() -> void:
	ShellLog.info("overlay: close pressed")
	Launcher.close_current()
	# The overlay goes away immediately; the rail comes back when the launch
	# seam's poll notices the process is gone, which is the same path a normal
	# exit takes. Waiting here would leave the overlay on screen over a dying
	# application.
	closed.emit()


func _on_minimize_pressed() -> void:
	ShellLog.info("overlay: minimize pressed")
	Launcher.minimize_current()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	# B returns to the application. The home button does the same, so the
	# button that opened the overlay also dismisses it -- which is what every
	# console does and what a person will try first.
	if event.is_action_pressed("ui_cancel") \
			or (InputMap.has_action("ui_shell_home") and event.is_action_pressed("ui_shell_home")):
		get_viewport().set_input_as_handled()
		ShellLog.info("overlay dismissed; returning to the app")
		closed.emit()
