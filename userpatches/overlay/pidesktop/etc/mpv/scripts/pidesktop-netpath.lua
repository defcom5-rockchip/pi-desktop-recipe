-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 defcom5-rockchip (Pi-Desktop). See LICENSE in the recipe repository.
-- pidesktop-netpath.lua — two things for files dropped on mpv or opened from the file manager's network view:
--  1. A network URL mpv has no handler for (smb://, sftp://, ftp://, nfs://, mtp://) is turned into a local path by the
--     desktop's own FUSE bridge (kio-fuse on KDE, GVFS on GNOME) through /usr/local/bin/pidesktop-local-path.
--     Such a path is read a little at a time, so the OSD suggests the Network Drive, which reads well ahead.
--  2. When a load fails, say what went wrong on the OSD. (Keeping the window open is the desktop entry's job: it starts mpv
--     with --idle=yes, because pseudo-gui's idle=once quits on a failed load and a runtime change of idle is not honoured.)
--     A kio-fuse path answers "Operation not permitted" when the file manager has not been given that share's password
--     (KIO cannot ask through FUSE), so the message points at the Network Drive.
local schemes = { smb = true, sftp = true, ftp = true, ftps = true, nfs = true, mtp = true, afp = true }

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
    local hint = ""
    if name:match("^/run/user/%d+/kio%-fuse%-") or name:match("/gvfs/") or name:match("^[%a][%w+.-]*://") then
        hint = "\nOpen it from the Network Drive instead (How-To, section 4): the file manager's own network view can't hand the file over."
    end
    mp.osd_message("Couldn't open " .. name .. "\n" .. (e.file_error or "unknown error") .. hint, 10)
end)
