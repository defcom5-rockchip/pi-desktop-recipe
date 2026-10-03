#!/usr/bin/env python3
# make-logo.py -- Pi-Desktop "Plaid" logo generator (SVG + PNG renders + Plymouth images + preview sheet).
#
# Artwork (c) 2026 defcom5-rockchip, licensed CC BY-SA 4.0.
#
# The logo is the Plaid tartan swatch from the fastfetch terminal art (plaid_logo.py: same palette, same
# sett, same soft 2/2 twill) inside the rounded square used by the installer icons, with a large cream
# pi glyph in front.  The pi outline is taken straight out of DejaVu Sans Bold's TrueType 'glyf' table
# and written as an SVG <path>, so the SVG needs no font at render time.
#
# Usage:  python3 make-logo.py [OUTDIR]        (default: the directory this script lives in)
# Needs:  python3, python3-pil, python3-gi + gir1.2-rsvg-2.0 + python3-cairo (librsvg renderer).
#         fontTools is used for the glyph if importable; otherwise the small built-in TrueType reader below
#         is used (both give the identical outline for this glyph).  xmllint is used for validation if present.
import math
import os
import shutil
import struct
import subprocess
import sys

OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
PI = 0x03C0

# ---- palette and sett (identical to plaid_logo.py) ---------------------------------------------------
CHAR, ORNG, CREAM, BLUE = '#1C1B1A', '#E85020', '#F3E2B8', '#21418C'
# sett from the pivot (centre thread) outward: thread colour, count -- mirrored about the centre
SETT = [(CHAR, 3), (BLUE, 1), (CHAR, 3), (ORNG, 3), (CHAR, 1), (CREAM, 1), (CHAR, 1), (ORNG, 3), (CHAR, 3)]
TWILL_HI, TWILL_LO = 0.68, 0.32            # warp share inside / outside the twill diagonal (plaid_logo.py)

# ---- geometry (viewBox 0 0 64 64, tile = installer-icon rounded square) ---------------------------------
TILE_X, TILE_W, TILE_R = 4.0, 56.0, 12.0   # <rect x=4 y=4 width=56 height=56 rx=12>
CX = TILE_X + TILE_W / 2                   # 32
THREADS = 2 * sum(n for _, n in SETT) - 1  # 37: one full sett, pivot thread centred
TW = TILE_W / THREADS                      # thread width in viewBox units (~1.514)
PI_WIDTH = 36.0                            # pi glyph width in viewBox units
PI_DY = 0.0                                # optical vertical nudge (+ = down)
RIM = 1.25                                 # dark rim around the pi, in viewBox units
RIM_DIRS = 16                              # offset copies used to build the rim
PNG_SIZES = (16, 22, 24, 32, 48, 64, 128, 256, 512)


def f(v):
    """Compact number formatting for SVG."""
    s = f'{v:.3f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


# ---- glyph outline -------------------------------------------------------------------------------------
def glyph_contours_fonttools(path, cp):
    from fontTools.ttLib import TTFont
    font = TTFont(path)
    name = font.getBestCmap()[cp]
    glyf = font['glyf']
    coords, ends, flags = glyf[name].getCoordinates(glyf)
    pts = [(x, y, bool(fl & 1)) for (x, y), fl in zip(coords, flags)]
    out, s = [], 0
    for e in ends:
        out.append(pts[s:e + 1])
        s = e + 1
    return out, font['head'].unitsPerEm


def glyph_contours_builtin(path, cp):
    """Minimal TrueType reader: cmap(4/12) -> loca -> glyf, simple glyphs only."""
    data = open(path, 'rb').read()
    n_tables = struct.unpack('>H', data[4:6])[0]
    tables = {}
    for i in range(n_tables):
        tag, _cs, off, ln = struct.unpack('>4sIII', data[12 + 16 * i:28 + 16 * i])
        tables[tag.decode('latin1')] = data[off:off + ln]
    head, maxp, cmap, loca, glyf = (tables[t] for t in ('head', 'maxp', 'cmap', 'loca', 'glyf'))
    upem = struct.unpack('>H', head[18:20])[0]
    long_loca = struct.unpack('>h', head[50:52])[0] == 1
    n_glyphs = struct.unpack('>H', maxp[4:6])[0]

    def cmap_lookup():
        for i in range(struct.unpack('>H', cmap[2:4])[0]):
            _pid, _eid, off = struct.unpack('>HHI', cmap[4 + 8 * i:12 + 8 * i])
            fmt = struct.unpack('>H', cmap[off:off + 2])[0]
            if fmt == 4:
                seg2 = struct.unpack('>H', cmap[off + 6:off + 8])[0]
                seg = seg2 // 2
                ends = struct.unpack(f'>{seg}H', cmap[off + 14:off + 14 + seg2])
                starts = struct.unpack(f'>{seg}H', cmap[off + 16 + seg2:off + 16 + 2 * seg2])
                deltas = struct.unpack(f'>{seg}h', cmap[off + 16 + 2 * seg2:off + 16 + 3 * seg2])
                ro_base = off + 16 + 3 * seg2
                ros = struct.unpack(f'>{seg}H', cmap[ro_base:ro_base + seg2])
                for k in range(seg):
                    if starts[k] <= cp <= ends[k]:
                        if ros[k] == 0:
                            return (cp + deltas[k]) & 0xFFFF
                        a = ro_base + 2 * k + ros[k] + 2 * (cp - starts[k])
                        g = struct.unpack('>H', cmap[a:a + 2])[0]
                        return (g + deltas[k]) & 0xFFFF if g else 0
            elif fmt == 12:
                n_groups = struct.unpack('>I', cmap[off + 12:off + 16])[0]
                for k in range(n_groups):
                    s, e, g = struct.unpack('>III', cmap[off + 16 + 12 * k:off + 28 + 12 * k])
                    if s <= cp <= e:
                        return g + (cp - s)
        return 0

    gid = cmap_lookup()
    if not gid:
        raise SystemExit(f'U+{cp:04X} not in {path}')
    if long_loca:
        offs = struct.unpack(f'>{n_glyphs + 1}I', loca[:4 * (n_glyphs + 1)])
    else:
        offs = [2 * v for v in struct.unpack(f'>{n_glyphs + 1}H', loca[:2 * (n_glyphs + 1)])]
    g = glyf[offs[gid]:offs[gid + 1]]
    nc = struct.unpack('>h', g[:2])[0]
    if nc < 0:
        raise SystemExit('composite glyph: not handled by the built-in reader (install fontTools)')
    ends = struct.unpack(f'>{nc}H', g[10:10 + 2 * nc])
    p = 10 + 2 * nc
    p += 2 + struct.unpack('>H', g[p:p + 2])[0]          # skip instructions
    npts = ends[-1] + 1
    flags = []
    while len(flags) < npts:
        fl = g[p]
        p += 1
        flags.append(fl)
        if fl & 8:
            rep = g[p]
            p += 1
            flags.extend([fl] * rep)
    xs, v = [], 0
    for fl in flags:
        if fl & 2:
            d = g[p]
            p += 1
            v += d if fl & 16 else -d
        elif not fl & 16:
            v += struct.unpack('>h', g[p:p + 2])[0]
            p += 2
        xs.append(v)
    ys, v = [], 0
    for fl in flags:
        if fl & 4:
            d = g[p]
            p += 1
            v += d if fl & 32 else -d
        elif not fl & 32:
            v += struct.unpack('>h', g[p:p + 2])[0]
            p += 2
        ys.append(v)
    pts = [(xs[i], ys[i], bool(flags[i] & 1)) for i in range(npts)]
    out, s = [], 0
    for e in ends:
        out.append(pts[s:e + 1])
        s = e + 1
    return out, upem


def glyph_contours(path, cp):
    try:
        import fontTools  # noqa: F401
        return glyph_contours_fonttools(path, cp), 'fontTools'
    except ImportError:
        return glyph_contours_builtin(path, cp), 'built-in TrueType reader'


def contours_to_path(contours, tf):
    """TrueType quadratic contours -> absolute SVG path (M/L/Q/Z), implied on-curve midpoints expanded."""
    cmds = []
    for pts in contours:
        if not any(on for _, _, on in pts):      # all off-curve: synthesise a start point
            mx, my = (pts[0][0] + pts[-1][0]) / 2, (pts[0][1] + pts[-1][1]) / 2
            pts = [(mx, my, True)] + pts
        k = next(i for i, p in enumerate(pts) if p[2])
        pts = pts[k:] + pts[:k]
        x0, y0 = tf(pts[0][0], pts[0][1])
        cmds.append(f'M{f(x0)} {f(y0)}')
        ctrl = None
        for x, y, on in pts[1:] + [pts[0]]:
            X, Y = tf(x, y)
            if on:
                cmds.append(f'L{f(X)} {f(Y)}' if ctrl is None else f'Q{f(ctrl[0])} {f(ctrl[1])} {f(X)} {f(Y)}')
                ctrl = None
            else:
                if ctrl is not None:
                    cmds.append(f'Q{f(ctrl[0])} {f(ctrl[1])} {f((ctrl[0] + X) / 2)} {f((ctrl[1] + Y) / 2)}')
                ctrl = (X, Y)
        cmds.append('Z')
    return ''.join(cmds)


def pi_path():
    (contours, upem), how = glyph_contours(FONT, PI)
    xs = [x for c in contours for x, _, _ in c]
    ys = [y for c in contours for _, y, _ in c]
    bx0, bx1, by0, by1 = min(xs), max(xs), min(ys), max(ys)
    s = PI_WIDTH / (bx1 - bx0)
    gcx, gcy = (bx0 + bx1) / 2, (by0 + by1) / 2

    def tf(x, y):                                   # font units -> viewBox (y flipped), centred on the tile
        return CX + (x - gcx) * s, CX + PI_DY - (y - gcy) * s

    d = contours_to_path(contours, tf)
    print(f'pi glyph: {how}, {len(contours)} contour(s), bbox {(bx1 - bx0) * s:.1f} x {(by1 - by0) * s:.1f} units')
    return d


# ---- tartan ---------------------------------------------------------------------------------------------
def bands():
    """Thread bands across the tile as (start, end, colour) in viewBox units, pivot centred at CX."""
    half, t = [], 0.0                               # (t0, t1, colour) outward from the centre, in threads
    for i, (colour, n) in enumerate(SETT):
        t1 = t + n - (0.5 if i == 0 else 0)         # the pivot thread straddles the centre: half of it per side
        half.append((t, t1, colour))
        t = t1
    _, t1, c = half[0]
    out = [(CX - t1 * TW, CX + t1 * TW, c)]         # pivot band as one rect
    for t0, t1, c in half[1:]:                      # every other band mirrored about the centre
        out.append((CX - t1 * TW, CX - t0 * TW, c))
        out.append((CX + t0 * TW, CX + t1 * TW, c))
    out.sort()
    return out


def twill_clip_path():
    """Union of 45-degree bands where the warp is on top: ((x-CX)+(y-CX))/TW mod 4 in [0,2)."""
    period, width = 4 * TW, 2 * TW
    lo, hi = TILE_X, TILE_X + TILE_W
    sub = []
    k = math.floor((2 * lo - 2 * CX) / period) - 1
    while True:
        c = 2 * CX + k * period                     # band: c <= x + y < c + width
        if c > 2 * hi:
            break
        # parallelogram between the lines x+y=c and x+y=c+width, spanning y = lo..hi (clipped later by the tile)
        sub.append(f'M{f(c - lo)} {f(lo)}h{f(width)}L{f(c + width - hi)} {f(hi)}h{f(-width)}Z')
        k += 1
    return ''.join(sub)


def build_svg():
    b = bands()
    tile = f'x="{f(TILE_X)}" y="{f(TILE_X)}" width="{f(TILE_W)}" height="{f(TILE_W)}" rx="{f(TILE_R)}"'
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!-- Pi-Desktop "Plaid" logo. Artwork (c) 2026 defcom5-rockchip, CC BY-SA 4.0.',
        '     Generated by make-logo.py: tartan sett + palette from the fastfetch art (plaid_logo.py),',
        '     rounded square from the installer icons, pi outline from DejaVu Sans Bold converted to a path.',
        '     Filled shapes only, no strokes, no filters, no fonts, no external references. -->',
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="64" height="64" viewBox="0 0 64 64">',
        '  <defs>',
        f'    <clipPath id="rr"><rect {tile}/></clipPath>',
        f'    <clipPath id="tw"><path d="{twill_clip_path()}"/></clipPath>',
        f'    <path id="pi" d="{pi_path()}"/>',
        '  </defs>',
        f'  <rect {tile} fill="{CHAR}"/>',
        '  <g clip-path="url(#rr)">',
    ]
    # weft (horizontal threads): opaque, the charcoal base rect already covers the CHAR bands
    for a, z, c in b:
        if c != CHAR:
            lines.append(f'    <rect x="{f(TILE_X)}" y="{f(a)}" width="{f(TILE_W)}" height="{f(z - a)}" fill="{c}"/>')
    # warp (vertical threads): a translucent layer everywhere + a second one inside the twill diagonals,
    # so the warp share is TWILL_HI on the diagonal and TWILL_LO between (the soft twill of plaid_logo.py)
    a_lo = TWILL_LO
    a_hi = 1 - (1 - TWILL_HI) / (1 - TWILL_LO)
    for alpha, open_tag in ((a_lo, None), (a_hi, '    <g clip-path="url(#tw)">')):
        if open_tag:
            lines.append(open_tag)
        ind = '      ' if open_tag else '    '
        for a, z, c in b:
            lines.append(f'{ind}<rect x="{f(a)}" y="{f(TILE_X)}" width="{f(z - a)}" height="{f(TILE_W)}" '
                         f'fill="{c}" fill-opacity="{f(alpha)}"/>')
        if open_tag:
            lines.append('    </g>')
    lines.append('  </g>')
    # pi: dark rim built from offset copies (filled shapes, no stroke), then the cream glyph
    lines.append(f'  <g fill="{CHAR}">')
    for i in range(RIM_DIRS):
        ang = 2 * math.pi * i / RIM_DIRS
        lines.append(f'    <use xlink:href="#pi" x="{f(RIM * math.cos(ang))}" y="{f(RIM * math.sin(ang))}"/>')
    lines.append('  </g>')
    lines.append(f'  <use xlink:href="#pi" fill="{CREAM}"/>')
    lines.append('</svg>')
    return '\n'.join(lines) + '\n'


# ---- rendering ------------------------------------------------------------------------------------------
def renderer():
    try:
        import gi
        gi.require_version('Rsvg', '2.0')
        gi.require_foreign('cairo')                 # lets Rsvg accept a pycairo Context (python3-gi-cairo)
        from gi.repository import Rsvg
        import cairo

        def render(svg, size, out):
            h = Rsvg.Handle.new_from_file(svg)
            surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
            vp = Rsvg.Rectangle()
            vp.x, vp.y, vp.width, vp.height = 0, 0, size, size
            h.render_document(cairo.Context(surf), vp)
            surf.flush()
            surf.write_to_png(out)
        return render, f'librsvg {Rsvg.MAJOR_VERSION}.{Rsvg.MINOR_VERSION}.{Rsvg.MICRO_VERSION} via python3-gi + cairo'
    except (ImportError, ValueError):
        pass
    try:                                            # same librsvg, without the pycairo bridge (python3-gi-cairo)
        import re
        import warnings
        import gi
        gi.require_version('Rsvg', '2.0')
        gi.require_version('GdkPixbuf', '2.0')
        from gi.repository import Rsvg

        def render(svg, size, out):
            data = open(svg, 'rb').read()           # librsvg renders at the root width/height: retarget them
            data = re.sub(rb'width="64" height="64"', b'width="%d" height="%d"' % (size, size), data, count=1)
            with warnings.catch_warnings():
                warnings.simplefilter('ignore')     # Handle.get_pixbuf() is deprecated but fine
                pb = Rsvg.Handle.new_from_data(data).get_pixbuf()
            assert pb.get_width() == size and pb.get_height() == size
            pb.savev(out, 'png', [], [])
        return render, f'librsvg {Rsvg.MAJOR_VERSION}.{Rsvg.MINOR_VERSION}.{Rsvg.MICRO_VERSION} via python3-gi + GdkPixbuf'
    except (ImportError, ValueError):
        pass
    if shutil.which('rsvg-convert'):
        def render(svg, size, out):
            subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), '-o', out, svg], check=True)
        return render, 'rsvg-convert'
    magick = shutil.which('magick') or shutil.which('convert')
    if magick:
        def render(svg, size, out):
            subprocess.run([magick, '-background', 'none', '-density', str(96 * size / 64), svg,
                            '-resize', f'{size}x{size}', out], check=True)
        return render, f'ImageMagick ({os.path.basename(magick)})'
    raise SystemExit('no SVG renderer found (need python3-gi + gir1.2-rsvg-2.0, rsvg-convert or ImageMagick)')


def preview(out):
    from PIL import Image, ImageDraw, ImageFont
    sizes = (16, 32, 64, 256)
    tiles = {}
    for s in sizes:
        p = os.path.join(OUT, f'pi-desktop-{s}.png')
        tiles[s] = Image.open(p).convert('RGBA')
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 13)
    except OSError:
        font = ImageFont.load_default()
    pad, zoom = 24, 6
    panel_w = pad + sum(s + pad for s in sizes) + (16 * zoom + pad) + (32 * zoom + pad)
    panel_h = pad + 256 + pad + 18
    sheet = Image.new('RGBA', (panel_w, 2 * panel_h), (0, 0, 0, 0))
    for row, (bg, fg, label) in enumerate((((246, 245, 244, 255), (40, 40, 40, 255), 'light #F6F5F4'),
                                           ((30, 30, 30, 255), (220, 220, 220, 255), 'dark #1E1E1E'))):
        y0 = row * panel_h
        panel = Image.new('RGBA', (panel_w, panel_h), bg)
        d = ImageDraw.Draw(panel)
        x = pad
        base = pad + 256                          # bottom-align everything on the 256 tile's baseline
        for s in sizes:
            panel.alpha_composite(tiles[s], (x, base - s))
            d.text((x, base + 4), f'{s} px', fill=fg, font=font)
            x += s + pad
        for s in (16, 32):
            z = tiles[s].resize((s * zoom, s * zoom), Image.NEAREST)
            panel.alpha_composite(z, (x, base - s * zoom))
            d.text((x, base + 4), f'{s} px, {zoom}x zoom', fill=fg, font=font)
            x += s * zoom + pad
        d.text((pad, 4), f'pi-desktop.svg on {label}', fill=fg, font=font)
        sheet.alpha_composite(panel, (0, y0))
    sheet.convert('RGB').save(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    svg = os.path.join(OUT, 'pi-desktop.svg')
    with open(svg, 'w', encoding='utf-8') as fh:
        fh.write(build_svg())
    print(f'wrote {svg} ({os.path.getsize(svg)} bytes)')
    if shutil.which('xmllint'):
        subprocess.run(['xmllint', '--noout', svg], check=True)
        print('xmllint: well-formed')
    render, how = renderer()
    print(f'renderer: {how}')
    for s in PNG_SIZES:
        render(svg, s, os.path.join(OUT, f'pi-desktop-{s}.png'))
    render(svg, 128, os.path.join(OUT, 'plymouth-watermark.png'))
    render(svg, 256, os.path.join(OUT, 'plymouth-bgrt-fallback.png'))
    preview(os.path.join(OUT, 'preview.png'))
    for n in sorted(os.listdir(OUT)):
        if n.endswith(('.svg', '.png')):
            print(f'  {os.path.getsize(os.path.join(OUT, n)):7d}  {n}')


if __name__ == '__main__':
    main()
