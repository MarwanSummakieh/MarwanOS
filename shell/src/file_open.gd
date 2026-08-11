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
##   2. AN INSTALLED APPLICATION, for everything else it can do. Kodi is a
##      media player driven by a pad natively; Zen is a browser and will render
##      a PDF, an HTML file or a text file. Both are in the image's shipped set.
##   3. THE HONEST SENTENCE, unchanged, for everything left -- and now it can be
##      specific about WHY: "Kodi opens .mkv" when Kodi is simply not installed
##      is a different problem from "nothing here opens .dll", and the person
##      can fix the first from the rail.
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
## KODI TAKES A PATH ON ITS COMMAND LINE and plays it; that is the whole
## integration, and it is why Kodi is the media answer rather than a player
## the shell would have to grow. Zen is Firefox-derived and will open a local
## file: URL for the document formats a browser already renders.
##
## A TABLE, not a chain of ifs, so adding a format is one line and so the hint
## the screen shows ("Kodi opens .mkv") is generated from the same data that
## decides what runs.
const HANDLERS := {
	# Video
	"mkv": "tv.kodi.Kodi", "mp4": "tv.kodi.Kodi", "avi": "tv.kodi.Kodi",
	"mov": "tv.kodi.Kodi", "m4v": "tv.kodi.Kodi", "webm": "tv.kodi.Kodi",
	"mpg": "tv.kodi.Kodi", "mpeg": "tv.kodi.Kodi", "ts": "tv.kodi.Kodi",
	# Audio
	"mp3": "tv.kodi.Kodi", "flac": "tv.kodi.Kodi", "m4a": "tv.kodi.Kodi",
	"ogg": "tv.kodi.Kodi", "opus": "tv.kodi.Kodi", "wav": "tv.kodi.Kodi",
	"aac": "tv.kodi.Kodi",
	# Documents and web, which a browser renders and a media player does not
	"pdf": "app.zen_browser.zen", "html": "app.zen_browser.zen",
	"htm": "app.zen_browser.zen", "txt": "app.zen_browser.zen",
	"md": "app.zen_browser.zen", "json": "app.zen_browser.zen",
	"xml": "app.zen_browser.zen", "csv": "app.zen_browser.zen",
	"log": "app.zen_browser.zen",
}

## Titles for the sentence, so it says "Kodi" rather than "tv.kodi.Kodi". The
## installed seam knows the title of everything on the machine -- and the case
## this sentence is FOR is the application being absent, which is exactly when
## that list cannot answer. Same two-source problem the rail's app alert has,
## solved the same way: a small table, then the raw id.
const HANDLER_TITLES := {
	"tv.kodi.Kodi": "Kodi",
	"app.zen_browser.zen": "Zen Browser",
}


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
## pad bridge all key on the entry id, and "Kodi as a library you browse" and
## "Kodi opened on one file" want different treatment from at least the first
## of them. It also keeps a file-open out of the pad-bridge table, which is
## right -- Kodi reads the pad itself.
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

	return {
		"id": "open.%s" % app_id,
		"title": "%s -- %s" % [title, path.get_file()],
		"exec": ["flatpak", "run", app_id, path],
		"app_id": app_id,
		"icon": icon,
		"accent": "#33526B",
	}
