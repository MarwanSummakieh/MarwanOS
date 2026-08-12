extends Node

## ============================================================================
## THE STEAM SEAM -- the shell half of a Steam client this repository owns.
##
## It replaces steamfront, which is deleted, and the difference is not the code
## but the SUBJECT: steamfront drew Valve's shop -- a front page, prices, a
## wishlist, a buy door -- and this draws one account's owned games. ADR 0010 is
## why: a store is where money changes hands and this appliance now has no
## surface where it can, so what is left is signing in, downloading what is
## already owned, and starting it.
##
## THE SHELL STILL OPENS NO SOCKETS, and that rule is older than every feature
## it has survived: this is the wifi seam's shape a sixth time. Write one line
## into a player-owned 0700 directory, poll a state file, read result files root
## wrote. marwanos-steam owns every socket, every token and every URL; what
## crosses into this file is a name, a list of appids, a status word and
## pictures that are already on disk. There is no URL in any file this reads --
## deliberately, because a live URL in a file the renderer parses is an
## invitation for a later change to make it one that fetches.
##
## Requests are FIRE AND FORGET. There is no correlation id and no reply
## channel: the answer to "did it work" is a file changing, which the screen is
## already watching. See docs/steam-client-contract.md, which both halves are
## written against and which is what gets fixed first if the two disagree.
##
## FOUR THINGS HERE ARE SCAR TISSUE and each one is load-bearing:
##
##   * REQUESTS ARE QUEUED AND HANDED OVER ONE AT A TIME, because the seam is
##     one filename and two writes inside one of root's half-second polls
##     overwrite rather than queue. See THE REQUEST QUEUE below -- it is the
##     difference between a scan that ends on the shelf and one that ends on a
##     dead code panel.
##
##   * SIGN-IN AND DOWNLOADS ARE READ ON EVERY TICK, independently of the state
##     word. Both are narrated by jobs that are forbidden from writing the state
##     file (one writer, see the contract), so the main loop can sit on `done
##     signin` for the several minutes a person takes to find their phone while
##     signin.json rotates a fresh code every thirty seconds underneath it. A
##     consumer that waited for a state transition would draw one dead QR
##     forever.
##   * RESULTS ARE RE-READ ON ANY TRANSITION, not only on `done`, and they are
##     loaded at startup rather than waited for. The service writes the result
##     file BEFORE the state word, and a repeated request answered from cache
##     may change no byte anywhere -- so a screen waiting for a signal waits
##     forever.
##   * EVERY FILE IS COMPARED AS RAW TEXT BEFORE IT IS PARSED. Four files at
##     two-second intervals for as long as the screen is open, most of them
##     unchanged: an unchanged file has to cost one string comparison rather
##     than a JSON parse and a rebuilt view under somebody's thumb.
## ============================================================================

## Emitted when the service's state word changes. Words from the contract:
## "idle", "working", "done", "offline", "failed", plus "unknown" for a machine
## that has not written one yet -- a desk run, or too early in boot.
signal state_changed(state: String, detail: String)

## Emitted when the signed-in account changes, including to and from nobody.
## Carries the display name and NEVER the SteamID: the number is in account.json
## because the service needs it, and nothing on a television should draw it.
signal account_changed(signed_in: bool, persona: String)

## Emitted when the owned-games list changes, including to and from empty.
signal library_changed(items: Array)

## Emitted when the QR sign-in's progress file moves -- which is roughly every
## thirty seconds while a scan is live, because that is how often Valve rotates
## the code. `client_signed_in` rides along because the approved sentence
## depends on it.
signal signin_changed(status: String, persona: String, client_signed_in: bool)

## Emitted when what is downloading changes, including to and from nothing.
signal downloads_changed(items: Array)

## Matches every other seam in this shell. A download's percentage moves faster
## than this, and two seconds is fine for it: the number is being read from
## three metres away by somebody who wants to know it is still going.
const POLL_SECONDS := 2.0

## What is only true about this boot lives in /run; what survives a reboot lives
## in /var. That split is the contract's and the reason is offline: a machine
## that has been online once still draws its library after a boot with no
## network.
const STATE_FILE := "/run/marwanos/steam.state"
const DOWNLOADS_FILE := "/run/marwanos/steam.downloads.json"
const REQUEST_FILE := "/run/marwanos/steam/request"
const RESULT_DIR := "/var/marwanos/steam"

## ONE LEVER FOR ONE FEATURE, and it is deliberately not the two the seams next
## door use. MARWANOS_SHELL_STATUS_DIR redirects /run/marwanos and
## MARWANOS_SHELL_STORE_DIR redirects /var/marwanos/store, and this seam spans
## both trees -- so honouring either would leave the other half of the client
## reading paths that do not exist on a desk. Set this to a single directory and
## EVERY file this seam reads or writes lives in it under its own basename:
##
##   steam.state            the state line
##   steam.downloads.json   what is downloading
##   account.json           who is signed in
##   library.json           the owned games
##   signin.json            the QR sign-in's progress
##   qr.png                 the code itself
##   art/<appid>.jpg        one picture per game
##   steam.request          where a request LANDS, so a desk run can show what
##                          the shell asked for with no service to answer it
##
## Nothing on the appliance sets it. See scripts/xvfb-shell-verify.sh for the
## harness this exists for.
const STEAM_DIR_ENV := "MARWANOS_SHELL_STEAM_DIR"

## The request's name inside a fixture directory. It cannot keep its real
## basename there: `request` alone in a directory of results says nothing about
## which seam wrote it, and a fixture directory is read by a person.
const REQUEST_FIXTURE_NAME := "steam.request"

## Ten digits, from the contract, and validated on both sides of the seam. An
## appid is the only free value the shell ever puts in a request, so it is the
## only place a request could be made to mean something else.
const APPID_MAX := 9999999999

## ============================================================================
## THE REQUEST QUEUE, and the defect that put it here.
##
## THE SEAM HOLDS EXACTLY ONE REQUEST, because it is one filename. The service
## consumes it by rename(2) twice a second; two requests written inside the same
## half-second therefore do not queue up, they OVERWRITE -- the second rename
## lands on the first before root has looked, and the first press is gone with
## nothing anywhere to say so.
##
## That is not a theoretical race. The shell writes two back to back in the one
## place the whole feature turns on: a scan is approved, and `account` and
## `library` are asked for in the same frame. `account` is the one that loses,
## so account.json still says signed_in false, the raw comparison in
## _load_account finds nothing changed, no signal fires, and the screen sits on
## "Signed in as <name>" above a dead code panel with no games on it -- rescued
## only by leaving the screen and coming back. The same drop hits an install
## press that lands in the same half-second as the shelf's artwork re-ask, which
## is worse for being intermittent: a button that works forty-nine times out of
## fifty reads as flaky hardware rather than as a bug.
##
## THE FIX IS A QUEUE ON THIS SIDE AND NOTHING NEW ON THE WIRE. The file's
## ABSENCE is already a handshake -- the service takes a request by renaming it
## away, so a missing request file means root has finished with the last one --
## and that is enough to hand them over one at a time without inventing a
## numbered filename that both halves of the seam would have to learn at once.
## A half-landed naming convention would be a worse bug than this one.
## ============================================================================

## How many requests may be waiting. A person cannot generate this many
## meaningful presses in the seconds a handover takes, so reaching it means
## something is wrong rather than somebody being fast -- and the cap is what
## stops a stopped service turning every press for the rest of the session into
## memory nobody will ever read.
const QUEUE_MAX := 16

## How long the queue may sit unable to hand anything over before it is thrown
## away. The request file not moving means marwanos-steam is dead, masked or
## wedged; thirty seconds is far longer than the half-second poll it answers on,
## and short enough that a service coming back does not first replay a minute of
## presses somebody made while nothing was listening.
##
## DROPPING IS THE POINT, and it is deliberately not the tempting alternative of
## holding them forever: a queue that quietly stops accepting presses, or that
## floods root with stale ones when it recovers, is the same class of failure as
## the overwrite this exists to fix. It is said once in the journal, which is
## the only place the difference between "the button did nothing" and "the
## service is not running" can be read.
const QUEUE_STALL_SECONDS := 30.0

## How long after a request has gone out an identical one counts as the same
## press rather than as a new one.
##
## THE QUEUE ALONE DOES NOT DEDUPE A BURST, which is a thing this file learned by
## being driven rather than by being read: the first of three rapid A presses is
## written and popped immediately (the queue is empty, so there is nothing to
## wait for), which leaves the second one looking at an empty queue and going out
## as well. Two downloads asked for, from one thumb, on a machine where the
## button in question starts a multi-gigabyte transfer.
##
## Two seconds is one poll of this seam -- long enough to cover a person hitting
## A because a screen took half a second to answer, short enough that a
## deliberate second press (a retry after watching nothing happen) still gets
## through.
const REPEAT_SECONDS := 2.0

## The pending lines, oldest first, already flattened and stripped.
var _queue: Array = []

## The last line actually handed to root, and when, for REPEAT_SECONDS.
var _last_written := ""
var _last_written_at := 0

## When the pump first found the request path occupied with something waiting
## behind it, in engine milliseconds; 0 when nothing is stalled.
var _stalled_since := 0

## Re-entrancy guard. The pump runs from the poll tick AND from every enqueue,
## which are the same frame often enough to be worth stating: nothing in _pump
## calls back into this file today, so this is a guard against the version of
## this file that logs through something that does.
var _pumping := false

## The id prefix marwanos-appscan gives a Steam library game, and the same
## string launcher.gd keys its handoff on. Shared here because this seam asks
## the installed list whether a game is on disk -- appscan reads the
## appmanifests our own downloader writes, so there is one answer to "is it
## here" and not a second one kept in this file.
const INSTALLED_PREFIX := "steam."

var state: String = "unknown"
var detail: String = ""

## Who is signed in, from account.json. NO STEAMID IS KEPT HERE at all -- not
## private, not unused-but-present -- because a field that exists is a field a
## later screen can draw.
var account_signed_in := false
var account_persona := ""
## Whether Valve's own client has an account of its own. A web token fetches the
## library and drives DepotDownloader; the client needs its own sign-in before
## it will start a DRM'd game, and the sign-in panel says so rather than letting
## the first launch fail without explanation.
var account_client_signed_in := false

## The QR sign-in's progress, mirroring signin.json. "" until one has run.
var signin_status := ""
var signin_persona := ""
var signin_client_signed_in := false
## When the service last published a code. THE ROTATION IS THIS NUMBER MOVING:
## Valve's challenge expires about every thirty seconds and the service
## re-publishes with the same status word, so `fetched` is the only field that
## says the picture on disk is a different picture. The screen re-reads the PNG
## when it moves.
var signin_fetched := 0

## The owned games, in the order the service published them. Each is
## {"appid", "name", "installed", "playtime", "native_linux"}.
var library_entries: Array = []
## When the library was last published, for the same reason signin_fetched
## exists: a re-publish of identical content still means the service has just
## fetched another page of artwork.
var library_fetched := 0

## What is downloading, keyed by appid, mirroring steam.downloads.json's items.
var downloads: Dictionary = {}
## The appid being worked on right now, or 0. The queue's head, published by the
## service so the shell does not have to infer it from a list of states.
var downloads_active := 0

var _state_path := STATE_FILE
var _downloads_path := DOWNLOADS_FILE
var _request_path := REQUEST_FILE
var _result_dir := RESULT_DIR

var _loaded := false
var _last_account_raw := ""
var _last_library_raw := ""
var _last_signin_raw := ""
var _last_downloads_raw := ""


func _ready() -> void:
	var override := OS.get_environment(STEAM_DIR_ENV)
	if not override.is_empty():
		_state_path = override.path_join(STATE_FILE.get_file())
		_downloads_path = override.path_join(DOWNLOADS_FILE.get_file())
		_request_path = override.path_join(REQUEST_FIXTURE_NAME)
		_result_dir = override
		ShellLog.warn("steam files redirected to %s (%s is set; a desk run, never the appliance)"
			% [override, STEAM_DIR_ENV])

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)

	# EVERYTHING ON DISK IS LOADED BEFORE THE FIRST FRAME, whether or not a state
	# file exists. A machine that fetched a library last week and booted with no
	# network has a full shelf to draw and nothing to say about it yet, and a
	# screen built in that moment must render the shelf rather than "fetching".
	# This is also the half of the contract's re-read rule that a signal cannot
	# carry: a request answered from cache changes no byte, so there is no signal
	# to wait for and the answer has to be on hand already.
	_load_account()
	_load_library()
	_load_signin()
	_load_downloads()
	_poll()


# ---------------------------------------------------------------------------
# Asking
# ---------------------------------------------------------------------------

## Begin a QR sign-in, or re-publish the one already running.
##
## SAFE TO PRESS TWICE, and that is the contract's guarantee rather than this
## file's optimism: a `signin` arriving while a job is live re-publishes the
## current challenge instead of starting a second session. It is what lets the
## panel offer one button that always means something.
##
## NO CREDENTIAL CROSSES THIS SEAM. The shell's whole part is drawing a picture
## and reading status words; the approval happens on a phone and the token lands
## root-side, 0600, under a directory this process cannot read.
func request_signin() -> void:
	ShellLog.info("steam: sign-in requested")
	_enqueue(["signin"])


## Ask who is signed in. Local only -- the service answers it without opening a
## socket -- so it is cheap and correct offline.
func request_account() -> void:
	_enqueue(["account"])


## Ask for the owned-games list, and with it a bounded page of artwork.
##
## THE ART IS WHY THIS IS ASKED MORE THAN ONCE. At most twenty-four new appids
## get pictures per request (the contract's bound, so one visit cannot spend
## minutes on somebody's four-hundred-game library), and each visit reaches
## further down the list -- so a library whose tiles are still washes fills in
## over a handful of requests rather than staying half-drawn forever.
func request_library() -> void:
	_enqueue(["library"])


## Queue a download. The destination is the service's decision, not the shell's:
## /var/home/player/Games/SteamLibrary, which is also the library the client is
## granted, so a game this repository downloaded is a game the client can start.
func request_install(appid: int) -> void:
	if not _valid_appid(appid):
		return
	ShellLog.info("steam: install requested for %d" % appid)
	_enqueue(["install", str(appid)])


## Stop a running or queued download and remove what it had fetched.
func request_cancel(appid: int) -> void:
	if not _valid_appid(appid):
		return
	ShellLog.info("steam: cancel requested for %d" % appid)
	_enqueue(["cancel", str(appid)])


## Delete an installed game and its manifest.
func request_uninstall(appid: int) -> void:
	if not _valid_appid(appid):
		return
	ShellLog.info("steam: uninstall requested for %d" % appid)
	_enqueue(["uninstall", str(appid)])


## Digits only, at most ten, refused on both sides of the seam. Refused HERE as
## well as root-side for the reason every one of these pairs exists in this
## project: the side that acts does not trust the side that asks, and the side
## that asks does not send garbage it could have caught.
func _valid_appid(appid: int) -> bool:
	if appid > 0 and appid <= APPID_MAX:
		return true
	ShellLog.warn("steam: refusing a request for appid %d" % appid)
	return false


## Put one request in the queue. `<verb>` or `<verb>TAB<arg>`, flattened here
## rather than at handover so the queue holds exactly what will be written and
## the dedupe below compares the thing itself.
##
## DEDUPED ON BOTH SIDES OF THE HANDOVER, and it is the press pattern rather
## than tidiness: A on a tile is a button somebody hits three times when a
## machine takes half a second to answer, and three identical `install 620` lines
## are three downloads asked for and a service doing the same work twice for no
## reason. Already waiting is one half of that; already SENT, within
## REPEAT_SECONDS, is the other and is the half a queue does not give you for
## free. Two DIFFERENT verbs both go through -- that is the whole point of there
## being a queue.
func _enqueue(fields: Array) -> void:
	var line := ""
	for field in fields:
		if not line.is_empty():
			line += "\t"
		# Belt and braces, exactly as the wifi seam does it. This is the function
		# that turns values into a LINE, and a separator arriving inside one would
		# restructure the file the service reads -- which on a TSV read by a shell
		# is not a parse error but a silent shift of every field one place left.
		line += str(field).replace("\n", "").replace("\r", "").replace("\t", "")

	if _queue.has(line):
		return
	if line == _last_written \
			and Time.get_ticks_msec() - _last_written_at < int(REPEAT_SECONDS * 1000.0):
		return
	if _queue.size() >= QUEUE_MAX:
		# Said every time rather than once: reaching this means presses are being
		# thrown away right now, and the alternative -- a silent cap -- is the
		# defect this whole block exists to fix, wearing a smaller hat.
		ShellLog.warn("steam: %d requests already waiting; dropping \"%s\""
			% [_queue.size(), line])
		return

	_queue.append(line)
	# Immediately, so a single press on an idle machine costs nothing at all: the
	# queue only ever holds anything when root is mid-request.
	_pump()


## Hand the head of the queue over, if root is ready for it.
##
## THE ABSENCE OF THE FILE IS THE HANDSHAKE. marwanos-steam takes a request by
## rename(2)ing it aside, so a request path that still exists is one root has not
## looked at yet and writing over it would be the overwrite this queue exists to
## prevent. There is no other signal available and none is needed: the seam has
## no reply channel by design, and "the file I wrote is gone" is a fact about the
## filesystem rather than a promise from the service.
##
## ONE PER PUMP, because the seam holds one. The rest wait for the next tick,
## which is two seconds -- the same latency every other answer on this seam has.
func _pump() -> void:
	if _pumping:
		return
	if _queue.is_empty():
		_stalled_since = 0
		return

	_pumping = true
	if FileAccess.file_exists(_request_path):
		_note_stall()
		_pumping = false
		return
	_stalled_since = 0

	var line: String = _queue[0]
	_queue.remove_at(0)
	_write_request(line)
	_pumping = false


## Root has not taken a request. Tolerated for QUEUE_STALL_SECONDS and then the
## backlog is thrown away.
##
## TIMED RATHER THAN COUNTED, and the difference matters because the pump runs on
## every enqueue as well as every tick: a counter would let somebody pressing A
## quickly spend the whole allowance in a second and lose a queue that was about
## to drain. What is being measured is how long the SERVICE has been silent, so
## the clock is the honest instrument.
func _note_stall() -> void:
	var now := Time.get_ticks_msec()
	if _stalled_since == 0:
		_stalled_since = now
		return
	if now - _stalled_since < int(QUEUE_STALL_SECONDS * 1000.0):
		return
	# Once, with the count, and then the queue is empty again and accepting
	# presses. A person who presses A after this gets a fresh attempt rather than
	# a queue that has quietly stopped taking them.
	ShellLog.warn("steam: marwanos-steam has not taken a request in %.0f s; dropping %d waiting"
		% [QUEUE_STALL_SECONDS, _queue.size()])
	_queue.clear()
	_stalled_since = 0


## Put one line where root will find it.
##
## TEMP FILE, chmod, THEN rename, and every word of that order was paid for. The
## service polls twice a second and DELETES what it finds, so a poll landing
## inside Godot's truncating open() reads an empty file, discards it, and leaves
## the real write going to an unlinked inode -- a button that does nothing, with
## nothing anywhere to say why. And FileAccess uses fopen(), which does not
## chmod, so a request left to systemd's umask lands 0644 and readable by every
## other process running as `player`. The directory mode is not the whole
## protection it looks like.
##
## A FAILED WRITE DROPS THE LINE rather than putting it back at the head. The two
## ways this fails -- no directory, or a rename that will not go -- are both
## conditions the next attempt would meet identically, so retrying would be an
## error line every two seconds for as long as the shell runs, in the journal
## somebody is reading to find out what went wrong.
func _write_request(line: String) -> void:
	var temp_path := _request_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		ShellLog.error("steam: cannot write a request to %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
		return

	file.store_line(line)
	# Closed explicitly rather than left to the collector: the service is polling
	# for this file and must not be racing Godot's finalisation to read a whole
	# one.
	file.close()

	# 384 is 0600. Spelled in decimal because GDSCRIPT HAS NO OCTAL LITERAL --
	# `0o600` is a parse error that takes this entire autoload down with it,
	# which silently removes every Steam feature while the shell still starts and
	# looks perfectly fine.
	FileAccess.set_unix_permissions(temp_path, 384)

	var error := DirAccess.rename_absolute(temp_path, _request_path)
	if error != OK:
		ShellLog.error("steam: cannot place the request at %s (error %d)"
			% [_request_path, error])
		DirAccess.remove_absolute(temp_path)
		return

	# Recorded only where the line provably went out, so a failed write cannot
	# suppress the press that follows it. See REPEAT_SECONDS.
	_last_written = line
	_last_written_at = Time.get_ticks_msec()


# ---------------------------------------------------------------------------
# Listening
# ---------------------------------------------------------------------------

func _poll() -> void:
	# THE QUEUE GETS ITS CHANCE FIRST, on the tick that already exists rather
	# than on a timer of its own: the thing it waits for is root having taken the
	# last request, which is a file disappearing, and this is the function that
	# looks at files. A request enqueued while the seam was busy is handed over
	# here, two seconds later at the worst -- the same latency every answer on
	# this seam has.
	_pump()

	# EVERY RESULT FILE, ON EVERY TICK, and this replaced a dispatch on the state
	# line's detail word that was wrong in three separate ways -- one of which was
	# MEASURED breaking the feature's main path on 2026-08-12.
	#
	# The first two the contract names outright. A repeated request answered from
	# cache changes no byte of the state line, so `done account` following `done
	# account` is not a transition and never arrives; and the download worker
	# rewrites library.json (a finished game is an installed one) while being
	# FORBIDDEN to touch steam.state, so the shelf's own flags moved under a word
	# that could not report it. The third was found by driving it: a fixture whose
	# state line never moved answered an `account` request perfectly, and the
	# screen sat on the sign-in panel with the shelf behind it never appearing --
	# which is exactly what a person scanning a code would have seen.
	#
	# The cost of reading instead of dispatching is four small reads every two
	# seconds while nothing is happening. Each one is compared as raw TEXT before
	# it is parsed, so an unchanged file costs one string comparison rather than a
	# JSON parse and a rebuilt shelf under somebody's thumb -- and the largest of
	# the four is a library that would have to hold several hundred games before
	# it approached the cost of one of the JPEGs this screen decodes anyway.
	_load_account()
	_load_library()
	_load_signin()
	_load_downloads()

	var line := _read_line(_state_path)
	var word := line.get_slice("\t", 0).strip_edges()
	var rest := ""
	if line.contains("\t"):
		rest = line.substr(line.find("\t") + 1).strip_edges()
	if word.is_empty():
		word = "unknown"

	if _loaded and word == state and rest == detail:
		return
	_loaded = true
	state = word
	detail = rest
	ShellLog.info("steam state: %s%s"
		% [state, (" (%s)" % detail) if not detail.is_empty() else ""])
	# THE WORD IS NOW ONLY A NARRATION. Nothing on this seam depends on it to
	# learn that an answer landed -- the files above are the answer, and they are
	# read whether or not anything was said about them. What the word is still for
	# is the sentence a screen draws when there is nothing else to show: fetching,
	# offline, or a failure with a reason on it.
	state_changed.emit(state, detail)


## Who is signed in, from disk.
func _load_account() -> void:
	var raw := _read_file(_result_dir.path_join("account.json"))
	if raw == _last_account_raw:
		return
	_last_account_raw = raw

	var signed_in := false
	var persona := ""
	var client := false
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		signed_in = bool(parsed.get("signed_in", false))
		persona = str(parsed.get("persona", ""))
		client = bool(parsed.get("client_signed_in", false))
	elif not raw.strip_edges().is_empty():
		ShellLog.warn("steam: the stored account is not in a shape this shell knows")

	account_signed_in = signed_in
	account_persona = persona
	account_client_signed_in = client
	# WHETHER, never WHO. A display name is somebody's, and the journal on this
	# machine is read by whoever can reach it over SSH.
	ShellLog.info("steam: %s" % ("signed in" if account_signed_in else "not signed in"))
	account_changed.emit(account_signed_in, account_persona)


## The owned games, from disk.
##
## AN ITEM WITHOUT AN APPID OR A NAME IS DROPPED. One cannot be installed and the
## other cannot be read, and either way a blank tile somebody can press is worse
## than a shorter shelf -- the storefront's rule, which outlived the storefront.
func _load_library() -> void:
	var raw := _read_file(_result_dir.path_join("library.json"))
	if raw == _last_library_raw:
		return
	_last_library_raw = raw

	var found: Array = []
	var fetched := 0
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		fetched = int(parsed.get("fetched", 0))
		for item in parsed.get("items", []):
			if not (item is Dictionary):
				continue
			var appid := int(item.get("appid", 0))
			var item_name := str(item.get("name", ""))
			if appid <= 0 or item_name.is_empty():
				continue
			found.append({
				"appid": appid,
				"name": item_name,
				"installed": bool(item.get("installed", false)),
				"playtime": int(item.get("playtime", 0)),
				"native_linux": bool(item.get("native_linux", false)),
			})
	elif not raw.strip_edges().is_empty():
		ShellLog.warn("steam: the stored library is not in a shape this shell knows")

	# THE SERVICE'S ORDER IS KEPT. It is the one side that knows what "most
	# recently played" means for this account, and a shelf that re-sorted itself
	# in the shell would be a second opinion about somebody's own library.
	library_entries = found
	library_fetched = fetched
	ShellLog.info("steam: %d owned game(s)" % library_entries.size())
	library_changed.emit(library_entries)


## The QR sign-in's progress, from disk. Read on every poll -- see _poll.
func _load_signin() -> void:
	var raw := _read_file(_result_dir.path_join("signin.json"))
	if raw == _last_signin_raw:
		return
	_last_signin_raw = raw

	var status := ""
	var persona := ""
	var client := false
	var fetched := 0
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		status = str(parsed.get("status", ""))
		persona = str(parsed.get("persona", ""))
		client = bool(parsed.get("client_signed_in", false))
		fetched = int(parsed.get("fetched", 0))

	signin_status = status
	signin_persona = persona
	signin_client_signed_in = client
	signin_fetched = fetched
	# The status word and never the persona, matching every other line here.
	ShellLog.info("steam: sign-in is %s"
		% (signin_status if not signin_status.is_empty() else "not running"))
	signin_changed.emit(signin_status, signin_persona, signin_client_signed_in)


## What is downloading, from disk. Read on every poll -- see _poll.
func _load_downloads() -> void:
	var raw := _read_file(_downloads_path)
	if raw == _last_downloads_raw:
		return
	_last_downloads_raw = raw

	var found: Dictionary = {}
	var active := 0
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		active = int(parsed.get("active", 0))
		for item in parsed.get("items", []):
			if not (item is Dictionary):
				continue
			var appid := int(item.get("appid", 0))
			if appid <= 0:
				continue
			found[appid] = {
				"appid": appid,
				"name": str(item.get("name", "")),
				"state": str(item.get("state", "")),
				"percent": int(item.get("percent", 0)),
				"detail": str(item.get("detail", "")),
				"error": str(item.get("error", "")),
			}
	elif not raw.strip_edges().is_empty():
		ShellLog.warn("steam: the download list is not in a shape this shell knows")

	downloads = found
	downloads_active = active
	ShellLog.info("steam: %d download(s) in flight" % downloads.size())
	downloads_changed.emit(downloads.values())


# ---------------------------------------------------------------------------
# Answers for the screen
# ---------------------------------------------------------------------------

## The library as drawable items. A copy, so a screen cannot write back into the
## seam's own record of what the account owns.
func library_items() -> Array:
	return library_entries.duplicate()


## One game's download record, or empty. Empty is the normal answer: it is what
## every game that is not being fetched right now looks like.
func download_for(appid: int) -> Dictionary:
	return downloads.get(appid, {})


## WHAT ONE GAME'S TILE SAYS ABOUT ITSELF, as a word rather than a sentence --
## "queued", "downloading", "installing", "failed", "installed", or "" for a
## game that is simply not here. The wording is the screen's job (see
## steam_tile.gd); the STATE is the seam's, because it is assembled from three
## sources that only this file watches.
##
## THREE SOURCES, IN THIS ORDER, AND THE ORDER IS THE WHOLE FUNCTION:
##
##   1. A live download outranks everything. It is the most recent true thing
##      about the game and it is the only one that moves under a thumb.
##   2. The INSTALLED SEAM, which is marwanos-appscan reading the appmanifests
##      our own downloader writes. This is the answer the rail draws, and the
##      two must not be able to disagree -- a game that is a card on the home
##      screen and "not installed" here would be one machine describing itself
##      twice.
##   3. library.json's own `installed` flag, which is the service's claim and
##      the only source a machine with no scanner has.
func item_state(appid: int) -> String:
	var download := download_for(appid)
	if not download.is_empty():
		var word := str(download.get("state", ""))
		match word:
			"queued", "downloading", "installing", "failed":
				return word
			"done":
				return "installed"
			_:
				# A word from a newer service. Falling through rather than
				# rendering it: the tables downstream are closed vocabularies and
				# an unknown word would draw as nothing at all.
				pass

	var id := "%s%d" % [INSTALLED_PREFIX, appid]
	for app in Installed.apps:
		if str(app.get("id", "")) != id:
			continue
		var app_state := str(app.get("state", ""))
		if app_state == "installed":
			return "installed"
		# The scanner reports a manifest without StateFlags bit 4 as
		# `downloading`, which is exactly what our downloader writes while it
		# works -- so this is the same download as case 1, seen from the disk
		# rather than from the service.
		return "downloading"

	for item in library_entries:
		if int(item.get("appid", 0)) == appid and bool(item.get("installed", false)):
			return "installed"

	return ""


## The picture for a game, or empty.
##
## RESOLVED AT DRAW TIME AND NEVER CACHED. Artwork lands minutes after the JSON
## on a cold machine -- the service fetches a bounded page per request and works
## down the list over several visits -- so a path resolved once at startup would
## be empty forever on exactly the boot where the library first arrived.
func art_path(appid: int) -> String:
	if appid <= 0:
		return ""
	var path := _result_dir.path_join("art").path_join("%d.jpg" % appid)
	return path if FileAccess.file_exists(path) else ""


## The sign-in code, or empty while there is none to draw. Resolved at draw time
## for art_path's reason and one of its own: the picture is REPLACED every
## thirty seconds while a scan is live, so the interesting question is never
## "was there a file at startup".
func qr_path() -> String:
	var path := _result_dir.path_join("qr.png")
	return path if FileAccess.file_exists(path) else ""


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _read_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line()
