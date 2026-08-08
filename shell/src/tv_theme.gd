extends RefCounted

## Every number the shell draws with, in one place.
##
## Not an autoload: nothing here has state or needs a node. Call sites do
## `const TvTheme = preload("res://src/tv_theme.gd")` and read the constants off
## the class. That keeps it greppable and keeps the values out of the scene tree.

const Icons = preload("res://src/icons.gd")
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

## Inset from a card's edge to its icon, at CARD_SIZE. An app icon sits inside
## the card's wash the way a launcher tile's does -- roughly two thirds of the
## card, so the wash reads as a frame rather than a border. A fixed pixel inset
## means the icon grows with the card when it takes focus, which is what keeps
## the selection's size channel working.
const CARD_ICON_INSET := 34

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

# ---------------------------------------------------------------------------
# The top bar's icon buttons (PS5-shaped: store and settings live in the bar)
#
# The bar stopped being pure text when the settings entry moved off the rail at
# the owner's request (ADR 0006, third amendment): store and settings are now
# focusable icons on the right of the bar, PS5-fashion, and the rail gained a
# second axis -- up from any card lands on the store icon. The icons are drawn
# with primitives in glyphs.gd rather than shipped as textures: an icon font or
# a PNG would be the repo's first binary asset, and three glyphs' worth of arcs
# and rectangles is reviewable the way every other number here is.

## Exactly the interactive floor from the header. The glyph inside is smaller;
## the box is the focus target and the thing the ring draws around.
const TOPBAR_ICON_SIZE := 64

## Inset from the icon box's edge to the glyph's drawing area. Chosen so the
## glyph reads at three metres without the box crowding it.
const TOPBAR_ICON_PAD := 14

## Line weight for glyph strokes. Matches the focus ring's weight so the two
## read as one family of marks.
const TOPBAR_GLYPH_WIDTH := 4.0

# ---------------------------------------------------------------------------
# The stores screen
#
# Side tabs on the left, the selected store's page rendered on the right --
# the PS Store shape. The page is drawn BY THE SHELL (title, art wash,
# description, live install state); pressing A launches the store application
# itself fullscreen, because embedding a foreign client's window inside a
# Godot control is compositor work this stack does not do. See ADR 0006's
# third amendment.

## Side of a store tab, which is square and carries only the store's icon (see
## store_tab.gd). This was STORE_TAB_WIDTH := 420, sized to hold a store NAME at
## SIZE_BODY; with the name gone the column is a strip of marks, and the width it
## no longer needs goes to the page beside it. Comfortably above the interactive
## floor in this file's header.
const STORE_TAB_SIZE := 132

## The stand-in glyph inside a tab, for a store whose application is not
## installed yet. Sized against STORE_TAB_SIZE rather than against the body
## text: it is the tab's whole content, not a mark beside a word.
const STORE_TAB_GLYPH_SIZE := 64

## Breathing room between a tab's edge and the real application icon it draws.
## Larger than the glyph needs because a PNG icon fills its square to the corners
## while a Phosphor mark carries its own margin.
const STORE_TAB_ICON_INSET := 22

## Gap between the tab column and the page pane.
const STORE_PAGE_GAP := 40

## Padding inside the page pane, between its rounded edge and its content.
const STORE_PAGE_PAD := 48

## Height of the accent wash band at the top of a store page -- stands in for
## key art the same way the rail's hero wash does.
const STORE_PAGE_HERO_HEIGHT := 220

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

# ---------------------------------------------------------------------------
# The settings screen
#
# Rows reuse the card's boxes and ring so the two screens read as one product.
# A row's focus runs on two channels (the ring and the brighter surface) where
# the card's runs on three, because the third does not transfer: a card grows
# into slack the rail keeps around it, but a full-width row that grew would
# shove every row below it, and a list that reflows on each press reads as
# nervous. The ring's ~8:1 against the surface carries WCAG's state-change
# contrast on its own, so dropping size costs redundancy, not legibility.

## Comfortably above the 64 px interactive floor named in the header, and tall
## enough that a name on the left and a value on the right read as one line
## from the couch.
const SETTINGS_ROW_HEIGHT := 88

const SETTINGS_ROW_GAP := 14

## Horizontal padding inside a row, between its rounded edge and its text.
const SETTINGS_ROW_PAD := 28

## (The settings card's accent lived here until the third amendment moved
## settings into the top bar as a gear icon; the constant went with the card.)

# RGB 16-235, light-on-dark, no hue carrying meaning on its own.
const BACKGROUND := Color(0.078431, 0.086275, 0.101961, 1.0)
const SURFACE := Color(0.149020, 0.164706, 0.196078, 1.0)
const SURFACE_FOCUS := Color(0.290196, 0.321569, 0.376471, 1.0)
## One step brighter than SURFACE_FOCUS, for the moment a press is held on a
## row that has no scene change to acknowledge it -- see settings_row.gd.
const SURFACE_PRESSED := Color(0.380392, 0.419608, 0.490196, 1.0)
const FOCUS_RING := Color(0.909804, 0.917647, 0.933333, 1.0)
const TEXT_PRIMARY := Color(0.886275, 0.901961, 0.921569, 1.0)
const TEXT_SECONDARY := Color(0.588235, 0.619608, 0.666667, 1.0)
const TEXT_ALERT := Color(0.921569, 0.690196, 0.360784, 1.0)
const ACCENT_FALLBACK := Color(0.290196, 0.321569, 0.376471, 1.0)

## The hint row's numbers, shared by every screen that draws one.
const HINT_GAP := 36
const HINT_GLYPH_GAP := 12


## The card's art fill, rounded to the same radius as the box and the ring.
##
## It is a StyleBoxFlat on a Panel rather than a ColorRect, and that is a fix
## rather than a preference: a ColorRect is always a hard rectangle, so its four
## square corners drew outside the rounded focus ring and the rounded card box
## beneath it. On hardware that reads as the art leaking past its own border --
## reported off the 2026-08-07 boot, and invisible until the ring started
## drawing at all. Phase 1 replaces the flat colour with real key art, which
## will need the same treatment (a texture rounded by a corner radius, not a
## bare TextureRect) for exactly this reason.
static func card_art_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


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


## The focus ring. draw_center is off so it is purely an outline and the
## brightness channel stays independent of it. The card draws this on an overlay
## child above its full-bleed art, NOT as Button's "focus" stylebox -- a Button
## paints that box before its children, so the art would swallow it whole. See
## tile.gd's _build_contents.
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


## A row that is being pressed and has nothing else to say so. Brighter than
## the focus surface, so the press is a visible pixel change even though the
## row was already lit by focus when the button went down.
static func row_pressed_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE_PRESSED
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
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


## The pad's face buttons as the DualSense actually labels them. The hint row
## used to say "A" and "B" -- correct for the logical action, wrong for the
## pad in the room, whose buttons say nothing of the kind. The LETTERS remain
## the API (call sites say what Godot's input map says: A confirms, B cancels)
## and this table is the one place that knows A is drawn as a cross and B as a
## circle. An Xbox pad arriving would make this a per-pad lookup keyed on
## PlayerOne's identity; today there is one controller and it is a DualSense.
const HINT_SHAPES := {
	"A": "cross",
	"B": "circle",
	"X": "square",
	"Y": "triangle",
}


## One glyph-plus-caption hint, e.g. cross + "Open". Built here rather than in
## each screen because the settings screen made it the first duplicated control
## in the project, and a third fullscreen surface copying the pattern would
## have made it three sites to retune after a couch test.
static func hint(glyph: String, caption_text: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", HINT_GLYPH_GAP)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", SIZE_SUPPLEMENTAL)
	badge.add_theme_color_override("font_color", TEXT_PRIMARY)
	badge.add_theme_stylebox_override("normal", glyph_box())
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if HINT_SHAPES.has(glyph):
		# A face button: draw the PS shape in the icon font.
		badge.add_theme_font_override("font", Icons.font())
		badge.text = Icons.glyph(str(HINT_SHAPES[glyph]))
	else:
		# Anything else (a word like "Shift" on the keyboard's action row, or a
		# button no shape table covers) stays text.
		badge.text = glyph
	row.add_child(badge)

	var caption := Label.new()
	caption.text = caption_text
	caption.add_theme_font_size_override("font_size", SIZE_SUPPLEMENTAL)
	caption.add_theme_color_override("font_color", TEXT_SECONDARY)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(caption)

	return row


# ---------------------------------------------------------------------------
# The app menu (home button, over a running application)
#
# THERE ARE NO STYLES LEFT IN THIS SECTION, and that is the point of keeping the
# heading. The menu is drawn over live application pixels rather than over the
# shell's own background, so it needed its own frame and its own opaque circular
# controls back when it framed the application and put two circles underneath.
# It is a centred panel of rows now (see app_overlay.gd for why), and a panel of
# rows is exactly what card_idle_box and the settings row already draw -- the
# scrim behind it does the work the opaque fills used to.
#
# overlay_card_frame, circle_box, circle_box_focused, circle_ring and
# CIRCLE_CORNER_RADIUS lived here and are gone with their only caller. The
# radius in particular was half of app_overlay's CIRCLE_SIZE, kept here so the
# two could not drift -- there is no CIRCLE_SIZE to drift from any more.

## The top-bar icon buttons, rounded to a circle. Half of TOPBAR_ICON_SIZE, so
## the corner radius meets in the middle of each edge and the square reads as a
## circle. These are now the shell's only round controls; when the menu framed
## the application there was a second, larger radius here and the two were
## deliberately not shared, because one constant would have rounded one of them
## wrong.
const TOPBAR_CIRCLE_RADIUS := TOPBAR_ICON_SIZE / 2


static func topbar_circle_box(focused: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE_FOCUS if focused else SURFACE
	box.set_corner_radius_all(TOPBAR_CIRCLE_RADIUS)
	return box


static func topbar_circle_ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(FOCUS_RING_WIDTH)
	box.border_color = FOCUS_RING
	box.set_corner_radius_all(TOPBAR_CIRCLE_RADIUS)
	return box


## Store entries carry their accent as a hex string so the hand-written data
## stays plain text. An unparseable value is a typo, not a reason to draw nothing.
static func accent(hex: String) -> Color:
	if Color.html_is_valid(hex):
		return Color.html(hex)
	return ACCENT_FALLBACK


## The wash behind an installed app's icon, derived from its id.
##
## An enumerated application has no accent to carry -- a desktop entry has an
## icon and nothing resembling a brand colour -- but a rail of identically
## coloured cards loses the "which one am I on" cue that the hero wash gives
## the rail for free. Deriving from the id rather than randomising means a card
## keeps its colour across rescans and reboots, so the rail stays a place with
## a remembered shape rather than one that repaints itself every boot.
##
## Muted on purpose: these sit UNDER an icon, so the wash is a backdrop rather
## than the subject, and it must not fight a colourful icon drawn on top.
const APP_ACCENTS := [
	"#3E5C7A", "#4A6B52", "#7A4E63", "#8A6A3E",
	"#456B70", "#5E5183", "#8A524A", "#4A5E7E",
]


static func accent_for_id(id: String) -> Color:
	if id.is_empty():
		return ACCENT_FALLBACK
	return accent(APP_ACCENTS[absi(id.hash()) % APP_ACCENTS.size()])
