extends Control

## The wordmark, as a MARK rather than a word.
##
## The bar used to carry the string "MarwanOS" at SIZE_TOPBAR, which is a name
## and not a logo: it took the width of eight characters, it sat in the reading
## order as though it were information, and it said the same thing on every
## screen forever. "M.OS", drawn, is the same identity in a third of the room --
## and the room is the point, because what goes next to it now is the service
## tray, which has something to say that changes.
##
## GRAFFITI, AND WHAT THAT MEANS IN DRAW CALLS. There is no display font in this
## image and adding one for four characters would be a megabyte for a logo. So
## the treatment is built out of the UI font and the three things that actually
## make lettering read as a tag: a SLANT, a heavy OUTLINE that is a different
## colour from the fill, and a hard OFFSET SHADOW behind it. Godot draws all
## three without a second asset -- draw_string takes an outline size, and a
## shear is two lines of Transform2D.
##
## THE DOT IS THE ONE COLOURED THING in the bar's left half: it makes "M.OS"
## parse as a mark rather than as an abbreviation somebody forgot to finish.
##
## It uses TEXT_ALERT's amber, and that is a borrowed colour rather than a new
## one on purpose -- this file adding a constant to the palette would be a logo
## deciding what the product's accent is. ACCENT_FALLBACK, the obvious
## candidate, is the muted surface grey a card falls back to and disappears
## against the bar entirely.
##
## Nothing here is focusable. The mark is furniture; the tray next to it is the
## control, for one-thing-one-home's reason -- a logo that could be pressed is a
## button whose label is a brand.

const TvTheme = preload("res://src/tv_theme.gd")

## How far the lettering leans, in radians of horizontal shear. Small: past
## about 0.2 the counters of the M close up at this weight and it stops reading
## as letters at three metres, which is the only test that matters here.
const SLANT := 0.16

## The shadow's offset. Hard-edged and down-right, the way a paint marker's
## second pass sits, rather than a blur -- a soft shadow at this size is a smudge
## on a TV and costs a texture besides.
const SHADOW_OFFSET := Vector2(3, 3)

## Outline thickness in pixels. This is what carries the whole effect: the fill
## is the background colour, so the letters are drawn BY the outline and read as
## hollow, which is the one thing that separates a tag from bold text.
const OUTLINE := 7

const TEXT := "M.OS"

## Where the dot sits in TEXT, so the accent pass knows which glyph to recolour
## without measuring twice.
const DOT_INDEX := 1

var _font_size: int = TvTheme.SIZE_TOPBAR + 6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := get_theme_default_font()
	var size := font.get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	# The shear pushes the top of the lettering right, so the box has to be
	# wider than the string or the M's shoulder is clipped by the container.
	custom_minimum_size = Vector2(
		size.x + size.y * SLANT + OUTLINE + SHADOW_OFFSET.x,
		size.y + OUTLINE)


func _draw() -> void:
	var font := get_theme_default_font()
	var size := font.get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	# Baseline, not top-left: draw_string positions by baseline, and centring on
	# the box means accounting for the descent the ascent does not have.
	var origin := Vector2(OUTLINE * 0.5, (self.size.y + size.y * 0.62) * 0.5)

	# THE SHEAR IS APPLIED TO THE CANVAS, not to the string, because Godot has no
	# slanted-text call. Columns of the transform: x stays, y gains a leftward
	# component so higher pixels move right.
	draw_set_transform_matrix(Transform2D(
		Vector2(1, 0), Vector2(-SLANT, 1), Vector2.ZERO))

	# Three passes, back to front. The shadow first so everything sits on it,
	# then the outline, then the fill -- and the fill is the BACKGROUND colour,
	# which is what makes the letterforms hollow rather than heavy.
	draw_string_outline(font, origin + SHADOW_OFFSET, TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, OUTLINE,
		Color(0, 0, 0, 0.55))
	draw_string_outline(font, origin, TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, OUTLINE,
		TvTheme.TEXT_PRIMARY)
	draw_string(font, origin, TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, TvTheme.BACKGROUND)

	# THE DOT, LAST AND IN THE ACCENT. Drawn as its own string rather than by
	# recolouring a glyph mid-run, because Godot draws a string in one colour and
	# the alternative is three draw calls with measured offsets -- which is what
	# this is, with the measuring done by the font instead of by hand.
	var before := font.get_string_size(TEXT.substr(0, DOT_INDEX),
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	var dot := TEXT.substr(DOT_INDEX, 1)
	draw_string_outline(font, origin + Vector2(before.x, 0), dot,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, OUTLINE, TvTheme.TEXT_ALERT)
	draw_string(font, origin + Vector2(before.x, 0), dot,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, TvTheme.TEXT_ALERT)

	draw_set_transform_matrix(Transform2D.IDENTITY)
