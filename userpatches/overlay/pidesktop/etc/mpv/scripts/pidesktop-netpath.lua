-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 defcom5-rockchip (Pi-Desktop). See LICENSE in the recipe repository.
-- pidesktop-netpath.lua — two things for files dropped on mpv or opened from the file manager's network view:
--  1. A network URL mpv has no handler for (smb://, sftp://, ftp://, nfs://, mtp://) is turned into a local path by the
--     desktop's own FUSE bridge (kio-fuse on KDE, GVFS on GNOME) through /usr/local/bin/pidesktop-local-path.
--     Such a path is read a little at a time, so the OSD suggests the Network Drive, which reads well ahead.
--  2. Started from the menu (pseudo-gui), mpv quits when a load fails (idle=once) — a dropped file that can't be opened
--     closes the window with no explanation. Keep the window and say what went wrong instead.
local utils = require 'mp.utils'
local schemes = { smb = true, sftp = true, ftp = true, ftps = true, nfs = true, mtp = true, afp = true }

if mp.get_property("player-operation-mode") == "pseudo-gui" then
    mp.set_property("idle", "yes")
end

mp.add_hook("on_load", 50, function()
    local url = mp.get_property("stream-open-filename")
    if not url then return end
    local scheme = url:match("^([%a][%w+.-]*)://")
    if not scheme or not schemes[scheme:lower()] then return end
    local r = mp.command_native({ name = "subprocess", playback_only = false, capture_stdout = true,
                                  args = { "/usr/local/bin/pidesktop-local-path", url } })
    if r and r.status == 0 and r.stdout and r.stdout ~= "" then
        local path = r.stdout:gsub("\n$", "")
        mp.msg.info("network location opened through the desktop's file bridge: " .. path)
        mp.set_property("stream-open-filename", path)
        mp.osd_message("Playing over the network, read a little at a time.\nFor smooth playback add this share as a Network Drive (see the How-To).", 6)
    else
        mp.msg.warn("no local path for " .. url)
    end
end)

mp.register_event("end-file", function(e)
    if e.reason ~= "error" then return end
    local name = mp.get_property("path") or "the file"
    mp.osd_message("Couldn't open " .. name .. "\n" .. (e.file_error or "unknown error"), 8)
end)
