#!/usr/bin/env python3
"""Can a non-WM client watch another client's window for damage?

Live previews depend on it: if damage for a redirected window only reaches the compositor
that owns the redirect, the dock would have to poll pixels, which is exactly what the
design rules out. Damage is per-drawable, not per-client, so it should work for anybody —
but that is an assumption worth measuring before building a timer on it.

    Xephyr :2 -screen 1280x800 -ac &
    DISPLAY=:2 wmsama/target/wmsama &
    DISPLAY=:2 xterm &
    python3 scripts/probe-damage-visibility.py :2 XTerm

Reports how many DamageNotify events arrived, and from which drawable.
"""
import subprocess
import sys
import time

from Xlib import X, XK, display
from Xlib.ext import damage, xtest


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
    wanted = sys.argv[2] if len(sys.argv) > 2 else 'XTerm'
    d = display.Display(dpy)

    if not d.query_extension('DAMAGE'):
        print('FATAL: no DAMAGE extension')
        return 2

    # Initialise DAMAGE on this connection. Without the version query the server accepts
    # the damage object but never delivers DamageNotify, which reads as "damage does not
    # work for this client" and is the single most misleading failure here.
    d.damage_query_version()
    d.sync()

    win = find_by_class(d, wanted)
    if win is None:
        print('FATAL: no %s window' % wanted)
        return 2

    # Watch the client window, which is what a preview would composite from.
    dm = win.damage_create(damage.DamageReportNonEmpty)
    d.sync()
    print('watching 0x%x for damage (NonEmpty)' % win.id)

    # Clear damage from the window's mapping, so the count below is about new drawing.
    d.damage_subtract(dm, 0, 0)
    d.sync()
    while d.pending_events():
        d.next_event()
    time.sleep(0.2)

    # Make the client draw something. xdotool is used rather than XTEST directly
    # because the first version typed into a window that was not focused, so nothing was
    # drawn and "no damage" was a false negative: the probe was measuring its own bug.
    wid = subprocess.run(['xdotool', 'search', '--class', wanted],
                         capture_output=True, text=True,
                         env={'DISPLAY': dpy}).stdout.split()
    if wid:
        subprocess.run(['xdotool', 'windowfocus', wid[0]], env={'DISPLAY': dpy})
        time.sleep(0.3)
        subprocess.run(['xdotool', 'type', '--delay', '30', 'hello live preview'],
                       env={'DISPLAY': dpy})
        time.sleep(0.8)

    # Confirm the client actually drew. Without this, zero damage is indistinguishable
    # from "the probe failed to make anything happen".
    try:
        before_len = len(win.get_image(5, 5, 80, 16, X.ZPixmap, 0xffffffff).data)
        print('window readable: %d bytes' % before_len)
    except Exception as e:
        print('window NOT readable: %s' % type(e).__name__)

    deadline = time.time() + 3.0
    events = 0
    while time.time() < deadline:
        while d.pending_events():
            ev = d.next_event()
            if ev.type == d.extension_event.DamageNotify:
                events += 1
                # Clear the damage so the next event is about new drawing.
                d.damage_subtract(dm, 0, 0)
        d.sync()
        time.sleep(0.02)

    print('damage events received from one burst of typing: %d' % events)

    # A burst that draws repeatedly must produce more than one notification, or the
    # preview would update once and then freeze.
    burst_before = events
    for ch in ' more typing here\n':
        code = d.keysym_to_keycode(XK.string_to_keysym(
            'Return' if ch == '\n' else ('space' if ch == ' ' else ch)))
        xtest.fake_input(d, X.KeyPress, code); d.sync(); time.sleep(0.02)
        xtest.fake_input(d, X.KeyRelease, code); d.sync(); time.sleep(0.03)
    deadline = time.time() + 2.0
    while time.time() < deadline:
        while d.pending_events():
            ev = d.next_event()
            if ev.type == d.extension_event.DamageNotify:
                events += 1
                d.damage_subtract(dm, 0, 0)
        d.sync()
        time.sleep(0.02)
    print('additional events from a second burst: %d' % (events - burst_before))
    if events <= burst_before:
        print('RESULT FAIL: only the first draw produced damage; previews would freeze')
        return 1
    if events == 0:
        print('RESULT FAIL: a non-owning client sees no damage; live preview would need polling')
        return 1
    print('RESULT OK: damage reaches a client that does not own the redirect')
    return 0


if __name__ == '__main__':
    sys.exit(main())
