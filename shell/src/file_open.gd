extends RefCounted

## What opens what, when A lands on a file.
##
## Until now the answer was a sentence: "Nothing on this machine opens .mkv
## yet." It was true and it was the right thing to say while it was true -- a
## viewer that renders three formats badly is worse than an honest refusal --
## but it is most of the distance between a file browser and a file manager,
## and this machine does ship things that can open files.
##
## THREE ANSWERS, IN THIS ORDER, and the order is the point:
##
##   1. THE SHELL ITSELF, for pictures. A photograph on a stick is the single
##      most likely thing anyone points this screen at, and opening one should
##      not depend on a multi-gigabyte flatpak being installed. The shell
##      already decodes PNG, JPEG, WEBP and SVG for thumbnails; showing one
##      fullscreen is the same loader and a black background. No dependency, no
##      launch, no wait.
##   2. AN INSTALLED APPLICATION, for everything else it can do. Chromium
##      renders a PDF, an HTML file or a text file, and it is in the image's
##      shipped set -- opened in kiosk mode, so the document arrives full
##      screen with no browser furniture around it (see Catalogue.browser_exec).
##   3. THE HONEST SENTENCE for everything left, and since Kodi's removal that
##      includes every video and audio file: "nothing on this machine opens
##      .mkv" is true, and truer than naming a player the machine refuses to
##      install. When an app that IS shipped is merely absent, the sentence
##      still says which app and how to get it.
##
## THE HANDLER MUST BE INSTALLED, and that is checked against the installed
## seam rather than assumed from the shipped list. Launching `flatpak run` for
## something that is not there fails in milliseconds with nothing on screen --
## the exact failure the stores screen's A-means-two-things branch exists to
## avoid, and the same fix.

const Catalogue = preload("res://src/catalogue.gd")

## Extensions the shell shows itself. Deliberately the same list FileThumbs
## previews from: if the icon view can draw it small, the viewer can draw it
## large, and a format in one list and not the other would be a thumbnail you
## cannot open or an opening that shows nothing.
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]

## Everything else, by handler. The application id is the desktop-entry id --
## what marwanos-appscan reports and what appctl installs -- because that is
## what "is it actually here" is answered against.
##
## MEDIA HAS NO HANDLER ANY MORE, and the absence is a decision with a date on
## it: Kodi -- which took a path on its command line and played it, the whole
## integration -- left the image on 2026-08-11 on the owner's word ("kodi is
## out no need to have it at all"). Every media extension therefore routes to
## plan()'s honest "none": A on an .mkv says nothing on this machine opens it,
## which is true, rather than naming a player the machine refuses to install.
## The extensions live on in MEDIA_EXTENSIONS below so the properties panel
## can still call a video a video.
##
## Chromium opens a local path handed on its command line -- it makes the
## file: URL itself -- for the document formats a browser engine already
## renders. (The handler was Zen until 2026-08-11; same formats, because the
## list was always "what a browser renders", not "what Zen renders".)
##
## A TABLE, not a chain of ifs, so adding a format is one line and so the hint
## the screen shows is generated from the same data that decides what runs.
const HANDLERS := {
	# Documents and web, which a browser engine renders
	"pdf": Catalogue.BROWSER_ID, "html": Catalogue.BROWSER_ID,
	"htm": Catalogue.BROWSER_ID, "txt": Catalogue.BROWSER_ID,
	"md": Catalogue.BROWSER_ID, "json": Catalogue.BROWSER_ID,
	"xml": Catalogue.BROWSER_ID, "csv": Catalogue.BROWSER_ID,
	"log": Catalogue.BROWSER_ID,
}

## Titles for the sentence, so it says "Chromium" rather than the raw id. The
## installed seam knows the title of everything on the machine -- and the case
## this sentence is FOR is the application being absent, which is exactly when
## that list cannot answer. Same two-source problem the rail's app alert has,
## solved the same way: a small table, then the raw id.
const HANDLER_TITLES := {
	Catalogue.BROWSER_ID: "Chromium",
}

## The formats that ARE media, kept for naming rather than for routing: nothing
## opens these since Kodi left, but the properties panel calling an .mkv a
## plain "File" would be a second, quieter lie on top of the honest "nothing
## opens this". Video and audio in one list because the distinction only
## mattered to the player.
const MEDIA_EXTENSIONS := [
	"mkv", "mp4", "avi", "mov", "m4v", "webm", "mpg", "mpeg", "ts",
	"mp3", "flac", "m4a", "ogg", "opus", "wav", "aac",
]


static func is_image(file_name: String) -> bool:
	return IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower())


## The application id that would open this file, or empty for a format nothing
## on this machine claims. Says nothing about whether it is installed.
static func handler_for(file_name: String) -> String:
	return str(HANDLERS.get(file_name.get_extension().to_lower(), ""))


static func handler_title(app_id: String) -> String:
	if HANDLER_TITLES.has(app_id):
		return str(HANDLER_TITLES[app_id])
	return app_id


static func is_installed(app_id: String) -> bool:
	for app in Installed.apps:
		if str(app.get("id", "")) == app_id and str(app.get("state", "")) == "installed":
			return true
	return false


## What the screen should say about pressing A on this file, given what is
## actually on the machine. Returns {"action", "detail"} where action is one of
## "image", "launch", "install", "none" -- the screen turns it into a hint
## caption, and files_screen turns it into behaviour. One function answering
## both keeps the hint and the press from ever disagreeing.
static func plan(file_name: String) -> Dictionary:
	if is_image(file_name):
		return {"action": "image", "app": "", "detail": "View"}

	var app := handler_for(file_name)
	if app.is_empty():
		return {"action": "none", "app": "",
			"detail": "Nothing on this machine opens .%s" % file_name.get_extension()}

	var title := handler_title(app)
	if is_installed(app):
		return {"action": "launch", "app": app, "detail": "Open in %s" % title}

	# The application that WOULD open it is a card on the rail waiting to be
	# downloaded, so the sentence names both the handler and the way to get it.
	return {"action": "install", "app": app,
		"detail": "%s opens .%s -- install it from the home screen"
			% [title, file_name.get_extension()]}


## The launch-seam entry for opening a path in an application.
##
## A SEPARATE ID FROM THE APPLICATION'S OWN CARD, "open.<app>", for the reason
## the store's buy entry has one: the launch seam, the splash and the
## pad bridge all key on the entry id, and "an app as a thing you browse" and
## "the same app opened on one file" want different treatment from at least
## the first of them. The pad bridge lists the open.-prefixed browser id
## separately in PAD_KEY_APPS -- a distinct id needs its own row, which is the
## cost of the ids being distinct and worth it for the splash alone.
##
## The icon is the application's real one where appscan resolved a path, so the
## launch splash shows the logo of the thing that is starting rather than a
## bare wash.
static func launch_entry(app_id: String, path: String) -> Dictionary:
	var icon := ""
	var title := handler_title(app_id)
	for app in Installed.apps:
		if str(app.get("id", "")) == app_id:
			icon = str(app.get("icon", ""))
			break
	if icon.is_empty():
		icon = Catalogue.store_icon_path(app_id)

	# The browser gets its one spelling of the kiosk launch -- the same flags
	# the buy page uses, for the same reason there is only one spelling of
	# Steam's launch line: a document that opened with browser furniture around
	# it while the checkout did not would be two browsers pretending to be one.
	# Any future non-browser handler falls through to the plain form, which is
	# how Kodi was launched when it held the media formats.
	var exec: Array = Catalogue.browser_exec(path) \
		if app_id == Catalogue.BROWSER_ID \
		else ["flatpak", "run", app_id, path]

	return {
		"id": "open.%s" % app_id,
		"title": "%s -- %s" % [title, path.get_file()],
		"exec": exec,
		"app_id": app_id,
		"icon": icon,
		"accent": "#33526B",
	}
