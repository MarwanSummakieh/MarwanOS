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
## Interactive elements are at least 32 epx / 64 px tall. A card is far above it.
##
## Colour stays inside RGB 16-235. TVs band and bloom at the extremes of the
## range, and the plan's risk table already treats TV colour behaviour as
## untrusted. Nothing here is pure black or pure white.

const BASE_WIDTH := 1920
const BASE_HEIGHT := 1080

# 5% of each axis. See the header: this is the knob the camera test turns.
const SAFE_MARGIN_X := 96
const SAFE_MARGIN_Y := 54

# ---------------------------------------------------------------------------
# The console-style home rail
#
# A horizontal row of cards with one enlarged selection, rather than a grid. The
# difference is not decoration: a rail has ONE axis, so left and right are the
# only moves that mean anything and there is no ambiguity about where focus goes
# next -- which is the property that makes a games console readable from a sofa
# with a thumbstick. The grid's 2D neighbour table exists to paper over exactly
# that ambiguity.
#
# The selected card sits at a FIXED x on screen and the rail slides underneath
# it. Anchoring the selection rather than the strip is what stops the eye having
# to re-find the cursor after every press.

## Unfocused card. Square, because a square is the only aspect ratio that reads
## the same whether the art is portrait key art or a square icon, and Phase 1
## does not get to choose what AppStream hands it.
const CARD_SIZE := 200

## The selected card. Roughly 1.7x, which is the point where the size difference
## is legible at three metres rather than merely present -- the same argument as
## FOCUS_RING_WIDTH being a floor to multiply rather than a value to copy.
const CARD_FOCUSED_SIZE := 340

const CARD_GAP := 26
const CARD_CORNER_RADIUS := 12

## How long the rail takes to slide and the card to grow. Long enough to read as
## motion, short enough that holding a direction does not feel like wading --
## FocusRepeat's hold-repeat interval is the real ceiling on this.
const RAIL_TWEEN_SECONDS := 0.18

## The hero art behind everything, at rest. The art is a full-bleed wash of the
## selected entry's accent; at full strength it would make white text illegible,
## and the number is chosen so TEXT_PRIMARY stays above 4.5:1 against the
## brightest accent in the placeholder catalogue.
const HERO_DIM := 0.22

## Height of the gradient that darkens the lower half, as a fraction of the
## surface. Text sits inside it; the wash is only visible above.
const HERO_GRADIENT_FRACTION := 0.62

const SIZE_HERO_TITLE := 72
const SIZE_TOPBAR := 28

# The focus indicator runs on three channels at once, because colour alone is
# unreliable on a TV and because WCAG 2.2 SC 2.4.13 asks for a >= 3:1 contrast
# between the focused and unfocused states of the same pixels -- a state-change
# ratio, which one channel struggles to carry. The channels are: a ring
# (FOCUS_RING vs the card beneath it is ~8:1), a brighter surface, and size --
# the card growing from CARD_SIZE to CARD_FOCUSED_SIZE.
#
# WCAG's 2-CSS-px thickness figure is calibrated for a monitor at desk distance
# and is invisible from a sofa. Take the contrast requirement as binding and the
# thickness as a floor to multiply.
const FOCUS_RING_WIDTH := 6

const SIZE_WORDMARK := 56
const SIZE_BODY := 30
const SIZE_SUPPLEMENTAL := 26

## Vertical breathing room between the top bar, the title block, the rail and
## the hint row.
const SECTION_GAP := 28

# RGB 16-235, light-on-dark, no hue carrying meaning on its own.
const BACKGROUND := Color(0.078431, 0.086275, 0.101961, 1.0)
const SURFACE := Color(0.149020, 0.164706, 0.196078, 1.0)
const SURFACE_FOCUS := Color(0.290196, 0.321569, 0.376471, 1.0)
const FOCUS_RING := Color(0.909804, 0.917647, 0.933333, 1.0)
const TEXT_PRIMARY := Color(0.886275, 0.901961, 0.921569, 1.0)
const TEXT_SECONDARY := Color(0.588235, 0.619608, 0.666667, 1.0)
const TEXT_ALERT := Color(0.921569, 0.690196, 0.360784, 1.0)
const ACCENT_FALLBACK := Color(0.290196, 0.321569, 0.376471, 1.0)


## A rail card at rest. No border: on a rail the selection is carried by size and
## by the ring, and a border on every card competes with both.
static func card_idle_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## The selected card. Brighter surface plus the ring -- see the three-channel
## comment above FOCUS_RING_WIDTH.
static func card_focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE_FOCUS
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


static func card_focus_ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(FOCUS_RING_WIDTH)
	box.border_color = FOCUS_RING
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## Top-to-bottom transparent-to-dark, so the title and rail keep their contrast
## over any hero wash. A GradientTexture2D rather than a shader: it is one
## resource, it costs nothing on llvmpipe, and it is reviewable as numbers.
static func hero_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 0.0))
	gradient.set_color(1, Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 0.96))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	# Small: it is stretched across the surface and the ramp is linear, so there
	# is nothing for more texels to describe.
	texture.width = 2
	texture.height = 256
	return texture


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
