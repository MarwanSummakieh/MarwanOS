extends RefCounted

## Every number the shell draws with, in one place.
##
## Not an autoload: nothing here has state or needs a node. Call sites do
## `const TvTheme = preload("res://src/tv_theme.gd")` and read the constants off
## the class. That keeps it greppable and keeps the values out of the scene tree.
##
## ---------------------------------------------------------------------------
## Why these particular numbers
##
## The design surface is a fixed 1920x1080, scaled to the negotiated output by
## the project's canvas_items stretch. So every constant below is "at 1080p" and
## stays proportionally correct on a 4K panel.
##
## TV-safe inset: 5% of each edge, which the three platform vendors agree on and
## express identically -- Microsoft's 10-foot guidance and Android TV both work
## from a 960x540 surface with 48/27 margins, which is 96 px horizontal and 54 px
## vertical at 1080p; tvOS says 90/60. 5% is a floor, not a guarantee: individual
## TVs overscan more, and M2's camera test is the arbiter here the same way it is
## for the silent boot. If the TV clips, raise SAFE_MARGIN_* -- that is the one
## knob, and it is why the margins are constants rather than inline numbers.
##
## Type: Microsoft's floors are 15 epx for reading content and 12 epx for
## supplemental, against a surface Xbox scales 200% for TV -- 30 px and 24 px at
## 1080p. Nothing here goes below those, and project.godot raises Godot's default
## font size to 30 so a control that forgets to set one renders too big rather
## than invisibly small.
##
## Interactive elements are at least 32 epx / 64 px tall. A tile is far above it.
##
## Colour stays inside RGB 16-235. TVs band and bloom at the extremes of the
## range, and the plan's risk table already treats TV colour behaviour as
## untrusted. Nothing here is pure black or pure white.
##
## Columns are capped at 6 by Microsoft's rule that traversal should take no more
## than six clicks edge to edge. Four is what the placeholder catalogue uses.

const BASE_WIDTH := 1920
const BASE_HEIGHT := 1080

# 5% of each axis. See the header: this is the knob the camera test turns.
const SAFE_MARGIN_X := 96
const SAFE_MARGIN_Y := 54

const GRID_COLUMNS := 4
const GRID_SEPARATION := 32

# Well above the 64 px interactive floor; the real height comes from the grid
# filling the space between the header and the hint row.
const TILE_MIN_HEIGHT := 200
const TILE_PADDING := 18
const TILE_CORNER_RADIUS := 14

# The focus indicator runs on three channels at once, because colour alone is
# unreliable on a TV and because WCAG 2.2 SC 2.4.13 asks for a >= 3:1 contrast
# between the focused and unfocused states of the same pixels -- a state-change
# ratio, which one channel struggles to carry. The channels are: a ring
# (FOCUS_RING vs the tile beneath it is ~8:1), a brighter surface, and scale.
#
# WCAG's 2-CSS-px thickness figure is calibrated for a monitor at desk distance
# and is invisible from a sofa. Take the contrast requirement as binding and the
# thickness as a floor to multiply.
const FOCUS_RING_WIDTH := 6
const IDLE_BORDER_WIDTH := 2
const FOCUS_SCALE := 1.05
const FOCUS_TWEEN_SECONDS := 0.10

const SIZE_WORDMARK := 56
const SIZE_TILE_TITLE := 34
const SIZE_BODY := 30
const SIZE_SUPPLEMENTAL := 26

## Vertical breathing room between the header, the grid and the hint row.
const SECTION_GAP := 28

# RGB 16-235, light-on-dark, no hue carrying meaning on its own.
const BACKGROUND := Color(0.078431, 0.086275, 0.101961, 1.0)
const SURFACE := Color(0.149020, 0.164706, 0.196078, 1.0)
const SURFACE_FOCUS := Color(0.290196, 0.321569, 0.376471, 1.0)
const BORDER_IDLE := Color(0.227451, 0.250980, 0.290196, 1.0)
const FOCUS_RING := Color(0.909804, 0.917647, 0.933333, 1.0)
const TEXT_PRIMARY := Color(0.886275, 0.901961, 0.921569, 1.0)
const TEXT_SECONDARY := Color(0.588235, 0.619608, 0.666667, 1.0)
const TEXT_ALERT := Color(0.921569, 0.690196, 0.360784, 1.0)
const ACCENT_FALLBACK := Color(0.290196, 0.321569, 0.376471, 1.0)


## The tile's resting background.
static func tile_idle_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.set_border_width_all(IDLE_BORDER_WIDTH)
	box.border_color = BORDER_IDLE
	box.set_corner_radius_all(TILE_CORNER_RADIUS)
	return box


## The tile's background while focused -- the brightness channel.
static func tile_focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE_FOCUS
	box.set_border_width_all(IDLE_BORDER_WIDTH)
	box.border_color = BORDER_IDLE
	box.set_corner_radius_all(TILE_CORNER_RADIUS)
	return box


## The focus ring, drawn over whichever background is current. draw_center is off
## so this is purely an outline and the brightness channel stays independent of
## it.
static func tile_focus_ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(FOCUS_RING_WIDTH)
	box.border_color = FOCUS_RING
	box.set_corner_radius_all(TILE_CORNER_RADIUS)
	return box


## The bordered square behind a button glyph in the hint row.
static func glyph_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.set_border_width_all(2)
	box.border_color = TEXT_SECONDARY
	box.set_corner_radius_all(6)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


## Catalogue entries carry their accent as a hex string so the placeholder data
## stays plain text. An unparseable value is a typo, not a reason to draw nothing.
static func accent(hex: String) -> Color:
	if Color.html_is_valid(hex):
		return Color.html(hex)
	return ACCENT_FALLBACK
