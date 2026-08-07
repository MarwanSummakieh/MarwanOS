extends RefCounted

## Phase 0's placeholder library.
##
## Phase 1 deletes this file. The home rail is populated from marwand's
## `ListInstalled` over JSON-RPC instead (docs/phase-1-plan.md, M2), and the
## daemon joins Flatpak refs against AppStream data to produce display name,
## summary and icon.
##
## The dictionary shape below is deliberately the shape that RPC returns -- an
## opaque id, a title, a one-line summary, and something to draw -- so swapping
## the source changes this file and nothing in the rail. `accent` stands in for
## `icon` for now: real icons arrive as a texture the daemon has cached, and the
## card learns to load one asynchronously in Phase 1 M2. A flat colour is what a
## card with no icon yet has to fall back to anyway, so it is not throwaway.
##
## Twelve entries -- enough that the rail is wider than the screen, so the slide,
## the clipping at both edges and the hold-to-repeat traversal all get exercised
## by the placeholder data rather than discovered in Phase 1.
##
## The names are obviously placeholders on purpose. Something that looked like a
## real library would make it impossible to tell, from a photograph of the TV,
## whether the rail was showing baked data or something it had actually enumerated.

static func entries() -> Array:
	return [
		{"id": "placeholder.01", "title": "Placeholder One", "subtitle": "Nothing is installed yet", "accent": "#3E6FA8"},
		{"id": "placeholder.02", "title": "Placeholder Two", "subtitle": "Phase 1 fills this in", "accent": "#5B7F52"},
		{"id": "placeholder.03", "title": "Placeholder Three", "subtitle": "From ListInstalled", "accent": "#8A5A78"},
		{"id": "placeholder.04", "title": "Placeholder Four", "subtitle": "Sorted most recent first", "accent": "#A87A3E"},
		{"id": "placeholder.05", "title": "Placeholder Five", "subtitle": "Icon comes from AppStream", "accent": "#4E7C82"},
		{"id": "placeholder.06", "title": "Placeholder Six", "subtitle": "A deliberately long summary line", "accent": "#6E5AA0"},
		{"id": "placeholder.07", "title": "Placeholder Seven", "subtitle": "Tests title truncation", "accent": "#A05A52"},
		{"id": "placeholder.08", "title": "Placeholder Eight", "subtitle": "Rail grows with the library", "accent": "#4A6B8A"},
		{"id": "placeholder.09", "title": "Placeholder Nine", "subtitle": "No store in Phase 0", "accent": "#7A8046"},
		{"id": "placeholder.10", "title": "Placeholder Ten", "subtitle": "No library in Phase 0", "accent": "#8C6A46"},
		{"id": "placeholder.11", "title": "Placeholder Eleven", "subtitle": "Launch is a scene swap", "accent": "#566E96"},
		{"id": "placeholder.12", "title": "Placeholder Twelve", "subtitle": "Settings sits after this", "accent": "#6A5F7E"},
	]
