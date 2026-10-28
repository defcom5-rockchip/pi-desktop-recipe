#!/usr/bin/env python3
# Plaid Pi KDE edition: make /usr/share/doc/pi-desktop/copyright describe what a KDE image contains.
# The GNOME-only parts (Dhruva dock, Plaid icon theme, patched gnome-control-center, screensaver clip, Files add-ons)
# are not installed on KDE; the Plasma look derived from Breeze Dark is. Every edit asserts its anchor, so a changed
# copyright file fails loudly at build time instead of shipping a wrong notice.
import re, sys
p = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/doc/pi-desktop/copyright"
s = open(p, encoding="utf-8").read()
def sub(old, new, regex=False):
    global s
    n = len(re.findall(old, s, re.S)) if regex else s.count(old)
    if n != 1:
        sys.exit(f"copyright-kde: anchor found {n} times: {old[:60]!r}")
    s = re.sub(old, new, s, count=1, flags=re.S) if regex else s.replace(old, new, 1)
sub("the two Files add-ons, the Network Drive window", "the Dolphin Network Drive menu, the Network Drive window")
sub("(the Plaid wallpaper, the penguin screensaver clip and still, the tartan", "(the Plaid wallpaper, the tartan")
sub("rebuilt or patched (sources in the recipe repository): gnome-control-center (+pd3),\n    Rhythmbox 3.5.1,",
    "rebuilt or patched (sources in the recipe repository):\n    Rhythmbox 3.5.1,")
sub(r"  \* The Plaid look: the Dhruva dock .*?Details: /usr/share/pi-desktop/look/README\.\n",
    "  * The Plaid look for Plasma (/usr/share/plasma/look-and-feel/org.plaidpi.desktop and the Plaid Pi Dark colour\n"
    "    scheme): KDE's Breeze Dark with the Plaid orange accent, the Plaid wallpaper and Plaid Pi's panel launchers,\n"
    "    GPL-2.0-or-later as Breeze; Killswitch (/usr/local/bin/killswitch), Plaid Pi's, GPL-3.0-or-later.\n", regex=True)
sub("Files: /usr/share/backgrounds/pi-desktop/* /usr/share/pi-desktop/screensaver/* /usr/share/pi-desktop/fastfetch/plaid.ans",
    "Files: /usr/share/backgrounds/pi-desktop/* /usr/share/wallpapers/PlaidPi/* /usr/share/pi-desktop/fastfetch/plaid.ans")
sub(r"\nFiles: /usr/share/gnome-shell/extensions/dhruva@narkagni/\*\n.*?published with each Plaid Pi release\.\n", "\n", regex=True)
sub(r"\nFiles: /usr/share/icons/Plaid/\*\n.*?at your option\.\n?",
    "\nFiles: /usr/share/plasma/look-and-feel/org.plaidpi.desktop/* /usr/share/color-schemes/PlaidPiDark.colors\n"
    "Copyright: 2014-2026 KDE Visual Design Group and the Breeze authors (Breeze Dark)\n"
    " 2026 defcom5-rockchip (Plaid Pi changes)\n"
    "License: GPL-2.0-or-later\n"
    " Derived from KDE's Breeze Dark look-and-feel package (plasma-workspace) and colour scheme (breeze) as shipped by\n"
    " Ubuntu 26.04: the Plaid orange accent, the Plaid wallpaper and Plaid Pi's panel launchers.\n"
    " On Debian-based systems the full text is in /usr/share/common-licenses/GPL-2.\n", regex=True)
s = re.sub(r"\n{3,}", "\n\n", s)   # no double blank lines left by removed paragraphs
open(p, "w", encoding="utf-8").write(s)
print("copyright-kde: KDE edition notice written")
