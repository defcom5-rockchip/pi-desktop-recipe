# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip (Pi-Desktop). See LICENSE in the recipe repository.
# Pi-Desktop: "Open in Terminator" in the Files right-click menu.
# Files 50 has no Open in Terminal of its own, and Terminator (the image's terminal) ships no Files integration.
# Shown on the folder background and on a single selected folder; opens Terminator in that folder.
import shutil
import subprocess

import gi

gi.require_version("Nautilus", "4.1")
from gi.repository import GObject, Nautilus


def _local_path(file_info):
    location = file_info.get_location()
    # network folders (smb://, sftp://) have a local path only through the gvfs FUSE mount
    return location.get_path() if location is not None else None


def _spawn(argv):
    """Start argv in its own systemd scope: Files runs as a D-Bus service (org.gnome.Nautilus.service) and everything
    in that service is stopped when Files exits, which would close the window it opened. Plain start without systemd-run."""
    run = shutil.which("systemd-run")
    cmd = [run, "--user", "--scope", "--collect", "--quiet", "--"] + argv if run else argv
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        pass


def _open(_item, path):
    _spawn(["terminator", "--working-directory", path])


def _item(name, path):
    item = Nautilus.MenuItem(name=name, label="Open in Terminator")
    item.connect("activate", _open, path)
    return [item]


class PiDesktopOpenTerminator(GObject.GObject, Nautilus.MenuProvider):
    def get_background_items(self, folder):
        path = _local_path(folder)
        return _item("PiDesktopOpenTerminator::background", path) if path else []

    def get_file_items(self, files):
        if len(files) != 1 or not files[0].is_directory():
            return []
        path = _local_path(files[0])
        return _item("PiDesktopOpenTerminator::folder", path) if path else []
