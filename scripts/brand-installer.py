#!/usr/bin/env python3
"""Apply PC1 presentation to an extracted Fedora 43 Anaconda runtime.

Fail on an incompatible runtime instead of silently shipping partial patches.
The original storage/payload/error machinery stays authoritative.
"""
import ast
import configparser
import shutil
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def replace_once(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f"Unsupported installer: expected one {old!r} in {path}")
    path.write_text(text.replace(old, new))


def label(parent, name, text):
    child = ET.SubElement(parent, "child")
    obj = ET.SubElement(child, "object", {"class": "GtkLabel", "id": name})
    for key, value in {"visible": "True", "label": text, "wrap": "True",
                       "name": name, "xalign": "0", "margin": "16"}.items():
        ET.SubElement(obj, "property", {"name": key}).text = value
    return child


def patch_runtime(root, repo):
    ui = root / "usr/share/anaconda/ui"
    shutil.copyfile(repo / "os/installer/pc1.css", root / "usr/share/anaconda/pc1.css")
    controller = root / "usr/libexec/pc1-installer-controller"
    shutil.copyfile(repo / "os/installer/controller.py", controller)
    controller.chmod(0o755)
    unit = root / "usr/lib/systemd/system/pc1-installer-controller.service"
    unit.write_text("""[Unit]
Description=PC1 installer controller input
After=systemd-udev-trigger.service
[Service]
ExecStart=/usr/bin/python3 /usr/libexec/pc1-installer-controller
Restart=on-failure
RestartSec=3
[Install]
WantedBy=anaconda.target
""")
    wants = root / "etc/systemd/system/anaconda.target.wants"
    wants.mkdir(parents=True, exist_ok=True)
    (wants / unit.name).symlink_to("/usr/lib/systemd/system/" + unit.name)
    config = root / "etc/anaconda/conf.d/99-pc1.conf"
    config.write_text("""[User Interface]
custom_stylesheet = /usr/share/anaconda/pc1.css
hidden_spokes = PasswordSpoke UserSpoke

[Storage]
default_scheme = PLAIN

[Anaconda]
activatable_modules =
    org.fedoraproject.Anaconda.Modules.*
""")
    stamp = configparser.ConfigParser()
    stamp.read(root / ".buildstamp")
    stamp["Main"]["Product"] = "PC1"
    stamp["Main"]["Version"] = "1"
    with (root / ".buildstamp").open("w") as stream:
        stamp.write(stream)

    welcome = ui / "spokes/welcome.glade"
    replace_once(welcome, "WELCOME TO %(name)s %(version)s.", "Welcome to %(name)s.")
    for filename, box_id, text in [
        ("spokes/welcome.glade", "welcomeWindowContentBox",
         "01  Welcome   /   02  Set up   /   03  Install   /   04  Play\n"
         "Choose your language. Next, review your settings and choose where PC1 will live.\n"
         "Controller: left stick moves the pointer · A/cross selects · B/circle goes back\n"
         "R1/RB moves focus · X/square activates · Y/triangle opens the keyboard in a text field"),
        ("spokes/installation_progress.glade", "progressWindow-actionArea",
         "03  Install\nKeep your computer powered on and the installer USB connected."),
    ]:
        path = ui / filename
        tree = ET.parse(path)
        box = tree.find(f".//object[@id='{box_id}']")
        if box is None:
            raise RuntimeError(f"Missing {box_id}")
        child = label(box, "pc1Journey", text)
        box.remove(child)
        # Properties must precede children in GtkBuilder XML.
        first = next(i for i, item in enumerate(box) if item.tag == "child")
        box.insert(first, child)
        if "progress" in filename:
            image_child = ET.SubElement(box, "child")
            obj = ET.SubElement(image_child, "object", {"class": "GtkImage", "id": "pc1ProgressArt"})
            ET.SubElement(obj, "property", {"name": "visible"}).text = "True"
            ET.SubElement(obj, "property", {"name": "file"}).text = "/usr/share/anaconda/pixmaps/pc1-progress.png"
        tree.write(path, encoding="unicode", xml_declaration=True)

    summary = ui / "hubs/summary.glade"
    text = summary.read_text()
    if text.count("INSTALLATION SUMMARY") != 2:
        raise RuntimeError("Unsupported summary screen")
    summary.write_text(text.replace("INSTALLATION SUMMARY", "02  SET UP YOUR PC1"))
    replace_once(summary, "We won't touch your disks until you click 'Begin Installation'.",
                 "Review Installation Destination carefully. Changes begin only when you select 'Begin Installation'.")
    progress = next(root.glob("usr/lib*/python*/site-packages/pyanaconda/ui/gui/spokes/installation_progress.py"))
    replace_once(progress, '"Go ahead and reboot your system to start using it!"',
                 '"Select Restart, then remove the USB when the screen goes dark. Boot from your internal drive to start playing."')
    replace_once(progress, '"_Reboot System"', '"_Restart"')
    replace_once(progress, "        self._task_proxy.Finish()",
                 "        self._task_proxy.Finish()\n"
                 "        self.builder.get_object(\"pc1Journey\").set_text(\n"
                 "            \"04  Ready to play\\nRestart, then remove the USB when the screen goes dark.\")")
    ast.parse(progress.read_text())
    welcome_code = progress.with_name("welcome.py")
    replace_once(welcome_code, '"WELCOME TO %(name)s %(version)s."', '"Welcome to %(name)s."')
    ast.parse(welcome_code.read_text())
    storage = progress.with_name("storage.py")
    replace_once(storage, '"Kickstart insufficient"', '"Choose and confirm your drive"')
    gui = progress.parents[1]
    shutil.copyfile(repo / "os/installer/keyboard.py", gui / "pc1_keyboard.py")
    replace_once(gui / "__init__.py", "        Gtk.main()",
                 "        from pyanaconda.ui.gui.pc1_keyboard import install as pc1_keyboard\n"
                 "        pc1_keyboard()\n        Gtk.main()")


def kickstart(source):
    """Keep established administrator identity, discard all automatic disk actions."""
    lines = source.read_text().splitlines()
    identity = [line for line in lines if line.startswith(("user --", "sshkey --", "rootpw --"))]
    if not identity:
        raise RuntimeError("Source ISO has no administrator identity; refusing to invent one")
    return ("# PC1 interactive installer. No disk is selected or erased by kickstart.\n"
            "%include /run/install/repo/osbuild-base.ks\n"
            "graphical\n" + "\n".join(identity) + "\n")


if __name__ == "__main__":
    if sys.argv[1] == "kickstart":
        Path(sys.argv[3]).write_text(kickstart(Path(sys.argv[2])))
    else:
        patch_runtime(Path(sys.argv[1]), Path(__file__).resolve().parents[1])
