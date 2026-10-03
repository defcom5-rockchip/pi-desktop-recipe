# Pi-Desktop "Plaid" branding

Artwork © 2026 defcom5-rockchip, licensed CC BY-SA 4.0.
(That line covers every file in this directory, `make-logo.py` included.)

The logo is the Plaid tartan swatch from the fastfetch terminal art (`plaid_logo.py`: same palette,
same sett, same soft 2/2 twill) inside the rounded square used by the installer icons
(`pidesktop-get-*.svg`), with a large cream π in front.

| | |
|---|---|
| Palette | charcoal `#1C1B1A`, orange `#E85020`, cream `#F3E2B8`, blue `#21418C` |
| Sett (from the pivot thread outward, mirrored) | CHAR 3, BLUE 1, CHAR 3, ORNG 3, CHAR 1, CREAM 1, CHAR 1, ORNG 3, CHAR 3 |
| Twill | warp on top 68 % along the 45° diagonals, 32 % between (the "soft" twill of the terminal art) |
| Tile | `rect x=4 y=4 width=56 height=56 rx=12` in a 64 × 64 viewBox, exactly like the installer icons |
| π | DejaVu Sans Bold U+03C0, converted to a `<path>`; 36 units wide, cream, with a 1.25-unit charcoal rim |

## Files

| File | What it is |
|---|---|
| `pi-desktop.svg` | The logo. viewBox `0 0 64 64`, filled shapes only (no strokes, no filters, no fonts, no external references); the only references are internal (`clip-path="url(#rr)"`, `url(#tw)`, `xlink:href="#pi"`). Validated with `xmllint --noout`. |
| `pi-desktop-{16,22,24,32,48,64,128,256,512}.png` | Square renders of the SVG, transparent outside the rounded square. |
| `plymouth-watermark.png` | The logo at 128 px, for the two-step `watermark.png` slot (bottom-right at `.96/.96`). Transparent background. |
| `plymouth-bgrt-fallback.png` | The logo at 256 px, for the two-step `bgrt-fallback.png` slot (centred, 38.2 % down the screen, when there is no firmware logo). Transparent background. |
| `pi-desktop.plymouth` | Theme descriptor derived from Ubuntu's `spinner.plymouth` (see below). |
| `preview.png` | Contact sheet: 16 / 32 / 64 / 256 px on light `#F6F5F4` and dark `#1E1E1E`, plus 6× zooms of the 16 and 32 px renders. |
| `make-logo.py` | Generator for everything above except the descriptor and this file. |

## How they were made

Everything is produced by one script, run from this directory:

```sh
python3 make-logo.py            # writes pi-desktop.svg, the PNGs, the two Plymouth images and preview.png here
python3 make-logo.py /some/dir  # or into another directory
xmllint --noout pi-desktop.svg  # the script already does this when xmllint is installed
```

What the script does, in order:

1. **Tartan.** Lays the sett out across the 56-unit tile with the pivot thread centred, so one full sett
   (37 threads, 56/37 ≈ 1.514 units per thread) fills the tile edge to edge. Horizontal (weft) threads are
   opaque rectangles over a charcoal base rectangle; vertical (warp) threads are drawn twice as translucent
   rectangles: once everywhere at `fill-opacity .32`, and once more at `.529` inside a clip path made of
   45° parallelograms two threads wide every four threads. Net warp share: 0.68 on the diagonal, 0.32
   between, i.e. the terminal art's `a = 0.68 if ((x + y) % 4) < 2 else 0.32`. Everything is clipped to
   the rounded square.
2. **π glyph.** Reads the U+03C0 outline directly out of DejaVu Sans Bold's TrueType `glyf` table
   (`/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf`), flips and scales it to 36 units wide centred
   on the tile, and writes it as an absolute `M/L/Q/Z` path. fontTools is used when importable; otherwise
   a small built-in TrueType reader in the script does the same job (both were run and produce a
   byte-identical SVG). No font is needed at render time.
3. **Rim.** The π is drawn 16 times in charcoal, each copy offset by 1.25 units around the compass
   (`<use xlink:href="#pi" x=… y=…>`), then once in cream on top. The union of the offset copies is a
   filled outline, so the file still contains no strokes.
4. **Renders.** The PNGs were rendered with **librsvg 2.61.3** (the library GNOME itself uses for icons)
   through `python3-gi` (`gir1.2-rsvg-2.0`, `Rsvg.Handle.get_pixbuf()` on a copy of the SVG whose root
   `width`/`height` are set to the target size, saved through GdkPixbuf). The script prefers the
   pycairo route when `python3-gi-cairo` is installed, then the `rsvg-convert` binary, and only as a
   last resort ImageMagick, whose built-in MSVG engine renders the clip paths less faithfully — if you
   regenerate, check that the script prints `renderer: librsvg …`.
5. **Preview.** `preview.png` is composed with Pillow from the 16 / 32 / 64 / 256 px renders.

Dependencies on the build host: `python3`, `python3-pil`, `python3-gi`, `gir1.2-rsvg-2.0`,
`gir1.2-gdkpixbuf-2.0`, optionally `python3-fonttools` and `libxml2-utils` (xmllint).
Only the DejaVu Bold font file is read, and only at generation time.

## Plymouth theme

`pi-desktop.plymouth` is Ubuntu's `spinner.plymouth` (two-step module) with these changes:

* `ImageDir=/usr/share/plymouth/themes/pi-desktop`, navy background gradient `0x1b2a55 → 0x101a36`,
  progress bar `0x2b3a66` / orange `0xe85020`, fonts `Ubuntu 12` / `Ubuntu Light 30` (what Ubuntu's own
  `bgrt` theme uses; the spinner uses Cantarell — Ubuntu's initramfs hook ships the Ubuntu font, so this
  is the safe choice).
* Watermark bottom-right (`WatermarkHorizontalAlignment=.96`, `WatermarkVerticalAlignment=.96`); dialog
  and title at `.382`; `DialogClearsFirmwareBackground=true`, `MessageBelowAnimation=true`.
* `UseFirmwareBackground=true` in `[boot-up]`, `[shutdown]` and `[reboot]` (as in Ubuntu's `bgrt`
  theme). The two-step plugin only looks at `bgrt-fallback.png` on that code path: it tries the ACPI
  BGRT image first and falls back to the PNG when there is none. The Orange Pi 5B boots through U-Boot
  with no ACPI/BGRT, so the fallback — our 256 px logo — is what shows, centred, 38.2 % down the screen.
* Throbber `VerticalAlignment=.7` (Ubuntu's value) rather than `.5`: a 256 px logo centred at 38.2 %
  of a 1080-px-tall screen reaches down to the 50 % line, so a spinner at `.5` would sit on top of it.

The plugin loads fixed file names from `ImageDir`, so the recipe should install the images as:

```
/usr/share/plymouth/themes/pi-desktop/pi-desktop.plymouth
/usr/share/plymouth/themes/pi-desktop/watermark.png        <- plymouth-watermark.png
/usr/share/plymouth/themes/pi-desktop/bgrt-fallback.png    <- plymouth-bgrt-fallback.png
/usr/share/plymouth/themes/pi-desktop/throbber-*.png       <- copied from the spinner theme at build time
/usr/share/plymouth/themes/pi-desktop/animation-*.png      <- idem
/usr/share/plymouth/themes/pi-desktop/{lock,entry,bullet,capslock,keyboard,keymap-render}.png  <- idem
```

and activate it with `plymouth-set-default-theme -R pi-desktop` (or the `default.plymouth`
update-alternatives entry) so the initramfs is rebuilt with the theme inside. Note that with both
images installed the logo appears twice (large centred, small bottom-right); drop `watermark.png` from
the install list if that is not wanted.

## Icon theme

For the desktop, install `pi-desktop.svg` as
`/usr/share/icons/hicolor/scalable/apps/pi-desktop.svg` and the PNGs as
`/usr/share/icons/hicolor/<N>x<N>/apps/pi-desktop.png` (N = 16 22 24 32 48 64 128 256 512), then run
`gtk-update-icon-cache /usr/share/icons/hicolor`.

## Credits

Tartan sett, palette and soft-twill rendering: the Pi-Desktop fastfetch art (`plaid_logo.py`).
π outline: DejaVu Sans Bold (DejaVu fonts, Bitstream Vera licence — the glyph is embedded as an
outline, no font files are distributed here). Rounded-square house style: the Pi-Desktop installer icons.
