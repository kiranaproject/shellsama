{ Unit ShellSama.PreviewLayout — geometry for the dock's window-preview popup.

  Pure arithmetic, deliberately: the sizes are the part that is easy to get subtly wrong
  and impossible to check by eye, so they are a function over integers with no X, no
  widgets and no toolkit. The popup unit draws whatever this returns.

  The shape comes from docs/window-previews.md §5: 208x117 tiles, a title row under each,
  up to four columns, and a popup anchored to the icon that opened it.

  Two overflow rules, applied in this order:

    1. Tall. If the grid would not fit above the icon, add a column so it loses a row.
       Twelve windows lay out as 6x2 rather than 4x3.
    2. Wide. If it would not fit across the screen, drop a column.

  The order matters. Adding a column makes the popup wider, so the wide rule has to run
  after the tall rule, not before. }

unit ShellSama.PreviewLayout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

const
  PREVIEW_W         = 208;
  PREVIEW_H         = 117;
  PREVIEW_TITLE_H   = 18;
  PREVIEW_TITLE_GAP = 4;    // between the tile and its title
  PREVIEW_GAP_X     = 10;
  PREVIEW_GAP_Y     = 12;
  PREVIEW_PAD       = 12;
  PREVIEW_MAX_COLS  = 4;    // wider stops reading as a popup
  PREVIEW_TALL_COLS = 6;    // how far the tall rule may go
  PREVIEW_SCREEN_EDGE = 8;  // minimum distance from a screen edge
  PREVIEW_ICON_CLEARANCE = 10;

  // One cell: tile, gap, title.
  PREVIEW_CELL_H = PREVIEW_H + PREVIEW_TITLE_GAP + PREVIEW_TITLE_H;

type
  TPreviewLayout = record
    Columns : Integer;
    Rows    : Integer;
    Width   : Integer;
    Height  : Integer;
  end;

  TPreviewRect = record
    X, Y, W, H: Integer;
  end;

{ The grid for AWindowCount tiles.

  AAvailableHeight is the room above the icon, so the tall rule knows when to add a
  column. AScreenWidth bounds the width. Returns a zeroed layout for a count below 1. }
function PreviewLayoutFor(AWindowCount, AScreenWidth, AAvailableHeight: Integer): TPreviewLayout;

{ The tile box for AIndex, in popup-local coordinates. }
function PreviewTileRect(const ALayout: TPreviewLayout; AIndex: Integer): TPreviewRect;

{ The title box under a tile: same width, starting PREVIEW_TITLE_GAP below it. }
function PreviewTitleRect(const ALayout: TPreviewLayout; AIndex: Integer): TPreviewRect;

{ Which tile contains (AX, AY), or -1. Covers the whole cell, title included, so the
  target is the thing the user aimed at rather than a 117px strip inside it. }
function PreviewHitTest(const ALayout: TPreviewLayout; AX, AY: Integer): Integer;

{ Popup left edge, centred on the icon and kept on screen. }
function PreviewAnchorX(const ALayout: TPreviewLayout; AIconCenterX,
  AScreenWidth: Integer): Integer;

{ Popup top edge, sitting above the icon and never under ATopInset. }
function PreviewAnchorY(const ALayout: TPreviewLayout; AIconTop,
  ATopInset: Integer): Integer;

implementation

function PreviewLayoutFor(AWindowCount, AScreenWidth,
  AAvailableHeight: Integer): TPreviewLayout;
var
  cols, rows: Integer;

  procedure Measure();
  begin
    rows := (AWindowCount + cols - 1) div cols;
    Result.Columns := cols;
    Result.Rows := rows;
    Result.Width := (2 * PREVIEW_PAD) + (cols * PREVIEW_W) + ((cols - 1) * PREVIEW_GAP_X);
    Result.Height := (2 * PREVIEW_PAD) + (rows * PREVIEW_CELL_H) +
                     ((rows - 1) * PREVIEW_GAP_Y);
  end;

begin
  Result.Columns := 0;
  Result.Rows := 0;
  Result.Width := 0;
  Result.Height := 0;
  if AWindowCount < 1 then Exit;

  cols := Min(AWindowCount, PREVIEW_MAX_COLS);
  Measure();

  // Tall: more columns, fewer rows. Stop as soon as it fits, or when the grid is as wide
  // as it is allowed to get.
  while (AAvailableHeight > 0) and (Result.Height > AAvailableHeight) and
        (cols < PREVIEW_TALL_COLS) and (cols < AWindowCount) do
  begin
    Inc(cols);
    Measure();
  end;

  // Wide: the tall rule may have made it too wide for the screen.
  while (AScreenWidth > 0) and
        (Result.Width > AScreenWidth - (2 * PREVIEW_SCREEN_EDGE)) and
        (cols > 1) do
  begin
    Dec(cols);
    Measure();
  end;
end;

function PreviewTileRect(const ALayout: TPreviewLayout; AIndex: Integer): TPreviewRect;
var
  col, row: Integer;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.W := 0;
  Result.H := 0;
  if (ALayout.Columns < 1) or (AIndex < 0) then Exit;

  col := AIndex mod ALayout.Columns;
  row := AIndex div ALayout.Columns;

  Result.X := PREVIEW_PAD + (col * (PREVIEW_W + PREVIEW_GAP_X));
  Result.Y := PREVIEW_PAD + (row * (PREVIEW_CELL_H + PREVIEW_GAP_Y));
  Result.W := PREVIEW_W;
  Result.H := PREVIEW_H;
end;

function PreviewTitleRect(const ALayout: TPreviewLayout; AIndex: Integer): TPreviewRect;
var
  tile: TPreviewRect;
begin
  tile := PreviewTileRect(ALayout, AIndex);
  Result.X := tile.X;
  Result.Y := tile.Y + tile.H + PREVIEW_TITLE_GAP;
  Result.W := tile.W;
  Result.H := PREVIEW_TITLE_H;
end;

function PreviewHitTest(const ALayout: TPreviewLayout; AX, AY: Integer): Integer;
var
  col, row, i, cellX, cellY: Integer;
begin
  Result := -1;
  if (ALayout.Columns < 1) or (ALayout.Rows < 1) then Exit;
  if (AX < 0) or (AY < 0) or (AX >= ALayout.Width) or (AY >= ALayout.Height) then Exit;

  // Cell coordinates, so the title row under a tile belongs to that tile.
  col := (AX - PREVIEW_PAD) div (PREVIEW_W + PREVIEW_GAP_X);
  row := (AY - PREVIEW_PAD) div (PREVIEW_CELL_H + PREVIEW_GAP_Y);
  if (col < 0) or (col >= ALayout.Columns) or (row < 0) or (row >= ALayout.Rows) then Exit;

  // Reject the gaps between cells rather than rounding them into a neighbour.
  cellX := AX - (PREVIEW_PAD + (col * (PREVIEW_W + PREVIEW_GAP_X)));
  cellY := AY - (PREVIEW_PAD + (row * (PREVIEW_CELL_H + PREVIEW_GAP_Y)));
  if (cellX < 0) or (cellX >= PREVIEW_W) then Exit;
  if (cellY < 0) or (cellY >= PREVIEW_CELL_H) then Exit;

  i := (row * ALayout.Columns) + col;
  if i < 0 then Exit;
  Result := i;
end;

function PreviewAnchorX(const ALayout: TPreviewLayout; AIconCenterX,
  AScreenWidth: Integer): Integer;
begin
  Result := AIconCenterX - (ALayout.Width div 2);

  if AScreenWidth > 0 then
  begin
    if Result + ALayout.Width > AScreenWidth - PREVIEW_SCREEN_EDGE then
      Result := AScreenWidth - PREVIEW_SCREEN_EDGE - ALayout.Width;
  end;

  if Result < PREVIEW_SCREEN_EDGE then
    Result := PREVIEW_SCREEN_EDGE;
end;

function PreviewAnchorY(const ALayout: TPreviewLayout; AIconTop,
  ATopInset: Integer): Integer;
begin
  Result := AIconTop - ALayout.Height - PREVIEW_ICON_CLEARANCE;
  if Result < ATopInset then
    Result := ATopInset;
end;

end.
