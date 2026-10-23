# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip (Plaid Pi). See LICENSE in the recipe repository.
# Plaid Pi: "Add as Network Drive…" in the Files right-click menu: on a share's icon on a server's page (smb://server/),
# and inside a share (smb://server/share/…). Opens the Network Drive window with the server, the share and any user
# name from the location filled in; the user adds the password and confirms.
# Why: films played straight from an smb:// location are read without read-ahead and skip when the NAS pauses;
# the same share as a network drive (kernel mount) plays smoothly in every program.
import os
import shutil
import subprocess
from urllib.parse import urlsplit

import gi

gi.require_version("Nautilus", "4.1")
from gi.repository import Gio, GObject, Nautilus

DIALOG = "/usr/local/bin/pidesktop-netdrive-dialog"


def _share_uri(file_info):
    """(smb://server/share, user-or-None) for a share or any location inside one; None for servers and workgroups.
    A share listed on a server's page is a 'mountable' whose activation URI is the share itself."""
    uri = file_info.get_activation_uri() or file_info.get_uri() or ""
    if not uri.lower().startswith("smb://"):
        return None
    parts = urlsplit(uri)
    share = parts.path.strip("/").split("/")[0] if parts.path else ""
    if not parts.hostname or not share:
        return None
    host = parts.netloc.rsplit("@", 1)[-1]
    user = (parts.username or "").split(";")[-1] or None
    return f"smb://{host}/{share}", user


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


def _open(_item, target):
    uri, user = target
    _spawn([DIALOG, uri] + (["--user", user] if user else []))


def _item(name, target):
    item = Nautilus.MenuItem(name=name, label="Add as Network Drive…",
                             tip="Mount this share as a network drive for smooth playback")
    item.connect("activate", _open, target)
    return [item]


class PlaidPiNetworkDrive(GObject.GObject, Nautilus.MenuProvider):
    def get_background_items(self, folder):
        if not os.access(DIALOG, os.X_OK):
            return []
        target = _share_uri(folder)
        return _item("PlaidPiNetworkDrive::background", target) if target else []

    def get_file_items(self, files):
        if len(files) != 1 or not os.access(DIALOG, os.X_OK):
            return []
        if files[0].get_file_type() not in (Gio.FileType.DIRECTORY, Gio.FileType.MOUNTABLE):
            return []
        target = _share_uri(files[0])
        return _item("PlaidPiNetworkDrive::folder", target) if target else []
