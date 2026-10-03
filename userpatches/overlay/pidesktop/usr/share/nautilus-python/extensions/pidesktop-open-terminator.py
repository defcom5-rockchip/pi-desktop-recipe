# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip (Pi-Desktop). See LICENSE in the recipe repository.
# Pi-Desktop: "Open in Terminator" in the Files right-click menu.
# Files 50 has no Open in Terminal of its own, and Terminator (the image's terminal) ships no Files integration.
# Shown on the folder background and on a single selected folder; opens Terminator in that folder.
import subprocess

import gi

gi.require_version("Nautilus", "4.1")
from gi.repository import GObject, Nautilus


def _local_path(file_info):
    location = file_info.get_location()
    # network folders (smb://, sftp://) have a local path only through the gvfs FUSE mount
    return location.get_path() if location is not None else None


def _open(_item, path):
    subprocess.Popen(
        ["terminator", "--working-directory", path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


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
