extends Control

## The file manager: the shell's own, from the couch, on the pad.
##
## It replaces a plan to ship the Dolphin flatpak, and the difference is not
## pride of authorship. Dolphin under the pad bridge is a mouse-first desktop
## program being puppeted with injected arrow keys -- workable, and still a
## foreign UI at desktop type sizes with verbs hidden in menus a stick cannot
## reach. A file browser is rows, a focus chain, and five verbs; that is
## exactly the furniture this shell already knows how to draw, at TV sizes,
## with the buttons the pad actually has.
##
## THE TOP LEVEL IS PLACES, NOT A PATH. "/" is an answer for people who
## already know the answer; the two places a person on a couch means when they
## say "my files" are their home and whatever stick they just plugged in. So
## the screen opens on Home plus one row per mount under /run/media, and the
## filesystem's plumbing (/proc, /sys, the ostree deployment) never appears
## unless someone deliberately walks up out of home -- which they cannot,
## because B at a place's root goes back to Places, not to its parent.
##
## NAVIGATION IS THE SETTINGS LIST'S TABLE VERBATIM: one axis, hard stops,
## perpendicular pointed at self, follow_focus scrolling for long directories.
## Hold-to-repeat comes free from FocusRepeat like everywhere else -- nothing
## here implements repetition. A descends into a folder; A on a file says,
## honestly, that Phase 0 has nothing to open it with -- no fake viewer,
## because a viewer that renders three formats badly is worse than a sentence
## that is true about all of them. B ascends one level, and at Places it
## closes the screen.
##
## EVERY OPERATION'S OUTCOME LANDS ON THE STATUS LINE AND IN ShellLog. This
## machine's user cannot see stderr, and a copy that silently did nothing is
## indistinguishable from a copy that worked until the file is needed.
##
## THE PLACES LIST IS LIVE, and that is the fix for the one report this screen
## has had from the couch: a stick was plugged in and "the files app did not
## recognize it at all". Two things were wrong and both are addressed here and
## in the OS. The OS half is that nothing mounted the stick -- an appliance with
## no desktop session has no automounter, so /run/media never gained a directory
## for this screen to find (see /usr/lib/marwanos/usbmount). The SHELL half is
## this: the places list was built once, in _ready, so even a mount that did
## appear was invisible until the screen was closed and reopened. A stick is
## plugged in WHILE someone is looking at the screen -- that is the whole
## gesture -- so the mount set is polled, and a drive arriving or leaving
## redraws Places under the cursor. See _start_mount_watch.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")
const FileMenu = preload("res://src/file_menu.gd")
const Keyboard = preload("res://src/keyboard.gd")

## The desk and harness override, in the spirit of MARWANOS_SHELL_STORE_DIR:
## point it at any directory and the Home place browses that instead of $HOME.
## The Xvfb harness needs it because its container pins HOME to an empty
## tmpfs, and a file manager verified only against an empty folder is a file
## manager whose listing code has never run.
const FILES_HOME_ENV := "MARWANOS_SHELL_FILES_HOME"

## Where removable media lands on the appliance. marwanos-usbmount mounts under
## /run/media/<user>/<label>, which is udisks2's own convention and therefore
## the one a desktop would use on the same stick; the user directory is
## enumerated rather than guessed from $USER because the shell does not get to
## assume whose session mounted the stick.
##
## NO ENVIRONMENT OVERRIDE, unlike FILES_HOME above, and that is deliberate
## rather than an omission: /run is a tmpfs in the Xvfb harness's container, so
## a directory of fake drives can simply be bind-mounted at the REAL path (see
## MEDIA_DIR in scripts/xvfb-shell-verify.sh). An override would be a second
## code path that only the harness ever took, to reach a place the harness can
## already reach.
const MEDIA_ROOT := "/run/media"

## How often the mount set is re-read while this screen is up. A directory
## listing of /run/media/<user> is two getdents on a tmpfs -- cheap enough that
## the interval is chosen by how long a person will hold a stick in a port
## wondering whether it worked, not by cost. Two seconds is under that.
const MOUNT_POLL_SECONDS := 2.0

## Empty string means the Places view; anything else is the directory on
## screen. The pair below is what B consults: at _place_root, back means
## Places, not the parent -- see the header.
var _current_path: String = ""
var _place_root: String = ""

## The clipboard: {"path": String, "cut": bool}, empty when nothing is armed.
## SCREEN-LIFETIME ON PURPOSE: it survives navigating anywhere within the
## screen (copy here, paste there is the whole point) and dies with the
## screen, because a clipboard that outlives its UI is an invisible loaded
## state the next opening would act on with no way to see it was armed.
var _clipboard: Dictionary = {}

var _rows: Array = []
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _path_label: Label = null
var _status: Label = null
var _empty: Label = null
var _hints: HBoxContainer = null

var _menu: FileMenu = null
var _keyboard: Keyboard = null
## What the open menu (and then the keyboard, for Rename) is about:
## {"path", "name", "is_dir"}. Captured when OPTIONS is pressed, because by the
## time a choice arrives the menu's row owns focus and the list cannot be asked.
var _menu_target: Dictionary = {}
## Where focus goes back to when the menu or keyboard closes, by entry name --
## by name rather than by node, because operations rebuild the list.
var _return_focus_name: String = ""

## Symlinks skipped by the last recursive copy, for the status line. A member
## rather than a return value because the copy is recursive and threading a
## count through every level buys nothing over resetting it at the top.
var _skipped_links: int = 0

## The mount set as of the last poll, so the redraw happens on CHANGE rather
## than every two seconds -- a Places view that rebuilt itself on a timer would
## drop the focus ring under the person's thumb for no reason at all.
var _known_mounts: Array = []

## What the keyboard is currently being used for: "rename" or "newfolder".
## Both open the same Keyboard on the same slot, and the submit handler has to
## know which question was asked.
var _keyboard_purpose: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The full TV-safe inset, all four edges. Everything on this screen is text
	# or carries a focus ring; nothing has the rail's licence to bleed.
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)
	add_child(safe)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", TvTheme.SECTION_GAP)
	safe.add_child(column)

	var heading := Label.new()
	heading.text = "Files"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	# WHERE YOU ARE. One line, ellipsized from the LEFT, because the useful end
	# of a deep path is its tail -- "…/Season 2/Episode 4" answers the question
	# and "/run/media/marwan/USB Drive/Sho…" does not. Godot's overrun trimming
	# only cuts the tail, so the eliding is done by hand in _elide_left.
	_path_label = Label.new()
	_path_label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_path_label.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_path_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_path_label)

	# The settings screen's scrolling, for the settings screen's reason: a long
	# directory reaches below the safe area, the focus chain does not care, and
	# a focused row off the bottom of a TV is a screen that silently ends
	# early. follow_focus plus the explicit ensure_control_visible on each
	# row's focus (see _on_row_focused) covers both the steady state and the
	# first grab before layout.
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	# Rows span the scroll viewport's width -- settings_screen's lesson about
	# the VBox shrinking to its children's minimum.
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	# The honest empty state. A folder with nothing in it must say so: a blank
	# pane on this machine reads as a render failure, not as emptiness.
	_empty = Label.new()
	_empty.text = "Nothing in this folder"
	_empty.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_empty.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_empty.visible = false
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(_empty)

	# The status line: what the last operation actually did. Above the hints
	# rather than in them, because it is a sentence and they are a legend.
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_status)

	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	column.add_child(_hints)

	_show_places()
	_start_mount_watch()
	Media.state_changed.connect(_on_media_state_changed)

	ShellLog.info("files screen up at places with %d place(s)" % _rows.size())


# ---------------------------------------------------------------------------
# Drives coming and going
# ---------------------------------------------------------------------------

## Watch /run/media for a stick arriving or leaving, for as long as this screen
## is up. See the class header for why a screen that only listed drives once
## was the shell's half of "it did not recognize it at all".
func _start_mount_watch() -> void:
	_known_mounts = _mounts()
	var timer := Timer.new()
	timer.wait_time = MOUNT_POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll_mounts)
	add_child(timer)


func _poll_mounts() -> void:
	# Not while a menu or the keyboard is up. Both are about a named row, and
	# rebuilding the list underneath them would leave the choice that comes back
	# pointing at a node that no longer exists.
	if _menu != null or _keyboard != null:
		return

	var now := _mounts()
	if now == _known_mounts:
		return

	var arrived: Array = []
	for path in now:
		if not _known_mounts.has(path):
			arrived.append(path)
	var left: Array = []
	for path in _known_mounts:
		if not now.has(path):
			left.append(path)
	_known_mounts = now

	for path in arrived:
		ShellLog.info("files: drive appeared at %s" % path)
	for path in left:
		ShellLog.info("files: drive went away from %s" % path)

	# THE DRIVE UNDER THE CURSOR WAS PULLED. Everything below _place_root is now
	# a path to nowhere, and _enter_directory's failure branch would leave the
	# screen showing a listing of a filesystem that is gone. Places is the only
	# view that is still true.
	if not _place_root.is_empty() and left.has(_place_root):
		_say("%s was removed" % _place_root.get_file(), true)
		_show_places()
		return

	# Only Places renders the drive list, so only Places has to be redrawn. A
	# stick arriving while someone is three folders deep in their home directory
	# is news that can wait until they walk back out.
	if not _current_path.is_empty():
		return

	# Keep the cursor where it was by path -- _show_places' own focus_path
	# argument -- so a drive appearing does not move the selection off Home.
	var focused := _focused_entry()
	_show_places(str(focused.get("path", "")))
	if not arrived.is_empty():
		var names := PackedStringArray()
		for path in arrived:
			names.append(path.get_file())
		_say("%s is ready" % ", ".join(names))


## The privileged half finished (or refused) an eject. The drive is already
## gone from the poll by then in the happy case -- this is what puts the REASON
## on screen when it did not go.
func _on_media_state_changed(state: String, mount_path: String, said: String) -> void:
	match state:
		"done":
			_say("%s can be unplugged" % mount_path.get_file())
		"failed":
			_say("Could not eject %s%s"
				% [mount_path.get_file(), (" -- %s" % said) if not said.is_empty() else ""], true)
		"refused":
			_say("This machine will not eject that", true)


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------

## The top level: Home, then one row per mounted stick. Never empty -- Home is
## always offered even if the directory behind it turns out hostile, because a
## Places view with zero rows would be a screen with nothing to focus and
## nothing to explain itself with.
func _show_places(focus_path: String = "") -> void:
	_current_path = ""
	_place_root = ""
	_path_label.text = "Places"

	var entries: Array = []
	# The folder glyph rather than the house: this row IS a folder -- the one
	# the person owns -- and the icon language should say what a thing is, not
	# where the metaphor came from.
	var home := _home_path()
	entries.append({
		"name": "Home", "value": _free_space_text(home), "icon": "folder",
		"meta": {"kind": "place", "path": home, "name": "Home", "removable": false},
	})
	for mount_path in _mounts():
		# FREE SPACE ON THE ROW, because "will this fit" is the question a
		# person asks of a stick before they copy anything to it, and the only
		# alternative on this machine is copying and finding out. It is the one
		# number a place row can carry that a directory listing cannot.
		entries.append({
			"name": mount_path.get_file(), "value": _free_space_text(mount_path), "icon": "usb",
			"meta": {"kind": "place", "path": mount_path, "name": mount_path.get_file(),
				"removable": true},
		})

	_rebuild_rows(entries)
	_refresh_hints()

	# Coming back from inside a place, land on that place rather than the top.
	var focused := false
	if not focus_path.is_empty():
		for row in _rows:
			var meta: Dictionary = row.get_meta("entry")
			if str(meta.get("path", "")) == focus_path:
				row.grab_focus()
				focused = true
				break
	if not focused and not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("files: at places (%d place(s), %d mount(s))"
		% [_rows.size(), _rows.size() - 1])


## One directory, as rows: folders first, then files, both alphabetical,
## dotfiles skipped -- this is a TV, not a shell prompt, and .config is
## plumbing nobody navigates to from a couch.
func _enter_directory(path: String, focus_name: String = "") -> void:
	var listing: Variant = _list_directory(path)
	if listing == null:
		# Stay where we are: a failed descent that also lost the current view
		# would be two failures for one press.
		_say("Could not open %s" % path.get_file(), true)
		return

	_current_path = path
	_path_label.text = _elide_left(path)

	var entries: Array = []
	for dir_name in listing["dirs"]:
		entries.append({
			"name": dir_name, "value": "", "icon": "folder",
			"meta": {"kind": "entry", "path": path.path_join(dir_name),
				"name": dir_name, "is_dir": true},
		})
	for file_name in listing["files"]:
		entries.append({
			"name": file_name, "value": _file_size_text(path.path_join(file_name)),
			"icon": "file",
			"meta": {"kind": "entry", "path": path.path_join(file_name),
				"name": file_name, "is_dir": false},
		})

	_rebuild_rows(entries)
	_refresh_hints()

	# Ascending focuses the folder just left; operations re-focus what they
	# touched; a plain descent starts at the top.
	var focused := false
	if not focus_name.is_empty():
		for row in _rows:
			var meta: Dictionary = row.get_meta("entry")
			if str(meta.get("name", "")) == focus_name:
				row.grab_focus()
				focused = true
				break
	if not focused and not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	ShellLog.info("files: entered %s (%d entries)" % [path, _rows.size()])


## Re-list the current directory after an operation changed it, keeping focus
## on a named entry where it survived.
func _refresh_listing(focus_name: String = "") -> void:
	if _current_path.is_empty():
		_show_places()
		return
	_enter_directory(_current_path, focus_name)


func _rebuild_rows(entries: Array) -> void:
	for row in _rows:
		_list.remove_child(row)
		row.queue_free()
	_rows.clear()

	for entry in entries:
		var row := ActionRow.new()
		row.setup(str(entry["name"]), str(entry["value"]), str(entry["icon"]))
		row.set_meta("entry", entry["meta"])
		row.activated.connect(_on_row_pressed.bind(row))
		row.focus_entered.connect(_on_row_focused.bind(row))
		_list.add_child(row)
		_rows.append(row)

	_empty.visible = _rows.is_empty()
	_wire_focus_neighbours()


## The settings list's table verbatim: one axis, hard stops, perpendicular
## pointed at self so Control's geometric search cannot wander to the hints.
func _wire_focus_neighbours() -> void:
	var count := _rows.size()
	for index in count:
		var row: Control = _rows[index]
		var up := index - 1 if index > 0 else index
		var down := index + 1 if index + 1 < count else index

		row.focus_neighbor_top = row.get_path_to(_rows[up])
		row.focus_neighbor_bottom = row.get_path_to(_rows[down])
		row.focus_neighbor_left = row.get_path_to(row)
		row.focus_neighbor_right = row.get_path_to(row)


## Keep the focused row on screen. Deferred for settings_screen's reason: the
## first call arrives from a grab_focus before the scroll container has been
## laid out, and asking an unsized viewport to reveal a control scrolls it
## nowhere.
func _on_row_focused(row: Control) -> void:
	if _scroll == null:
		return
	_scroll.ensure_control_visible.call_deferred(row)
	# At Places the OPTIONS hint belongs to the ROW -- a drive has an eject and
	# Home has nothing -- so moving the cursor has to redraw the legend. Inside
	# a place every row has the same menu and the hints are already right, which
	# is why this is not simply called on every focus change.
	if _current_path.is_empty():
		_refresh_hints()


func _refresh_hints() -> void:
	if _hints == null:
		return
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()

	_hints.add_child(TvTheme.hint("A", "Open"))
	# OPTIONS only where it does something, and advertising a button whose press
	# is correctly ignored is the exact shape of "broken input" on a machine
	# with no other feedback. Inside a place that is always: there is a file or
	# a folder to act on, or at minimum a folder to make a new one in. At PLACES
	# it depends on the row -- a drive can be ejected, Home cannot be anything.
	if not _current_path.is_empty() or _places_row_has_options():
		_hints.add_child(TvTheme.hint("OPTIONS", "Options"))
	_hints.add_child(TvTheme.hint("B", "Back"))


## Does the focused Places row have a menu behind it? Only a removable drive
## does -- Eject is the whole of it. Asked of the focus owner rather than of
## the list, so the hint tracks the cursor moving between Home and a stick.
func _places_row_has_options() -> bool:
	if not _current_path.is_empty():
		return false
	return bool(_focused_entry().get("removable", false))


# ---------------------------------------------------------------------------
# Listing
# ---------------------------------------------------------------------------

func _home_path() -> String:
	var override := OS.get_environment(FILES_HOME_ENV)
	if not override.is_empty():
		return override
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		return home
	# The appliance's session always exports HOME; this is the desk fallback,
	# and on the desks this repo runs on the desk user is root.
	return "/root"


## Every mount under /run/media/<any user>/. No /run/media at all -- a desk, a
## container, a machine with nothing plugged in -- is the normal case and
## returns the normal answer: nothing.
func _mounts() -> Array:
	var result: Array = []
	var media := DirAccess.open(MEDIA_ROOT)
	if media == null:
		return result
	for user_name in media.get_directories():
		var user_dir := DirAccess.open(MEDIA_ROOT.path_join(user_name))
		if user_dir == null:
			continue
		for mount_name in user_dir.get_directories():
			result.append(MEDIA_ROOT.path_join(user_name).path_join(mount_name))
	result.sort()
	return result


## {dirs: [...], files: [...]} sorted for the screen, or null when the
## directory cannot be opened. get_directories/get_files skip hidden entries
## by default, which is exactly the dotfile policy the header states -- no
## filtering code, just the default left alone on purpose.
func _list_directory(path: String) -> Variant:
	var dir := DirAccess.open(path)
	if dir == null:
		ShellLog.warn("files: could not open %s (%s)"
			% [path, error_string(DirAccess.get_open_error())])
		return null

	var dirs: Array = []
	for entry_name in dir.get_directories():
		dirs.append(entry_name)
	var files: Array = []
	for entry_name in dir.get_files():
		files.append(entry_name)

	# Case-insensitive, so "Downloads" and "docs" interleave the way a person
	# alphabetises rather than the way ASCII does.
	var by_name := func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0
	dirs.sort_custom(by_name)
	files.sort_custom(by_name)

	return {"dirs": dirs, "files": files}


## A file's size, cheaply. FileAccess.open + get_length stats the file without
## reading it; get_file_as_bytes would pull the whole thing through memory to
## measure it, which on a 40 GB rip on a USB stick is not a size query, it is
## an accident. Directories deliberately show nothing: their "size" would be
## an entry count, and counting costs a directory read PER ROW -- a listing of
## fifty folders would do fifty extra reads to decorate a column nobody asked
## for. An unreadable file shows nothing too; the name still lists.
func _file_size_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return _human_size(file.get_length())


## "12.4 GB free", or empty when the volume will not answer.
##
## DirAccess.get_space_left reports the free space of the filesystem the open
## directory lives on -- a statvfs, not a walk -- so it costs the same on a
## 2 GB stick and a 4 TB disk. A directory that will not open (a mount that
## vanished between the listing and this call, which the poll makes a real
## race) renders no number rather than a zero, because "0 B free" is a claim
## and "nothing" is an absence.
func _free_space_text(path: String) -> String:
	var dir := DirAccess.open(path)
	if dir == null:
		return ""
	var free := dir.get_space_left()
	# Godot returns 0 for a filesystem it cannot stat as well as for a genuinely
	# full one. Full is real and worth saying; the ambiguity is accepted here
	# because the honest failure -- a drive that is actually out of room --
	# is the one a person needs to be told about.
	return "%s free" % _human_size(free)


func _human_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	var value := float(bytes)
	for unit in ["KB", "MB", "GB", "TB"]:
		value /= 1024.0
		if value < 1024.0 or unit == "TB":
			return "%.1f %s" % [value, unit]
	return ""


## Ellipsize from the LEFT against the safe width, by hand -- Godot's overrun
## trimming only cuts a string's tail. Measured against the design surface's
## safe width rather than the label's own rect because the label may not be
## laid out yet on the frame the path changes; the design width is known
## always and errs conservative on the wider stretch-expanded panels.
func _elide_left(path_text: String) -> String:
	var font := _path_label.get_theme_font("font")
	var font_size := TvTheme.SIZE_BODY
	var budget := float(TvTheme.BASE_WIDTH - 2 * TvTheme.SAFE_MARGIN_X)
	if font.get_string_size(path_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= budget:
		return path_text
	var tail := path_text
	while tail.length() > 1 \
			and font.get_string_size("…" + tail, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > budget:
		tail = tail.substr(1)
	return "…" + tail


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_row_pressed(row: Control) -> void:
	var entry: Dictionary = row.get_meta("entry")
	var path := str(entry.get("path", ""))

	if str(entry.get("kind", "")) == "place":
		# Descending into a place sets the floor B stops at. Set BEFORE the
		# descent so a failed open leaves no half-armed floor: _enter_directory
		# bails without touching _current_path on failure, and the stale
		# _place_root is overwritten by the next successful descent.
		_place_root = path
		_status.text = ""
		_enter_directory(path)
		return

	if bool(entry.get("is_dir", false)):
		_status.text = ""
		_enter_directory(path)
		return

	# A on a file. Phase 0 has no viewers, and the honest sentence beats a
	# fake one: nothing opens, and the screen says why in terms of THIS file.
	var file_name := str(entry.get("name", ""))
	var ext := file_name.get_extension()
	if ext.is_empty():
		_say("Nothing on this machine opens \"%s\" yet" % file_name)
	else:
		_say("Nothing on this machine opens .%s yet" % ext)


func _unhandled_input(event: InputEvent) -> void:
	# OPTIONS opens the focused row's options -- checked before B for
	# shell_root's reason: it is the door to the verbs, and B is the door out.
	if InputMap.has_action("ui_shell_options") and event.is_action_pressed("ui_shell_options"):
		get_viewport().set_input_as_handled()
		_open_menu()
		return

	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath never sees the same press.
	get_viewport().set_input_as_handled()

	if _current_path.is_empty():
		ShellLog.info("files: closed by B at places")
		closed.emit()
		return
	_status.text = ""
	if _current_path == _place_root:
		# The floor: a place's root backs out to Places, never to its parent.
		# /home and /run/media/<user> are plumbing, and B walking into them
		# would put the whole filesystem one held button away from the couch.
		ShellLog.info("files: back to places from %s" % _current_path)
		_show_places(_place_root)
		return
	_enter_directory(_current_path.get_base_dir(), _current_path.get_file())


# ---------------------------------------------------------------------------
# The options menu
# ---------------------------------------------------------------------------

func _open_menu() -> void:
	if _menu != null or _keyboard != null:
		return
	if _current_path.is_empty():
		_open_place_menu()
		return

	var target := _focused_entry()
	var items: Array = []
	if not target.is_empty():
		items.append({"id": "copy", "label": "Copy", "icon": "copy"})
		items.append({"id": "cut", "label": "Cut", "icon": "cut"})
	if not _clipboard.is_empty():
		# Paste appears ONLY while armed: a permanent Paste that mostly says
		# "nothing to paste" would train the button to mean nothing. The verb
		# names its object so the menu carries its own state. "download" is
		# the closest mark the vendored table has -- an arrow into a tray IS
		# paste-into-here, and PROVENANCE.md forbids guessing new codepoints.
		items.append({"id": "paste",
			"label": "Paste %s" % str(_clipboard.get("path", "")).get_file(),
			"icon": "download"})
	if not target.is_empty():
		items.append({"id": "rename", "label": "Rename", "icon": "rename"})
		items.append({"id": "delete", "label": "Delete", "icon": "trash"})
	# ALWAYS OFFERED, and it is the one item that is about the FOLDER rather
	# than about a row in it -- which is also why it is last, under the verbs
	# that act on the thing the cursor is on. It is what makes an empty folder
	# have a menu at all: before it, OPTIONS in a folder with nothing in it and
	# nothing on the clipboard opened nothing, and "a file manager you cannot
	# make a folder with" is most of the distance between this screen and one.
	items.append({"id": "newfolder", "label": "New folder", "icon": "folder"})

	_menu_target = target
	_return_focus_name = str(target.get("name", ""))
	_menu = FileMenu.new()
	# An empty-folder paste has no row to be about; the folder itself is the
	# subject then.
	_menu.title_text = str(target.get("name", _current_path.get_file()))
	_menu.items = items
	if not target.is_empty():
		# Named cost, card_menu's discipline: delete here is the trash, which
		# is reversible from a desktop -- and saying "cannot be undone" about
		# it would be the note lying in the scary direction.
		_menu.note_text = "Delete moves it to the system's wastebasket, not into thin air."
	_menu.chosen.connect(_on_menu_chosen)
	_menu.closed.connect(_on_menu_closed, CONNECT_ONE_SHOT)
	# Deaf while the menu is up, so one B press cannot close both surfaces.
	set_process_unhandled_input(false)
	add_child(_menu)


## OPTIONS at Places, which used to be a no-op with a journal line. A drive has
## exactly one verb and it is the one that matters most: taking it out without
## losing what was just written to it. Home has none -- you cannot eject the
## disk the shell is running from -- so the menu simply does not open there,
## and the hint row already said it would not (see _places_row_has_options).
func _open_place_menu() -> void:
	var target := _focused_entry()
	if not bool(target.get("removable", false)):
		ShellLog.info("files: OPTIONS on a place with nothing to offer")
		return
	if Media.is_busy():
		ShellLog.info("files: OPTIONS while an eject is already in flight; ignoring")
		return

	_menu_target = target
	_return_focus_name = str(target.get("name", ""))
	_menu = FileMenu.new()
	_menu.title_text = str(target.get("name", ""))
	_menu.items = [{"id": "eject", "label": "Safely remove", "icon": "eject"}]
	# The cost, named the way card_menu names a re-download: what the person
	# gets for the extra press is the promise that the write finished.
	_menu.note_text = "Everything is written to the drive first. Wait for the message before unplugging it."
	_menu.chosen.connect(_on_menu_chosen)
	_menu.closed.connect(_on_menu_closed, CONNECT_ONE_SHOT)
	set_process_unhandled_input(false)
	add_child(_menu)


func _focused_entry() -> Dictionary:
	var owner := get_viewport().gui_get_focus_owner()
	for row in _rows:
		if row == owner:
			return row.get_meta("entry")
	return {}


func _on_menu_chosen(id: String) -> void:
	match id:
		"copy":
			_arm_clipboard(false)
		"cut":
			_arm_clipboard(true)
		"paste":
			_paste_into(_current_path)
		"rename":
			_open_rename()
		"delete":
			_delete_target()
		"newfolder":
			_open_new_folder()
		"eject":
			_eject_target()
		_:
			ShellLog.error("file menu item \"%s\" has no action" % id)


func _on_menu_closed() -> void:
	_close_menu.call_deferred()


func _close_menu() -> void:
	if _menu == null:
		return
	var menu := _menu
	_menu = null
	remove_child(menu)
	menu.queue_free()
	# Rename opens the keyboard from the menu's chosen handler; when it did,
	# the keyboard owns input and focus until it closes, and re-enabling here
	# would let B reach this screen THROUGH it.
	if _keyboard != null:
		return
	set_process_unhandled_input(true)
	_focus_row_named(_return_focus_name)


func _focus_row_named(entry_name: String) -> void:
	for row in _rows:
		var meta: Dictionary = row.get_meta("entry")
		if str(meta.get("name", "")) == entry_name:
			row.grab_focus()
			return
	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()


# ---------------------------------------------------------------------------
# The clipboard
# ---------------------------------------------------------------------------

func _arm_clipboard(cut: bool) -> void:
	var path := str(_menu_target.get("path", ""))
	if path.is_empty():
		return
	_clipboard = {"path": path, "cut": cut}
	var target_name := str(_menu_target.get("name", ""))
	_say("%s %s -- Paste puts it in the folder you are in"
		% ["Cut" if cut else "Copied", target_name])
	ShellLog.info("files: clipboard armed (%s) for %s" % ["cut" if cut else "copy", path])


## Paste the armed path into a directory. Copy leaves the clipboard armed --
## pasting the same thing into three folders is a legitimate afternoon -- and
## cut clears it, because the source the clipboard names no longer exists.
func _paste_into(dest_dir: String) -> void:
	var src := str(_clipboard.get("path", ""))
	var cut := bool(_clipboard.get("cut", false))
	if src.is_empty():
		return
	var src_name := src.get_file()
	var src_is_dir := DirAccess.dir_exists_absolute(src)

	if not src_is_dir and not FileAccess.file_exists(src):
		# The source left between the arm and the paste -- deleted, unmounted,
		# renamed. The clipboard is now a claim about nothing; disarm it.
		_say("%s is gone; nothing to paste" % src_name, true)
		_clipboard = {}
		return

	if src_is_dir and (dest_dir == src or dest_dir.begins_with(src + "/")):
		# A folder pasted into itself recurses forever, copying its own copy.
		_say("Cannot paste %s into itself" % src_name, true)
		return

	if cut and src.get_base_dir() == dest_dir:
		# Moving a thing into the folder it is already in is a no-op that the
		# collision rule below would turn into a puzzling duplicate.
		_say("%s is already here" % src_name)
		return

	if _is_symlink(src):
		# The copy machinery refuses links wholesale -- see _copy_directory
		# for the policy -- and a link at the TOP of the request deserves a
		# sentence, not a silent skip count.
		_say("%s is a link; links are not copied" % src_name, true)
		return

	var dest := _unique_destination(dest_dir, src_name, src_is_dir)
	var dest_name := dest.get_file()
	_skipped_links = 0

	var err: int = OK
	if cut:
		# rename_absolute is the move when both ends share a filesystem --
		# instant, atomic, and it carries directories whole. Across
		# filesystems (home to a USB stick, the common case here) the kernel
		# refuses, and the honest fallback is copy-then-delete.
		err = DirAccess.rename_absolute(src, dest)
		if err != OK:
			err = _copy_any(src, dest, src_is_dir)
			if err == OK:
				err = _remove_recursive(src)
				if err != OK:
					# The copy landed; the source would not go. Worse ways to
					# fail exist -- the data now exists twice, not zero times
					# -- but the person must hear it is still there.
					_say("Moved %s, but the original would not delete" % dest_name, true)
					ShellLog.error("files: cut of %s copied to %s but source removal failed (%s)"
						% [src, dest, error_string(err)])
					_clipboard = {}
					_refresh_listing(dest_name)
					return
	else:
		err = _copy_any(src, dest, src_is_dir)

	if err != OK:
		_say("Could not paste %s (%s)" % [src_name, error_string(err)], true)
		ShellLog.error("files: paste of %s into %s failed (%s)"
			% [src, dest_dir, error_string(err)])
		return

	if cut:
		_clipboard = {}
		ShellLog.info("files: moved %s to %s" % [src, dest])
	else:
		ShellLog.info("files: copied %s to %s" % [src, dest])

	var line := "%s %s" % ["Moved" if cut else "Copied", dest_name]
	if _skipped_links > 0:
		line += " (%d link(s) skipped)" % _skipped_links
	_say(line)
	_refresh_listing(dest_name)


## A destination that exists nowhere yet. " (copy)" before the extension, then
## " (copy 2)" and up -- looping rather than stopping at one, because the rule
## is absolute: paste NEVER overwrites. Silently destroying the thing already
## there to make room for its twin is the one behaviour a file manager is
## never forgiven. Directories keep their whole name as the stem: get_basename
## would read "Season.2" as a file called "Season" with an extension.
func _unique_destination(dest_dir: String, source_name: String, is_dir: bool) -> String:
	var dest := dest_dir.path_join(source_name)
	if not _exists(dest):
		return dest
	var stem := source_name if is_dir else source_name.get_basename()
	var ext := "" if is_dir else source_name.get_extension()
	var attempt := 0
	while true:
		attempt += 1
		var tag := " (copy)" if attempt == 1 else " (copy %d)" % attempt
		var candidate := stem + tag
		if not ext.is_empty():
			candidate += "." + ext
		dest = dest_dir.path_join(candidate)
		if not _exists(dest):
			break
	return dest


func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


## Is the entry itself a symlink? Asked of the PARENT directory, because
## DirAccess resolves the path being opened but reports honestly about the
## names inside it.
func _is_symlink(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	if parent == null:
		return false
	return parent.is_link(path.get_file())


func _copy_any(src: String, dest: String, src_is_dir: bool) -> int:
	if src_is_dir:
		return _copy_directory(src, dest)
	return DirAccess.copy_absolute(src, dest)


## Recursive directory copy, written with the two rules that make it safe:
##
## SYMLINKS ARE SKIPPED, NOT FOLLOWED. Following one can loop a copy forever
## (a link up its own tree), silently drag in another filesystem, or turn one
## stick's 2 GB into a full disk. Recreating links was considered and dropped:
## an absolute link copied to a USB stick points at a path the next machine
## does not have, which is a broken promise dressed as fidelity. Skipped links
## are counted into _skipped_links and the status line says so.
##
## HIDDEN ENTRIES ARE COPIED even though the listing hides them. The listing's
## dotfile policy is about what a couch needs to SEE; a copy that quietly
## dropped a folder's .config would hand back a folder that looks identical
## and is not, which is the listing's cosmetic choice corrupting data.
##
## Stops at the first error rather than pressing on: a copy that continues
## past a failure hands back a directory that LOOKS copied, and a partial tree
## with a loud error beats a partial tree with a green tick.
func _copy_directory(src: String, dest: String) -> int:
	var err := DirAccess.make_dir_recursive_absolute(dest)
	if err != OK:
		return err

	var dir := DirAccess.open(src)
	if dir == null:
		return DirAccess.get_open_error()
	dir.include_hidden = true

	for entry_name in dir.get_files():
		if dir.is_link(entry_name):
			_skipped_links += 1
			continue
		err = DirAccess.copy_absolute(src.path_join(entry_name), dest.path_join(entry_name))
		if err != OK:
			return err
	for entry_name in dir.get_directories():
		if dir.is_link(entry_name):
			_skipped_links += 1
			continue
		err = _copy_directory(src.path_join(entry_name), dest.path_join(entry_name))
		if err != OK:
			return err
	return OK


## Permanent recursive removal -- ONLY the tail end of a cross-filesystem cut,
## where the copy has already landed and the source is now the duplicate. The
## Delete verb never comes here: it goes to the trash or it reports, because
## "reversible" is the property that makes delete offerable on a machine
## where a thumb can slip. Links are removed AS links (remove on the link
## name), never followed into.
func _remove_recursive(path: String) -> int:
	if _is_symlink(path) or FileAccess.file_exists(path):
		return DirAccess.remove_absolute(path)

	var dir := DirAccess.open(path)
	if dir == null:
		return DirAccess.get_open_error()
	dir.include_hidden = true

	for entry_name in dir.get_files():
		var err := DirAccess.remove_absolute(path.path_join(entry_name))
		if err != OK:
			return err
	for entry_name in dir.get_directories():
		var child := path.path_join(entry_name)
		var err: int
		if dir.is_link(entry_name):
			err = DirAccess.remove_absolute(child)
		else:
			err = _remove_recursive(child)
		if err != OK:
			return err
	return DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Naming things: rename, and new folder
# ---------------------------------------------------------------------------

## The wifi screen's keyboard pattern, with the entry prefilled: renaming is
## an edit, and starting from an empty field would make every rename a full
## retype of the part being kept.
func _open_rename() -> void:
	var target_name := str(_menu_target.get("name", ""))
	if target_name.is_empty():
		return
	_open_keyboard("rename", "Rename %s" % target_name, target_name)


## The same keyboard, asked a different question. EMPTY rather than prefilled
## with "New folder": a suggested name is only a saving if it is the one you
## wanted, and clearing a 5x10 grid one backspace at a time from a sofa costs
## more than typing the name did.
func _open_new_folder() -> void:
	_open_keyboard("newfolder", "New folder in %s" % _current_path.get_file(), "")


## One keyboard, one slot, one purpose at a time. `_keyboard_purpose` is what
## the submit handler branches on; without it the two questions would need two
## signal connections onto the same node and the second would have to remember
## to disconnect the first.
func _open_keyboard(purpose: String, title: String, initial: String) -> void:
	if _keyboard != null:
		return
	_keyboard_purpose = purpose
	_keyboard = Keyboard.new()
	_keyboard.title_text = title
	# A file name is not a secret; masking it would hide the one thing the
	# screen exists to show.
	_keyboard.masked = false
	_keyboard.initial_text = initial
	_keyboard.submitted.connect(_on_name_submitted)
	_keyboard.cancelled.connect(_on_name_cancelled)
	# A child of this screen, wifi_screen's reason: closing the files screen
	# can then never leave a keyboard orphaned over the rail.
	add_child(_keyboard)
	set_process_unhandled_input(false)


func _close_keyboard() -> void:
	if _keyboard == null:
		return
	var keyboard := _keyboard
	_keyboard = null
	_keyboard_purpose = ""
	remove_child(keyboard)
	keyboard.queue_free()
	set_process_unhandled_input(true)
	_focus_row_named(_return_focus_name)


func _on_name_submitted(text: String) -> void:
	var purpose := _keyboard_purpose
	# Read BEFORE the close, which clears it.
	_close_keyboard()
	match purpose:
		"rename":
			_rename_to(text)
		"newfolder":
			_make_folder(text)
		_:
			ShellLog.error("files: a name arrived with no question attached")


func _on_name_cancelled() -> void:
	_close_keyboard()


## The rules every new name goes through, both questions sharing one gate:
## empty is not a name, and a slash is a path. Returns the cleaned name, or
## empty when it said why on the status line and there is nothing to do.
func _clean_name(text: String) -> String:
	var name := text.strip_edges()
	if name.is_empty():
		_say("A name cannot be empty", true)
		return ""
	if name.contains("/"):
		# A slash is a move wearing a costume, and the costume ends in a file
		# created somewhere the screen is not showing.
		_say("A name cannot contain /", true)
		return ""
	if name == "." or name == "..":
		# Not a name at all: mkdir refuses both, and rename would either refuse
		# or do something nobody meant.
		_say("That is not a name", true)
		return ""
	return name


## mkdir, one level, in the folder on screen. Never recursive: a name with a
## slash in it is already refused above, so there is no second component to
## create, and make_dir_recursive_absolute would silently succeed on a path
## that already existed -- which is the one answer this must not give.
func _make_folder(text: String) -> void:
	var name := _clean_name(text)
	if name.is_empty():
		return
	if _current_path.is_empty():
		return

	var path := _current_path.path_join(name)
	if _exists(path):
		_say("Something called %s is already here" % name, true)
		return

	var err := DirAccess.make_dir_absolute(path)
	if err != OK:
		_say("Could not make %s (%s)" % [name, error_string(err)], true)
		ShellLog.error("files: mkdir of %s failed (%s)" % [path, error_string(err)])
		return

	_say("Made %s" % name)
	ShellLog.info("files: created folder %s" % path)
	_return_focus_name = name
	_refresh_listing(name)


func _rename_to(text: String) -> void:
	var old_path := str(_menu_target.get("path", ""))
	var old_name := str(_menu_target.get("name", ""))
	var new_name := _clean_name(text)

	if new_name.is_empty():
		return
	if new_name == old_name:
		return

	var new_path := old_path.get_base_dir().path_join(new_name)
	if _exists(new_path):
		# Same rule as paste: never overwrite. rename_absolute would clobber
		# an existing file without a murmur.
		_say("Something called %s is already here" % new_name, true)
		return

	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		_say("Could not rename %s (%s)" % [old_name, error_string(err)], true)
		ShellLog.error("files: rename of %s to %s failed (%s)"
			% [old_path, new_path, error_string(err)])
		return

	# The clipboard may name the path that just stopped existing; follow it.
	if str(_clipboard.get("path", "")) == old_path:
		_clipboard["path"] = new_path

	_say("Renamed %s to %s" % [old_name, new_name])
	ShellLog.info("files: renamed %s to %s" % [old_path, new_path])
	_return_focus_name = new_name
	_refresh_listing(new_name)


# ---------------------------------------------------------------------------
# Delete
# ---------------------------------------------------------------------------

## OS.move_to_trash, and NOTHING ELSE on failure. The trash is the honest
## reversible delete -- freedesktop trash, recoverable from any desktop that
## mounts the drive -- and a "helpful" fallback to permanent deletion would
## mean the exact same button press destroys data or does not depending on
## conditions the person cannot see. If the trash refuses, the file stays and
## the screen says so.
func _delete_target() -> void:
	var path := str(_menu_target.get("path", ""))
	var target_name := str(_menu_target.get("name", ""))
	if path.is_empty():
		return

	var err := OS.move_to_trash(path)
	if err != OK:
		_say("Could not move %s to the wastebasket (%s)" % [target_name, error_string(err)], true)
		ShellLog.error("files: trash of %s failed (%s)" % [path, error_string(err)])
		return

	# A clipboard naming a trashed path would paste an error later; disarm it
	# now, while the connection between the two is still on screen.
	if str(_clipboard.get("path", "")) == path:
		_clipboard = {}

	_say("Moved %s to the wastebasket" % target_name)
	ShellLog.info("files: trashed %s" % path)
	_refresh_listing()


# ---------------------------------------------------------------------------
# Eject
# ---------------------------------------------------------------------------

## Ask for the drive to be unmounted. THE SHELL DOES NOT UNMOUNT: umount(2)
## needs root, the shell runs as player, and every other privileged thing this
## appliance does goes through a request file that a root service consumes --
## see media.gd and /usr/lib/marwanos/usbmount. So this writes and waits.
##
## The clipboard is disarmed first if it named anything on the drive. A paste
## after the drive is gone would fail with a message about a missing file,
## which describes the symptom rather than the thing the person just did.
func _eject_target() -> void:
	var path := str(_menu_target.get("path", ""))
	var target_name := str(_menu_target.get("name", ""))
	if path.is_empty():
		return

	var armed := str(_clipboard.get("path", ""))
	if armed == path or armed.begins_with(path + "/"):
		_clipboard = {}

	Media.request_eject(path)
	# Said now rather than when the state file changes, for the store page's
	# reason: the request is consumed within half a second, and a screen that
	# does not change for two seconds is a screen that did not hear the press.
	# The outcome arrives on _on_media_state_changed and overwrites this.
	_say("Finishing writes to %s" % target_name)


# ---------------------------------------------------------------------------
# The status line
# ---------------------------------------------------------------------------

## Every outcome, on screen and in the journal, always together: the person
## on the couch reads the line, and the person on the other end of ssh reads
## the journal, and neither should ever know more than the other.
func _say(text: String, alert: bool = false) -> void:
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color",
			TvTheme.TEXT_ALERT if alert else TvTheme.TEXT_SECONDARY)
	ShellLog.info("files: %s" % text)
