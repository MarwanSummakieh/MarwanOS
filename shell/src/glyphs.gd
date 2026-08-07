extends Control

## The shell's icon glyphs -- a storefront, a gear, and a wifi fan -- drawn
## with canvas primitives in _draw().
##
## Primitives rather than an icon font or PNGs, and that is a repo decision
## more than an art one: either alternative would be the project's first binary
## asset, authored by a tool outside the repo and unreviewable in a diff. Three
## glyphs' worth of arcs and rectangles is twenty lines a person can read, and
## they inherit the theme's colours the same way every Label does. If the
## glyph count ever grows past a handful, that is the signal to revisit -- the
## same tripwire shape as launcher.gd's "if something wants to grow here".
##
## The control draws to whatever size its parent gives it; callers set
## custom_minimum_size. Stroke weight is TOPBAR_GLYPH_WIDTH so the marks read
## as one family with the focus ring.

const TvTheme = preload("res://src/tv_theme.gd")

## Which glyph: "store", "gear", "wifi", or "wifi-off". Anything else draws
## nothing, which on a TV is better than drawing the wrong claim.
var kind: String = "":
	set(value):
		kind = value
		queue_redraw()

var color: Color = TvTheme.TEXT_PRIMARY:
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	match kind:
		"store":
			_draw_store()
		"gear":
			_draw_gear()
		"wifi":
			_draw_wifi(false)
		"wifi-off":
			_draw_wifi(true)


## A shopping bag: an outlined body with a handle arced over its top edge.
func _draw_store() -> void:
	var s := size
	var w := TvTheme.TOPBAR_GLYPH_WIDTH
	var body := Rect2(Vector2(s.x * 0.14, s.y * 0.36), Vector2(s.x * 0.72, s.y * 0.52))
	draw_rect(body, color, false, w)
	# The handle: the upper half-circle, angles PI..TAU because y grows
	# downward on a canvas and that sweep passes through straight up.
	draw_arc(Vector2(s.x * 0.5, s.y * 0.36), s.x * 0.20, PI, TAU, 16, color, w, true)


## A gear: a ring, a hub, and eight radial teeth. Reads as "settings" at three
## metres, which is the entire acceptance test.
func _draw_gear() -> void:
	var s := size
	var w := TvTheme.TOPBAR_GLYPH_WIDTH
	var center := s / 2.0
	var tooth_tip := minf(center.x, center.y) - w * 0.5
	var ring := tooth_tip * 0.62
	draw_arc(center, ring, 0.0, TAU, 32, color, w, true)
	draw_circle(center, ring * 0.34, color)
	for i in 8:
		var direction := Vector2.from_angle(TAU * i / 8.0)
		draw_line(center + direction * ring, center + direction * tooth_tip, color, w, true)


## The wifi fan: a dot and three arcs opening upward. `struck` lays a diagonal
## through it -- the difference between "connected" and "not", carried by shape
## as well as colour, because colour alone is unreliable on a TV (the same
## argument as the focus ring's three channels).
func _draw_wifi(struck: bool) -> void:
	var s := size
	var w := TvTheme.TOPBAR_GLYPH_WIDTH
	var base := Vector2(s.x * 0.5, s.y * 0.85)
	draw_circle(base, w * 0.85, color)
	for radius in [s.y * 0.30, s.y * 0.52, s.y * 0.74]:
		draw_arc(base, radius, -3.0 * PI / 4.0, -PI / 4.0, 24, color, w, true)
	if struck:
		draw_line(Vector2(s.x * 0.18, s.y * 0.08), Vector2(s.x * 0.82, s.y * 0.92), color, w, true)
