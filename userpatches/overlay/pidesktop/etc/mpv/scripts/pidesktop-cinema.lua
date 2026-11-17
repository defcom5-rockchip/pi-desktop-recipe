-- SPDX-License-Identifier: GPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 defcom5-rockchip
-- pidesktop-cinema.lua — Cinemosk, mpv side (Plaid Pi). The Cinemosk app (/usr/local/bin/cinemosk) shows the measured cost of
-- each choice and writes ~/.config/mpv/script-opts/cinemosk.conf, read here each time a file starts (shared contract):
--   downscale    = smooth|balanced|sharp  video bigger than the window (4K on a 1080p screen): bilinear / hermite / lanczos
--   upscale      = smooth|balanced|sharp  VIDEO-rate sources (> 31 fps: TV, concerts, 50/60p) smaller than the window:
--                                         bilinear / spline16 / spline36
--   upscale_film = smooth|balanced|sharp  FILM-rate sources (<= 31 fps) smaller than the window: the same filters
--   sd_colour    = fast|exact             BT.601/470M colour: fast = gamut clipping, as a TV does; exact = mpv's perceptual
--                                         gamut mapping, which doubled the GPU load on the 5 Plus
--   deband_sd    = yes|no                 SD (<= 576 lines): deband on with no grain (grain made at 720x480 shows as blobs at
--                                         4.5x); at Smooth also sigmoid-upscaling=no, so bilinear stays a single pass
--   fill         = auto|off               4:3 SD with black bars burnt in, on a wider screen: crop the bars
--   even_film    = auto|off               soft-telecined film on a 24/48/120 Hz display: retime to an even 23.976 fps
-- Defaults = the choice that leaves the GPU the most headroom. Everything below is set as a file-local option in the on_loaded
-- hook, before mpv builds the video chain: the first frame already uses it and nothing carries over to the next file.
--   Deinterlacing: a DVD opened as a folder or ISO is a plain file to mpv, so mpv.conf's [protocol.dvd] profile does not
--     apply; discs and MPEG-2 at <= 576 lines get deinterlace=auto here (a deinterlace=yes set by the user is kept).
--   Film or video: estimated-vf-fps (container-fps reads 31 for a 23.976 soft-telecined DVD), read from 3 s after each
--     start/seek/title change and acted on once the same class has held for 5 s. Starts as film (most SD MPEG-2 is), so a
--     title switches at most once. SD at Balanced/Sharp also scales chroma with the luma filter; Smooth keeps bilinear.
--   Fill: software-decoded SD (MPEG-1/2/4 part 2) whose frame is clearly narrower than the screen. A labelled lavfi
--     cropdetect (a union that only grows) is in the chain from the start; the script keeps that union per title, since
--     mpv rebuilds lavfi graphs on every seek. The bars are cropped (video-crop) once the picture spans the width, each bar
--     is >= 4% of the height, top and bottom are within 16 lines and the result is within 3% of a standard ratio
--     (1.66-2.39), with no material change in the union (> 4 lines or 8 columns) for 45 s of playback: opening credits can
--     hold a steady false band for half a minute. After that the crop widens at once if the union grows; it rounds outward
--     (never cuts into the union) and is lifted while an image subtitle track is selected or a disc menu shows. A title
--     change starts over with a fresh detector. The detector stays in for the whole file (cheap on SD software frames;
--     removing it would rebuild the filter chain).
--   Even film: soft-telecined MPEG-2 keeps 3:2 timestamps (frames alternate 50/33 ms), which a 120 Hz display shows as 6:4.
--     When the title measures as film with repeat-field flags (>= 20% of the frames sampled over 5 s) and the display runs
--     at a whole multiple of 23.976 Hz, lavfi fps=24000/1001 is appended (every frame then lasts 41.7 ms); it comes off if
--     the flags stop, the frames turn interlaced or the class turns video, and stays off for the rest of that title. At
--     60 Hz it would change nothing: skipped.
-- While a film plays:  Alt+c  this folder only: Auto (the app's choices) / Smooth / Balanced / Sharp (a disc is keyed by its
--   own folder, dvd:// by "dvd://")   Alt+f  fill on/off for this file   Alt+m  meter: settings, drops/min, GPU used, °C
-- Hidden, for headless tests only: test_screen=WxH (e.g. 3840x2160) stands in for the window size, which vo=null lacks.
-- Measured on an Orange Pi 5 Plus (KDE, Panthor, mpv 0.42), 60 s runs, 2026-11-13; the numbers are in the app.
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local options = require 'mp.options'

local DEFAULTS = { downscale = "smooth", upscale = "smooth", upscale_film = "balanced", sd_colour = "fast",
                   deband_sd = "yes", fill = "auto", even_film = "auto", test_screen = "" }
local NAMES = { smooth = "Smooth", balanced = "Balanced", sharp = "Sharp" }
local UP   = { smooth = "bilinear", balanced = "spline16", sharp = "spline36" }
local DOWN = { smooth   = { dscale = "bilinear", cd = "no"  },
               balanced = { dscale = "hermite",  cd = "yes" },
               sharp    = { dscale = "lanczos",  cd = "yes" } }
local SD_PRIMARIES = { ["bt.601-525"] = true, ["bt.601-625"] = true, ["bt.470m"] = true }
local IMAGE_SUBS = { dvd_subtitle = true, hdmv_pgs_subtitle = true, dvb_subtitle = true, xsub = true,
                     dvb_teletext = true, arib_caption = true }
local FILL_CODECS = { mpeg1video = true, mpeg2video = true, mpeg4 = true }   -- software-decoded here (not in hwdec-codecs)
local RATIOS = { 1.66, 1.75, 16 / 9, 1.85, 2.0, 2.2, 2.35, 2.39 }
local CROPDETECT = "cropdetect=limit=24/255:round=2:reset=0"
local EVEN_LABEL, EVEN_GRAPH, FILM_FPS = "cinemosk-even", "fps=24000/1001", 24000 / 1001
local SET = { "scale", "dscale", "correct-downscaling", "cscale", "deband", "deband-grain", "sigmoid-upscaling",
              "gamut-mapping-mode" }
local TICK, SAMPLE = 0.5, 0.1          -- s: class/fill/even checks; repeat-flag sampling (0.1 s does not alias with 2 frames)
local FILL_STEADY = 45                 -- s of playback with an unchanged union before the first crop of a title: the
                                       -- opening credits of the 4:3 test disc hold a steady 2.36:1 band for ~32 s

local state_file = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/mpv/cinema-modes.json"
local opts = {}
local overrides = {}        -- folder key -> "smooth"|"balanced"|"sharp" (absent = Auto)
local orig = {}             -- option values before this file's changes (what "not set by Cinemosk" means)
local st = { active = false }
local gen = 0               -- cropdetect generation (a fresh detector per title)
local meter_on, meter_timer = false, nil

local function info(fmt, ...) msg.info("cinemosk: " .. string.format(fmt, ...)) end

local function read_opts()
  local o = {}; for k, v in pairs(DEFAULTS) do o[k] = v end
  options.read_options(o, "cinemosk")
  for _, k in ipairs({ "downscale", "upscale", "upscale_film" }) do
    o[k] = tostring(o[k]):lower(); if not NAMES[o[k]] then o[k] = "smooth" end
  end
  o.sd_colour = tostring(o.sd_colour):lower() == "exact" and "exact" or "fast"
  o.deband_sd = tostring(o.deband_sd):lower() ~= "no"
  o.fill = tostring(o.fill):lower() ~= "off"
  o.even_film = tostring(o.even_film):lower() ~= "off"
  local w, h = tostring(o.test_screen):match("^(%d+)x(%d+)$")
  o.screen = w and { tonumber(w), tonumber(h) } or nil
  return o
end

local function load_overrides()
  overrides = {}
  local f = io.open(state_file, "r"); if not f then return end
  local ok, t = pcall(utils.parse_json, f:read("*a")); f:close()
  if ok and type(t) == "table" then
    for k, v in pairs(t) do local l = tostring(v):lower(); if NAMES[l] then overrides[k] = l end end
  end
end
local function save_overrides()
  local f = io.open(state_file, "w")
  if not f then
    -- a fresh account that has never opened the Cinemosk app has no ~/.config/mpv yet: make it, then retry once
    mp.command_native({name = "subprocess", args = {"mkdir", "-p", (state_file:gsub("/[^/]+$", ""))}, playback_only = false})
    f = io.open(state_file, "w")
  end
  if not f then
    msg.warn("could not save the folder choice to " .. state_file)
    mp.osd_message("Cinemosk: could not save the folder choice", 3)
    return
  end
  f:write(utils.format_json(overrides)); f:close()
end

-- Folder key for Alt+c. KDE's network mount lives in a per-session directory (/run/user/<uid>/kio-fuse-<random>/smb/...):
-- key by the share instead. A disc is keyed by its own root folder (the one holding VIDEO_TS or BDMV, or the loose IFOs)
-- or ISO, so discs that sit side by side keep separate choices; dvd:// and bd:// stay "dvd://" and "bd://".
local function kio(p) return (p:gsub("^/run/user/%d+/kio%-fuse%-[^/]+/", "kio:")) end
local function folder_key(path, disc)
  local proto = path:match("^(%a[%w+.%-]*)://")
  if disc and proto then return proto:lower() .. "://" end
  if disc then
    local p = path:gsub("/+$", "")
    if p:lower():match("%.ifo$") or p:lower():match("%.bdmv$") then p = utils.split_path(p):gsub("/+$", "") end
    local base = (p:match("([^/]+)$") or ""):upper()
    if base == "VIDEO_TS" or base == "BDMV" then p = utils.split_path(p):gsub("/+$", "") end
    if p ~= "" then return kio(p:lower():match("%.iso$") and p or (p .. "/")) end
  end
  local dir = kio(utils.split_path(path))
  return dir ~= "" and dir or "."
end

-- Window size (test_screen in headless tests) and the picture size, which includes video-crop (video-out-params; before the
-- first frame of a file the VO still holds the previous file's values, so the track's own size stands in until then)
local function screen()
  if opts.screen then return opts.screen[1], opts.screen[2] end
  local d = mp.get_property_native("osd-dimensions")
  if d and (d.w or 0) > 0 and (d.h or 0) > 0 then return d.w, d.h end
end
local function out_params()
  if not st.vo_ready then return nil end
  local p = mp.get_property_native("video-out-params")
  if p and (p.w or 0) > 0 and (p.h or 0) > 0 then return p end
end
local function scaling_case()
  local p = out_params()
  local w, h = p and p.dw or st.pdw, p and p.dh or st.pdh
  local ow, oh = screen()
  if not (w and h and ow and oh and w > 0 and h > 0) then return nil end
  local f = math.min(ow / w, oh / h)
  if math.abs(f - 1) < 0.02 then return "none", 1 end
  return f > 1 and "up" or "down", f
end

-- Scalers, chroma, deband and gamut mapping for this file, from the class, the folder override and the source
local function setopt(name, value)
  local cur = mp.get_property(name)
  if cur == value then return false end
  local a, b = tonumber(cur), tonumber(value)
  if a and b and math.abs(a - b) < 1e-6 then return false end
  mp.set_property("file-local-options/" .. name, value)
  return true
end

local function describe(why, changed, show)
  local o = overrides[st.key]
  local case, f = scaling_case()
  st.case, st.factor = case, f
  st.level = case == "up" and st.up or case == "down" and st.down or nil
  local t = st.t
  local label = (o and (NAMES[o] .. " (this folder)") or "Auto") .. (st.level and not o and (" → " .. NAMES[st.level]) or "")
  local what = case == "up" and string.format("enlarged %.1fx with %s", f, t.scale)
            or case == "down" and string.format("reduced to %.0f%% with %s", f * 100, t.dscale)
            or case == "none" and "shown at its own size" or "size not known yet"
  local extra = {}
  if st.sd and t.cscale ~= orig.cscale then extra[#extra + 1] = "chroma " .. t.cscale end
  if t.deband == "yes" and orig.deband ~= "yes" then
    local sig = t["sigmoid-upscaling"] == "no" and orig["sigmoid-upscaling"] ~= "no"
    extra[#extra + 1] = "deband on, no grain" .. (sig and ", sigmoid off" or "")
  end
  if t["gamut-mapping-mode"] == "clip" and orig["gamut-mapping-mode"] ~= "clip" then
    extra[#extra + 1] = "SD colour: fast (gamut clip)"
  end
  st.desc = string.format("%s; picture %s%s", label, what, #extra > 0 and ("; " .. table.concat(extra, "; ")) or "")
  info("%s [%s, %s]%s", st.desc, why, st.class, #changed > 0 and (" set " .. table.concat(changed, " ")) or "")
  if show then mp.osd_message(string.format("Cinemosk: %s\nPicture %s", label, what), 4) end
end

local function apply(why, show)
  if not st.active then return end
  local o = overrides[st.key]
  local up = o or (st.class == "video" and opts.upscale or opts.upscale_film)
  local down = o or opts.downscale
  local t = { scale = UP[up], dscale = DOWN[down].dscale, ["correct-downscaling"] = DOWN[down].cd,
              cscale = (st.sd and up ~= "smooth") and UP[up] or orig.cscale,
              deband = orig.deband, ["deband-grain"] = orig["deband-grain"], ["sigmoid-upscaling"] = orig["sigmoid-upscaling"],
              ["gamut-mapping-mode"] = (opts.sd_colour == "fast" and st.sd_prim) and "clip" or orig["gamut-mapping-mode"] }
  if st.sd and opts.deband_sd then
    t.deband, t["deband-grain"] = "yes", "0"
    if up == "smooth" then t["sigmoid-upscaling"] = "no" end
  end
  local changed = {}
  for _, k in ipairs(SET) do if t[k] and setopt(k, t[k]) then changed[#changed + 1] = k .. "=" .. t[k] end end
  st.t, st.up, st.down = t, up, down
  describe(why, changed, show)
end

-- Video filters for this file: the user's own list, then the fill detector, then the even-film retimer
local function update_vf()
  local l = {}
  for _, f in ipairs(st.vf_base or {}) do l[#l + 1] = f end
  if st.fill.det then l[#l + 1] = { name = "lavfi", label = st.fill.det, enabled = true, params = { graph = CROPDETECT } } end
  if st.even.on then l[#l + 1] = { name = "lavfi", label = EVEN_LABEL, enabled = true, params = { graph = EVEN_GRAPH } } end
  local sig = utils.format_json(l)
  if sig == st.vf_sig then return end
  st.vf_sig = sig
  if #l == 0 then mp.set_property("file-local-options/vf", "") else mp.set_property_native("file-local-options/vf", l) end
end

-- Fill: crop black bars burnt into a 4:3 SD frame
local function fill_blocked()
  if not st.fill.want then return "off for this file (Alt+f)" end
  if mp.get_property_bool("disc-menu-active", false) then return "a disc menu is showing" end
  for _, k in ipairs({ "current-tracks/sub/codec", "current-tracks/sub2/codec" }) do
    local c = mp.get_property(k)
    if c and IMAGE_SUBS[c] then return "image subtitles (" .. c .. ") are selected" end
  end
end

-- crop for the cropdetect union u, or nil + a reason code and text
local function crop_for(u)
  local p = out_params()
  if not p then return nil, "frame", "no frame yet" end
  local W, H, par = p.w, p.h, (p.par and p.par > 0) and p.par or 1
  local sw, sh = screen()
  if not sw then return nil, "screen", "window size not known" end
  local far = W * par / H
  if far >= 0.9 * sw / sh then
    return nil, "wide", string.format("the %.2f:1 frame is not clearly narrower than the %.2f:1 screen", far, sw / sh)
  end
  if not u then return nil, "empty", "no picture seen yet" end
  local top, bottom, left, right = u.y1, H - 1 - u.y2, u.x1, W - 1 - u.x2
  if left > 0.04 * W or right > 0.04 * W then
    return nil, "width", string.format("picture does not span the width yet (%d/%d columns free)", left, right)
  end
  if top < 0.04 * H or bottom < 0.04 * H then
    return nil, "bars", string.format("bars of %d/%d lines are under 4%% of the height", top, bottom)
  end
  if math.abs(top - bottom) > 16 then return nil, "centre", string.format("bars of %d/%d lines are not centred", top, bottom) end
  local x0, y0 = u.x1 - u.x1 % 2, u.y1 - u.y1 % 2                 -- round outward to even: never cut picture
  local x1, y1 = math.min(W, u.x2 + 1 + (u.x2 + 1) % 2), math.min(H, u.y2 + 1 + (u.y2 + 1) % 2)
  local cw, ch = x1 - x0, y1 - y0
  local ar, best = cw * par / ch, nil
  for _, r in ipairs(RATIOS) do if not best or math.abs(ar / r - 1) < math.abs(ar / best - 1) then best = r end end
  if math.abs(ar / best - 1) > 0.03 then
    return nil, "ratio", string.format("%.2f:1 is not within 3%% of a standard ratio", ar)
  end
  return string.format("%dx%d+%d+%d", cw, ch, x0, y0), "ok",
         string.format("bars %d/%d lines, %.2f:1 (standard %.2f:1)", top, bottom, ar, best)
end

local function fill_check(dt)
  local F = st.fill
  if not F.det or F.swap then return end
  -- mpv rebuilds a lavfi graph on every seek, which empties cropdetect's union: keep the union here, per title
  local m = mp.get_property_native("vf-metadata/" .. F.det)
  if type(m) == "table" then
    local x1, x2 = tonumber(m["lavfi.cropdetect.x1"]), tonumber(m["lavfi.cropdetect.x2"])
    local y1, y2 = tonumber(m["lavfi.cropdetect.y1"]), tonumber(m["lavfi.cropdetect.y2"])
    if x1 and x2 and y1 and y2 and x2 >= x1 and y2 >= y1 then
      local a = F.acc
      F.acc = a and { x1 = math.min(a.x1, x1), y1 = math.min(a.y1, y1), x2 = math.max(a.x2, x2), y2 = math.max(a.y2, y2) }
              or { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    end
  end
  local u, r = F.acc, F.ref
  local ukey = u and string.format("%d,%d-%d,%d", u.x1, u.y1, u.x2, u.y2)
  F.ukey = ukey
  -- the wait restarts only on a material change (a false band from credits differs by dozens of lines); 1-2 px of creep
  -- at the edges does not restart it, though the crop still follows it
  if u and (not r or math.abs(u.y1 - r.y1) > 4 or math.abs(u.y2 - r.y2) > 4 or math.abs(u.x1 - r.x1) > 8
            or math.abs(u.x2 - r.x2) > 8) then
    F.ref, F.steady = { x1 = u.x1, y1 = u.y1, x2 = u.x2, y2 = u.y2 }, 0
  else F.steady = F.steady + dt end
  local geom, code, text = crop_for(u)
  if geom and F.steady >= FILL_STEADY then F.confident = true end   -- from then on a growing union widens the crop at once
  local blocked = fill_blocked()
  local want = (F.confident and geom and not blocked) and geom or nil
  local said = false
  if want ~= F.crop then
    local was = F.crop
    F.crop, said = want, true
    mp.set_property("file-local-options/video-crop", want or "")
    if want and was then info("fill: union grew to %s, crop widened %s -> %s (%s)", ukey, was, want, text)
    elseif want and F.applied then info("fill: video-crop=%s again (%s)", want, text)
    elseif want then info("fill: video-crop=%s after %d s without a material change (union %s; %s)", want, FILL_STEADY, ukey, text)
    else info("fill: crop lifted (%s)", blocked or text) end
    F.applied = F.applied or want ~= nil
  end
  local rcode = blocked and ("held:" .. blocked) or F.crop and "applied" or geom and "measuring" or code
  if rcode ~= F.rcode then
    F.rcode = rcode
    if not said and rcode ~= "applied" then
      info("fill: %s", blocked and ("held, " .. blocked) or geom and
        string.format("candidate %s (%s), waiting for %d s without a material change", geom, text, FILL_STEADY) or text)
    end
  end
  F.state = F.crop and ("fill " .. F.crop) or not F.want and "fill off"
            or blocked and ("fill held (" .. (blocked:match("subtitles") and "subtitles" or "menu") .. ")") or "fill: looking"
end

-- Even film: repeat-field flags sampled from the shown frame; on once per title when the class settles as film
local function even_display()
  local d = mp.get_property_number("display-fps")
  if not d or d <= 0 then return false, "display rate not known" end
  local n = math.floor(d / FILM_FPS + 0.5)
  if n >= 1 and math.abs(d - n * FILM_FPS) / d < 0.01 then return true, string.format("display %.2f Hz = %d x 23.976", d, n) end
  return false, string.format("display %.2f Hz has no even cadence for 23.976 fps", d)
end
local function telecine_ratio()
  local E, n = st.even, 0
  for _, r in ipairs(E.win) do if r then n = n + 1 end end
  return #E.win > 0 and n / #E.win or 0, #E.win
end
local function update_even(why)
  local E = st.even
  if not (E.elig and st.confirmed) then return end
  local ratio, n = telecine_ratio()
  local fps = mp.get_property_number("estimated-vf-fps") or 0
  local want, text
  if st.class ~= "film" then want, text = false, "not film rate"
  elseif mp.get_property_bool("disc-menu-active", false) then want, text = false, "a disc menu is showing"
  elseif mp.get_property_bool("deinterlace-active", false) then want, text = false, "frames are interlaced"
  elseif E.on then
    if n >= 50 and ratio < 0.05 then want, text, E.hold = false, "repeat flags stopped; off for the rest of this title", true
    else want, text = even_display() end
  elseif E.hold then want, text = false, "held off for this title"
  elseif n < 30 or ratio < 0.2 or fps < 23.5 or fps > 24.5 then
    want, text = false, string.format("not soft telecine (repeat flag on %.0f%% of %d samples, %.3f fps)", ratio * 100, n, fps)
  else want, text = even_display() end
  if want ~= E.on or E.text == nil then
    local was = E.on
    E.on, E.text = want, text
    if want ~= was then update_vf() end
    info("even_film: %s (%s; %s)", want and "on, lavfi fps=24000/1001 appended" or (was and "off, retimer removed" or "off"),
         text, why)
  end
end
local function sample_repeat()
  if not st.active or not st.even.elig or mp.get_property_bool("core-idle", true) then return end   -- paused: same frame
  local r = mp.get_property_native("video-frame-info/repeat")
  if r == nil then return end
  local w = st.even.win
  w[#w + 1] = r == true
  if #w > 50 then table.remove(w, 1) end
end

-- Film or video class from the measured frame rate
local function class_check(dt)
  if mp.get_property_bool("disc-menu-active", false) then return end
  st.since = st.since + dt
  if st.since < 3 then return end
  local fps = mp.get_property_number("estimated-vf-fps")
  if not fps or fps <= 0 then return end
  local c = fps <= 31 and "film" or "video"
  if c ~= st.cand then st.cand, st.held = c, 0; return end
  st.held = st.held + dt
  if st.held >= 5 and (c ~= st.class or not st.confirmed) then
    local old, first = st.class, not st.confirmed
    st.class, st.confirmed = c, true
    if c ~= old then
      info("class %s -> %s (estimated %.3f fps for 5 s)", old, c, fps)
      apply("class " .. c)
    else info("class %s confirmed (estimated %.3f fps for 5 s)", c, fps) end
    if first or c ~= old then update_even("class " .. c) end
  end
end

local function tick()
  if not st.active then return end
  -- after a title change, one filter update once the edition has held for 0.75 s (it can flip 0 -> -1 -> 1 -> 0 in a second)
  if st.vf_due and mp.get_time() - st.vf_due >= 0.75 then
    st.vf_due = nil
    if st.fill.swap then
      gen = gen + 1; st.fill.det, st.fill.swap = "cinemosk-crop" .. gen, nil
      info("fill: fresh detector @%s", st.fill.det)
    end
    update_vf()
  end
  local dt = mp.get_property_bool("core-idle", true) and 0 or TICK
  class_check(dt)
  fill_check(dt)
  if st.even.elig and st.confirmed then update_even("watch") end   -- e.g. a title that opens with a 30 fps logo
end
local tick_timer = mp.add_periodic_timer(TICK, tick); tick_timer:kill()
local sample_timer = mp.add_periodic_timer(SAMPLE, sample_repeat); sample_timer:kill()

local function on_loaded()
  tick_timer:kill(); sample_timer:kill()
  opts = read_opts(); load_overrides()
  local vt = mp.get_property_native("current-tracks/video")
  local path = mp.get_property("path") or ""
  local demuxer = mp.get_property("current-demuxer") or ""
  st = { active = false, fill = {}, even = { win = {} } }
  if type(vt) ~= "table" or vt.image or vt.albumart then return end
  for _, k in ipairs(SET) do orig[k] = mp.get_property(k) end
  local codec, w, h = vt.codec or "?", vt["demux-w"], vt["demux-h"]
  local par = (vt["demux-par"] or 0) > 0 and vt["demux-par"] or 1
  local fps = vt["demux-fps"]
  st.active, st.disc, st.codec, st.vo_ready = true, demuxer == "disc", codec, false
  st.key = folder_key(path, st.disc)
  st.sd = h ~= nil and h <= 576
  st.sd_prim = st.sd                                   -- mpv's guess for untagged SD; corrected from video-params below
  if w and h then st.pdw, st.pdh = par > 1 and math.floor(w * par + 0.5) or w, par < 1 and math.floor(h / par + 0.5) or h end
  st.class = (st.disc or (st.sd and codec:match("^mpeg[12]video$")) or not fps or fps <= 31) and "film" or "video"
  st.confirmed, st.cand, st.held, st.since = false, nil, 0, 0
  st.edition = mp.get_property_number("current-edition")
  st.vf_base = mp.get_property_native("vf") or {}
  st.vf_sig = utils.format_json(st.vf_base)
  info("start: %s %sx%s %s%s, folder key %q, class %s (start guess: %s)", codec, tostring(w), tostring(h),
       st.disc and "disc" or demuxer, fps and string.format(" %.3f fps", fps) or "", st.key, st.class,
       fps and string.format("container %.3f fps", fps) or "no container rate")
  -- deinterlace before the chain is built
  if st.disc or (codec == "mpeg2video" and st.sd) then
    local di = mp.get_property("deinterlace")
    if di == "no" then
      mp.set_property("file-local-options/deinterlace", "auto")
      info("deinterlace=auto (%s; mpv.conf's [protocol.dvd] profile only covers dvd:// URLs)",
           st.disc and "disc opened as " .. (path:match("^%a[%w+.%-]*://") and "a URL" or "a folder or ISO") or "SD MPEG-2")
    else info("deinterlace=%s kept (already set)", di) end
  end
  apply("start")
  -- fill: detector added now, so the chain is built with it (no reinit later)
  local F = st.fill
  local hw, hc = mp.get_property("hwdec") or "no", "," .. (mp.get_property("hwdec-codecs") or "") .. ","
  if not FILL_CODECS[codec] then F.why = codec .. " is not MPEG-1/2/4 part 2 video"
  elseif not st.sd then F.why = "not standard definition"
  elseif hw ~= "no" and (hc == ",all," or hc:find("," .. codec .. ",", 1, true)) then F.why = codec .. " may be hardware-decoded"
  elseif w and h and w * par / h >= 1.6 then F.why, F.wide = string.format("the frame is already %.2f:1", w * par / h), true
  else F.elig = true end
  F.want, F.steady, F.confident = F.elig and opts.fill or false, 0, false
  if F.want then gen = gen + 1; F.det = "cinemosk-crop" .. gen end
  info("fill: %s", F.det and ("detector @" .. F.det .. " added (" .. CROPDETECT .. ")")
                    or (F.elig and "off (fill=off; Alt+f turns it on)") or ("not used: " .. F.why))
  F.state = F.det and "fill: looking" or (F.elig and "fill off" or "fill n/a")
  -- even film: soft telecine only exists in MPEG-2; decided once the class settles
  local E = st.even
  E.elig = opts.even_film and codec == "mpeg2video" and st.sd
  info("even_film: %s", E.elig and "watching the repeat-field flags; decided when the class settles"
       or not opts.even_film and "off (even_film=off)" or ("not used: " .. codec .. " is not SD MPEG-2"))
  update_vf()
  tick_timer:resume()
  if E.elig then sample_timer:resume() end
end

local function on_restart()
  if not st.active then return end
  local first = not st.vo_ready
  st.vo_ready = true
  st.since, st.cand, st.held = 0, nil, 0          -- estimated-vf-fps starts over after a seek or title jump
  st.even.win = {}
  if first then describe("first frame", {}) end
end

local function on_title(_, e)
  if not st.active or e == nil or e == st.edition then return end
  local old = st.edition
  st.edition = e
  info("title change (edition %s -> %s): class, fill and even_film start over", tostring(old), tostring(e))
  st.since, st.cand, st.held, st.confirmed = 0, nil, 0, false
  local F = st.fill
  if F.crop then F.crop = nil; mp.set_property("file-local-options/video-crop", ""); info("fill: crop lifted (title change)") end
  F.acc, F.ref, F.ukey, F.steady, F.confident, F.rcode, F.applied = nil, nil, nil, 0, false, nil, nil
  if F.det then F.swap, F.state = true, F.want and "fill: looking" or "fill off" end   -- a union cannot be emptied: replace it
  if st.even.on then st.even.on = false; info("even_film: off, retimer removed (title change)") end
  st.even.win, st.even.text, st.even.hold = {}, nil, nil
  st.vf_due = mp.get_time()
end

local function on_end()
  tick_timer:kill(); sample_timer:kill()
  st.active = false
end

local function cycle()
  if not st.active then return end
  local order = { "auto", "smooth", "balanced", "sharp" }
  local cur = overrides[st.key] or "auto"
  local i = 1; for k, v in ipairs(order) do if v == cur then i = k end end
  local nxt = order[i % #order + 1]
  load_overrides()
  overrides[st.key] = nxt ~= "auto" and nxt or nil
  save_overrides(); apply("Alt+c", true)
end

local function toggle_fill()
  if not st.active then return end
  local F = st.fill
  if not F.elig and F.wide then                   -- judged wide at the start; the title now showing may be 4:3
    local p = out_params()
    if p and p.w * ((p.par and p.par > 0) and p.par or 1) / p.h < 1.6 then F.elig, F.why = true, nil end
  end
  if F.want then
    F.want = false
    info("fill: off for this file (Alt+f)")
    fill_check(0)
    mp.osd_message("Cinemosk: Fill off for this film", 3)
  elseif not F.elig then
    info("fill: Alt+f ignored, %s", F.why or "not available")
    mp.osd_message("Cinemosk: Fill is for standard-definition MPEG video in a 4:3 frame\n(" .. (F.why or "") .. ")", 4)
  else
    F.want = true
    if not F.det then
      gen = gen + 1; F.det = "cinemosk-crop" .. gen; update_vf()
      info("fill: on (Alt+f), detector @%s added", F.det)
    else info("fill: on (Alt+f)") end
    fill_check(0)
    mp.osd_message(F.crop and ("Cinemosk: Fill on (" .. F.crop .. ")") or "Cinemosk: Fill on, looking for black bars", 3)
  end
end

-- GPU load: devfreq "load" reads "<busy %>@<Hz>"; used = busy x clock / max clock = share of the GPU's full capacity
local function devfreq_dir()
  for _, d in ipairs({ "/sys/class/devfreq/fb000000.gpu-panthor", "/sys/class/devfreq/fb000000.gpu" }) do
    local f = io.open(d .. "/load", "r"); if f then f:close(); return d end
  end
end
local GPU = devfreq_dir()
local function read_line(p) local f = io.open(p, "r"); if not f then return nil end; local s = f:read("*l"); f:close(); return s end
local function gpu_used()
  if not GPU then return nil end
  local busy, hz = (read_line(GPU .. "/load") or ""):match("^(%d+)@(%d+)")
  local max = tonumber(read_line(GPU .. "/max_freq") or "")
  if not (busy and hz and max and max > 0) then return nil end
  return tonumber(busy) * tonumber(hz) / max, tonumber(hz) / 1e6
end

-- Meter: the picture settings in effect, then drops per minute and GPU use over the last 30 s (a 2 s window overstates
-- bursts), plus the total
local function picture_line()
  if not st.active or not st.t then return "no film playing" end
  local t = st.t
  local filt = st.case == "down" and t.dscale or st.case == "up" and t.scale or "no scaling"
  local chroma = st.sd and t.cscale ~= orig.cscale and (", chroma " .. t.cscale) or ""
  return string.format("%s · %s%s%s · %s · deband %s%s",
    st.level and NAMES[st.level] or "no scaling", st.class, st.confirmed and "" or "?",
    st.case and (" · " .. filt .. chroma) or "", st.fill.state or "fill n/a", t.deband == "yes" and "on" or "off",
    st.even.on and " · even 23.976" or "")
end
local hist = {}
local function meter()
  local d = mp.get_property_number("frame-drop-count") or 0
  local t = mp.get_time(); local u, mhz = gpu_used()
  hist[#hist + 1] = { t, d, u or 0 }
  while #hist > 1 and t - hist[1][1] > 30 do table.remove(hist, 1) end
  local span = t - hist[1][1]
  local per_min = span >= 5 and (d - hist[1][2]) * 60 / span or nil
  local usum = 0; for _, s in ipairs(hist) do usum = usum + s[3] end
  local temp = tonumber(read_line("/sys/class/thermal/thermal_zone0/temp") or "")
  mp.osd_message(string.format("%s\n%s · %d dropped so far · GPU %s · %s", picture_line(),
    per_min and string.format("%.0f drops/min (last %ds)", per_min, math.floor(span)) or "measuring…", d,
    u and string.format("%d%% used (%d MHz)", math.floor(usum / #hist + 0.5), math.floor(mhz)) or "n/a",
    temp and string.format("%d °C", math.floor(temp / 1000)) or "n/a"), 2.5)
end
local function toggle_meter()
  meter_on = not meter_on
  if meter_on then hist = {}; meter(); meter_timer = mp.add_periodic_timer(2, meter)
  else if meter_timer then meter_timer:kill(); meter_timer = nil end; mp.osd_message("") end
end

mp.add_hook("on_loaded", 50, on_loaded)
mp.register_event("playback-restart", on_restart)
mp.register_event("end-file", on_end)
mp.observe_property("video-out-params", "native", function()
  if not (st.active and st.vo_ready and st.t) then return end
  local case, f = scaling_case()
  if case ~= st.case or (f and st.factor and math.abs(f / st.factor - 1) > 0.02) then describe("picture size", {}) end
end)
mp.observe_property("osd-dimensions", "native", function()
  if st.active and st.t then
    local case, f = scaling_case()
    if case ~= st.case or (f and st.factor and math.abs(f / st.factor - 1) > 0.02) then describe("window size", {}) end
  end
end)
mp.observe_property("video-params", "native", function(_, p)
  if not (st.active and st.t and type(p) == "table" and p.h and p.primaries) then return end
  local sd, sdp = p.h <= 576, p.primaries ~= nil and SD_PRIMARIES[p.primaries] == true
  if sd ~= st.sd or sdp ~= st.sd_prim then
    st.sd, st.sd_prim = sd, sdp
    apply(string.format("decoded %dx%d %s", p.w or 0, p.h, p.primaries or "?"))
  end
end)
mp.observe_property("current-edition", "number", on_title)
mp.observe_property("disc-menu-active", "bool", function() if st.active then fill_check(0); update_even("disc menu") end end)
mp.observe_property("current-tracks/sub/codec", "string", function() if st.active then fill_check(0) end end)
mp.observe_property("current-tracks/sub2/codec", "string", function() if st.active then fill_check(0) end end)
mp.observe_property("display-fps", "number", function() if st.active and st.confirmed then update_even("display rate") end end)
mp.add_key_binding("Alt+c", "cinema-cycle", cycle)
mp.add_key_binding("Alt+f", "cinema-fill", toggle_fill)
mp.add_key_binding("Alt+m", "cinema-meter", toggle_meter)
