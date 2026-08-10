extends RefCounted

## What a game IS, assembled the way Playnite assembles it.
##
## THE PROCESS BEING COPIED, in Playnite's own terms. When Playnite adds a game
## it does not ask one provider for a record and use it. It holds a table of
## FIELDS -- name, description, genres, developers, release date, score -- and
## each field carries its OWN ordered list of sources. The downloader walks the
## table field by field, asks each source in that field's order, takes the first
## answer that is not empty, and stops. A field already answered is never asked
## about again. The result is a single record whose fields may have come from
## three different places, and whose consumer never learns which.
##
## THE ORDER IS PER FIELD, NOT PER SOURCE, and that is the part worth copying
## rather than the provider list. A per-source order means picking one winner
## and inheriting everything it is bad at; Playnite's arrangement lets the store
## own the description it wrote and lets the local record own the title the rail
## is already showing. FIELDS below is that table, and it is the whole design --
## everything under it is plumbing.
##
## WHY THIS IS A RESOLVER AND NOT A DOWNLOADER. Playnite's version runs on a
## timer, hits the network and writes a library database. Half of that already
## exists here and belongs to somebody else: marwanos-storeart does the
## fetching, and the shell opens no sockets (see gameart.gd and steamfront.gd
## for the same rule stated twice more). What was missing was never the fetch,
## it was the ASSEMBLY -- one place that knows a game has a developer and a
## release date and where each of those comes from. So this is the second half
## of Playnite's downloader with the network cut out of the middle: the sources
## are files that are already on the disk, and asking all of them costs one
## JSON parse.
##
## RESOLVED AT THE MOMENT IT IS SHOWN, for catalogue.gd's steam_meta reason and
## in the same breath: there is exactly one consumer and it is a button press.
## The details panel opens for one game and asks about one game. A resolver that
## kept a warm table of every installed game's metadata would be maintaining an
## answer nobody is looking at, and would have to be invalidated when storeart
## lands a file -- which is a cache with an invalidation story, the thing this
## project keeps declining to build.
##
## ART IS NOT IN THE TABLE, and its absence is deliberate rather than an
## oversight. A game's three pictures already have a resolver with the same
## shape -- GameArt, joining gameart.tsv by id, portrait-then-header-then-hero
## -- and tile.gd and shell_root read it directly. Putting cover and background
## in this table as well would create two files that both answer "what picture
## goes behind this game", and the first time one of them learned something the
## other did not they would disagree on the TV with nothing to say which was
## right. Text here, pictures there.
##
## Phase 1 note: when marwand owns metadata over RPC, this table survives and
## its sources change. A field that today has one source gets marwand's answer
## in front of Steam's, which is one line per field -- which is the reason the
## order is data rather than a chain of `if not x.is_empty()` in the panel.

const Catalogue = preload("res://src/catalogue.gd")

## Same prefix, same meaning as tile.gd's, shell_root's and details_panel's.
const STEAM_PREFIX := "steam."

## THE SOURCES. Named rather than inlined because a name appears twice -- in
## FIELDS as a priority and in _ask as a branch -- and a typo between two string
## literals is a field that silently never resolves.
##
## Steam's cached appdetails document, written by marwanos-storeart. The only
## source here that knows anything a human did not type into this repo, and the
## only one that can answer a question about a game nobody anticipated.
const SOURCE_STEAM := "steam-store"

## Catalogue.AVAILABLE_APPS, the hand-written shelf. One line per shipped
## flatpak, and the only description this project has ever had for Kodi or a
## browser -- neither of which has a Steam store page to fall back on.
const SOURCE_CATALOGUE := "catalogue"

## The apps.tsv record itself: what marwanos-appscan read off the disk. Authoritative
## about the title (it is what the rail is already drawing) and last about
## everything else.
const SOURCE_RECORD := "record"

## THE TABLE. Read it as "this field, from the first of these that answers".
##
## `name` PUTS THE RECORD FIRST and it is the only field that does. The rail has
## already drawn this title, the panel slides up over the rail, and a panel that
## renames the thing the person was just looking at is a bug that looks like a
## different game. Steam's `name` is the fallback for the day appscan reads a
## manifest whose name field is empty.
##
## `description` IS THE OLD THREE-TIER CHAIN, MOVED. details_panel._description
## walked exactly these three sources in exactly this order; it now asks here,
## and the journal line it used to write is written from the sources map below.
## Nothing about that field's behaviour changed -- it was the proof that the
## per-field chain is the right shape, so it became the first row of the table.
##
## EVERY OTHER FIELD HAS ONE SOURCE TODAY, and that is a statement about this
## machine rather than about the design. Nothing in this repo knows a game's
## publisher except Valve. Those rows are one-element lists rather than direct
## reads so that adding a second source is an edit to this table and to nothing
## else.
const FIELDS := [
	{"key": "name", "sources": [SOURCE_RECORD, SOURCE_STEAM]},
	{"key": "description", "sources": [SOURCE_STEAM, SOURCE_CATALOGUE, SOURCE_RECORD]},
	{"key": "genres", "sources": [SOURCE_STEAM]},
	{"key": "developers", "sources": [SOURCE_STEAM]},
	{"key": "publishers", "sources": [SOURCE_STEAM]},
	{"key": "release_date", "sources": [SOURCE_STEAM]},
	{"key": "critic_score", "sources": [SOURCE_STEAM]},
	{"key": "features", "sources": [SOURCE_STEAM]},
]


## The merged record for an entry: every field in FIELDS that some source could
## answer, plus a `sources` dictionary saying which one did.
##
## A FIELD NOBODY ANSWERED IS ABSENT, not empty. The caller asks `has()` rather
## than comparing against "" or [] or 0, which keeps the three empty-shaped
## types from having to mean the same thing at every call site -- and means a
## Metacritic score of zero, if Valve ever published one, would be a score
## rather than a silence.
##
## THE SOURCES MAP IS NOT DECORATION. On this machine the difference between
## "storeart has not fetched this game yet" and "the panel is not reading what
## it fetched" is otherwise a thing you can only photograph, and both look
## identical on the TV -- the same argument details_panel's description logging
## was built on, now available for every field at once.
static func resolve(entry: Dictionary) -> Dictionary:
	var id := str(entry.get("id", ""))

	# Read ONCE and passed down, rather than per field. Eight fields asking
	# SOURCE_STEAM would otherwise be eight opens and eight JSON parses of the
	# same hundred-KB document for one button press.
	var steam := Catalogue.steam_meta(id)

	var resolved: Dictionary = {}
	var answered: Dictionary = {}

	for field in FIELDS:
		var key := str(field["key"])
		for source in field["sources"]:
			var value: Variant = _ask(str(source), key, entry, steam)
			if not _has_answer(value):
				continue
			resolved[key] = value
			answered[key] = str(source)
			break

	resolved["sources"] = answered
	return resolved


## One source's answer for one field, or something _has_answer rejects.
##
## A source that has no opinion about a field returns null rather than being
## absent from the match -- "I was asked and I have nothing" and "nobody asks me
## this" are the same answer to the caller, and collapsing them here is what
## lets FIELDS list a source for a field it happens not to carry without that
## being an error.
static func _ask(source: String, key: String, entry: Dictionary,
		steam: Dictionary) -> Variant:
	match source:
		SOURCE_RECORD:
			return _from_record(key, entry)
		SOURCE_CATALOGUE:
			return _from_catalogue(key, entry)
		SOURCE_STEAM:
			return _from_steam(key, steam)
	return null


## What the apps.tsv row itself knows. Two fields, and both are things appscan
## read off the disk rather than off a network.
static func _from_record(key: String, entry: Dictionary) -> Variant:
	match key:
		"name":
			return str(entry.get("title", ""))
		"description":
			# The desktop entry's Comment field for an application, which ranges
			# from a useful sentence to the application's own name again -- true,
			# occasionally useless, and better than an empty panel. For a game
			# this column is always empty (see appscan's scan_steam), so it
			# falls through.
			return str(entry.get("subtitle", ""))
	return null


## The hand-written shelf. Only ever a description: AVAILABLE_APPS carries a
## tagline and nothing else, and inventing a release date for a flatpak would be
## this file making something up.
static func _from_catalogue(key: String, entry: Dictionary) -> Variant:
	if key != "description":
		return null
	return Catalogue.tagline_for(str(entry.get("id", "")))


## Steam's own appdetails document, as marwanos-storeart cached it.
##
## EVERY FIELD BELOW EXCEPT name AND short_description NEEDS THE UNFILTERED
## PAYLOAD. The fetch used to pass `filters=basic`, which returns the
## description block and drops developers, publishers, genres, categories,
## release_date and metacritic wholesale -- so on a machine whose cache predates
## that change these all resolve to nothing and the panel draws what it drew
## before. storeart's META_REV is what replaces such a document; this function
## needs no version check of its own, because "the key is not there" and "the
## key is there and empty" already have the same answer here.
static func _from_steam(key: String, steam: Dictionary) -> Variant:
	if steam.is_empty():
		return null

	match key:
		"name":
			return str(steam.get("name", ""))
		"description":
			# short_description, not detailed_description: the latter is the
			# store page's marketing body, arrives as HTML, and would need a
			# parser and about forty lines of the panel to draw. This is the
			# sentence under the title, written to say what a game is to
			# somebody who has not played it, which is exactly the panel's
			# question.
			return str(steam.get("short_description", ""))
		"genres":
			return _descriptions(steam.get("genres", []))
		"features":
			# Steam calls these categories and Playnite imports them as
			# Features, which is the more honest word: "Single-player", "Full
			# controller support", "Steam Cloud". Handed over whole rather than
			# filtered here -- which of them is worth a ten-foot screen is a
			# question about the panel, and it is answered in the panel.
			return _descriptions(steam.get("categories", []))
		"developers":
			return _strings(steam.get("developers", []))
		"publishers":
			return _strings(steam.get("publishers", []))
		"release_date":
			return _release_date(steam.get("release_date", {}))
		"critic_score":
			return _critic_score(steam.get("metacritic", {}))
	return null


## The `description` field of each element of a `[{id, description}]` array --
## the shape Steam uses for both genres and categories.
##
## Defensive about the element type rather than trusting the document: this
## parses a file fetched from somebody else's public endpoint with no contract
## (steamfront.gd says the same about the same host), and a malformed element
## should cost its own line rather than the whole panel.
static func _descriptions(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var text := str((item as Dictionary).get("description", "")).strip_edges()
		if not text.is_empty():
			out.append(text)
	return out


## A plain array of strings -- the shape Steam uses for developers and
## publishers -- with the blanks dropped. Valve ships `"developers": [""]` for a
## handful of titles, and an empty string in this array would satisfy
## _has_answer's "the array is not empty" and draw a stray separator.
static func _strings(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		var text := str(item).strip_edges()
		if not text.is_empty():
			out.append(text)
	return out


## Steam's release_date block as one displayable string, or empty.
##
## COMING_SOON IS A REFUSAL, not a date. For an unreleased game Valve puts
## things like "Q4 2026" or "To be announced" in the date field, and a library
## panel is a screen about a game that is installed -- so a date that says the
## game is not out yet is describing something other than the copy on the disk,
## and saying nothing is more honest than saying that.
static func _release_date(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	var block := raw as Dictionary
	if bool(block.get("coming_soon", false)):
		return ""
	return str(block.get("date", "")).strip_edges()


## Metacritic's score as an integer, or 0 for a game they never reviewed.
##
## Godot's JSON parser returns every number as a float, so this is a conversion
## rather than a read: `str(90.0)` is "90" only by luck of Godot's float
## formatting, and the panel needs to append it to a label.
static func _critic_score(raw: Variant) -> int:
	if typeof(raw) != TYPE_DICTIONARY:
		return 0
	var score: Variant = (raw as Dictionary).get("score", 0)
	if typeof(score) != TYPE_FLOAT and typeof(score) != TYPE_INT:
		return 0
	return int(score)


## Whether a source actually answered.
##
## THE THREE EMPTY SHAPES ARE ONE QUESTION. A field's value is a String, an
## Array or a number depending on the field, and "the source has nothing" looks
## different in each -- so every call site that walked a chain by hand had to
## know which shape it was testing. That is the check this centralises, and it
## is why the chain in FIELDS can be data instead of code.
##
## A ZERO SCORE IS NOT AN ANSWER. Metacritic scores run 1-100 and Valve omits
## the block entirely for a game nobody reviewed, so a 0 here is the default
## from _critic_score rather than a review -- and "Metacritic 0" on the TV would
## be this shell inventing a savaging.
static func _has_answer(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_STRING:
			return not (value as String).strip_edges().is_empty()
		TYPE_ARRAY:
			return not (value as Array).is_empty()
		TYPE_INT:
			return (value as int) != 0
		TYPE_FLOAT:
			return not is_zero_approx(value as float)
	return true
