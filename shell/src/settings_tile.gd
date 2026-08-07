extends "res://src/tile.gd"

## The one card on the rail that is shell furniture rather than library content.
##
## It extends the card instead of duplicating it so it looks, focuses, grows and
## slides exactly like every other card -- the rail stays one kind of thing to
## navigate. The single difference is what pressing A does: this card opens the
## settings screen directly and never touches the launch seam. That keeps
## Launcher.launch "the only call into the launch path" true for things that
## run, and keeps the seam clean for Phase 1's rewiring -- settings must not
## become an RPC to marwand by accident when _run() does.
##
## Appended by shell_root AFTER the catalogue entries rather than defined in
## catalogue.gd: the catalogue file is deleted whole in Phase 1 (the rail is
## populated from ListInstalled instead), and the settings card has to survive
## that deletion.


func _on_pressed() -> void:
	Settings.open()
