extends "res://src/settings_row.gd"

## One tab in the stores screen's side column.
##
## It extends the settings row so tabs, rows and cards stay one family of
## focusable rectangles; the differences are that it carries a store entry and
## that pressing A means something. _on_pressed is overridden rather than
## re-connected: the base class connected its own method name to `pressed`,
## and GDScript resolves that call on the instance, so the override is the
## whole mechanism.

signal opened(entry: Dictionary)

var entry: Dictionary = {}


func setup_store(new_entry: Dictionary) -> void:
	entry = new_entry
	setup(str(entry.get("title", "")), "")


func _on_pressed() -> void:
	opened.emit(entry)
