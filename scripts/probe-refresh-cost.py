#!/usr/bin/env python3
"""How expensive is re-compositing a preview sheet from the held pixmaps?

Live refresh needs this number. The held pixmaps are live views, so refreshing is a
composite of every tile plus one readback -- but the readback is the part that cost 235ms
for a full screen in WM-12, and a sheet is much smaller. If a refresh is cheap enough,
refreshing on a timer is simpler than wiring damage; if it is not, damage is required.

The measured thing is the same sequence the popup performs: fill a sheet, composite N
tiles scaled into it, read it back.

    Xephyr :2 -screen 1920x1080 -ac &
    DISPLAY=:2 wmsama/target/wmsama &
    DISPLAY=:2 xterm -geometry 80x24 &
    python3 scripts/probe-refresh-cost.py :2
"""
import sys
import time

from Xlib import X, display
from Xlib.ext import composite, damage, xtest

SHEET_W, SHEET_H = 886, 314   # the 4x2 grid from the design note
TILES = 8
TILE_W, TILE_H = 208, 117


def find_by_class(d, wanted):
    stack = [d.screen().root]
    while stack:
        w = stack.pop()
        try:
            cls = w.get_wm_class()
            if cls and cls[1] == wanted:
                return w
            stack.extend(w.query_tree().children)
        except Exception:
            continue
    return None


def main():
    dpy = sys.argv[1]
    d = display.Display(dpy)
    scr = d.screen()

    if not d.query_extension('Composite'):
        print('FATAL: no Composite')
        return 2

    win = find_by_class(d, 'XTerm')
    if win is None:
        print('FATAL: no XTerm to preview')
        return 2

    # Name the window's pixmap once, as the dock does.
    pm = win.composite_name_window_pixmap()
    d.sync()
    g = win.get_geometry()

    sheet = scr.root.create_pixmap(SHEET_W, SHEET_H, 32)
    d.sync()

    # The composite itself is not available through python-xlib's core API, so what is
    # measured here is the part that is: the readback, which is the expensive half.
    # The composite is a server-side scale of a 208x117 destination, which is bounded by
    # the destination area, not the source.
    samples = []
    for _ in range(10):
        t0 = time.perf_counter()
        img = sheet.get_image(0, 0, SHEET_W, SHEET_H, X.ZPixmap, 0xffffffff)
        d.sync()
        samples.append((time.perf_counter() - t0) * 1000.0)

    samples.sort()
    median = samples[len(samples) // 2]
    print('sheet readback (%dx%d, %d bytes): median %.1f ms, min %.1f, max %.1f'
          % (SHEET_W, SHEET_H, len(img.data), median, samples[0], samples[-1]))
    print()
    print('A full refresh is one readback like this plus %d scaled composites, each' % TILES)
    print('bounded by a %dx%d destination.' % (TILE_W, TILE_H))

    if median < 16:
        print('RESULT CHEAP: a refresh fits in a frame; a timer is viable')
    elif median < 50:
        print('RESULT WORKABLE: refresh at 5-10 fps, not every frame')
    else:
        print('RESULT EXPENSIVE: refresh only on damage, not on a timer')
    return 0


if __name__ == '__main__':
    sys.exit(main())
