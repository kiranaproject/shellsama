# Dock Window Previews — Design Note

**Scope:** replacing the dock's text window list with a grid of window thumbnails, so a
multi-window application can be picked by looking rather than by reading.

**Baseline:** `shellsama@7ed9f75`, `florialib@aae988d`, `floria-toolkit@ce8a26e`,
`wmsama@17b750f`
**Written:** 2026-11-04

This note records the design and the measurements behind it. It is not an implementation.
Every claim about existing code cites the file and line it came from, so the note can be
checked against the tree it describes.

---

## 0. How to Read This

| Mark | Meaning |
| :--- | :--- |
| `☐` | Not started |
| `◐` | In progress |
| `☑` | Done and verified |
| `⊘` | Rejected or deferred, with the reason recorded |

Open questions are collected in [§8](#8-open-questions). The one that blocked the design —
what happens to a minimized window's pixels — is answered in [§7.5](#75-minimized-windows-measured)
and it changed the thumbnail pipeline.

---

## 1. What Changes

Today, clicking a dock icon with more than one window opens a `TFtPopupMenu` of window
titles (`shellsama.dock.pas`, `TShellDock.ShowWindowList`). Selecting an item calls
`ActivateWindow`.

After: clicking that icon opens a popup of thumbnails, one per window, each with its title
underneath. Selecting a thumbnail activates that window.

Unchanged:

- One dock icon per application, grouped by `WM_CLASS`.
- Clicking an icon with one window activates it directly; with none it launches.
- The per-application right-click menu (pin/unpin).
- Activation goes through the existing `_NET_ACTIVE_WINDOW` path in
  `TShellTaskSurface.ActivateWindow` (`shellsama.bottompanel.pas:1340`).

---

## 2. How the Other Desktops Do It

Neither Windows nor Plasma takes a screenshot on open.

**Windows.** `DwmRegisterThumbnail(dest, source)` links the source window's composition
surface to a destination rectangle. DWM renders that rectangle every frame with the
transform applied. Pixels never leave the compositor, which is why Aero Peek thumbnails are
live and cost nothing extra to keep live.

**Plasma.** The same relationship, expressed differently per backend. On Wayland it is a
requirement: a client cannot read another client's buffer, so KWin must render the
thumbnail and hand over the result. On X11 it is XComposite, as here.

The lesson is not "copy the Windows API". It is that the thumbnail is a *view of a surface
that already exists*, and the cost of adding one is a scale operation, not a capture.

---

## 3. What This Stack Already Has

`floria.xcb.wm.compositor.pas:622` and `:722` already name a pixmap for each client:

```pascal
FClientPixmap := xcb_generate_id(FCompositor.Connection);
xcb_composite_name_window_pixmap(FCompositor.Connection, FClientWindow, FClientPixmap);
```

Those pixmaps belong to `wmsama`'s connection, not to `shellsama`. That does not matter:
`NameWindowPixmap` is available to any client once the window is redirected, and the
redirect is manual and server-wide (`floria.xcb.wm.compositor.pas:1029`,
`XCB_COMPOSITE_REDIRECT_MANUAL`). The dock can name the same window's pixmap on its own
connection and get the same pixels.

One restriction applies, and it shapes the whole design: a pixmap can only be named while
the window is **mapped**. Measured in [§7.5](#75-minimized-windows-measured).

The cost that must be avoided is readback. `floria.xcb.wm.compositor.pas:647` fetches a
whole surface with `xcb_get_image` into a `TFloriaImage`. Per WM-12 that is ~4 MB per
content frame and 235–259 ms for a full-screen fetch. Ten windows refreshed from that path
would be unusable. The design below reads back **once per popup open**, and only a
small composited sheet.

---

## 4. Decision: Who Renders

| | shellsama renders (chosen) | wmsama publishes |
| :--- | :--- | :--- |
| Mechanism | dock names the pixmap, scales into its own popup | compositor draws thumbnails into a buffer the dock reads |
| New protocol | none | one, between two processes |
| Duplicate logic | scaling lives in the shell | none |
| Layering | the dock already speaks EWMH and XCB directly | puts UI knowledge in the window manager |

Chosen: **shellsama renders**. The compositor keeps its job, which is compositing what
exists; the shell decides what a window preview looks like. This also keeps the feature
inside one repository, so it can be reviewed and reverted on its own.

Rejected: wmsama publishing thumbnails. It would avoid a scale per open, but the scale is
not the expensive part, and it introduces a cross-process buffer protocol for a popup that
is open for a second at a time.

---

## 5. Layout

### 5.1 Wireframe

One window — a single tile, above the icon that opened it:

```
                 ┌───────────────────┐
                 │                   │
                 │    thumbnail      │   208 x 117
                 │    (16:9 box)     │
                 │                   │
                 ├───────────────────┤
                 │ Document 1.odt    │   18px title row
                 └───────────────────┘
                        ▲
                        │ 10px
                    ┌───────┐
                    │  ▣    │   dock icon, 48px
                    │   ●   │
                    └───────┘
```

Four windows — the grid grows upward and the icon stays under its centre:

```
        ┌─────────────────────────────────────────────────────────┐
        │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
        │  │              │  │              │  │              │   │
        │  ├──────────────┤  ├──────────────┤  ├──────────────┤   │
        │  │ Document 1   │  │ Document 2   │  │ Document 3   │   │
        │  └──────────────┘  └──────────────┘  └──────────────┘   │
        │  ┌──────────────┐                                       │
        │  │              │                                       │
        │  ├──────────────┤                                       │
        │  │ Document 4   │                                       │
        │  └──────────────┘                                       │
        └─────────────────────────────────────────────────────────┘
```

The popup is anchored to the icon's horizontal centre, not to a tile. That is what makes it
read as belonging to that icon even when the icon is nowhere near the grid's middle.

### 5.2 Metrics

| Item | Value | Reason |
| :--- | :--- | :--- |
| tile box | 208 x 117 | 16:9; ~16% of a 1280px screen, large enough to recognise content |
| title row | 18px, 4px above | one line, ellipsized at the tile edge |
| cell | 208 x 139 | tile + gap + title |
| max columns | 4 | wider stops reading as a popup |
| column gap | 10 | |
| row gap | 12 | rows need more air than columns |
| padding | 12 | same as `DOCK_PADDING` (`shellsama.dock.pas:128`) |
| corner radius | 14 | the dock plate uses 18; a smaller surface needs a smaller radius |
| icon clearance | 10 | matches the existing list offset in `ShowWindowList` |

Resulting sizes:

| windows | cols x rows | popup |
| :--- | :--- | :--- |
| 1 | 1x1 | 232 x 163 |
| 2 | 2x1 | 450 x 163 |
| 3 | 3x1 | 668 x 163 |
| 4 | 4x1 | 886 x 163 |
| 5–8 | 4x2 | 886 x 314 |
| 9–12 | 4x3 | 886 x 465 |

### 5.3 Arithmetic

```pascal
  PREVIEW_W        = 208;
  PREVIEW_H        = 117;
  PREVIEW_TITLE    = 18;
  PREVIEW_GAP_X    = 10;
  PREVIEW_GAP_Y    = 12;
  PREVIEW_PAD      = 12;
  PREVIEW_MAX_COLS = 4;

  cols := Min(n, PREVIEW_MAX_COLS);
  rows := (n + cols - 1) div cols;
  popW := 2 * PREVIEW_PAD + cols * PREVIEW_W + (cols - 1) * PREVIEW_GAP_X;
  popH := 2 * PREVIEW_PAD + rows * (PREVIEW_H + 4 + PREVIEW_TITLE)
                         + (rows - 1) * PREVIEW_GAP_Y;
```

Anchor, in dock-local coordinates — the space `TFtPopupMenu.Show` already takes today:

```pascal
  iconCx := FEntries[idx].Button.X + FEntries[idx].Button.Width div 2;
  px := iconCx - popW div 2;
  py := FEntries[idx].Button.Y - popH - 10;

  px := Max(8, Min(px, ScreenWidthHint() - popW - 8));
  py := Max(topInset + 8, py);
```

Two overflow rules, applied in this order:

1. **Tall.** If `py` lands above the top inset, add a column (up to 6) to lose a row, then
   recompute. Twelve windows lay out as 6x2 rather than 4x3. Past 6 columns, clamp and
   accept overlap.
2. **Wide.** If `popW > screenW - 16`, drop a column and recompute. The 886px four-column
   grid fits any screen 1024 wide or larger.

No header row and no close affordance in the first version. The dock icon already names the
application, and at 208px a close glyph would cost a title character for something the
per-window menu will offer anyway.

---

## 6. Structure

### 6.1 Widget Tree

```
TFtWindow (ftwtPopupMenu, borderless, radius 14 via CSS, BackgroundOpacity 0.92)
└── TFtDrawingArea (0, 0, popW, popH)
```

Two levels, deliberately.

The window paints the plate. It follows the path the dock already uses: a CSS string with
`border-radius` and `background-color`, plus `BackgroundOpacity`. That also gets the
rounded click region for free, because `TFtX11Window.ApplyInputShape`
(`floria-toolkit/src/main/pascal/ft.backend.x11.pas`) derives the SHAPE input region from
the resolved border radius on every repaint.

The drawing area paints tiles, titles and hover. It is the only widget with a paint hook
that ftpas exposes (`ft_drawingarea_on_paint`, `floria-toolkit/include/ft.h:1232`), and it
also supplies `on_mouse_down`, `on_mouse_move`, `on_mouse_leave` and `on_mouse_wheel`,
which is the whole interaction surface this popup needs.

One drawing area rather than one widget per tile: hover, hit-testing and layout become
three small functions instead of `n` widget lifetimes to keep in step with a list that can
change underneath them.

### 6.2 New State on `TShellDock`

```pascal
    // Per window, held for the window's life. See §7.2 for the lifetime rules.
    // Parallel arrays rather than a map: the dock has no fgl dependency and the list is
    // a few dozen entries at most, so a linear lookup is the cheaper thing to read.
    FWindowPixmapWin : array of Cardinal;
    FWindowPixmap    : array of TPixmapEntry;

    // The popup, only alive while it is open.
    FPreview        : TFtWindow;
    FPreviewArea    : TFtDrawingArea;
    FPreviewKey     : string;
    FPreviewWindows : array of Cardinal;
    FPreviewTitles  : array of string;
    FPreviewSheet   : TFloriaImage;
    FPreviewHover   : Integer;      // -1 when none
```

```pascal
  TPixmapEntry = record
    Pixmap : xcb_pixmap_t;
    Width  : Integer;   // the pixmap's own bounds, recorded when it was named
    Height : Integer;
  end;
```

Replaces `FWindowList: TFtPopupMenu` and `FWindowListKey`.

### 6.3 Painting

```pascal
procedure TShellDock.PreviewPaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  i: Integer;
  r: TRect;
begin
  if FPreviewSheet = nil then Exit;
  for i := 0 to High(FPreviewWindows) do
  begin
    r := TileRect(i);
    Canvas.DrawImagePart(r.X, r.Y, r.W, r.H, FPreviewSheet, r.X, r.Y, r.W, r.H);
    Canvas.DrawTextLeft(r.X, r.Y + PREVIEW_H + 4, r.W, PREVIEW_TITLE,
                        Ellipsize(FPreviewTitles[i], r.W), FSmallFont, 0.86, 0.88, 0.92);
    if i = FPreviewHover then
      Canvas.DrawRoundedRectOutline(r.X, r.Y, r.W, r.H, 8, 2, 0.35, 0.62, 0.95);
  end;
end;
```

`DrawImagePart` is a 1:1 blit from the sheet, which is already at tile size. No scaling
happens on the client side.

### 6.4 Hit Testing and Input

```pascal
procedure TShellDock.PreviewMouseDown(Sender: TFtDrawingArea; AX, AY, AButton: Integer);
var
  i: Integer;
begin
  i := TileAt(AX, AY);
  if i < 0 then Exit;
  case AButton of
    1: ActivatePreviewWindow(i);
    3: ShowPreviewWindowMenu(i, AX, AY);   // later increment
  end;
end;
```

`ActivatePreviewWindow` re-checks that the id is still present in the entry's `Windows`
array before calling `ActivateWindow`. An X id is reusable after destroy; a stale id would
raise an unrelated application. The popup can be open while a window closes elsewhere, so
this check is required, not defensive.

---

## 7. The Thumbnail Pipeline

### 7.1 Constraint

The toolkit's paint path renders the entire window into a CPU buffer and `PutImage`s it
(`TFtX11Window.Repaint` → `PresentPixels`,
`floria-toolkit/src/main/pascal/ft.backend.x11.pas`). Anything composited with XRender
directly onto the popup window is erased by the next repaint. Thumbnails therefore cannot
live in the window; they must become an image the canvas draws.

Readback per window is the cost to avoid (§3). The fix is to let the server do the
shrinking, then read back only the result.

### 7.2 Pixmap Lifetime

The first version of this note assumed the dock would name a fresh pixmap per window each
time the popup opened. Measurement (§7.5) ruled that out: naming a pixmap for an
**unmapped** window fails with `BadMatch`, so a minimized window has nothing to show at
popup-open time. The pixels do survive a minimize, but only in a pixmap that was named
while the window was still mapped.

The dock therefore keeps **one named pixmap per window**, for as long as the window lives:

| Event | Action | Why |
| :--- | :--- | :--- |
| window first seen, mapped | `NameWindowPixmap` | the only moment a pixmap can be created |
| window first seen, unmapped | skip, retry on `MapNotify` | naming would fail |
| `MapNotify` | re-name, free the old | a re-map gives the window new storage; the old name goes stale |
| `ConfigureNotify` | re-name, free the old | resizing does the same; the old name keeps the old bounds |
| `DestroyNotify` | free | the pixmap outlives its window (§7.5), so this is a leak if skipped |

Holding a name costs no extra server memory. Per the Composite specification,
`NameWindowPixmap` returns a pixmap that *refers to* the window's existing off-screen
storage rather than copying it. The live-view result in §7.5 is consistent with that: a
copy would have been a snapshot.

Selecting `StructureNotify` on each client window is how the dock learns of these events.
It is a plain event mask, not one of the redirect masks, so a non-owning client may select
it.

### 7.3 Sequence, Once Per Popup Open

```pascal
  // One sheet, the size of the grid's content area, depth 24.
  sheet := xcb_generate_id(conn);
  xcb_create_pixmap(conn, 24, sheet, root, sheetW, sheetH);
  dstPic := xcb_generate_id(conn);
  xcb_render_create_picture(conn, dstPic, sheet, rgb24Format, 0, nil);
  // Plate colour underneath, so letterboxed areas are not black.
  xcb_render_fill_rectangles(conn, XCB_RENDER_PICT_OP_SRC, dstPic, plateColour, 1, @sheetRect);

  for i := 0 to High(FPreviewWindows) do
  begin
    // Held since the window appeared. Index 0 means never mapped: nothing to show.
    idx := PixmapIndex(FPreviewWindows[i]);
    if idx < 0 then Continue;

    srcPic := xcb_generate_id(conn);
    xcb_render_create_picture(conn, srcPic, FWindowPixmap[idx].Pixmap,
                              FormatForDepth(pixmapDepth), 0, nil);
    xcb_render_set_picture_filter(conn, srcPic, 'good', 0, nil);

    // Aspect from the pixmap's recorded bounds, not the window's live geometry.
    r := FittedTileRect(i, FWindowPixmap[idx].Width, FWindowPixmap[idx].Height);
    xcb_render_composite(conn, XCB_RENDER_PICT_OP_OVER, srcPic, 0, dstPic,
                         0, 0, 0, 0, r.X, r.Y, r.W, r.H);

    xcb_render_free_picture(conn, srcPic);
  end;

  FPreviewSheet := SheetToImage(conn, sheet, sheetW, sheetH);   // one readback

  xcb_render_free_picture(conn, dstPic);
  xcb_free_pixmap(conn, sheet);
```

No naming, no error handling for dead windows: the pixmap is created and freed on the
dock's own schedule, and a pixmap the dock owns stays valid even if its window dies
(§7.5). The only case that needs a guard is a window with no held pixmap — one that has
never been mapped.

Three details that are not optional:

- **`PictOpOver` onto a pre-filled plate, not `Src`.** A 32-bit client (a terminal with
  transparency) hands over a pixmap whose transparent pixels carry arbitrary RGB. `Src`
  composites that noise; `Over` on the plate colour shows what the window actually looks
  like.
- **Aspect preserved, letterboxed.** Stretching a 4:3 terminal into 16:9 looks like a bug.
- **Use the pixmap's recorded bounds as the source rectangle, not the window's current
  geometry.** If a resize arrives before the dock has re-named, the two disagree and the
  composite reads past the pixmap, which is a `BadMatch` (§7.5). The recorded bounds are
  always inside the pixmap; the geometry is not.

### 7.4 Readback Size

Sheet for eight windows: 886 x 314 at 4 bytes ≈ 1.1 MB, one `xcb_get_image`. Against
8 x 4 MB with per-window readback, that is the whole difference between this being
possible and not.

### 7.5 Minimized Windows, Measured

Measured on `Xephyr :244` with `wmsama@17b750f` running as the manager, using
`scripts/probe-window-pixmap.py`. The probe draws a known colour, names the pixmap, and
reads a pixel back at each step. It asserts every row below, so a future X server or
`wmsama` change shows up as a failing check rather than a quietly different design.

| Case | Result |
| :--- | :--- |
| window mapped, fresh pixmap named | reads the drawn colour — works |
| window minimized, **fresh** pixmap named | `BadMatch` on `NameWindowPixmap` (opcode 142, minor 6) |
| window minimized, pixmap named **before** the minimize | reads the last drawn colour — last frame intact |
| window re-mapped, fresh pixmap named | reads the current colour — works again |
| window destroyed, pixmap held from before | still readable |
| window mapped, content changed, **same** pixmap re-read | reads the new colour — the name is a **live view** |
| window resized, **same** pixmap re-read | reads the **old** colour, and fails past the old size — **stale** |

Three consequences, all of which are now in the design:

1. **Naming per popup open cannot work for minimized windows.** The request fails
   outright. Any design that names on demand shows nothing for exactly the windows a
   preview is most useful for.
2. **A pixmap named while mapped is a live view**, not a snapshot. Holding one per window
   costs no copy and no refresh: it always shows current content, and a minimize freezes
   it at the last frame for free. This is what removes the need for `wmsama` to snapshot
   at iconify time, and removes the alternative of capturing on focus change.
3. **A name does not survive a resize or a re-map.** Both replace the window's off-screen
   storage, so the held name keeps the old contents and the old bounds. Re-naming on
   `ConfigureNotify` and `MapNotify` is required, not an optimisation.

The stale row also decides the source rectangle: it must come from the size recorded when
the pixmap was named, never from the window's current geometry. A resize can arrive before
the dock has re-named, and the two then disagree; reading past the pixmap's real bounds is
the `BadMatch` in that row. The recorded size is always inside the pixmap, the live
geometry is not.

### 7.6 Missing Bindings

`floria.xcb.render.pas` does not bind the four calls the pipeline needs. The generator
skipped them because their return type, `xcb_void_cookie_t`, comes from a filtered-out
header (see the `skipped` comments at `floria.xcb.render.pas:878-884`):

- `xcb_render_create_picture`
- `xcb_render_free_picture`
- `xcb_render_composite`
- `xcb_render_set_picture_filter`

`xcb_void_cookie_t` is already declared and used in `floria.xcb.composite.pas:60`, so this
is four hand-written declarations plus a `FormatForDepth` helper over
`xcb_render_query_pict_formats`, which the compositor already calls. No existing caller
changes.

`xcb_composite_name_window_pixmap` is already bound, in `floria.xcb.composite.pas`.

---

## 8. Open Questions

### Q1. Does a minimized window still have a valid named pixmap? — `☑` **answered**

Answered by measurement, see [§7.5](#75-minimized-windows-measured). The short version:

- the last frame **does** survive a minimize, so `wmsama` needs no snapshot at iconify
  time and this repository stays the only one that changes;
- but a pixmap **cannot be named while the window is unmapped** (`BadMatch`), so the dock
  must hold the name from before the minimize;
- the held name is a live view, not a snapshot, so holding costs nothing and needs no
  refresh;
- the name goes stale on resize and on re-map, so those two events force a re-name.

The consequence is §7.2: one named pixmap per window, maintained for the window's life,
instead of a fresh name per popup open.

### Q2. Client or frame?

`NameWindowPixmap` accepts either. Client-only is recommended: at 208px the titlebar is
noise and the content is what identifies the window. Revisit if the previews read as
anonymous.

### Q3. Dismissal

A custom popup does not inherit outside-click dismissal. Today that lives inside
`TFtPopupMenu`: `FtGrabMenuInput` takes a pointer and keyboard grab
(`floria-toolkit/src/main/pascal/ft.backend.x11.pas:575`) and the backend dismisses when a
press lands outside the popup's bounds (`:2430-2446`). That path is hardwired to
`GGrabbedPopup` being a `TFtPopupMenu`, including casts, and `FtGrabMenuInput` is not
exported to ftpas at all.

Two options:

- **Toolkit addition, ~30 lines.** Export the grab pair and add
  `ft_window_set_popup_dismiss(window, callback)`; the backend calls the callback instead
  of `DismissAll` when the grabbed window is not a menu. Behaviour then matches native
  popups, including Escape.
- **No toolkit change.** Close on tile click, on clicking the icon again, on any dock
  interaction, and on drawing-area `OnMouseLeave` after ~400 ms. Covers most cases but
  dismisses on hover rather than on click, which reads as twitchy.

Not blocking, but it is the only part that needs a decision outside this repository's UI
code.

### Q4. Downscale quality

1920 → 208 is 9:1 through one bilinear filter; title text in the thumbnail will alias.
Acceptable at this size. If not, two halving passes (1920 → 416 → 208) still happen
server-side and remain cheap.

### Q5. Live refresh

Not in this design. Cost scales with output pixels, so one 208x117 composite is trivial,
but the source sampling is still 2M pixels per window on a software server. Damage-driven
and throttled to 5–10 fps is the ceiling if it is ever wanted. Windows gets it free because
DWM owns the surfaces; here it would cost a timer and damage wiring in the shell.

---

## 9. Acceptance Checks

### A1. Minimized window keeps its pixmap — `☑` done, answers Q1

Run under Xephyr with `wmsama` managing, not on a live desktop:

```bash
Xephyr :2 -screen 1280x800 -ac &
DISPLAY=:2 wmsama/target/wmsama &
python3 shellsama/scripts/probe-window-pixmap.py :2
```

The probe creates its own managed window, so it does not depend on a particular client
being installed, and reports each behaviour in [§7.5](#75-minimized-windows-measured)
separately. It exits non-zero on the first difference, naming the behaviour that changed.

Verified: all ten checks pass; sabotaging the "live view" expectation and the "stale
after resize" expectation each makes it fail, so the probe is not passing vacuously.

### A2. Scale is correct and cheap

A helper test in `florialib` with two assertions:

- **Scaling.** Composite a 4x4 pattern of distinct colours into a 2x2 box and assert the
  four resulting colours. Proves the transform and the picture format without a WM.
- **Alpha handling.** Composite a 32-bit source with a fully transparent pixel over a
  filled destination, using `PictOpOver`, and assert the destination colour survives. Then
  repeat with `PictOpSrc` and assert it does not. This is the assertion that keeps the
  `Over`-onto-plate rule from silently regressing into `Src`.

Sabotage check: swapping the operator in the first test must fail the second.

### A3. Popup geometry

Unit tests in `shellsama.dock.test.pas`, on the arithmetic only:

- `n = 1..12` produce the sizes in §5.2;
- the anchor keeps the popup inside the screen at both edges;
- the tall rule adds a column before clamping.

### A4. Activation and staleness

With the popup open for a two-window app, close one window from another terminal; clicking
its tile must do nothing rather than raise an unrelated window.

### A5. Dismissal

Whichever option §Q3 lands on: clicking the desktop, another dock icon, or pressing Escape
closes the popup; the popup never survives its owning application's last window.

---

## 10. Implementation Order

| # | Step | Status |
| :--- | :--- | :--- |
| 1 | Answer Q1 with A1 | `☑` measured, see §7.5 |
| 2 | Bind the four render calls in `florialib`; add and test the scale helper (A2) | `☐` |
| 3 | Pixmap lifetime: hold per window, re-name on `MapNotify`/`ConfigureNotify`, free on `DestroyNotify` | `☐` |
| 4 | Popup geometry, plate, sheet, paint, click-to-activate (A3, A4) | `☐` |
| 5 | Dismissal, per Q3 (A5) | `☐` |
| 6 | Per-tile right-click menu, reusing the task menu items | `☐` |
| 7 | Live refresh, only if wanted (Q5) | `☐` |

Step 2 is independently useful and independently testable, so it can land before the popup
exists. Step 3 is where a wrong lifetime shows up as either `BadMatch` on minimized windows
or a frozen preview after a resize, so it deserves its own change and its own live check.
Steps 4 and 5 together are the feature; step 6 is polish.

---

## 11. What This Does Not Do

- It does not touch the top panel's task list. That stays text.
- It does not add window previews to hover. Hover keeps the faint highlight.
- It does not change `wmsama`. Q1 was measured precisely to avoid that: the last frame of
  a minimized window survives without the manager doing anything.
- It does not show a preview for a window that has never been mapped. The tile is left as
  the plate colour; there is nothing to show.
