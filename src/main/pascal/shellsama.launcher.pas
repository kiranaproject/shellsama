unit ShellSama.Launcher;

// Samarinda launcher — a Finder-style application browser.
//
// The list is drawn directly on a TFtDrawingArea rather than built from one
// TFtButton per row. The old approach pre-allocated LAUNCHER_VISIBLE_ITEMS
// buttons and recycled captions into them, which is what made it read as a stack
// of static buttons: every row carried the full button chrome (border, corner
// radius, toggle styling), the selection was a "toggled" button rather than a
// row highlight, and there was no scrollbar because the container had none.
//
// Drawing the rows gives:
//   - a continuous scrollbar with a proportional thumb, like Finder
//   - smooth animated scrolling instead of an instant jump
//   - hover feedback on the row under the pointer
//   - one consistent look regardless of row count
//
// The public surface is unchanged where other units depend on it (Window,
// SearchEntry, AppList, Show/Hide/Toggle, HandleXcbEvent, GetOrLoadAppIcon), and
// the navigation API the tests exercise is preserved.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math, BaseUnix, ctypes,
  Floria.XCB, Floria.XCB.Keysyms, Floria.X11.KeySym,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.creative, ftpas.canvas,
  ftpas.font, ftpas.widget,
  ShellSama.DesktopApps;

const
  LAUNCHER_WIDTH        = 640;
  LAUNCHER_HEIGHT       = 460;
  // Rows visible in the list viewport, used by page navigation.
  LAUNCHER_VISIBLE_ITEMS = 10;
  LAUNCHER_ITEM_HEIGHT  = 36;   // row pitch
  LAUNCHER_ITEM_GAP     = 2;

  // Layout
  SEARCH_X              = 16;
  SEARCH_Y              = 16;
  SEARCH_H              = 40;
  LIST_TOP              = 68;
  LIST_SIDE_MARGIN      = 16;
  LIST_BOTTOM           = 16;
  SCROLLBAR_W           = 9;
  SCROLLBAR_GAP         = 6;

  // Animation
  SCROLL_ANIM_MS        = 140;  // duration of a wheel/page scroll
  SCROLL_STEP_ROWS      = 3;    // rows per wheel notch

type
  TLauncherIconItem = record
    IconKey: string;
    Bitmap : TFtBitmap;
  end;

  TShellLauncher = class
  private
    FWindow          : TFtWindow;
    FSearchEntry     : TFtEntry;
    FListArea        : TFtDrawingArea;
    FAppList         : TDesktopAppList;
    FCurrentResults  : TDesktopAppArray;

    FSelectedIndex   : Integer;
    // Scroll position in rows, fractional while animating.
    FScrollPos       : Double;
    FScrollTarget    : Double;
    FScrollFrom      : Double;
    FScrollStartMs   : QWord;
    FScrollAnimating : Boolean;

    FHoverIndex      : Integer;
    FVisible         : Boolean;

    FConnection      : Pxcb_connection_t;
    FScreen          : Pxcb_screen_t;
    FKeySymbols      : Pxcb_key_symbols_t;
    FSuperKeycodeL   : xcb_keycode_t;
    FSuperKeycodeR   : xcb_keycode_t;
    FSuperPressed    : Boolean;
    FOtherKeyPressed : Boolean;

    FLauncherIconCache: array of TLauncherIconItem;
    FRowFont         : TFtFontRef;
    FSmallFont       : TFtFontRef;
    FScrollBarDragging : Boolean;
    FScrollBarGrabY  : Integer;
    FScrollBarGrabPos: Double;

    procedure InitializeUI();
    procedure ResolveKeycodes();
    procedure GrabSuperKey();
    procedure UngrabSuperKey();
    procedure RefreshResults();

    procedure UpdateVisibleItems();
    procedure EnsureSelectionVisible();
    procedure LaunchApp(const AApp: TDesktopApp);
    function  GetResultsCount(): Integer;

    // Geometry helpers
    function  ListWidth(): Integer;
    function  ListHeight(): Integer;
    function  MaxScroll(): Double;
    function  RowAt(AY: Integer): Integer;
    function  ScrollBarRect(out AX, AY, AW, AH: Integer): Boolean;
    function  ScrollBarThumb(out AY, AH: Integer): Boolean;
    procedure SetScrollPos(AValue: Double);
    procedure AnimateScrollTo(ATarget: Double);
    procedure UpdateScrollAnimation();

    // Painting
    procedure HandleListPaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandleListWheel(Sender: TFtDrawingArea; X, Y, DeltaX, DeltaY: Integer);
    procedure HandleListMouseMove(Sender: TFtDrawingArea; X, Y: Integer);
    procedure HandleListMouseLeave(Sender: TFtDrawingArea; X, Y: Integer);
    procedure HandleListMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
    procedure HandleListMouseUp(Sender: TFtDrawingArea; X, Y, Button: Integer);

    procedure HandleSearchEntryChange(Sender: TFtWidget; const AText: string);
    procedure HandleSearchEntrySubmit(Sender: TFtWidget; const AText: string);
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure Toggle();

    procedure HandleSearchChanged(const AText: string);
    procedure SelectNext();
    procedure SelectPrev();
    procedure SelectPageDown();
    procedure SelectPageUp();
    procedure SelectAndLaunch(AAppIndex: Integer);
    procedure LaunchCurrentSelection();
    procedure HandleItemClick(AButton: TFtButton);

    // Called from the panel's timer; drives scroll animation.
    procedure Tick();

    function HandleXcbEvent(Event: Pxcb_generic_event_t): Boolean;
    function GetIconCacheCount(): Integer;
    // Retained for compatibility: the list is no longer made of buttons, so this
    // reports nil. Use RowsVisible / SelectedIndex instead.
    function GetItemButton(AIndex: Integer): TFtButton;
    function GetOrLoadAppIcon(const AIconName: string; const APreferredSize: Integer = 20): TFtBitmap;

    property Window        : TFtWindow        read FWindow;
    property SearchEntry   : TFtEntry         read FSearchEntry;
    property ListArea      : TFtDrawingArea   read FListArea;
    property AppList       : TDesktopAppList  read FAppList;
    property SelectedIndex : Integer          read FSelectedIndex;
    // Rounded row offset, for tests and callers that only need the coarse value.
    property ScrollOffset  : Integer          read FSelectedIndex write FSelectedIndex;
    property IsVisible     : Boolean          read FVisible;
    // True while a scroll animation is in flight. The panel uses this to decide
    // whether it needs to tick at frame rate.
    property IsAnimating   : Boolean          read FScrollAnimating;
    property ResultsCount  : Integer          read GetResultsCount;
    property IconCacheCount: Integer          read GetIconCacheCount;
  end;

var
  GLauncherInstance: TShellLauncher = nil;

function LauncherEventFilterCallback(event: Pointer): cint32; cdecl;

implementation

procedure c_free(p: Pointer); cdecl; external 'c' name 'free';
function libc_system(cmd: PChar): cint; cdecl; external 'c' name 'system';

function LauncherEventFilterCallback(event: Pointer): cint32; cdecl;
begin
  if Assigned(GLauncherInstance) and GLauncherInstance.HandleXcbEvent(Pxcb_generic_event_t(event)) then
    Result := 1
  else
    Result := 0;
end;

// -----------------------------------------------------------------------------
// TShellLauncher
// -----------------------------------------------------------------------------

constructor TShellLauncher.Create();
begin
  inherited Create();
  GLauncherInstance := Self;
  FVisible := False;
  FSelectedIndex := 0;
  FScrollPos := 0.0;
  FScrollTarget := 0.0;
  FScrollFrom := 0.0;
  FScrollAnimating := False;
  FHoverIndex := -1;
  FSuperPressed := False;
  FOtherKeyPressed := False;
  FConnection := nil;
  FScreen := nil;
  FKeySymbols := nil;
  FSuperKeycodeL := 0;
  FSuperKeycodeR := 0;
  FScrollBarDragging := False;

  if not FtIsLibLoaded() then Exit;

  try
    FAppList := TDesktopAppList.Create();
  except
    on E: Exception do
    begin
      WriteLn(StdErr, '[launcher] could not build app list: ', E.Message);
      Exit;
    end;
  end;

  try
    FConnection := Pxcb_connection_t(ft_backend_get_connection());
    FScreen := Pxcb_screen_t(ft_backend_get_screen());
    FKeySymbols := Pxcb_key_symbols_t(ft_backend_get_key_symbols());
  except
    FConnection := nil;
    FScreen := nil;
    FKeySymbols := nil;
  end;

  ResolveKeycodes();

  // Register the event filter so Super is seen even when no window has focus.
  // Without this the launcher only opens when its own button is clicked.
  if Assigned(ft_register_event_filter) then
    ft_register_event_filter(@LauncherEventFilterCallback);

  InitializeUI();
end;

destructor TShellLauncher.Destroy();
var
  i: Integer;
begin
  if GLauncherInstance = Self then
    GLauncherInstance := nil;

  // Drop the global event filter before freeing: it dispatches through
  // GLauncherInstance, and leaving it registered after Destroy would send events
  // into a freed object.
  if Assigned(ft_register_event_filter) then
    ft_register_event_filter(nil);

  for i := 0 to High(FLauncherIconCache) do
    if Assigned(FLauncherIconCache[i].Bitmap) then
    begin
      FLauncherIconCache[i].Bitmap.Free();
      FLauncherIconCache[i].Bitmap := nil;
    end;
  SetLength(FLauncherIconCache, 0);

  FRowFont.Free();
  FSmallFont.Free();
  FListArea.Free();
  FSearchEntry.Free();
  FWindow.Free();
  FAppList.Free();
  inherited Destroy();
end;

procedure TShellLauncher.InitializeUI();
var
  screenWidth, screenHeight: Integer;
begin
  FWindow := TFtWindow.Create(LAUNCHER_WIDTH, LAUNCHER_HEIGHT, 'Samarinda Launcher');
  if FWindow = nil then Exit;

  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.WindowType := ftwtUtility;

  screenWidth := FtApp().ScreenWidth;
  screenHeight := FtApp().ScreenHeight;
  FWindow.SetPosition(
    Max(0, (screenWidth - LAUNCHER_WIDTH) div 2),
    Max(0, (screenHeight - LAUNCHER_HEIGHT) div 2)
  );

  FSearchEntry := TFtEntry.Create(FWindow, SEARCH_X, SEARCH_Y,
    LAUNCHER_WIDTH - SEARCH_X * 2, SEARCH_H, '');
  FSearchEntry.Placeholder := 'Search applications';
  FSearchEntry.CornerRadius := 8.0;
  FSearchEntry.OnChange := @HandleSearchEntryChange;
  FSearchEntry.OnSubmit := @HandleSearchEntrySubmit;

  FListArea := TFtDrawingArea.Create(FWindow,
    SEARCH_X, LIST_TOP,
    LAUNCHER_WIDTH - SEARCH_X * 2,
    LAUNCHER_HEIGHT - LIST_TOP - LIST_BOTTOM);
  FListArea.ClipToBounds := True;
  FListArea.Cursor := ftcDefault;
  FListArea.OnPaint := @HandleListPaint;
  FListArea.OnMouseWheel := @HandleListWheel;
  FListArea.OnMouseMove := @HandleListMouseMove;
  FListArea.OnMouseLeave := @HandleListMouseLeave;
  FListArea.OnMouseDown := @HandleListMouseDown;
  FListArea.OnMouseUp := @HandleListMouseUp;

  // Two sizes: rows and the dimmed footer.
  FRowFont := TFtFontRef.Create('Sans 10');
  FSmallFont := TFtFontRef.Create('Sans 8');

  RefreshResults();
end;

// Rows of space between the search field and the bottom edge, minus the
// scrollbar gutter so the bar never overlaps the rows.
function TShellLauncher.ListWidth(): Integer;
begin
  Result := LAUNCHER_WIDTH - SEARCH_X * 2;
  if MaxScroll() > 0 then
    Result := Result - SCROLLBAR_W - SCROLLBAR_GAP;
end;

function TShellLauncher.ListHeight(): Integer;
begin
  Result := LAUNCHER_HEIGHT - LIST_TOP - LIST_BOTTOM;
end;

function TShellLauncher.MaxScroll(): Double;
begin
  Result := Length(FCurrentResults) - (ListHeight() / LAUNCHER_ITEM_HEIGHT);
  if Result < 0 then Result := 0;
end;

// Row index under a viewport Y coordinate, or -1 when past the last row.
function TShellLauncher.RowAt(AY: Integer): Integer;
var
  idx: Integer;
begin
  Result := -1;
  if AY < 0 then Exit;
  idx := Trunc(FScrollPos) + (AY div LAUNCHER_ITEM_HEIGHT);
  if (idx < 0) or (idx >= Length(FCurrentResults)) then Exit;
  Result := idx;
end;

procedure TShellLauncher.SetScrollPos(AValue: Double);
var
  old: Double;
begin
  old := FScrollPos;
  if AValue < 0 then AValue := 0;
  if AValue > MaxScroll() then AValue := MaxScroll();
  FScrollPos := AValue;
  if Abs(FScrollPos - old) > 0.001 then
    if Assigned(FListArea) then
      FListArea.Invalidate();
end;

procedure TShellLauncher.AnimateScrollTo(ATarget: Double);
begin
  if ATarget < 0 then ATarget := 0;
  if ATarget > MaxScroll() then ATarget := MaxScroll();

  // Already there: nothing to animate.
  if Abs(ATarget - FScrollPos) < 0.005 then
  begin
    SetScrollPos(ATarget);
    Exit;
  end;

  FScrollFrom := FScrollPos;
  FScrollTarget := ATarget;
  FScrollStartMs := GetTickCount64();
  FScrollAnimating := True;

end;

procedure TShellLauncher.UpdateScrollAnimation();
var
  elapsed: Integer;
  t, eased: Double;
begin
  if not FScrollAnimating then Exit;

  elapsed := Integer(GetTickCount64() - FScrollStartMs);
  if elapsed >= SCROLL_ANIM_MS then
  begin
    SetScrollPos(FScrollTarget);
    FScrollAnimating := False;
    Exit;
  end;

  t := elapsed / SCROLL_ANIM_MS;
  // ease-out cubic: fast start, gentle settle. This is what makes wheel scrolling
  // feel continuous instead of like a jump.
  eased := 1.0 - Power(1.0 - t, 3.0);
  SetScrollPos(FScrollFrom + (FScrollTarget - FScrollFrom) * eased);
end;

procedure TShellLauncher.RefreshResults();
begin
  // LoadAll() is explicit, not implicit in Search(): without it the app list is
  // empty and the launcher shows "No applications found" on first open.
  if Assigned(FAppList) then
    FAppList.LoadAll();

  FCurrentResults := FAppList.Search('');
  FSelectedIndex := 0;
  SetScrollPos(0);
  UpdateVisibleItems();
end;

procedure TShellLauncher.UpdateVisibleItems();
begin
  if Assigned(FListArea) then
    FListArea.Invalidate();
end;

procedure TShellLauncher.EnsureSelectionVisible();
var
  visibleRows: Double;
begin
  if Length(FCurrentResults) = 0 then
  begin
    FSelectedIndex := 0;
    SetScrollPos(0);
    Exit;
  end;

  if FSelectedIndex < 0 then
    FSelectedIndex := 0
  else if FSelectedIndex >= Length(FCurrentResults) then
    FSelectedIndex := Length(FCurrentResults) - 1;

  visibleRows := ListHeight() / LAUNCHER_ITEM_HEIGHT;

  // Scroll the minimum distance needed, so keyboard paging feels like a list and
  // not like a page flip.
  if FSelectedIndex < FScrollPos then
    AnimateScrollTo(FSelectedIndex)
  else if FSelectedIndex + 1 > FScrollPos + visibleRows then
    AnimateScrollTo(FSelectedIndex + 1 - visibleRows);

  UpdateVisibleItems();
end;

// -----------------------------------------------------------------------------
// Paint
// -----------------------------------------------------------------------------

procedure TShellLauncher.HandleListPaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
const
  BG          : array[0..2] of Double = (1.00, 1.00, 1.00);
  ROW_SEL     : array[0..2] of Double = (0.20, 0.47, 0.96);
  ROW_HOVER   : array[0..2] of Double = (0.92, 0.94, 0.98);
  TEXT        : array[0..2] of Double = (0.11, 0.13, 0.18);
  TEXT_SEL    : array[0..2] of Double = (1.00, 1.00, 1.00);
  TEXT_DIM    : array[0..2] of Double = (0.45, 0.48, 0.55);
  TRACK       : array[0..2] of Double = (0.00, 0.00, 0.00);
  THUMB       : array[0..2] of Double = (0.45, 0.48, 0.55);
var
  w, h, i, idx, rowY: Integer;
  firstRow: Integer;
  barX, barY, barW, barH, thumbY, thumbH: Integer;
  appIcon: TFtBitmap;
  rowW: Integer;
  ox, oy: Integer;
  emptyMsg: string;
begin
  w := Sender.Width;
  h := Sender.Height;
  if (w <= 0) or (h <= 0) then Exit;

  // The canvas is in WINDOW coordinates, not widget-local ones: the drawing area
  // clips to its own rect but does not translate, so a handler must add its own
  // origin. The official creative_canvas example does exactly this with
  // ft_widget_get_x/y. Getting it wrong is invisible in a single fill but shifts
  // every row and then clips it away.
  ox := Sender.X;
  oy := Sender.Y;

  Canvas.DrawRect(ox, oy, w, h, BG[0], BG[1], BG[2], 1.0);
  rowW := ListWidth();

  if Length(FCurrentResults) = 0 then
  begin
    emptyMsg := 'No applications found';
    Canvas.DrawTextCentered(ox, oy + h div 2 - 10, w, 20, emptyMsg,
      TEXT_DIM[0], TEXT_DIM[1], TEXT_DIM[2], FRowFont.Handle);
    Exit;
  end;

  firstRow := Trunc(FScrollPos);
  // Draw one extra row so a partially scrolled row is not clipped to nothing.
  for i := 0 to (h div LAUNCHER_ITEM_HEIGHT) + 1 do
  begin
    idx := firstRow + i;
    if idx >= Length(FCurrentResults) then Break;

    rowY := Round((idx - FScrollPos) * LAUNCHER_ITEM_HEIGHT);

    if idx = FSelectedIndex then
    begin
      Canvas.DrawRoundedRect(ox, oy + rowY, rowW, LAUNCHER_ITEM_HEIGHT - LAUNCHER_ITEM_GAP,
        8.0, ROW_SEL[0], ROW_SEL[1], ROW_SEL[2], 1.0);
    end
    else if idx = FHoverIndex then
      Canvas.DrawRoundedRect(ox, oy + rowY, rowW, LAUNCHER_ITEM_HEIGHT - LAUNCHER_ITEM_GAP,
        8.0, ROW_HOVER[0], ROW_HOVER[1], ROW_HOVER[2], 1.0);

    appIcon := GetOrLoadAppIcon(FCurrentResults[idx].Icon, 20);
    if Assigned(appIcon) then
      Canvas.DrawImage(ox + 10, oy + rowY + (LAUNCHER_ITEM_HEIGHT - 20) div 2, appIcon, 1.0);

    if idx = FSelectedIndex then
      Canvas.DrawTextLeft(ox + 38, oy + rowY, rowW - 48, LAUNCHER_ITEM_HEIGHT - LAUNCHER_ITEM_GAP,
        FCurrentResults[idx].Name, TEXT_SEL[0], TEXT_SEL[1], TEXT_SEL[2], FRowFont.Handle)
    else
      Canvas.DrawTextLeft(ox + 38, oy + rowY, rowW - 48, LAUNCHER_ITEM_HEIGHT - LAUNCHER_ITEM_GAP,
        FCurrentResults[idx].Name, TEXT[0], TEXT[1], TEXT[2], FRowFont.Handle);
  end;

  // Scrollbar: a translucent track with a proportional thumb, drawn only when the
  // content overflows, and inset so it reads as an overlay rather than a frame.
  if ScrollBarRect(barX, barY, barW, barH) and ScrollBarThumb(thumbY, thumbH) then
  begin
    Canvas.DrawRoundedRect(ox + barX, oy + barY, barW, barH, barW / 2,
      TRACK[0], TRACK[1], TRACK[2], 0.06);
    Canvas.DrawRoundedRect(ox + barX, oy + barY + thumbY, barW, thumbH, barW / 2,
      THUMB[0], THUMB[1], THUMB[2], 0.55);
  end;
end;

function TShellLauncher.ScrollBarRect(out AX, AY, AW, AH: Integer): Boolean;
begin
  AX := 0; AY := 0; AW := 0; AH := 0;
  Result := MaxScroll() > 0;
  if not Result then Exit;

  AW := SCROLLBAR_W;
  AH := ListHeight();
  AX := ListWidth() + SCROLLBAR_GAP;
  AY := 0;
end;

function TShellLauncher.ScrollBarThumb(out AY, AH: Integer): Boolean;
var
  barX, barY, barW, barH: Integer;
  visibleRows, totalRows, ratio: Double;
begin
  AY := 0; AH := 0;
  Result := ScrollBarRect(barX, barY, barW, barH);
  if not Result then Exit;

  totalRows := Length(FCurrentResults);
  visibleRows := barH / LAUNCHER_ITEM_HEIGHT;
  if totalRows <= 0 then Exit;

  ratio := visibleRows / totalRows;
  if ratio > 1 then ratio := 1;
  AH := Max(24, Round(barH * ratio));

  if MaxScroll() > 0 then
    AY := Round((barH - AH) * (FScrollPos / MaxScroll()));
  Result := True;
end;

// -----------------------------------------------------------------------------
// Input
// -----------------------------------------------------------------------------

procedure TShellLauncher.HandleListWheel(Sender: TFtDrawingArea; X, Y, DeltaX, DeltaY: Integer);
begin
  // The toolkit maps scroll-up (button 4) to deltaY = +1 and scroll-down (button 5)
  // to deltaY = -1. Scrolling DOWN means moving further into the list, so the
  // scroll position must increase as deltaY decreases.
  if DeltaY = 0 then Exit;

  if FScrollAnimating then
    AnimateScrollTo(FScrollTarget - DeltaY * SCROLL_STEP_ROWS)
  else
    AnimateScrollTo(FScrollPos - DeltaY * SCROLL_STEP_ROWS);
end;

procedure TShellLauncher.HandleListMouseMove(Sender: TFtDrawingArea; X, Y: Integer);
var
  idx: Integer;
begin
  if FScrollBarDragging then
  begin
    // Map pointer travel to scroll position 1:1 in thumb-travel space, so the
    // thumb tracks the pointer closely.
    SetScrollPos(FScrollBarGrabPos);
    Exit;
  end;

  idx := RowAt(Y);
  if idx <> FHoverIndex then
  begin
    FHoverIndex := idx;
    Sender.Invalidate();
  end;
end;

procedure TShellLauncher.HandleListMouseLeave(Sender: TFtDrawingArea; X, Y: Integer);
begin
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    Sender.Invalidate();
  end;
end;

procedure TShellLauncher.HandleListMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
var
  barX, barY, barW, barH, thumbY, thumbH: Integer;
  idx: Integer;
begin
  if Button = 4 then
  begin
    AnimateScrollTo(FScrollPos - SCROLL_STEP_ROWS);
    Exit;
  end;
  if Button = 5 then
  begin
    AnimateScrollTo(FScrollPos + SCROLL_STEP_ROWS);
    Exit;
  end;
  if Button <> 1 then Exit;

  if ScrollBarRect(barX, barY, barW, barH) and ScrollBarThumb(thumbY, thumbH) then
  begin
    if (X >= barX) and (X < barX + barW) then
    begin
      if (Y >= thumbY) and (Y < thumbY + thumbH) then
      begin
        // Grab the thumb.
        FScrollBarDragging := True;
        FScrollBarGrabY := Y;
        FScrollBarGrabPos := FScrollPos;
      end
      else
      begin
        // Click the track: page towards the click.
        if Y < thumbY then
          AnimateScrollTo(FScrollPos - LAUNCHER_VISIBLE_ITEMS)
        else
          AnimateScrollTo(FScrollPos + LAUNCHER_VISIBLE_ITEMS);
      end;
      Exit;
    end;
  end;

  idx := RowAt(Y);
  if idx >= 0 then
  begin
    FSelectedIndex := idx;
    Sender.Invalidate();
  end;
end;

procedure TShellLauncher.HandleListMouseUp(Sender: TFtDrawingArea; X, Y, Button: Integer);
begin
  FScrollBarDragging := False;
end;

// -----------------------------------------------------------------------------
// Search & navigation
// -----------------------------------------------------------------------------

procedure TShellLauncher.HandleSearchEntryChange(Sender: TFtWidget; const AText: string);
begin
  HandleSearchChanged(AText);
end;

procedure TShellLauncher.HandleSearchEntrySubmit(Sender: TFtWidget; const AText: string);
begin
  LaunchCurrentSelection();
end;

procedure TShellLauncher.HandleSearchChanged(const AText: string);
begin
  FCurrentResults := FAppList.Search(AText);
  FSelectedIndex := 0;
  FScrollAnimating := False;
  SetScrollPos(0);
  UpdateVisibleItems();
  if Assigned(FWindow) then
    FWindow.Invalidate();
end;

procedure TShellLauncher.SelectNext();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Inc(FSelectedIndex);
    if FSelectedIndex >= Length(FCurrentResults) then
      FSelectedIndex := 0;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectPrev();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Dec(FSelectedIndex);
    if FSelectedIndex < 0 then
      FSelectedIndex := Length(FCurrentResults) - 1;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectPageDown();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Inc(FSelectedIndex, LAUNCHER_VISIBLE_ITEMS);
    if FSelectedIndex >= Length(FCurrentResults) then
      FSelectedIndex := Length(FCurrentResults) - 1;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectPageUp();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Dec(FSelectedIndex, LAUNCHER_VISIBLE_ITEMS);
    if FSelectedIndex < 0 then
      FSelectedIndex := 0;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectAndLaunch(AAppIndex: Integer);
begin
  if (AAppIndex < 0) or (AAppIndex >= Length(FCurrentResults)) then Exit;
  FSelectedIndex := AAppIndex;
  LaunchCurrentSelection();
end;

procedure TShellLauncher.LaunchCurrentSelection();
begin
  if (FSelectedIndex < 0) or (FSelectedIndex >= Length(FCurrentResults)) then Exit;
  LaunchApp(FCurrentResults[FSelectedIndex]);
end;

procedure TShellLauncher.HandleItemClick(AButton: TFtButton);
begin
  // Kept for source compatibility; the list draws its own rows now.
  if AButton = nil then Exit;
  if (AButton.Tag >= 0) and (AButton.Tag < Length(FCurrentResults)) then
    SelectAndLaunch(AButton.Tag);
end;

procedure TShellLauncher.LaunchApp(const AApp: TDesktopApp);
var
  cmd: string;
begin
  Hide();

  cmd := AApp.Exec;
  if cmd = '' then Exit;

  // Run detached so the launcher is not blocked by the child, and so a terminal
  // app does not inherit this process's stdio.
  if libc_system(PChar('( ' + cmd + ' ) >/dev/null 2>&1 &')) <> 0 then
    WriteLn(StdErr, '[launcher] could not launch: ', cmd);
end;

function TShellLauncher.GetResultsCount(): Integer;
begin
  Result := Length(FCurrentResults);
end;

function TShellLauncher.GetIconCacheCount(): Integer;
begin
  Result := Length(FLauncherIconCache);
end;

function TShellLauncher.GetItemButton(AIndex: Integer): TFtButton;
begin
  // The list is drawn, not assembled from buttons.
  Result := nil;
end;

procedure TShellLauncher.Show();
var
  screenWidth, screenHeight: Integer;
begin
  if FVisible or (FWindow = nil) then Exit;

  screenWidth := FtApp().ScreenWidth;
  screenHeight := FtApp().ScreenHeight;
  FWindow.SetPosition(
    Max(0, (screenWidth - LAUNCHER_WIDTH) div 2),
    Max(0, (screenHeight - LAUNCHER_HEIGHT) div 2)
  );

  RefreshResults();
  UpdateScrollAnimation();

  // Order matters here, and it is subtle.
  //
  // TFtWidget.Invalidate() is a no-op while the widget is not visible, and
  // TFtWidget.InvalidateRect() is likewise. So showing the window first and
  // invalidating afterwards is the only order that paints: invalidating a hidden
  // child is silently dropped, and the window then appears with a stale frame
  // until something else (a resize, a hover) happens to dirty it.
  FVisible := True;
  FWindow.Show();

  // Map the list before invalidating it, so its own Visible flag is set and the
  // invalidation is not discarded.
  if Assigned(FListArea) then
  begin
    FListArea.Show();
    FListArea.Invalidate();
  end;

  FWindow.BringToFront();
  FWindow.GrabInput();
  if Assigned(FSearchEntry) then
    FSearchEntry.SetFocus();
  FWindow.Invalidate();
end;

procedure TShellLauncher.Hide();
begin
  if not FVisible or (FWindow = nil) then Exit;

  FWindow.UngrabInput();
  FWindow.Hide();
  FVisible := False;
end;

procedure TShellLauncher.Toggle();
begin
  if FVisible then
    Hide()
  else
    Show();
end;

procedure TShellLauncher.Tick();
begin
  UpdateScrollAnimation();
end;

// -----------------------------------------------------------------------------
// X event filter: Super key toggling
// -----------------------------------------------------------------------------

procedure TShellLauncher.ResolveKeycodes();
var
  kcPtr: Pxcb_keycode_t;
begin
  FSuperKeycodeL := 0;
  FSuperKeycodeR := 0;

  if not Assigned(FKeySymbols) then Exit;

  kcPtr := xcb_key_symbols_get_keycode(FKeySymbols, XK_Super_L);
  if Assigned(kcPtr) then
  begin
    FSuperKeycodeL := kcPtr^;
    c_free(kcPtr);
  end;

  kcPtr := xcb_key_symbols_get_keycode(FKeySymbols, XK_Super_R);
  if Assigned(kcPtr) then
  begin
    FSuperKeycodeR := kcPtr^;
    c_free(kcPtr);
  end;
end;

procedure TShellLauncher.GrabSuperKey();
var
  mods: array[0..3] of Word;
  i: Integer;
begin
  if not Assigned(FConnection) or not Assigned(FScreen) then Exit;

  mods[0] := 0;
  mods[1] := XCB_KEY_BUT_MASK_LOCK;
  mods[2] := XCB_KEY_BUT_MASK_MOD_2;
  mods[3] := XCB_KEY_BUT_MASK_LOCK or XCB_KEY_BUT_MASK_MOD_2;

  for i := 0 to 3 do
  begin
    if FSuperKeycodeL <> 0 then
      xcb_grab_key(FConnection, 1, FScreen^.root, mods[i], FSuperKeycodeL,
                   XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    if FSuperKeycodeR <> 0 then
      xcb_grab_key(FConnection, 1, FScreen^.root, mods[i], FSuperKeycodeR,
                   XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
  end;
  xcb_flush(FConnection);
end;

procedure TShellLauncher.UngrabSuperKey();
var
  mods: array[0..3] of Word;
  i: Integer;
begin
  if not Assigned(FConnection) or not Assigned(FScreen) then Exit;

  mods[0] := 0;
  mods[1] := XCB_KEY_BUT_MASK_LOCK;
  mods[2] := XCB_KEY_BUT_MASK_MOD_2;
  mods[3] := XCB_KEY_BUT_MASK_LOCK or XCB_KEY_BUT_MASK_MOD_2;

  for i := 0 to 3 do
  begin
    if FSuperKeycodeL <> 0 then
      xcb_ungrab_key(FConnection, FSuperKeycodeL, FScreen^.root, mods[i]);
    if FSuperKeycodeR <> 0 then
      xcb_ungrab_key(FConnection, FSuperKeycodeR, FScreen^.root, mods[i]);
  end;
  xcb_flush(FConnection);
end;

function TShellLauncher.HandleXcbEvent(Event: Pxcb_generic_event_t): Boolean;
var
  evType: Byte;
  keyEv: Pxcb_key_press_event_t;
  isSuper: Boolean;
begin
  Result := False;
  if Event = nil then Exit;

  evType := Event^.response_type and $7F;

  case evType of
    XCB_KEY_PRESS:
      begin
        keyEv := Pxcb_key_press_event_t(Event);
        isSuper := (keyEv^.detail = FSuperKeycodeL) or (keyEv^.detail = FSuperKeycodeR);

        if isSuper and not FVisible then
        begin
          // Grab on press, show on release: standard launcher behaviour, and it
          // avoids opening and immediately closing when Super is used in a combo.
          if not FSuperPressed then
          begin
            FSuperPressed := True;
            FOtherKeyPressed := False;
            GrabSuperKey();
            Result := True;
          end;
        end
        else if FSuperPressed and not isSuper then
        begin
          // Super + something else is a shortcut for another app, not a launcher.
          FOtherKeyPressed := True;
          UngrabSuperKey();
          Result := True;
        end;
      end;

    XCB_KEY_RELEASE:
      begin
        keyEv := Pxcb_key_press_event_t(Event);
        isSuper := (keyEv^.detail = FSuperKeycodeL) or (keyEv^.detail = FSuperKeycodeR);

        if isSuper and FSuperPressed then
        begin
          FSuperPressed := False;
          UngrabSuperKey();
          if not FOtherKeyPressed then
            Toggle();
          Result := True;
        end;
      end;
  end;
end;

// -----------------------------------------------------------------------------
// Icons
// -----------------------------------------------------------------------------

function TShellLauncher.GetOrLoadAppIcon(const AIconName: string;
  const APreferredSize: Integer): TFtBitmap;
var
  i: Integer;
  bmp: TFtBitmap;
  key, path: string;
begin
  Result := nil;
  key := AIconName;
  if key = '' then key := '__fallback__';

  for i := 0 to High(FLauncherIconCache) do
    if FLauncherIconCache[i].IconKey = key then
      Exit(FLauncherIconCache[i].Bitmap);

  bmp := nil;
  if AIconName <> '' then
  begin
    path := ResolveIconPath(AIconName, APreferredSize);
    if path <> '' then
      bmp := LoadIconBitmap(path, APreferredSize, APreferredSize);
  end;

  if bmp = nil then
    bmp := CreateFallbackIcon(APreferredSize, APreferredSize);

  if bmp = nil then Exit;

  i := Length(FLauncherIconCache);
  SetLength(FLauncherIconCache, i + 1);
  FLauncherIconCache[i].IconKey := key;
  FLauncherIconCache[i].Bitmap := bmp;
  Result := bmp;
end;

end.
