extends RefCounted

## The shell's icon language: Phosphor, one font, these codepoints.
##
## WHY A FONT AND NOT MORE DRAWN PRIMITIVES. The first five glyphs were arcs
## and rectangles in glyphs.gd, and that was right for five: reviewable text,
## no assets. "Clean icons on everything" is not five -- it is dozens, across
## the explorer, the power menu, the hint row -- and hand-drawing plateaus at
## "geometric" while each new icon is bespoke code. A single MIT-licensed TTF
## trades one vendored binary (pinned by hash -- see assets/phosphor/
## PROVENANCE.md) for a complete, consistent set that scales and recolors like
## text.
##
## CODEPOINTS ARE DECLARED, NOT DISCOVERED. Phosphor ships ligature support, so
## `Label.text = "wifi-high"` with the right font feature would also work --
## and would break silently the day a name changes, with the icon degrading to
## literal text. A wrong codepoint degrades to a visible tofu box, which is a
## failure someone notices. Every value below is from the same commit as the
## vendored TTF; PROVENANCE.md says why they must be re-checked together.

## Loaded from the RAW ttf at runtime, not preloaded -- and the build's smoke
## gate is why this is known to matter rather than suspected. `preload` of a
## font goes through the import system, whose cache is authored by the editor;
## this project's pipeline is deliberately editor-free, so the preload parse-
## failed and took every dependent script with it. load_dynamic_font reads the
## ttf bytes directly, needs no import artefacts, and the file reaches the
## pack through the export preset's include_filter (raw files are otherwise
## not packed at all -- the OTHER half of the same trap).
static var _font: FontFile = null


static func font() -> FontFile:
	if _font == null:
		_font = FontFile.new()
		var error := _font.load_dynamic_font("res://assets/phosphor/Phosphor.ttf")
		if error != OK:
			ShellLog.error("could not load the icon font (error %d); icons will be blank" % error)
	return _font

const CODEPOINTS := {
	# The shell's existing marks
	"store": 0xe470,        # storefront
	"gear": 0xe270,
	"wifi": 0xe4ea,         # wifi-high
	"wifi-off": 0xe4f2,     # wifi-slash
	"close": 0xe4f6,        # x
	"minimize": 0xe32a,     # minus

	# The pad's face buttons, PS5-shaped. Named for the SHAPE, not the action:
	# tv_theme.hint maps logical buttons (A/B/X/Y) onto these, and that mapping
	# is the one place that knows cross means confirm.
	"cross": 0xe4f6,        # x -- same mark, both meanings
	"circle": 0xe18a,
	"square": 0xe45e,
	"triangle": 0xe4b0,

	# The power menu
	"power": 0xe3da,
	"restart": 0xe094,      # arrows-clockwise
	"sleep": 0xe330,        # moon

	# The updater
	"download": 0xe20c,     # download-simple
	"check": 0xe182,

	# The file explorer
	"folder": 0xe24a,
	"folder-open": 0xe256,
	"file": 0xe230,
	"arrow-left": 0xe058,
	"arrow-up": 0xe08e,
	"trash": 0xe4a6,
	"copy": 0xe1ca,
	"cut": 0xeae0,          # scissors
	"rename": 0xe3b4,       # pencil-simple
	"drive": 0xe2a0,        # hard-drives
	"usb": 0xe956,
	"home": 0xe2c2,         # house
	"eject": 0xe212,
	"more": 0xe1fe,         # dots-three
	"caret-right": 0xe13a,
	"caret-left": 0xe138,

	# Elsewhere in settings
	"controller": 0xe26e,   # game-controller
	"display": 0xe32e,      # monitor
	"terminal": 0xeae8,     # terminal-window
	"keyboard": 0xe2d8,
}


## The glyph for a name, as a one-character String, or empty for a name this
## table does not know -- which renders as nothing rather than as a tofu box,
## because a missing name is a shell bug and the failure that points at it is
## the log line, not a broken rectangle on the TV.
static func glyph(name: String) -> String:
	if not CODEPOINTS.has(name):
		ShellLog.warn("no icon named \"%s\"" % name)
		return ""
	return String.chr(int(CODEPOINTS[name]))


## A ready-made icon Label: the font, the glyph, a size and a colour. The
## caller owns layout; this owns nothing but appearance.
static func label(name: String, size: int, color: Color) -> Label:
	var icon := Label.new()
	icon.text = glyph(name)
	icon.add_theme_font_override("font", font())
	icon.add_theme_font_size_override("font_size", size)
	icon.add_theme_color_override("font_color", color)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
