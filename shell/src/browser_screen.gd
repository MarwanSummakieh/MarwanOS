extends Control

## THE BROWSER. Not a browser the shell launches -- a browser the shell IS.
##
## Everything on this screen except the page itself is drawn here, in this
## project's theme, by this project's code: the cursor, the status line, the
## hint row, the error sentence. The page is a MowserView, which is Chromium's
## engine rendering off-screen into a texture (see mowser/src/mowser.h). That
## division is the whole point of the owner's ask -- "my own custom made
## chromium that is only the engine inside my launcher" -- and it is why there
## is no address bar here unless this file draws one, no tab strip unless this
## file draws one, and no settings page at all.
##
## WHAT REPLACED WHAT. Zen was a browser with a UI nobody could drive with a
## pad. The Chromium flatpak that replaced it for a day was the same problem
## with the UI hidden rather than absent -- kiosk mode is a flag on somebody
## else's application, one changed default away from a window this machine
## cannot dismiss. This is the third and last answer: the engine is a library,
## and the browser is ours.
##
## THE PAD DRIVES THE PAGE BY METHOD CALL. pad_keys.gd exists because the shell
## could not reach inside a foreign X client, so it spawns an xdotool process
## per event and aims it at whatever gamescope focused. None of that applies to
## a page inside this process: the stick moves a cursor this screen owns, and A
## is one call into the engine at a coordinate in this control's own space. No
## processes, no injection, no guessing which window has focus.
##
## NAVIGATION, and it is the settings list's argument adapted to a surface that
## has no rows: there is nothing focusable on this screen at all. The page is
## not a Control tree the engine's focus can walk, so B is not "up one level" --
## it is the page's own history, and only when the history is empty does it
## close the screen. That is the one place this shell lets a button mean two
## things, and it is what a person expects from a back button in a browser.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const Keyboard = preload("res://src/keyboard.gd")

## Cursor speed and response, lifted verbatim from pad_keys.gd's pointer
## dialect -- the same stick doing the same job should feel identical whether
## the thing under it is a page in this shell or an application beside it.
const POINTER_SPEED := 900.0
const POINTER_CURVE := 2.0

## How far one shoulder press scrolls. CEF takes wheel deltas in pixels, and
## this is about a third of a screen -- a reading step rather than a nudge.
const SCROLL_STEP := 320.0

## Repeat cadence for a held shoulder, matching the pad bridge's own.
const SCROLL_INTERVAL := 0.1

## The cursor this screen draws, because the engine deliberately draws none.
## A ring rather than an arrow: an arrow has a hotspot a person has to learn,
## and on a television at three metres the thing that matters is being able to
## FIND it against arbitrary page content -- so it is a light ring with a dark
## outline, which survives being over white text and over a black hero image.
const CURSOR_RADIUS := 11.0
const CURSOR_OUTLINE := 3.0

## What the status line says while the engine works. The page cannot be trusted
## to explain itself -- a site that hangs shows nothing at all -- so this line
## is the shell's own account of what it asked for and what came back.
const STATUS_LOADING := "Loading"
const STATUS_READY := ""

var _view: Control = null
var _status: Label = null
var _hints: HBoxContainer = null
var _cursor_layer: Control = null
var _keyboard: Keyboard = null

var _scroll_dir := 0
var _scroll_clock := 0.0

## Where this screen was opened FROM, for the one sentence the status line shows
## before anything has loaded. Set by the caller through open_url.
var _opening_title := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# THE PAGE GETS THE SCREEN, EDGE TO EDGE, and this is the one surface in the
	# shell that does not take the TV-safe inset. A web page is somebody else's
	# layout: insetting it would letterbox every site behind a border while the
	# page's own margins are already inside that, and a checkout's Pay button
	# sitting under a black bar is the failure this whole route exists to avoid.
	# The shell's own furniture below KEEPS the inset, so nothing this file
	# draws lands in the overscan.
	_view = _build_view()
	add_child(_view)
	# THE PRESET IS RE-APPLIED AFTER PARENTING, and it is not superstition.
	# Anchors set on a Control that has no parent yet have nothing to resolve
	# against, so the view can end up in the tree at zero size -- which the
	# engine never notices (it is told a size through GetViewRect and paints
	# happily at the fallback) and which draws as nothing at all. Cheap, and it
	# removes a whole class of "the page is black" from this screen.
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The cursor and the chrome ride above the page, in their own layer, so the
	# page cannot paint over them.
	_cursor_layer = Control.new()
	_cursor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.draw.connect(_draw_cursor)
	add_child(_cursor_layer)

	add_child(_build_chrome())

	set_process(true)
	set_process_unhandled_input(true)
	ShellLog.info("browser screen up")


## The engine, or the honest sentence when there is none.
##
## MowserView is a GDExtension class, so a build whose image is missing
## libmowser.so does not merely fail to browse -- the class does not exist and
## naming it is a script error. That is checked rather than assumed: the shell
## must still come up on a machine whose browser payload did not land, exactly
## as it comes up with no network and no Steam.
func _build_view() -> Control:
	if not ClassDB.class_exists("MowserView"):
		ShellLog.error("MowserView is not registered -- the browser engine is not in this image")
		return _build_engine_missing("the browser is not installed in this image")

	var view: Control = ClassDB.instantiate("MowserView")
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.page_started.connect(_on_page_started)
	view.page_finished.connect(_on_page_finished)
	view.page_failed.connect(_on_page_failed)
	view.title_changed.connect(_on_title_changed)
	return view


## A page-shaped panel saying why there is no page. Same first-class-render rule
## the storefront grid follows: every state draws something that explains
## itself, and a black rectangle explains nothing.
func _build_engine_missing(reason: String) -> Control:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", TvTheme.card_idle_box())
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = "The browser cannot open -- %s." % reason
	label.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


## The shell's own furniture: a status line and the hint row, both inside the
## TV-safe inset even though the page above them is not.
func _build_chrome() -> Control:
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_theme_constant_override("margin_left", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_right", TvTheme.SAFE_MARGIN_X)
	safe.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	safe.add_theme_constant_override("margin_bottom", TvTheme.SAFE_MARGIN_Y)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(column)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	_status.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	column.add_child(_hints)
	_refresh_hints()

	return safe


## THE HINT ROW SAYS WHAT B DOES RIGHT NOW, and it changes, because B does two
## things: the page's history while there is any, and closing this screen when
## there is not. Advertising one word for both would make the button a surprise
## exactly once per visit -- which is the visit where somebody loses a checkout.
func _refresh_hints() -> void:
	if _hints == null:
		return
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()
	_hints.add_child(TvTheme.hint("A", "Click"))
	_hints.add_child(TvTheme.hint("Y", "Type"))
	_hints.add_child(TvTheme.hint("L1/R1", "Scroll"))
	_hints.add_child(TvTheme.hint("B", "Back" if _can_go_back() else "Close"))


func _can_go_back() -> bool:
	return _view != null and _view.has_method("can_go_back") and _view.can_go_back()


## Open a URL, with a human name for it to show while it loads. The name is the
## caller's -- the store knows the game's title long before the page does -- and
## a status line that said the raw URL would be showing somebody a query string
## on a television.
func open_url(url: String, title: String = "") -> void:
	_opening_title = title
	# AN EMPTY URL IS A CALLER BUG AND MUST SAY SO. Handed one, the engine
	# stays on about:blank and renders a blank page -- indistinguishable from a
	# page that failed to load, which is exactly how a broken file_url() hid
	# behind a log line that only ever printed the title.
	if url.is_empty():
		ShellLog.error("browser asked to open an empty URL; nothing to show")
		if _status != null:
			_status.text = "There is nothing to open here"
			_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
		return
	if _view != null and _view.has_method("load_url"):
		_view.load_url(url)
	_refresh_status()
	# THE URL, not just the title. The title is what a person reads; the URL is
	# what the machine was actually told to do, and they are only the same when
	# nothing has gone wrong.
	ShellLog.info("browser opening %s%s"
		% [url, "" if title.is_empty() else " for %s" % title])


func _refresh_status() -> void:
	if _status == null:
		return
	if _view == null or not _view.has_method("is_loading"):
		_status.text = ""
		return
	if _view.is_loading():
		_status.text = "%s -- %s" % [STATUS_LOADING, _opening_title] \
			if not _opening_title.is_empty() else STATUS_LOADING
		_status.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
		return
	# ONCE A PAGE IS UP THE LINE GOES QUIET. The page is its own title, drawn at
	# full size by the site itself, and a shell caption repeating it would be
	# the storefront's "caption on a photograph of itself" all over again.
	_status.text = STATUS_READY


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## The stick, polled rather than evented, for pad_keys.gd's reason: a stick held
## at half tilt produces no further events, and a cursor that only moves when
## somebody wiggles it is a broken mouse.
func _process(delta: float) -> void:
	if _view == null or not _view.has_method("move_pointer"):
		return

	var dx := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	var dy := Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	var tilt := Vector2(dx, dy)
	if tilt.length() > 1.0:
		tilt = tilt.normalized()
	if tilt.length() > 0.0:
		# Squared response: a slow edge without costing the fast middle, the
		# same curve the pad bridge uses.
		var step: Vector2 = tilt * pow(tilt.length(), POINTER_CURVE - 1.0) * POINTER_SPEED * delta
		_view.move_pointer(step)
		if _cursor_layer != null:
			_cursor_layer.queue_redraw()

	if _scroll_dir != 0:
		_scroll_clock += delta
		if _scroll_clock >= SCROLL_INTERVAL:
			_scroll_clock = 0.0
			_view.scroll(Vector2(0, SCROLL_STEP * _scroll_dir))


func _unhandled_input(event: InputEvent) -> void:
	if _keyboard != null:
		return

	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_click(true)
		return
	if event.is_action_released("ui_accept"):
		get_viewport().set_input_as_handled()
		_click(false)
		return

	if event.is_action_pressed("ui_shell_y"):
		get_viewport().set_input_as_handled()
		_open_keyboard()
		return

	# The shoulders scroll, and they arrive as raw buttons because the shell's
	# nine actions deliberately do not cover them -- pad_keys.gd's own note.
	if event is InputEventJoypadButton:
		var direction := 0
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			direction = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			direction = 1
		if direction != 0:
			get_viewport().set_input_as_handled()
			if event.pressed:
				_scroll_dir = direction
				_scroll_clock = 0.0
				if _view != null and _view.has_method("scroll"):
					_view.scroll(Vector2(0, SCROLL_STEP * direction))
			elif _scroll_dir == direction:
				_scroll_dir = 0
			return

	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# B IS THE PAGE'S HISTORY FIRST. See the header: this is the one button in
	# the shell that means two things, because a back button that closed the
	# browser from three pages deep would be the wrong one every time.
	if _can_go_back():
		_view.go_back()
		_refresh_hints()
		ShellLog.info("browser went back")
		return
	closed.emit()


func _click(pressed: bool) -> void:
	if _view != null and _view.has_method("click"):
		_view.click(1, pressed)
	if not pressed:
		# A click is the most likely thing to have started a navigation, so the
		# hint row's B word is re-derived on the release rather than waiting for
		# a load to report.
		_refresh_hints()


## The cursor, drawn by the shell over the page. See CURSOR_RADIUS for why it is
## a ring: this has to be findable over arbitrary content nobody here chose.
func _draw_cursor() -> void:
	if _view == null or not _view.has_method("get_pointer"):
		return
	var at: Vector2 = _view.get_pointer() + _view.position
	_cursor_layer.draw_circle(at, CURSOR_RADIUS + CURSOR_OUTLINE, Color(0, 0, 0, 0.65))
	_cursor_layer.draw_circle(at, CURSOR_RADIUS, TvTheme.TEXT_PRIMARY)


# ---------------------------------------------------------------------------
# Typing
# ---------------------------------------------------------------------------

## Y opens the shell's own keyboard and its result is typed into whatever the
## page has focused.
##
## THE SAME HONEST LIMIT THE APP MENU'S "Type" HAS, and for the same reason
## stated in app_overlay.gd: nothing here can know that a text field just took
## focus inside a page. There is no signal for it that this screen subscribes
## to, so the trigger is manual -- point at the field, press A to focus it,
## press Y, write, done. What is different from the app menu's version is that
## the characters do not go through XTEST into whatever window happens to be
## focused: they are a method call into this page.
func _open_keyboard() -> void:
	if _keyboard != null or _view == null or not _view.has_method("type_text"):
		return
	_keyboard = Keyboard.new()
	_keyboard.title_text = "Type"
	_keyboard.masked = false
	_keyboard.submitted.connect(_on_typed)
	_keyboard.cancelled.connect(_close_keyboard)
	add_child(_keyboard)
	# Deaf while it is up, for the stores screen's reason: the keyboard owns B
	# and both reacting would close the keyboard and this screen on one press.
	set_process_unhandled_input(false)


func _on_typed(text: String) -> void:
	_close_keyboard()
	if text.is_empty():
		return
	_view.type_text(text)
	# Return after the text, because a search box that has been filled and not
	# submitted is a person pressing Y again wondering what happened.
	_view.send_editing_key("Return")
	ShellLog.info("browser typed %d character(s) into the page" % text.length())


func _close_keyboard() -> void:
	if _keyboard == null:
		return
	var keyboard := _keyboard
	_keyboard = null
	remove_child(keyboard)
	keyboard.queue_free()
	set_process_unhandled_input(true)


# ---------------------------------------------------------------------------
# Engine callbacks
# ---------------------------------------------------------------------------

func _on_page_started(_url: String) -> void:
	_refresh_status()
	_refresh_hints()


func _on_page_finished(_url: String, http_status: int) -> void:
	_refresh_status()
	_refresh_hints()
	ShellLog.info("browser page finished with status %d" % http_status)


## A LOAD FAILURE IS THIS SCREEN'S TO RENDER, not the engine's. Chromium has its
## own error pages and they are somebody else's design, in somebody else's
## typeface, telling a person on a sofa to check their proxy settings. The
## status line says what happened in this shell's own words instead.
func _on_page_failed(_url: String, reason: String) -> void:
	if _status != null:
		_status.text = "That page did not open -- %s" % reason
		_status.add_theme_color_override("font_color", TvTheme.TEXT_ALERT)
	_refresh_hints()
	ShellLog.warn("browser page failed: %s" % reason)


func _on_title_changed(title: String) -> void:
	# Kept for the status line's loading sentence, which prefers the caller's
	# name but falls back to the page's own once it has one.
	if _opening_title.is_empty():
		_opening_title = title
