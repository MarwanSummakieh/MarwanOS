extends Node

## ============================================================================
## A GAME'S OWN ARTWORK, read from what the system says.
##
## The seam next door (installed.gd) answers "what is on this machine". This one
## answers "what does it LOOK like", and only for the entries that have an answer
## worth the second file: Steam's library cache holds a square icon and a wide
## hero background per game, and neither fits in apps.tsv's icon column, which is
## one path and is already spoken for by the portrait.
##
## marwanos-gameart writes /run/marwanos/gameart.tsv, tab separated:
##
##   steam.<appid>  <square icon path or empty>  <hero background path or empty>
##
## and this autoload polls it exactly the way installed.gd polls apps.tsv --
## same interval, same raw-text change signature, same "a missing file and an
## empty file mean the same thing" rule. The shell walks no Steam directory and
## parses no .vdf: it is a renderer.
##
## TWO PATHS PER ROW BECAUSE THEY ARE DRAWN IN TWO PLACES AND ARE NOT
## INTERCHANGEABLE. The icon is square and goes ON the card, where the portrait
## it replaces is letterboxed and unreadable at rest. The hero is a wide picture
## Steam draws edge to edge in its own library, and it goes BEHIND everything --
## unblurred, because unlike a portrait it was designed to be a background. See
## shell_root._on_card_selected for the preference order and tile._build_icon for
## the card's.
##
## EITHER COLUMN MAY BE EMPTY AND THAT IS NORMAL, not a failure: the cache warms
## per game as Steam fetches it, so a freshly installed game has a row with two
## empty fields for a while. Every consumer falls back to what it drew before
## this file existed, so a cold cache is last week's shell rather than a blank
## one.
##
## Phase 1 deletes this file with the rest of the file-polling seams: marwand's
## library listing carries artwork alongside the title, and the rail is rewired
## by changing this seam and nothing else.
## ============================================================================

## Emitted whenever the table changes, including to and from empty. No payload:
## the two lookups below are the interface, and a consumer that took a copy of
## the whole table would be holding a snapshot that the next poll replaced.
signal changed()

## Two seconds, matching installed.gd and the status seam. The file changes only
## when Steam's cache gains a picture, and reading a few short lines off a tmpfs
## costs nothing.
const POLL_SECONDS := 2.0

const GAMEART_FILE := "/run/marwanos/gameart.tsv"

## The same desk-run lever every other status file uses, and deliberately not a
## new one: gameart.tsv sits in /run/marwanos beside apps.tsv, so one directory
## of fixtures still drives every file the shell reads.
const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

## id, icon, hero. A line with fewer is malformed and skipped rather than guessed
## at -- the same rule installed.gd applies, and for the same reason: a row that
## is half a record would put a path in the wrong column.
const FIELD_COUNT := 3

var _icons: Dictionary = {}
var _heroes: Dictionary = {}

var _path := GAMEART_FILE

## Whether _poll has ever completed -- installed.gd's reason exactly: without it
## the first poll on a machine with no artwork is silent, and "the cache is
## empty" and "the shell never looked" have to be distinguishable in a journal
## that is the only debugging surface this appliance has.
var _loaded := false
var _last_raw := ""


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_path = override.path_join(GAMEART_FILE.get_file())

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)

	# Polled once here rather than a tick from now, so the first rail the TV
	# draws already carries the icons -- the rail is built in shell_root's
	# _ready, which runs after every autoload's.
	_poll()


func _poll() -> void:
	var raw := _read_file(_path)
	if _loaded and raw == _last_raw:
		return
	_loaded = true
	_last_raw = raw

	_parse(raw)
	ShellLog.info("game artwork: %d icons, %d backgrounds" % [_icons.size(), _heroes.size()])
	changed.emit()


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## Two dictionaries rather than one of pairs: every call site wants exactly one
## of the two pictures, and a lookup that returns a record the caller then
## indexes is a second chance to read the wrong column.
##
## AN EMPTY FIELD IS NOT AN ENTRY. Storing "" would make has() true and the
## fallbacks below never fire, which is the whole failure this seam has to avoid
## on a cold cache.
func _parse(raw: String) -> void:
	_icons.clear()
	_heroes.clear()

	for line in raw.split("\n", false):
		var fields := line.split("\t", true)
		if fields.size() < FIELD_COUNT:
			if not line.strip_edges().is_empty():
				ShellLog.warn("skipping malformed gameart.tsv line: %s" % line)
			continue

		var id := fields[0]
		if id.is_empty():
			continue
		if not fields[1].is_empty():
			_icons[id] = fields[1]
		if not fields[2].is_empty():
			_heroes[id] = fields[2]


## The square icon for an entry id, or empty if the cache has not landed one.
func icon_for(id: String) -> String:
	return str(_icons.get(id, ""))


## The wide background for an entry id, or empty if the cache has not landed one.
func hero_for(id: String) -> String:
	return str(_heroes.get(id, ""))
