"""Controller-accessible text entry attached to Anaconda's GTK windows."""
from gi.repository import Gdk, GLib, Gtk

_dialog = None
_attached = set()


def on_key(window, event):
    global _dialog
    if event.keyval != Gdk.KEY_F8 or _dialog is not None:
        return False
    target = window.get_focus()
    if not isinstance(target, Gtk.Entry):
        return False
    dialog = Gtk.Dialog(title="PC1 · On-screen keyboard", transient_for=window, modal=True)
    _dialog = dialog
    dialog.add_button("Done", Gtk.ResponseType.OK)
    area = dialog.get_content_area()
    entry = Gtk.Entry()
    entry.set_visibility(target.get_visibility())
    entry.set_text(target.get_text())
    entry.set_position(-1)
    area.pack_start(entry, False, False, 12)
    grid = Gtk.Grid(column_spacing=6, row_spacing=6, margin=12)
    area.pack_start(grid, True, True, 0)
    shifted = [False]
    keys = []

    def insert(button, character):
        start, end = (entry.get_selection_bounds() or (entry.get_position(), entry.get_position()))
        text = entry.get_text()
        value = character.upper() if shifted[0] else character
        entry.set_text(text[:start] + value + text[end:])
        entry.set_position(start + len(value))

    for row, characters in enumerate(("1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm", "@._-+!?/", "#$%&*()=:")):
        for column, character in enumerate(characters):
            button = Gtk.Button(label=character)
            button.connect("clicked", insert, character)
            grid.attach(button, column, row, 1, 1)
            keys.append((button, character))

    def shift(_button):
        shifted[0] = not shifted[0]
        for key, character in keys:
            key.set_label(character.upper() if shifted[0] else character)

    def backspace(_button):
        selection = entry.get_selection_bounds()
        pos = entry.get_position()
        start, end = selection or (max(0, pos - 1), pos)
        entry.set_text(entry.get_text()[:start] + entry.get_text()[end:])
        entry.set_position(start)

    for title, callback, column, width in (
        ("Shift", shift, 0, 2), ("Space", lambda b: insert(b, " "), 2, 5),
        ("Delete", backspace, 7, 3)):
        button = Gtk.Button(label=title)
        button.connect("clicked", callback)
        grid.attach(button, column, 6, width, 1)
    dialog.show_all()
    keys[0][0].grab_focus()
    result = dialog.run()
    if result == Gtk.ResponseType.OK:
        target.set_text(entry.get_text())
        target.set_position(-1)
    dialog.destroy()
    _dialog = None
    target.grab_focus()
    return True


def attach():
    for window in Gtk.Window.list_toplevels():
        if window not in _attached:
            window.connect("key-press-event", on_key)
            window.connect("destroy", lambda w: _attached.discard(w))
            _attached.add(window)
    return True


def install():
    attach()
    GLib.timeout_add(500, attach)
