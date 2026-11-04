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
  ShellSama.WindowPixmaps;

type
  TPreviewActivateEvent = procedure(AWindow: Cardinal) of object;
  TPreviewDismissEvent  = procedure() of object;

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
  PREVIEW_SHEET_DEPTH = 32;

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
    // Raw BGRA rows for the sheet, kept only long enough for ft_bitmap_create_from_bgra
    // to copy them.
    FSheetPixels: Pointer;
    FSheetPixelsSize: Integer;
    FCaptionFont: TFtFontRef;

    FWindows  : array of Cardinal;
    FTitles   : array of string;
    FLayout   : TPreviewLayout;
    FHover    : Integer;
    FOpen     : Boolean;

    FOnActivate: TPreviewActivateEvent;
    FOnDismiss : TPreviewDismissEvent;

    procedure HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandleMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
    procedure HandleMouseMove(Sender: TFtDrawingArea; X, Y: Integer);
    procedure HandleMouseLeave(Sender: TFtDrawingArea; X, Y: Integer);
    procedure HandleDismiss(Sender: TFtWindow);

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
    function WindowCount(): Integer;
    function Layout(): TPreviewLayout;
    function Hover(): Integer;
    function WindowAt(AIndex: Integer): Cardinal;
    // Test seam: the window id of the popup, or 0 when closed.
    function NativeWindow(): Cardinal;

    property OnActivate: TPreviewActivateEvent read FOnActivate write FOnActivate;
    property OnDismiss: TPreviewDismissEvent read FOnDismiss write FOnDismiss;
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
  FWindow := nil;
  FArea := nil;
  FSheet := nil;
  FSheetPixels := nil;
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
  if FSheetPixels <> nil then
  begin
    FreeMem(FSheetPixels);
    FSheetPixels := nil;
    FSheetPixelsSize := 0;
  end;
end;

procedure TShellPreviewPopup.ReleaseWindow();
begin
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
  ReleaseSheet();
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
  FSheetPixelsSize := FLayout.Width * FLayout.Height * 4;
  GetMem(FSheetPixels, FSheetPixelsSize);
  if not XcbRenderReadPixmap(FConn, sheetPixmap, FLayout.Width, FLayout.Height,
                             FSheetPixels, FSheetPixelsSize) then
  begin
    FreeMem(FSheetPixels);
    FSheetPixels := nil;
    FSheetPixelsSize := 0;
  end;
  xcb_free_pixmap(FConn, sheetPixmap);

  if FSheetPixels <> nil then
  begin
    // Render's output is premultiplied; ftpas has no way to mark a bitmap as such, so
    // straighten it here or every partially transparent window draws too dark.
    XcbDemultiplyBgra(FSheetPixels, FLayout.Width, FLayout.Height);
    // Through the toolkit's own bitmap constructor rather than TFtBitmap.Wrap: a
    // TFloriaImage built by this program's copy of the image unit is a different class
    // object from the one libft checks for, and the draw call would silently skip it.
    FSheet := TFtBitmap.CreateFromBGRA(FSheetPixels, FLayout.Width, FLayout.Height);
  end;
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
  if Button <> 1 then Exit;

  idx := PreviewHitTest(FLayout, X, Y);
  if (idx < 0) or (idx > High(FWindows)) then Exit;

  // Hide before activating. Activation raises another window, and leaving this one
  // mapped on top of it would look like the click did nothing.
  Close();
  if Assigned(FOnActivate) then
    FOnActivate(FWindows[idx]);
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

procedure TShellPreviewPopup.HandleDismiss(Sender: TFtWindow);
begin
  Close();
  if Assigned(FOnDismiss) then
    FOnDismiss();
end;

end.
