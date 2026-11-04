{ Unit ShellSama.PreviewPopup — the dock's window-preview popup.

  A grid of window thumbnails with a caption under each, shown above the dock icon that
  opened it. Selecting a tile activates that window. See docs/window-previews.md.

  Structure, and why it is two widgets rather than one:

    TFtWindow          paints the plate. A CSS border-radius gives it rounded corners and,
                       through ApplyInputShape, a matching click region.
    TFtDrawingArea     paints the tiles, captions and hover. It is the only widget ftpas
                       exposes a paint hook for, and it also carries every mouse event
                       this popup needs.

  The thumbnails are composited by the server into one 32-bit pixmap, read back once, and
  handed to the canvas as a single image. That is the whole reason a preview is affordable
  here: the alternative, reading each window back at full size, is several megabytes per
  window per frame. §7 of the design note has the measurements.

  The sheet is transparent outside the tiles, so the window's own rounded plate shows
  around and between them. That is why the tile rectangles can stay square without the
  popup looking square-cornered. }

unit ShellSama.PreviewPopup;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Floria.XCB,
  Floria.Image.Core,
  Floria.XCB.Render,
  Floria.XCB.Render.Pictures,
  ftpas.api, ftpas.types, ftpas, ftpas.creative,
  ShellSama.PreviewLayout,
  ShellSama.PreviewRefresh,
  ShellSama.WindowPixmaps;

type
  TPreviewActivateEvent = procedure(AWindow: Cardinal) of object;
  TPreviewDismissEvent  = procedure() of object;
  // Fills AParent with the actions for AWindow, tagged by the caller's convention.
  TPreviewBuildTileMenu = procedure(AWindow: Cardinal; AParent: TFtWidget) of object;

const
  PREVIEW_PLATE_CSS =
    'background-color: rgba(24, 24, 32, 0.92);' +
    'border-radius: 14px;';

  PREVIEW_CAPTION_R = 0.86;
  PREVIEW_CAPTION_G = 0.88;
  PREVIEW_CAPTION_B = 0.92;

  PREVIEW_HOVER_R = 0.35;
  PREVIEW_HOVER_G = 0.62;
  PREVIEW_HOVER_B = 0.95;

  // 32-bit so the sheet can be transparent outside the tiles. Windows are composited
  // OVER it, so their own alpha is preserved: a terminal with a transparent background
  // shows the plate through it, exactly as it would on screen.
  //
  // Not 24. A 24-bit sheet has no alpha channel, so the picture format comes back opaque,
  // OVER has no destination alpha to write, and every tile is composited onto whatever
  // the fill left behind -- which is transparent black. The result is tiles that look
  // like holes punched in the popup.
  PREVIEW_SHEET_DEPTH = 32;

  // Minimum time between live refreshes. Measured at ~2.3ms for a full 8-tile sheet
  // (scripts/probe-refresh-cost.py), so 10 per second costs a few percent of one core.
  // Faster buys nothing: the content a preview shows changes at human speed, and a
  // preview that repaints at 60Hz would keep a laptop's GPU busy for no reason.
  PREVIEW_REFRESH_MS = 100;

type
  TShellPreviewPopup = class
  private
    FConn     : Pxcb_connection_t;
    FRoot     : Cardinal;
    FRootVisual: Cardinal;
    FTopInset : Integer;

    FWindow   : TFtWindow;
    FArea     : TFtDrawingArea;
    FSheet    : TFtBitmap;
    // Size of the sheet in bytes, used to bound the readback into FSheet.Pixels.
    FSheetPixelsSize: Integer;
    FCaptionFont: TFtFontRef;

    FWindows  : array of Cardinal;
    FTitles   : array of string;
    FLayout   : TPreviewLayout;
    FHover    : Integer;
    FOpen     : Boolean;
    FTileMenu : TFtPopupMenu;

    // Live refresh. The held pixmaps are live views of the windows, so re-compositing is
    // all that is needed to show new content; nothing has to be re-named.
    FLive       : Boolean;
    FRefresh    : TPreviewRefreshState;
    // Kept so a refresh can rebuild without the caller passing the store again.
    FStore      : TWindowPixmapStore;
    // Set when a tile menu has been shown and cleared when the popup is released. There is
    // no menu-close notification, and a refresh while the menu is up repaints underneath
    // it; after the action the popup closes anyway, so this only has to be conservative.
    FTileMenuShown: Boolean;

    FOnActivate: TPreviewActivateEvent;
    FOnDismiss : TPreviewDismissEvent;
    // Builds the per-window menu for a tile. Supplied by the dock so the tile offers the
    // same actions as the task list, from one implementation.
    FOnBuildTileMenu: TPreviewBuildTileMenu;

    procedure HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandleMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
    procedure HandleMouseMove(Sender: TFtDrawingArea; X, Y: Integer);
    procedure HandleMouseLeave(Sender: TFtDrawingArea; X, Y: Integer);
    procedure HandleDismiss(Sender: TFtWindow);
    // Right-click on a tile: build the menu for that window and pop it up at the pointer.
    procedure HandleTileMenu(AIndex, AButton, AX, AY: Integer);
    procedure ReleaseTileMenu();

    // Composites every tile into one sheet and reads it back. Replaces any previous
    // sheet, so a failure leaves the popup with no thumbnails rather than stale ones.
    procedure BuildSheet(AStore: TWindowPixmapStore);
    procedure ReleaseSheet();
    procedure ReleaseWindow();
  public
    constructor Create(AConn: Pxcb_connection_t; ARoot, ARootVisual: Cardinal;
                       ATopInset: Integer);
    destructor Destroy(); override;

    // Opens the popup for these windows, anchored to the icon at (AIconCenterX,
    // AIconTop). Closes and releases any previous one first.
    procedure Show(const AWindows: array of Cardinal; const ATitles: array of string;
                   AStore: TWindowPixmapStore;
                   AIconCenterX, AIconTop, AScreenWidth: Integer);

    // Hides the popup. Safe to call from inside its own event handlers: it does not free
    // the window, so a dismiss callback cannot destroy the window that is dispatching.
    procedure Close();
    // Frees the window and the sheet. Only call this from outside the popup's own event
    // dispatch, which in practice means the dock's Show and the destructor.
    procedure Release();

    function IsOpen(): Boolean;
    // True while a tile menu is open. The dock must not close the popup while that is
    // true: it would take the menu down with it.

    function WindowCount(): Integer;
    function Layout(): TPreviewLayout;
    function Hover(): Integer;
    function WindowAt(AIndex: Integer): Cardinal;
    // Test seam: the window id of the popup, or 0 when closed.
    function NativeWindow(): Cardinal;

    // Turns live refresh on or off for the open popup.
    procedure SetLive(AValue: Boolean);
    function Live(): Boolean;
    // Re-composites the sheet if the refresh interval has elapsed. Returns True when it
    // actually rebuilt, so a caller (and a test) can tell a real refresh from a skip.
    function RefreshIfDue(ANowMs: QWord): Boolean;

    property OnActivate: TPreviewActivateEvent read FOnActivate write FOnActivate;
    property OnDismiss: TPreviewDismissEvent read FOnDismiss write FOnDismiss;
    property OnBuildTileMenu: TPreviewBuildTileMenu read FOnBuildTileMenu write FOnBuildTileMenu;
  end;

implementation









constructor TShellPreviewPopup.Create(AConn: Pxcb_connection_t;
  ARoot, ARootVisual: Cardinal; ATopInset: Integer);
begin
  inherited Create();
  FConn := AConn;
  FRoot := ARoot;
  FRootVisual := ARootVisual;
  FTopInset := ATopInset;
  FHover := -1;
  FOpen := False;
  FTileMenu := nil;
  FLive := False;
  FRefresh := PreviewRefreshStateInit();
  FStore := nil;
  FTileMenuShown := False;
  FWindow := nil;
  FArea := nil;
  FSheet := nil;
  FSheetPixelsSize := 0;
  FCaptionFont := TFtFontRef.Create('Sans 9');
end;

destructor TShellPreviewPopup.Destroy();
begin
  Release();
  if Assigned(FCaptionFont) then
    FCaptionFont.Free();
  inherited Destroy();
end;

procedure TShellPreviewPopup.ReleaseSheet();
begin
  if Assigned(FSheet) then
  begin
    FSheet.Free();
    FSheet := nil;
  end;
  FSheetPixelsSize := 0;
end;

procedure TShellPreviewPopup.ReleaseTileMenu();
begin
  FTileMenuShown := False;
  if Assigned(FTileMenu) then
  begin
    FTileMenu.Close();
    FTileMenu.Free();
    FTileMenu := nil;
  end;
end;

procedure TShellPreviewPopup.ReleaseWindow();
begin
  ReleaseTileMenu();
  FStore := nil;
  if Assigned(FArea) then
  begin
    FArea.Free();
    FArea := nil;
  end;
  if Assigned(FWindow) then
  begin
    FWindow.Free();
    FWindow := nil;
  end;
  FOpen := False;
  FHover := -1;
end;

procedure TShellPreviewPopup.Release();
begin
  if Assigned(FWindow) then
  begin
    FWindow.UngrabInput();
    FWindow.Hide();
  end;
  ReleaseWindow();
  ReleaseSheet();
end;

procedure TShellPreviewPopup.BuildSheet(AStore: TWindowPixmapStore);
var
  i: Integer;
  sheetPixmap: xcb_pixmap_t;
  dstPic: xcb_render_picture_t;
  dstFormat, srcFormat: xcb_render_pictformat_t;
  pm: xcb_pixmap_t;
  w, h: Integer;
  visual: Cardinal;
  r: TPreviewRect;
begin
  // Deliberately NOT ReleaseSheet(): a refresh reuses the existing bitmap and only
  // reallocates it when the grid size changes. Freeing it here recreated the bitmap on
  // every refresh, which defeated the caching and left the paint callback reading an
  // object that had just been destroyed.
  if (FConn = nil) or (FRoot = 0) or (FLayout.Width <= 0) then Exit;

  // The sheet's format must match the sheet's own depth, not the root window's. Asking
  // for the root visual's format and then creating a 32-bit pixmap is a BadMatch, and
  // because X errors are asynchronous the composite silently draws nothing.
  dstFormat := XcbRenderPictFormatForDepth(FConn, PREVIEW_SHEET_DEPTH);
  if dstFormat = 0 then Exit;

  sheetPixmap := xcb_generate_id(FConn);
  xcb_create_pixmap(FConn, PREVIEW_SHEET_DEPTH, sheetPixmap, FRoot,
                    FLayout.Width, FLayout.Height);

  dstPic := xcb_generate_id(FConn);
  XcbRenderCreatePicture(FConn, dstPic, sheetPixmap, dstFormat, 0, nil);
  try
    // Fully transparent, not the plate colour: the window paints the plate, and a
    // transparent sheet lets its rounded corners stay rounded.
    XcbRenderFill(FConn, dstPic, 0, 0, 0, 0, 0, 0, FLayout.Width, FLayout.Height);

    for i := 0 to High(FWindows) do
    begin
      if not AStore.LookupFull(FWindows[i], pm, w, h, visual) then Continue;
      if (w <= 0) or (h <= 0) then Continue;

      srcFormat := XcbRenderPictFormatForVisual(FConn, visual);
      if srcFormat = 0 then Continue;

      r := PreviewTileRect(FLayout, i);
      XcbRenderCompositeScaled(FConn, pm, srcFormat, w, h,
                               sheetPixmap, dstFormat,
                               r.X, r.Y, r.W, r.H,
                               XCB_RENDER_PICT_OP_OVER);
    end;
  finally
    XcbRenderFreePicture(FConn, dstPic);
  end;

  // One readback for the whole grid, then the pixmap can go: the bytes are the sheet.
  // Read straight into the bitmap's own buffer, allocating the bitmap ONCE per popup.
  //
  // This is the fix for the refresh leak. A sheet is ~1.1MB, which is above glibc's
  // mmap threshold, so allocating a fresh buffer with GetMem and freeing it each refresh
  // maps and unmaps a region per refresh; the address space (and RSS) grows long before
  // the allocator reuses it. Reading into a buffer that already exists keeps the memory
  // in one place, and it also removes a full copy: CreateFromBGRA used to copy the whole
  // sheet again.
  FSheetPixelsSize := FLayout.Width * FLayout.Height * 4;
  if (FSheet = nil) or (FSheet.Width <> FLayout.Width) or
     (FSheet.Height <> FLayout.Height) then
  begin
    if Assigned(FSheet) then
    begin
      FSheet.Free();
      FSheet := nil;
    end;
    // The toolkit's own bitmap constructor, not TFtBitmap.Wrap: a TFloriaImage built by
    // this program's copy of the image unit is a different class object from the one
    // libft checks for, and the draw call would silently skip it.
    FSheet := TFtBitmap.Create(FLayout.Width, FLayout.Height);
  end;

  if Assigned(FSheet) and (FSheet.Pixels <> nil) then
  begin
    if XcbRenderReadPixmap(FConn, sheetPixmap, FLayout.Width, FLayout.Height,
                           FSheet.Pixels, FSheetPixelsSize) then
    begin
      // Render's output is premultiplied; ftpas has no way to mark a bitmap as such, so
      // straighten it here or every partially transparent window draws too dark.
      XcbDemultiplyBgra(FSheet.Pixels, FLayout.Width, FLayout.Height);
    end;
  end;
  xcb_free_pixmap(FConn, sheetPixmap);
end;

procedure TShellPreviewPopup.Show(const AWindows: array of Cardinal;
  const ATitles: array of string; AStore: TWindowPixmapStore;
  AIconCenterX, AIconTop, AScreenWidth: Integer);
var
  i, availableHeight: Integer;
  px, py: Integer;
begin
  Release();
  if Length(AWindows) = 0 then Exit;

  FStore := AStore;

  SetLength(FWindows, Length(AWindows));
  for i := 0 to High(AWindows) do
    FWindows[i] := AWindows[i];

  SetLength(FTitles, Length(AWindows));
  for i := 0 to High(ATitles) do
    if i <= High(FTitles) then
      FTitles[i] := ATitles[i];

  // Room above the icon, which is what the tall rule works with.
  availableHeight := AIconTop - PREVIEW_ICON_CLEARANCE - FTopInset;
  FLayout := PreviewLayoutFor(Length(FWindows), AScreenWidth, availableHeight);

  FWindow := TFtWindow.Create(FLayout.Width, FLayout.Height, 'shellsama-preview');
  if FWindow = nil then Exit;

  FWindow.WindowType := ftwtPopupMenu;   // override-redirect: no frames, no focus theft
  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.Style := PREVIEW_PLATE_CSS;
  FWindow.BackgroundOpacity := 0.92;
  FWindow.OnPopupDismiss := @HandleDismiss;

  FArea := TFtDrawingArea.Create(FWindow, 0, 0, FLayout.Width, FLayout.Height);
  FArea.OnPaint := @HandlePaint;
  FArea.OnMouseDown := @HandleMouseDown;
  FArea.OnMouseMove := @HandleMouseMove;
  FArea.OnMouseLeave := @HandleMouseLeave;

  BuildSheet(AStore);

  px := PreviewAnchorX(FLayout, AIconCenterX, AScreenWidth);
  py := PreviewAnchorY(FLayout, AIconTop, FTopInset);
  FWindow.SetPosition(px, py);

  FWindow.Show();
  FArea.Visible := True;
  FWindow.BringToFront();
  // The grab that reports clicks outside the popup back to it. GrabInput would not: it
  // lets clicks on other windows of this client go to those windows.
  FWindow.GrabPopupInput();
  FWindow.Invalidate();

  FOpen := True;
  FRefresh := PreviewRefreshStateInit();
end;

procedure TShellPreviewPopup.Close();
begin
  if Assigned(FWindow) then
  begin
    FWindow.UngrabInput();
    FWindow.Hide();
  end;
  FOpen := False;
  FHover := -1;
end;

procedure TShellPreviewPopup.SetLive(AValue: Boolean);
begin
  FLive := AValue;
end;

function TShellPreviewPopup.Live(): Boolean;
begin
  Result := FLive;
end;

function TShellPreviewPopup.RefreshIfDue(ANowMs: QWord): Boolean;
begin
  Result := False;
  if not FOpen or not FLive then Exit;
  if not Assigned(FWindow) or not Assigned(FArea) then Exit;
  if not Assigned(FStore) then Exit;

  // Not while the tile menu is up. The menu is a separate window, but rebuilding the
  // sheet behind it repaints the popup underneath, which flicks. FTileMenu.Visible is
  // not usable for this: the menu widget is a child of the popup's window and its
  // Visible flag tracks the toolkit's own bookkeeping, not whether its popup window is
  // mapped, so it says True even before Show.
  if FTileMenuShown then Exit;

  if not PreviewRefreshDue(FRefresh, ANowMs) then Exit;

  BuildSheet(FStore);
  // Force a full repaint rather than a dirty-rect one. The popup is small, so the cost
  // difference is negligible, and it removes the partial-present path from the question.
  FArea.Invalidate();
  Result := True;
end;

function TShellPreviewPopup.IsOpen(): Boolean;
begin
  Result := FOpen;
end;

function TShellPreviewPopup.WindowCount(): Integer;
begin
  Result := Length(FWindows);
end;

function TShellPreviewPopup.Layout(): TPreviewLayout;
begin
  Result := FLayout;
end;

function TShellPreviewPopup.Hover(): Integer;
begin
  Result := FHover;
end;

function TShellPreviewPopup.WindowAt(AIndex: Integer): Cardinal;
begin
  if (AIndex < 0) or (AIndex > High(FWindows)) then
    Exit(0);
  Result := FWindows[AIndex];
end;

function TShellPreviewPopup.NativeWindow(): Cardinal;
begin
  Result := 0;
  if Assigned(FWindow) then
    Result := Cardinal(PtrUInt(FWindow.Handle));
end;

procedure TShellPreviewPopup.HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  i: Integer;
  r, t: TPreviewRect;
begin
  if Canvas = nil then Exit;

  // One blit: the sheet already holds every tile at its final size.
  if Assigned(FSheet) then
    Canvas.DrawImage(0, 0, FSheet, 1.0);

  for i := 0 to High(FWindows) do
  begin
    t := PreviewTitleRect(FLayout, i);
    Canvas.DrawTextLeft(t.X, t.Y, t.W, t.H, FTitles[i],
                        PREVIEW_CAPTION_R, PREVIEW_CAPTION_G, PREVIEW_CAPTION_B,
                        FCaptionFont.Handle);
  end;

  if (FHover >= 0) and (FHover <= High(FWindows)) then
  begin
    r := PreviewTileRect(FLayout, FHover);
    Canvas.DrawRoundedRectOutline(r.X, r.Y, r.W, r.H, 8, 2,
                                  PREVIEW_HOVER_R, PREVIEW_HOVER_G, PREVIEW_HOVER_B,
                                  1.0);
  end;
end;

procedure TShellPreviewPopup.HandleMouseDown(Sender: TFtDrawingArea;
  X, Y, Button: Integer);
var
  idx: Integer;
begin
  if Button <> 1 then
  begin
    // Right-click still has to land on a tile, but the early return above would have
    // swallowed it. Fall through to the same hit test.
    idx := PreviewHitTest(FLayout, X, Y);
    if (idx >= 0) and (idx <= High(FWindows)) then
      HandleTileMenu(idx, Button, X, Y);
    Exit;
  end;

  idx := PreviewHitTest(FLayout, X, Y);
  if (idx < 0) or (idx > High(FWindows)) then Exit;

  case Button of
    1:
    begin
      // Hide before activating. Activation raises another window, and leaving this one
      // mapped on top of it would look like the click did nothing.
      Close();
      if Assigned(FOnActivate) then
        FOnActivate(FWindows[idx]);
    end;
    3: HandleTileMenu(idx, Button, X, Y);
  end;
end;

procedure TShellPreviewPopup.HandleMouseMove(Sender: TFtDrawingArea; X, Y: Integer);
var
  idx: Integer;
begin
  idx := PreviewHitTest(FLayout, X, Y);
  if idx = FHover then Exit;

  FHover := idx;
  if Assigned(FArea) then
    FArea.Invalidate();
end;

procedure TShellPreviewPopup.HandleMouseLeave(Sender: TFtDrawingArea; X, Y: Integer);
begin
  if FHover < 0 then Exit;
  FHover := -1;
  if Assigned(FArea) then
    FArea.Invalidate();
end;

procedure TShellPreviewPopup.HandleTileMenu(AIndex, AButton, AX, AY: Integer);
begin
  if (AButton <> 3) or not Assigned(FOnBuildTileMenu) or not Assigned(FWindow) then Exit;
  if (AIndex < 0) or (AIndex > High(FWindows)) then Exit;

  // One menu, reused. A shown menu is the toolkit's grabbed popup until it closes, so
  // freeing it right after Show would leave the grab pointing at freed memory. Keeping
  // one also avoids a new menu object per right-click.
  if not Assigned(FTileMenu) then
  begin
    FTileMenu := TFtPopupMenu.Create(FWindow);
    if FTileMenu = nil then Exit;
  end
  else
    FTileMenu.Clear();

  // The dock fills it, so the tile offers exactly the task list's actions.
  //
  // The items are NOT re-wired here to close the popup: ftpas gives an item one click
  // callback, so doing that would silently replace the action with a dismissal and the
  // menu would do nothing. The popup closes from the tick instead, which sees the
  // window set change and is already the mechanism for that.
  FOnBuildTileMenu(FWindows[AIndex], FTileMenu);

  // Hand the grab to the menu: two owners cannot share it, and the menu is what the user
  // is now interacting with. The popup's own dismissal is not lost, because the dock's
  // tick closes it as soon as the window set changes — which is exactly what any of these
  // actions causes.
  if Assigned(FWindow) then
    FWindow.UngrabInput();

  // The drawing area fills the popup, so its coordinates are already window-local, and
  // ft_popup_menu_show converts window-local to screen itself. Passing screen
  // coordinates here would add the popup's origin a second time.
  FTileMenuShown := True;
  FTileMenu.Show(AX, AY);
end;

procedure TShellPreviewPopup.HandleDismiss(Sender: TFtWindow);
begin
  Close();
  if Assigned(FOnDismiss) then
    FOnDismiss();
end;

end.
