extends Control

## The settings page -- the first screen in the shell that is not the home rail.
##
## EVERY ROW HERE DOES SOMETHING, and that is new. This screen began read-only
## (Phase 0 had no marwand to send a change to, so it answered questions
## instead) and then grew rows that act, one at a time, each for a specific bad
## afternoon: Display and Steam for the flicker, Wi-Fi for a machine that could
## not join a network from the couch, Updates, and the devmode Terminal. By the
## fourteenth row the screen was two screens wearing one coat -- nine facts to
## scroll past to reach the five controls -- and the facts were where the
## duplicates were hiding: three rows about the picture above a Display row that
## changes it, three about the network above a Wi-Fi row that joins one.
##
## So the facts left, whole, for info_screen.gd, which merged them on the way
## (see its header). What is left is one row per thing a person can DO: four
## rows on a shipped machine and five with the devmode Terminal, where there
## were fourteen. Nothing scrolls on any panel this appliance has been run on,
## and the A hint means one thing again.
##
## THE INFO ROW WENT TOO, in the menu rewrite of 2026-08-12, and this screen is
## better for it rather than merely shorter. Info is a peer surface now with its
## own door -- the bar's status corner, the wifi glyph and the clock (see
## info.gd). This screen is the list of things you can DO; a row that does
## nothing, sitting at the top of it, was the one remaining exception to the
## sentence above, and it was also a second door onto a page that already had
## one. Every row here now changes something.
##
## NAVIGATION IS THE RAIL'S ARGUMENT ROTATED 90 DEGREES. One axis -- up and
## down are the only moves, the ends are hard stops, left and right are pointed
## at self so Control's geometric search cannot wander to the hint row. B
## closes the screen; there is no deeper level to be lost in.
##
## The screen assumes nothing about why it is on screen. Settings (the seam)
## opens it and tears it down; the home rail hides and restores itself off the
## seam's signals. This file only builds rows and emits closed.

signal closed()

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/action_row.gd")
const WifiScreen = preload("res://src/wifi_screen.gd")
const UpdateScreen = preload("res://src/update_screen.gd")
const Catalogue = preload("res://src/catalogue.gd")

var _rows: Array = []
var _scroll: ScrollContainer = null
## Typed as the SUBCLASS, not as SettingsRow: `activated` is declared on
## ActionRow, and GDScript resolves signal access against the static type --
## a SettingsRow-typed variable would fail to parse on `.activated.connect`.
var _display_row: ActionRow = null
var _window_row: ActionRow = null
var _wifi_row: ActionRow = null
var _wifi_screen: WifiScreen = null
var _updates_row: ActionRow = null
var _update_screen: UpdateScreen = null
## Built only on a devmode machine, and null everywhere else -- see the row's
## comment in _ready. Every use is guarded, like the two screens above it.
var _terminal_row: ActionRow = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = TvTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The full TV-safe inset, all four edges. Every control on this screen is
	# text or carries a focus ring; nothing here is background-class furniture
	# with the rail's licence to bleed.
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
	heading.text = "Settings"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_WORDMARK)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_PRIMARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	# THE LIST SCROLLS, AND IT HAS TO. Ten rows at SETTINGS_ROW_HEIGHT plus their
	# gaps are taller than the safe area is once the heading and the hint row
	# have taken their share, so the last rows used to sit below the bottom edge
	# -- reachable by the focus chain, which does not care about the viewport,
	# and invisible while focused. On a machine with no pointer and no scrollbar
	# to notice, that is a settings screen that silently ends early.
	#
	# follow_focus is the property that fixes it: ScrollContainer scrolls to keep
	# the focused child on screen. The explicit ensure_control_visible on each
	# row's focus_entered below is not redundant -- follow_focus acts on the
	# focus change, and the screen GRABS focus on the first row during _ready,
	# before this container has been laid out and has anything to scroll.
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)

	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", TvTheme.SETTINGS_ROW_GAP)
	# Rows span the scroll viewport's width; without this the VBox shrinks to
	# its children's minimum and the rows stop reaching the right margin.
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)

	# FIRST, AND THE SCREEN OPENS ON IT. That used to be the Info row, chosen as
	# the safe place for a first press from a cold start -- a row that reads the
	# machine rather than changing anything. Info has its own door now, so the
	# first row acts like every other one here, and the safety argument is spent
	# rather than transferred: this is the display-profile ring, which is closed
	# (press A enough times and you are back where you started) and changes
	# nothing at all until gamescope restarts. An accidental A on it is a word on
	# a row, not a television somebody was happy with going dark.
	#
	# THE ROW THAT EXISTS BECAUSE OF A HEADACHE. On 2026-08-10 the owner said
	# the screen was "so flickery it's giving me a headache", and the bench was
	# unreachable over SSH -- so the one person who could see the problem was
	# also the one person with no way to try anything. This row is that way.
	#
	# A CYCLES IN PLACE rather than opening a screen, unlike the two rows below
	# it. Cycling is the whole interaction: there are five configurations, the
	# useful thing is to step to the next one and look at the panel, and a
	# sub-screen would put a menu between somebody with a headache and the only
	# control that matters. It also keeps the ring closed -- press A enough times
	# and you are back where you started, which is the property that makes this
	# safe to hand to somebody with no manual.
	_display_row = ActionRow.new()
	_display_row.setup("Display", _display_profile_value())
	_display_row.activated.connect(_on_display_row_pressed)
	list.add_child(_display_row)
	_rows.append(_display_row)

	# THE SECOND FLICKER SWITCH, and it is a separate row because it is a
	# separate question. Display asks what the panel is being driven at; this
	# asks what the compositor thinks Steam's windows are, which is the axis the
	# 2026-08-11 report ("the moment steam runs the screen starts flickering")
	# actually lives on. One row cycling twenty-five combinations would be a
	# bisect nobody could finish; two rings of five is two afternoons at most.
	#
	# Named for the symptom rather than for the mechanism: "Steam windows" is
	# what somebody with a flickering television is looking for on this screen.
	# A person who has never read this repository cannot be expected to go
	# looking under "Compositor".
	_window_row = ActionRow.new()
	# "Steam", not "Steam windows", and the rename is a correction rather than a
	# tidy-up. The row shipped believing the flicker was Steam's WINDOWS fighting
	# the shell's for the screen; the owner's next sentence -- the screen blacks
	# and flickers the moment the WINDOWLESS background client runs -- says the
	# axis is really about what the compositor does when Steam attaches to it at
	# all. Two of the seven profiles now have nothing to do with windows.
	_window_row.setup("Steam", _window_profile_value())
	_window_row.activated.connect(_on_window_row_pressed)
	list.add_child(_window_row)
	_rows.append(_window_row)

	_wifi_row = ActionRow.new()
	_wifi_row.setup("Wi-Fi", _wifi_value())
	_wifi_row.activated.connect(_on_wifi_row_pressed)
	list.add_child(_wifi_row)
	_rows.append(_wifi_row)

	# The second row that acts. Last, because it is the one that can restart
	# the machine and should not sit under a thumb that was aiming for Wi-Fi.
	_updates_row = ActionRow.new()
	_updates_row.setup("Updates", _updates_value())
	_updates_row.activated.connect(_on_updates_row_pressed)
	list.add_child(_updates_row)
	_rows.append(_updates_row)

	# THE ROW THAT IS NOT THERE ON A SHIPPED MACHINE, and the only row on this
	# screen whose EXISTENCE is conditional rather than its value.
	#
	# A "Terminal -- not available" row would be the wrong kind of honest. Every
	# other read-only row on this screen answers a question somebody has; this
	# one would advertise a door and then refuse to open it, on a machine whose
	# entire thesis is that the door is not there. Absent is the truth. On a
	# devmode machine the flag is set and the row appears, which is the same
	# switch sshd and the tty2 getty are on -- see catalogue.gd's terminal block
	# and ADR 0009.
	#
	# LAST, and by a wider margin than Updates earned. Updates is here rather
	# than mid-list because it can restart the machine; this one hands over the
	# whole machine, so it sits below the row somebody's thumb might overshoot
	# onto, not above it.
	if Catalogue.devmode():
		_terminal_row = ActionRow.new()
		_terminal_row.setup("Terminal", "Opens a shell -- press A")
		_terminal_row.activated.connect(_on_terminal_row_pressed)
		list.add_child(_terminal_row)
		_rows.append(_terminal_row)

	# The spacer that used to take the slack here is gone: the scroll container
	# above is the expanding child now, which is what keeps the hint row pinned
	# to the bottom of the safe area instead of riding up under a short list.
	column.add_child(_build_hints())

	_wire_focus_neighbours()

	# The rail's lesson holds here too: nothing navigates until something is
	# focused. The screen opens with the first row lit rather than with a page
	# the pad cannot reach into.
	if not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()

	# NO PlayerOne CONNECTS HERE ANY MORE: the Controller row went to the Info
	# page and took its own subscriptions with it. The network seams stay,
	# because the Wi-Fi row's value is a live description of the network and not
	# just a label on a door.
	SystemStatus.network_changed.connect(_on_network_changed)
	SystemStatus.network_info_changed.connect(_on_network_info_changed)
	# The Wi-Fi row's value tracks the seam too, so joining a network updates
	# the row behind the screen that joined it.
	Wifi.state_changed.connect(_on_wifi_state_changed)
	# The Display row tracks its seam for the same reason the network rows track
	# theirs: the answer is root's to give, and a row that only updated on its
	# own press would keep showing an optimistic guess after a refusal.
	DisplayProfile.state_changed.connect(_on_display_state_changed)
	WindowProfile.state_changed.connect(_on_window_state_changed)
	# OUT OF THE WAY WHILE A LAUNCH IS UP -- the stores and files screens' rule,
	# arriving here for the same reason they have it: this screen can now start
	# something. Their version goes deaf; this one HIDES, and the difference is
	# what the two screens are made of. Those two read input themselves, so
	# turning the readers off is enough. Every control here is a focusable
	# Button driven through the viewport's GUI focus, and the shell keeps
	# receiving pad input while another client owns the screen (see pad_keys.gd)
	# -- so a deaf-but-visible settings screen would still walk its own focus
	# ring under a running terminal, and an A meant for the shell prompt would
	# also press whatever row the ring had landed on. Hiding drops the focus
	# with the visibility, which is exactly the state this screen should be in
	# while it is not on screen.
	#
	# AND IT IS NOT ONLY ABOUT INPUT. Pressing home over a running application
	# makes the shell's whole window transparent (Kiosk.set_overlay -- that is
	# how the app menu shows the application through itself), so a settings
	# screen left VISIBLE behind a launch would paint its opaque background over
	# the terminal the menu is supposed to be floating on top of.
	Launcher.launch_started.connect(_on_launch_started)
	Launcher.launch_finished.connect(_on_launch_finished)

	ShellLog.info("settings screen up with %d rows" % _rows.size())


## Keep the focused row on screen. Deferred because the first call arrives from
## the grab_focus in _ready, before the scroll container has been laid out --
## asking an unsized viewport to reveal a control scrolls it nowhere, which is
## exactly the bug this whole seam exists to fix.
func _on_row_focused(row: Control) -> void:
	if _scroll == null:
		return
	_scroll.ensure_control_visible.call_deferred(row)


## The shared one-axis table (TvTheme.wire_column), plus the scroll-follow
## connect that is this screen's own. Kept as a named function rather than
## inlined at the call site because the focus_entered connect has to happen for
## every row in one place -- the rows are built in several spots and a per-site
## connect would be several chances to add a row that scrolls off the bottom.
func _wire_focus_neighbours() -> void:
	TvTheme.wire_column(_rows)
	for row in _rows:
		row.focus_entered.connect(_on_row_focused.bind(row))


func _build_hints() -> Control:
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("separation", TvTheme.HINT_GAP)
	# "Select", still, and now it is true of every row rather than most of them:
	# Wi-Fi and Updates open a page, Display and Steam step to the next value in
	# place, Terminal launches. Nothing here answers A with a log line saying it
	# is read-only any more, because nothing here is.
	hints.add_child(TvTheme.hint("A", "Select"))
	hints.add_child(TvTheme.hint("B", "Back"))
	return hints


# ---------------------------------------------------------------------------
# Values
# ---------------------------------------------------------------------------
#
# THE READ-ONLY ONES ARE NOT HERE ANY MORE. System, Engine, Display server,
# Surface, Renderer, Controller, Network, Connection and Address moved to
# info_screen.gd whole -- and Surface merged into Display server and Connection
# into Network on the way, which is why looking for those two by name here or
# there finds one row rather than two. Every value below belongs to a row that
# acts.


## What a wifi SETTINGS row can honestly say in Phase 0: the network's name
## when wifi carries the link, and otherwise where the credentials actually
## live. Joining a network from the couch needs an on-screen keyboard and a
## write path to NetworkManager -- both marwand, both Phase 1.
## The row's value doubles as its affordance: it says what the Wi-Fi situation
## is, and pressing A opens the screen that can change it.
func _wifi_value() -> String:
	match Wifi.state:
		"no-device":
			return "No adapter -- press A"
		"rf-killed":
			return "Switched off in hardware -- press A"
		"connected":
			return Wifi.detail if not Wifi.detail.is_empty() else "Connected"
		_:
			var info := SystemStatus.network_info
			if info.get_slice(" ", 0) == "wifi":
				return info.substr("wifi".length()).strip_edges()
			return "Set up a network -- press A"


## What display configuration is on screen, and what pressing A will do about it.
##
## THE VALUE ALWAYS CARRIES THE RESTART, in both states, and that is deliberate
## rather than repetitive. A profile changes nothing until gamescope is started
## again, so somebody who presses A, looks at the panel, sees the same flicker
## and concludes the setting does not work would be exactly wrong -- and would
## stop, on the one screen that could have fixed their headache. The word
## "restart" is on the row before they press anything and after.
func _display_profile_value() -> String:
	# Not `name`: this script extends Control, and a local called `name` shadows
	# Node.name. Same rule the row builders follow with name_text.
	#
	# chosen_profile(), not current_profile(): the row must name what the person
	# picked from the moment they picked it. Drawing what is on disk instead would
	# have the row jump backwards through profiles while a fast sequence of
	# presses works its way through root, one poll at a time.
	var profile_name := DisplayProfile.label_for(DisplayProfile.chosen_profile())
	if DisplayProfile.state == "refused":
		# The service did not recognise what it was sent, so the machine is still
		# running whatever it was running. Said plainly: the row must never name a
		# profile the session is not using.
		return "%s -- not changed, press A to try again" % profile_name
	if DisplayProfile.is_pending():
		return "%s -- restart to apply" % profile_name
	return "%s -- A changes it, restart applies" % profile_name


## Step to the next profile and say so on the row immediately.
##
## Optimistic, and see Display.request_next for why: the consumer polls twice a
## second, and a button that looks dead for two seconds on the screen somebody
## opened because their display is misbehaving reads as a second fault. The next
## poll overwrites this with whatever actually happened.
func _on_display_row_pressed() -> void:
	var want := DisplayProfile.request_next()
	if _display_row != null:
		_display_row.set_value(_display_profile_value())
	ShellLog.info("display row: cycled to \"%s\"" % want)


func _on_display_state_changed(_state: String, _profile: String) -> void:
	if _display_row != null:
		_display_row.set_value(_display_profile_value())


## What window configuration is on screen, and what pressing A will do about it.
##
## THE PENDING CASE IS BROADER HERE than on the Display row, and deliberately.
## WindowProfile.is_pending() is also true when the file and the RUNNING session
## simply disagree -- somebody who pressed A last night and never restarted is in
## that state with nothing outstanding at the seam. On the display axis that
## situation is invisible because nothing keys off it; on this one `yield` is a
## word the shell itself acts on, so "chosen" and "in force" being different is a
## fact the row has to keep saying out loud rather than a transient.
func _window_profile_value() -> String:
	var profile_name := WindowProfile.label_for(WindowProfile.chosen_profile())
	if WindowProfile.state == "refused":
		return "%s -- not changed, press A to try again" % profile_name
	if WindowProfile.is_pending():
		return "%s -- restart to apply" % profile_name
	return "%s -- A changes it, restart applies" % profile_name


## Step to the next window profile and say so on the row immediately, for the
## Display row's reason verbatim: the consumer polls twice a second and a button
## that looks dead reads as a second fault.
func _on_window_row_pressed() -> void:
	var want := WindowProfile.request_next()
	if _window_row != null:
		_window_row.set_value(_window_profile_value())
	ShellLog.info("window row: cycled to \"%s\"" % want)


func _on_window_state_changed(_state: String, _profile: String) -> void:
	if _window_row != null:
		_window_row.set_value(_window_profile_value())


## Opens the Wi-Fi screen as a child of this one. A child rather than a third
## seam: it is a page WITHIN settings, it returns here when it closes, and the
## home rail underneath must keep seeing exactly one surface come and go.
func _on_wifi_row_pressed() -> void:
	if _wifi_screen != null:
		return
	_wifi_screen = WifiScreen.new()
	_wifi_screen.closed.connect(_on_wifi_screen_closed)
	add_child(_wifi_screen)
	# Deaf while it is up, so one B press does not close both screens.
	set_process_unhandled_input(false)
	ShellLog.info("wifi screen opened from settings")


func _updates_value() -> String:
	match Updates.state:
		"available":
			return "Update available -- press A"
		"staged":
			return "Restart to finish"
		"applying", "checking":
			return "Working"
		"failed":
			return "Last attempt failed"
		_:
			return "Check for updates"


func _on_updates_row_pressed() -> void:
	if _update_screen != null:
		return
	_update_screen = UpdateScreen.new()
	_update_screen.closed.connect(_on_update_screen_closed)
	add_child(_update_screen)
	set_process_unhandled_input(false)
	ShellLog.info("update screen opened from settings")


## Open the terminal. The one row on this screen that goes through the LAUNCH
## seam rather than a settings seam, and it uses it exactly as the rail and the
## stores screen do: build an entry, hand it to Launcher, and let the seam own
## everything after that -- the splash, the pad bridge, the app menu's Type and
## Close, and putting this screen back when it exits.
##
## The busy guard is the stores screen's: a second press while something is
## already up is a bounced button. Launcher.launch refuses anyway; saying so in
## the journal is what makes an unexpectedly missing terminal readable later.
func _on_terminal_row_pressed() -> void:
	if Launcher.is_busy():
		ShellLog.info("terminal row: something is already running; ignoring")
		return
	# A failure to spawn is the launch seam's to report and to recover from --
	# it logs "could not start" and hands the screen straight back, which on a
	# machine where /usr/lib/marwanos/terminal is missing or the wrapper refuses
	# (no devmode flag on the ROOT side) is the whole failure path.
	Launcher.launch(Catalogue.terminal_entry())


## Off the screen for as long as something is running on it. See the connect in
## _ready for why this hides rather than going deaf.
func _on_launch_started(_entry: Dictionary) -> void:
	hide()
	# BOTH HALVES, and the second one is the half a hide does not cover: input
	# callbacks are not gated on a Control's visibility, so an invisible screen
	# still hears every button. B is the press that proves it -- the pad bridge
	# sends B to the terminal as BackSpace, and this screen's _unhandled_input
	# reads the same press as "close settings", which would tear the screen down
	# underneath a running application and hand the rail back over the top of it.
	set_process_unhandled_input(false)


func _on_launch_finished(_entry: Dictionary) -> void:
	show()
	# Not while a sub-screen is up: one of those owns B, and this is the wifi
	# screen's guard said the other way round. A launch cannot be started from
	# under one today -- the row is unreachable while a child screen holds focus
	# -- so this is a guard against a future arrangement rather than a live case.
	if _wifi_screen == null and _update_screen == null:
		set_process_unhandled_input(true)
	# Nothing is focused after a hide, and a settings screen with no focus owner
	# is a settings screen the pad cannot move -- the rail's _ensure_focus
	# lesson, in the one place on this screen where focus can be lost without a
	# button having been pressed. Back onto the row that started it, which is
	# where the person who just closed a terminal is looking.
	if _terminal_row != null:
		_terminal_row.grab_focus()
	elif not _rows.is_empty():
		var first: Control = _rows[0]
		first.grab_focus()


func _on_update_screen_closed() -> void:
	_close_update_screen.call_deferred()


func _close_update_screen() -> void:
	if _update_screen == null:
		return
	var screen := _update_screen
	_update_screen = null
	remove_child(screen)
	screen.queue_free()
	set_process_unhandled_input(true)
	if _updates_row != null:
		_updates_row.set_value(_updates_value())
		_updates_row.grab_focus()
	ShellLog.info("update screen closed")


func _on_wifi_screen_closed() -> void:
	_close_wifi_screen.call_deferred()


func _close_wifi_screen() -> void:
	if _wifi_screen == null:
		return
	var screen := _wifi_screen
	_wifi_screen = null
	remove_child(screen)
	screen.queue_free()
	set_process_unhandled_input(true)
	_refresh_network_rows()
	if _wifi_row != null:
		_wifi_row.grab_focus()
	ShellLog.info("wifi screen closed")


## ONE ROW LEFT TO REFRESH, where there were four. The Network, Connection and
## Address rows now live on the Info page and track the same seams from there;
## what remains here is the Wi-Fi row, whose value doubles as its affordance and
## therefore has to follow the network as closely as it ever did.
func _refresh_network_rows() -> void:
	if _wifi_row != null:
		_wifi_row.set_value(_wifi_value())


func _on_network_changed(_state: String) -> void:
	_refresh_network_rows()


func _on_network_info_changed(_info: String) -> void:
	_refresh_network_rows()


func _on_wifi_state_changed(_state: String, _detail: String) -> void:
	_refresh_network_rows()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consumed so the home rail underneath -- hidden until the seam restores it
	# -- never sees the same press as a second back-out.
	get_viewport().set_input_as_handled()
	closed.emit()
