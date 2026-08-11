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
##   2. THE SHELL'S OWN BROWSER, for everything else it can render. A PDF, an
##      HTML file, a text file: these are documents a web engine draws, and
##      this shell now CONTAINS one (see mowser/src/mowser.h). So opening one
##      is not launching an application -- it is a screen, like the picture
##      viewer above it, and it cannot be "not installed".
##   3. THE HONEST SENTENCE for everything left, and since Kodi's removal that
##      includes every video and audio file: "nothing on this machine opens
##      .mkv" is true, and truer than naming a player the machine refuses to
##      install. When an app that IS shipped is merely absent, the sentence
##      still says which app and how to get it.
##
## "THE HANDLER MUST BE INSTALLED" USED TO BE THE HARD PART OF THIS FILE, and
## it is gone. Both remaining answers are the shell itself -- the picture
## viewer and the browser screen -- so there is no `flatpak run` to fail in
## milliseconds with nothing on screen, no installed-seam lookup, and no
## sentence naming an application somebody has to go and download first. A
## format is either one this binary can draw or one nothing here opens, and
## which of those it is does not depend on the state of the machine.

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
## THE HANDLER IS A WORD NOW, NOT AN APPLICATION ID. It used to be a
## desktop-entry id -- app.zen_browser.zen, then org.chromium.Chromium -- back
## when opening a document meant launching somebody else's program with a path
## on its command line. The engine is in this binary now, so what the table
## names is which of the SHELL'S OWN surfaces draws the file.
##
## The format list did not change when the handler did, twice, which is the
## evidence it was always the right list: it is "what a web engine renders",
## and it was never about who shipped the engine.
##
## A TABLE, not a chain of ifs, so adding a format is one line and so the hint
## the screen shows is generated from the same data that decides what runs.
const HANDLER_BROWSER := "browser"

const HANDLERS := {
	# Documents and web, which a browser engine renders
	"pdf": HANDLER_BROWSER, "html": HANDLER_BROWSER,
	"htm": HANDLER_BROWSER, "txt": HANDLER_BROWSER,
	"md": HANDLER_BROWSER, "json": HANDLER_BROWSER,
	"xml": HANDLER_BROWSER, "csv": HANDLER_BROWSER,
	"log": HANDLER_BROWSER,
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


## Which shell surface opens this file, or empty for a format nothing here
## claims.
static func handler_for(file_name: String) -> String:
	return str(HANDLERS.get(file_name.get_extension().to_lower(), ""))


## What the screen should say about pressing A on this file. Returns
## {"action", "detail"} where action is one of "image", "browser", "none" --
## the screen turns it into a hint caption, and files_screen turns it into
## behaviour. One function answering both keeps the hint and the press from
## ever disagreeing.
##
## "install" IS GONE FROM THE ANSWERS, and its absence is the whole of what
## embedding the engine changed here. It meant "the thing that opens this is a
## card on the rail waiting to be downloaded" -- a real state when the handler
## was a multi-gigabyte flatpak that might not have arrived yet, and an
## impossible one now: the browser is in the same binary as this function.
static func plan(file_name: String) -> Dictionary:
	if is_image(file_name):
		return {"action": "image", "app": "", "detail": "View"}

	var handler := handler_for(file_name)
	if handler.is_empty():
		return {"action": "none", "app": "",
			"detail": "Nothing on this machine opens .%s" % file_name.get_extension()}

	return {"action": HANDLER_BROWSER, "app": "", "detail": "Open"}


## A local path as the URL the browser screen takes.
##
## THE PATH IS ESCAPED, and it is the one place in this shell where somebody
## else's filename becomes part of a URL. A stick can carry a file called
## anything at all -- '#' truncates a URL at the fragment, '?' starts a query,
## a space ends it in some parsers -- so a file whose name contains any of them
## would open as a different path or as nothing. uri_encode leaves the slashes
## alone, which is why it is applied per SEGMENT rather than to the whole path.
## A PackedStringArray, NOT an Array, and the difference was a whole evening.
## String.join takes a PackedStringArray; handed an untyped Array it returns
## the EMPTY STRING rather than failing, so this function quietly produced ""
## for every path. The browser then loaded nothing, sat on about:blank, and
## rendered a blank page -- while the shell's own log said "opening a page for
## page.html", because it logs the title. Nothing in the chain was wrong except
## the one value nobody printed.
static func file_url(path: String) -> String:
	var encoded := PackedStringArray()
	for segment in path.split("/"):
		encoded.append(segment.uri_encode())
	return "file://" + "/".join(encoded)


## launch_entry() STOOD HERE, and this comment is its headstone because what it
## did is now done by not doing it.
##
## It built a launch-seam entry -- a distinct "open.<app>" id, an icon resolved
## off the installed application, a `flatpak run <app> <path>` exec -- so that
## pressing A on a PDF spawned a sandboxed browser, waited for gamescope to seat
## its window, raised a splash over the wait, and started a pad bridge injecting
## xdotool events at whatever had focus. Every part of that existed to get a
## document in front of a person who has no keyboard, through a process boundary
## the shell could not see across.
##
## There is no process boundary now. files_screen opens the browser screen with
## file_url(path) and the document is on the television in the next frame. The
## flatpak's `:ro` filesystem overrides went with it too: an engine inside this
## binary reads the stick with the session user's own permissions, so there is
## no sandbox left to poke a hole in for the file manager's sake.
