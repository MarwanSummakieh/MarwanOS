"""Desktop entries resolve their own artwork across installed icon layouts."""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


SCANNER = Path(__file__).resolve().parents[1] / "os/files/usr/lib/marwanos/appscan"
SOURCE = SCANNER.read_text(encoding="utf-8")
GIT_BASH = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe"
BASH = str(GIT_BASH) if os.name == "nt" and GIT_BASH.is_file() else shutil.which("bash")


def shell_path(path):
    value = Path(path).as_posix()
    if os.name == "nt" and len(value) > 1 and value[1] == ":":
        value = "/" + value[0].lower() + value[2:]
    return value


def function(name):
    return re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}", SOURCE, re.M | re.S).group()


@unittest.skipUnless(BASH, "Bash is required to exercise the Linux icon scanner")
class AppscanIconsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="app icon fixtures ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.theme = self.root / "user icons/hicolor"
        self.fallback = self.root / "local pixmaps"
        self.cache = self.root / "Steam cache"
        self.art = self.root / "Steam art"
        self.windows = self.root / "Windows games"
        self.index = self.root / "windows.tsv"
        self.helper_arguments = self.root / "icon-helper-arguments"

    def asset(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"fixture artwork")
        return path

    def run_function(self, name, *arguments, dependencies=(), before=""):
        setup = "\n".join([
            "set -uo pipefail",
            "PATH=/usr/bin:$PATH",
            "ICON_ROOTS=(" + shlex.quote(shell_path(self.theme)) + ")",
            "ICON_FALLBACK_DIRS=(" + shlex.quote(shell_path(self.fallback)) + ")",
            "ICON_SIZES_LARGE=(1024x1024 512x512 256x256)",
            "ICON_SIZES_SMALL=(192x192 128x128 96x96 64x64 48x48 32x32 24x24 22x22 16x16)",
            "APP_DIRS=()",
            "STEAM_LIBCACHE=" + shlex.quote(shell_path(self.cache)),
            "STEAM_ART_DIR=" + shlex.quote(shell_path(self.art)),
            "WINDOWS_DIR=" + shlex.quote(shell_path(self.windows)),
            "WINDOWS_INDEX=" + shlex.quote(shell_path(self.index)),
            "HELPER_ARGUMENTS=" + shlex.quote(shell_path(self.helper_arguments)),
            "\n".join(function(dependency) for dependency in dependencies),
            function(name),
            before,
            name + " " + " ".join(shlex.quote(arg) for arg in arguments),
        ])
        result = subprocess.run([BASH, "-c", setup], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_named_icon_with_extension_resolves_high_resolution_artwork(self):
        icon = self.asset(self.theme / "256x256/apps/org.example.App.png")
        self.assertEqual(self.run_function("icon_path", "org.example.App.png"), shell_path(icon))

    def test_sized_svg_beats_a_small_raster(self):
        self.asset(self.theme / "48x48/apps/example.png")
        vector = self.asset(self.theme / "64x64/apps/example.svg")
        self.assertEqual(self.run_function("icon_path", "example"), shell_path(vector))

    def test_uncommon_size_and_context_preserve_the_exact_application_icon(self):
        icon = self.asset(self.theme / "72x72/places/org.example.App.png")
        self.asset(self.theme / "256x256/apps/org.example.Other.png")
        self.assertEqual(self.run_function("icon_path", "org.example.App"), shell_path(icon))
        self.assertEqual(self.run_function("icon_path", "missing"), "")

    def test_unthemed_and_absolute_bitmap_icons_are_supported(self):
        icon = self.asset(self.fallback / "example.png")
        self.assertEqual(self.run_function("icon_path", "example"), shell_path(icon))
        absolute = self.asset(self.root / "official logo.jpg")
        self.assertEqual(self.run_function("icon_path", shell_path(absolute)), shell_path(absolute))

    def test_steam_square_logo_wins_over_portrait_and_downloaded_art(self):
        portrait = self.asset(self.cache / "570_library_600x900.jpg")
        self.asset(self.art / "570.jpg")
        self.assertEqual(self.run_function("steam_art", "570"), shell_path(portrait))
        square = self.asset(self.cache / "570/icon.jpg")
        self.assertEqual(self.run_function("steam_art", "570"), shell_path(square))

    def test_new_icon_triggers_a_rescan_without_an_application_install(self):
        directory = self.theme / "256x256/apps"
        directory.mkdir(parents=True)
        signature = self.run_function("dirs_signature")
        previous = directory.stat().st_mtime
        self.asset(directory / "late-icon.png")
        os.utime(directory, (previous + 2, previous + 2))
        self.assertNotEqual(self.run_function("dirs_signature"), signature)

    def scan_windows(self, helper):
        return self.run_function("scan_windows", dependencies=("windows_slug", "windows_exe"),
                                 before="warn() { :; }; err() { :; }; " + helper).strip().split("\t")

    def test_legacy_windows_icon_helper_runs_as_player_with_literal_arguments(self):
        executable = self.asset(self.windows / "Game $(literal) ' Title/Game $(literal) '.exe")
        cached_icon = self.asset(self.root / "cached official logo.png")
        helper = "runuser() { printf '%s\\0' \"$@\" > \"$HELPER_ARGUMENTS\"; printf '%s' " + shlex.quote(shell_path(cached_icon)) + "; }"
        fields = self.scan_windows(helper)
        self.assertEqual(fields[0], "win.game-literal-title")
        self.assertEqual(fields[3], shell_path(cached_icon))
        self.assertEqual(self.helper_arguments.read_bytes().decode().split("\0")[:-1], [
            "-u", "player", "--", "/usr/lib/marwanos/windows/manager.py", "icon",
            "legacy-game-literal-title", shell_path(executable),
        ])

    def test_legacy_windows_explicit_icon_wins_and_missing_helper_is_graceful(self):
        executable = self.asset(self.windows / "Game/Game.exe")
        icon = self.asset(executable.parent / ".icon.png")
        helper = 'runuser() { printf called > "$HELPER_ARGUMENTS"; return 127; }'
        self.assertEqual(self.scan_windows(helper)[3], shell_path(icon))
        self.assertFalse(self.helper_arguments.exists())
        icon.unlink()
        fields = self.scan_windows(helper)
        self.assertEqual(fields[3], "")
        self.assertEqual(fields[-1], "installed")
        self.assertTrue(self.helper_arguments.exists())

    def test_nested_windows_target_and_matching_sidecar_invalidate_signature(self):
        executable = self.asset(self.windows / "Game/bin/Game.exe")
        (executable.parent.parent / ".launch").write_text("bin/Game.exe\n")
        sidecar = self.asset(executable.with_suffix(".ICO"))
        unrelated = self.asset(executable.parent / "other.png")

        def signature():
            return self.run_function("windows_signature", dependencies=("windows_exe",),
                                     before="warn() { :; }")

        original = signature()
        unrelated.write_bytes(b"different unrelated image")
        self.assertEqual(signature(), original)
        executable.write_bytes(b"changed executable resources")
        self.assertNotEqual(signature(), original)
        original = signature()
        sidecar.write_bytes(b"changed official sidecar image")
        self.assertNotEqual(signature(), original)


if __name__ == "__main__":
    unittest.main()
