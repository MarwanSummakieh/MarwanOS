# Fullscreen browser and desktop extension installation — 2026-10-10

The browser now fills the screen with a single 60 px address toolbar and 44 px
controls. The outer frame, title bar, tab rail and bottom dock have been removed.
The Tabs button opens the retained tab list. The native start page keeps search,
shortcuts, bookmarks and recent visits; L3 moves between page input and browser
controls. Status messages overlay the page only while needed.

The puzzle button and Options → Extensions offer Chrome Web Store and Manage
extensions. Installation follows the desktop flow: choose an extension in the
[Chrome Web Store](https://chromewebstore.google.com/category/extensions), select
Add to Chrome, then approve Chromium's native Add extension permission prompt.
Manage extensions opens Chromium's real manager for settings, disabling and
removal. The former ZIP installer is no longer exposed by the browser.

The store and manager open in a fullscreen Chrome-style CEF window because
the embedded Alloy/OSR view cannot host the native install prompt or the
chrome://extensions WebUI. One 60 px shell toolbar provides Back, Chrome Web
Store, Manage extensions and Return to browser. Store URLs entered in the
address bar also route here. The native window and embedded pages share the
default persistent profile at `~/.local/share/marwanos/mowser`. Chromium handles
package verification, permissions, registration and updates; content scripts
activate without a shell restart.

The client owns both the installer and extension-created Chrome tabs. Automatic
welcome tabs are closed so they cannot take over the screen. Tracking browser
IDs separately is essential: Chromium can reuse the installer's CefClient for
those tabs. Overwriting the primary browser reference left an unclosed window
and caused a profile shutdown crash. All owned native windows close before
CefShutdown. Returning to the embedded browser restores page input and focus.

Embedded pages still lack Chrome's own toolbar and tab/window UI, so extension
features depending on those surfaces may differ from desktop Chrome. Chrome Web
Store may display a Switch to Chrome banner for CEF even though Add to Chrome
and the standard installer work. The store install and persistence checks below
cover Dark Reader; compatibility with every extension is not asserted.

## Validation

- 59 native browser layout and controller checks passed, including rendered
  checks at 960×720, 1280×720, 1920×1080 and 2580×1080.
- 11 extension menu and lifecycle checks passed. Rendered menus were inspected
  at 960×720 and 1920×1080.
- The C++ engine compiled against the project's pinned Godot 4.7.1 and CEF 151.
- A real Dark Reader store installation passed using Add to Chrome and its
  native Add extension prompt. Chromium recorded `from_webstore: true`, the
  store changed to Remove from Chrome, and Dark Reader immediately activated
  on an embedded local HTTP fixture. The process exited with status 0.
- A fresh engine process using the same isolated profile loaded Dark Reader
  and activated it on the fixture without opening the installer. Exit status 0.
- Eight full-shell native window checks passed under a private Xvfb display
  running PC1's Openbox configuration. The compact toolbar was inspected above
  the fullscreen manager, a real X11 click on Return to browser restored the
  embedded page, store URL routing worked, and leaving the browser closed the
  native window. Exit status 0; no script or asset errors.
- CEF 151 logs browser-info timeout warnings when loading native Chrome WebUI.
  The manager and store loaded successfully despite those warnings.

Linux testing used `/var/tmp/marwanos-browser-compact-check` on PC1 and a private
Xvfb display, profile and local HTTP fixture. Early tests without a window
manager resized the native Chrome window explicitly; the final full-shell test
used Openbox to match the appliance. The root harness explicitly used
the existing test-only sandbox opt-out; appliance sandbox settings were not
changed. The running shell was not replaced or restarted. Rendered previews
and test logs are in the local ignored `out/browser-redesign-check` folder.

Tested `libmowser.so` SHA-256:
`6c5f61e620f70a51edfd91934e98db6c69607c236b04837e4608ce1f1f9c6f5d`.

## Bench activation

The isolated checks above preceded deployment. On October 10, the matching shell
and engine were [applied directly to PC1](browser-install-crash-20261010.md)
after a further normal-user, sandbox-enabled NordVPN Web Store installation
check. The running shell now uses the native installation flow.
