#!/usr/bin/env python3
"""Probes Composite pixmap behaviour for dock window previews.

Answers Q1 of docs/window-previews.md. The dock wants to show a thumbnail of every
window of an application, including minimized ones, without reading back pixels per
refresh. Whether that is possible depends on three X server behaviours that are easy to
guess wrong:

  1. can a pixmap be named for a window that is minimized?
  2. does a named pixmap track the window's contents, or freeze at the moment of naming?
  3. does a named pixmap survive a resize, a re-map, or the window's destruction?

Each answer changes the design, so this script asserts all of them and fails loudly if a
future X server or window manager behaves differently.

Requires a running compositing manager on the display, because naming a pixmap requires
the window to be redirected. wmsama is the one this targets:

    Xephyr :2 -screen 1280x800 -ac &
    DISPLAY=:2 wmsama/target/wmsama &
    python3 scripts/probe-window-pixmap.py :2

Exit status 0 when every behaviour is as documented.
"""
import sys
import time

from Xlib import X, display
from Xlib.ext import composite
from Xlib.protocol import event


RED = 0xCC2233
GREEN = 0x22CC33
BLUE = 0x3344CC

TOL = 24


def rgb(img):
    data = img.data
    if isinstance(data, str):
        data = data.encode('latin-1')
    b, g, r = data[0], data[1], data[2]
    return (r, g, b)


def as_tuple(pixel):
    return ((pixel >> 16) & 0xFF, (pixel >> 8) & 0xFF, pixel & 0xFF)


def near(got, want):
    return got is not None and all(abs(a - b) <= TOL for a, b in zip(got, as_tuple(want)))


def read(pm, x, y):
    """Read one pixel, or None if the read fails at the protocol level."""
    try:
        return rgb(pm.get_image(x, y, 1, 1, X.ZPixmap, 0xffffffff))
    except Exception:
        return None


ERRORS = []


def name(d, win):
    """Name a pixmap, or None if the server refuses (the window is not redirected)."""
    before = len(ERRORS)
    try:
        pm = win.composite_name_window_pixmap()
        d.sync()
    except Exception:
        return None
    if len(ERRORS) > before:
        return None
    return pm


def fill(d, win, pixel):
    win.change_attributes(background_pixel=pixel)
    win.clear_area(0, 0, 0, 0)
    d.sync()
    time.sleep(0.3)


def iconify(d, win):
    """WM_CHANGE_STATE -> IconicState, the request a titlebar minimize sends."""
    ev = event.ClientMessage(
        window=win,
        client_type=d.intern_atom('WM_CHANGE_STATE'),
        data=(32, [3, 0, 0, 0, 0]))
    d.screen().root.send_event(ev, event_mask=(X.SubstructureRedirectMask |
                                               X.SubstructureNotifyMask))
    d.sync()


def main():
    d = display.Display(sys.argv[1] if len(sys.argv) > 1 else '')
    scr = d.screen()

    if not d.query_extension('Composite'):
        print('FATAL: no Composite extension')
        return 2
    composite.query_version(d)

    win = scr.root.create_window(
        300, 200, 240, 160, 0, scr.root_depth, X.InputOutput, X.CopyFromParent,
        background_pixel=RED, event_mask=X.ExposureMask)
    win.set_wm_name('pixmap-probe')
    win.set_wm_class('pixmap-probe', 'PixmapProbe')
    win.map()
    d.sync()
    time.sleep(1.5)   # let the manager adopt and redirect it

    # Several checks trigger a protocol error on purpose. Record them rather than letting
    # the default handler raise, but keep the count so name() can tell success from
    # refusal. A real, unexpected error still shows up in the summary.
    d.set_error_handler(lambda err, request: ERRORS.append(err))

    results = []

    def check(label, got, want, note):
        if isinstance(want, bool):
            ok = (got == want)
        elif want is None:
            ok = (got is None)
        else:
            ok = near(got, want)
        results.append(ok)
        print('  %-46s %-5s  %s' % (label, 'ok' if ok else 'FAIL', note))
        if not ok:
            print('  %-46s got=%r want=%r' % ('', got, want))
        return ok

    print('1. a mapped window')
    fill(d, win, RED)
    held = name(d, win)
    if held is None:
        print('FATAL: could not name a pixmap for a mapped window; is a compositor running?')
        win.destroy()
        return 2
    check('pixmap named while mapped reads the window', read(held, 120, 80), RED,
          'control: the probe measures what it thinks it measures')

    print('2. is the name a live view?')
    fill(d, win, GREEN)
    check('same pixmap after a content change', read(held, 120, 80), GREEN,
          'live view, not a snapshot')

    print('3. does the name survive a resize?')
    win.configure(width=360, height=240)
    d.sync()
    time.sleep(1.0)
    fill(d, win, BLUE)
    check('same pixmap after a resize', read(held, 120, 80), GREEN,
          'stale: the window got new storage, so re-name on ConfigureNotify')
    check('same pixmap past its old bounds', read(held, 300, 200), None,
          'BadMatch: a stale name must not be read at the new size')
    fresh = name(d, win)
    check('a new name after the resize', read(fresh, 120, 80) if fresh else None, BLUE,
          'works, and carries the new content')

    # This is the name a preview would actually hold across a minimize.
    held.free()
    held = fresh

    print('4. minimize')
    iconify(d, win)
    time.sleep(1.0)
    unmapped = win.get_attributes().map_state == X.IsUnmapped
    check('the window is unmapped', unmapped, True, 'WM_CHANGE_STATE took effect')
    check('pixmap named before the minimize', read(held, 120, 80), BLUE,
          'last frame intact: previews of minimized windows are possible')
    refused = name(d, win)
    check('a fresh name while minimized', refused, None,
          'BadMatch: the dock must hold the name from before the minimize')
    if refused is not None:
        refused.free()

    print('5. re-map')
    win.map()
    d.sync()
    time.sleep(1.0)
    again = name(d, win)
    check('a fresh name after re-map', read(again, 120, 80) if again else None, BLUE,
          'works again')
    if again is not None:
        again.free()

    print('6. destroy the window while holding a name')
    survivor = name(d, win)
    win.destroy()
    d.sync()
    time.sleep(0.6)
    check('a held pixmap after its window died', read(survivor, 120, 80), BLUE,
          'still readable, so free it on DestroyNotify or leak it')

    held.free()
    survivor.free()
    d.sync()

    print()
    if all(results):
        print('RESULT OK: every documented behaviour reproduced')
        return 0
    print('RESULT FAIL: %d check(s) differ from docs/window-previews.md'
          % results.count(False))
    return 1


if __name__ == '__main__':
    sys.exit(main())
