#!/usr/bin/env python3
# plaid_logo.py — Plaid Pi terminal logo for fastfetch.
# A real 2/2-twill tartan swatch with a π glyph, rendered as truecolor half-blocks
# (▀ with fg=top pixel, bg=bottom pixel) so it works in ANY terminal (VTE has no sixel by default).
import sys, numpy as np
from PIL import Image, ImageDraw, ImageFont
W, H = 36, 18                       # terminal cells -> pixel grid 36 x 36 (square pixels)
PW, PH = W, 2 * H
OUT = sys.argv[1] if len(sys.argv) > 1 else 'plaid.ans'
def hx(s): return np.array([int(s[i:i+2], 16) for i in (1, 3, 5)], dtype=float)
CHAR, ORNG, CREAM, BLUE = '#1C1B1A', '#E85020', '#F3E2B8', '#21418C'
# sett from the pivot (centre thread) outward: thread colour, count — mirrored about the centre
SETT = [(CHAR, 3), (BLUE, 1), (CHAR, 3), (ORNG, 3), (CHAR, 1), (CREAM, 1), (CHAR, 1), (ORNG, 3), (CHAR, 3)]
seq = [hx(c) for c, n in SETT for _ in range(n)]
def thread(p):                       # colour of warp/weft thread at pixel p (centre = PW/2)
    t = abs(int(p) - PW // 2)
    L = len(seq); k = t % (2 * L - 2) if L > 1 else 0
    return seq[k if k < L else 2 * L - 2 - k]
px = np.zeros((PH, PW, 3))
for y in range(PH):
    for x in range(PW):
        a = 0.68 if ((x + y) % 4) < 2 else 0.32                       # soft 2/2 twill
        px[y, x] = a * thread(x) + (1 - a) * thread(y)
# π glyph: supersampled mask, anti-aliased down, with a 1-px charcoal rim for legibility
S = 8
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 28 * S)
m = Image.new('L', (PW * S, PH * S), 0); d = ImageDraw.Draw(m)
bb = d.textbbox((0, 0), 'π', font=font)
d.text(((PW * S - (bb[2] - bb[0])) / 2 - bb[0], (PH * S - (bb[3] - bb[1])) / 2 - bb[1] - S), 'π', font=font, fill=255)
mask = np.asarray(m.resize((PW, PH), Image.LANCZOS), dtype=float) / 255.0
rim = np.zeros_like(mask)
for dy in (-1, 0, 1):
    for dx in (-1, 0, 1):
        rim = np.maximum(rim, np.roll(np.roll(mask, dy, 0), dx, 1))
rim = np.clip(rim - mask, 0, 1)
px = px * (1 - rim[..., None] * 0.85) + hx('#0E0D0C') * rim[..., None] * 0.85
px = px * (1 - mask[..., None]) + hx('#FFF6DC') * mask[..., None]
px = np.clip(px, 0, 255).astype(int)
def sgr(fg, bg): return f'\x1b[38;2;{fg[0]};{fg[1]};{fg[2]}m\x1b[48;2;{bg[0]};{bg[1]};{bg[2]}m▀'
lines = [''.join(sgr(px[2*r, c], px[2*r+1, c]) for c in range(W)) + '\x1b[0m' for r in range(H)]
def centre(s): return ' ' * max(0, (W - len(s)) // 2) + s
lines.append('')
lines.append(f'\x1b[1;38;2;232;80;32m{centre("PLAID PI")}\x1b[0m')
lines.append(f'\x1b[38;2;243;226;184m{centre("- 5 . 0 -")}\x1b[0m')
open(OUT, 'w').write('\n'.join(lines) + '\n')
# PNG preview of the swatch (10x) so it can be eyeballed without a terminal
Image.fromarray(px.astype('uint8')).resize((PW * 12, PH * 12), Image.NEAREST).save(OUT.rsplit('.', 1)[0] + '-preview.png')
print(f'wrote {OUT}: {W}x{len(lines)} cells (swatch {W}x{H} + wordmark)')
