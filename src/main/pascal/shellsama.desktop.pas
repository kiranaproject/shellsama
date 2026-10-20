{ Unit ShellSama.Desktop — Desktop Background & Wallpaper for Samarinda DE }

unit ShellSama.Desktop;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math, BaseUnix, ctypes,
  ftpas.api, ftpas.types, ftpas, ftpas.canvas, ftpas.creative, ftpas.menus,
  ShellSama.DesktopApps;

type
  TWallpaperMode = (
    wmFill,      // Scale to fill screen (crop if necessary, maintain aspect ratio)
    wmFit,       // Fit within screen with letterboxing
    wmStretch,   // Stretch to fill screen (ignore aspect ratio)
    wmCenter,    // Center at original resolution
    wmTile,      // Repeat across screen
    wmSolidColor // Solid background color
  );

  TShellDesktop = class
  private
    FWindow           : TFtWindow;
    FDrawingArea      : TFtDrawingArea;
    FContextMenu      : TFtPopupMenu;
    FWallpaperPath    : string;
    FWallpaperBitmap  : TFtBitmap;
    FWallpaperMode    : TWallpaperMode;
    FBgColorR         : Double;
    FBgColorG         : Double;
    FBgColorB         : Double;
    FWidth            : Integer;
    FHeight           : Integer;
    FIsVisible        : Boolean;

    procedure SetupWindow();
    procedure SetupContextMenu();
    procedure HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandleMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
    procedure HandleChangeWallpaperClick(Sender: TFtMenuItem);
    procedure HandleStyleModeClick(Sender: TFtMenuItem);
    procedure HandleOpenTerminalClick(Sender: TFtMenuItem);
    procedure LoadConfig();
    procedure SaveConfig();
    function GetConfigFilePath(): string;
  public
    constructor Create(AWidth: Integer = 0; AHeight: Integer = 0);
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure SetWallpaper(const APath: string; AMode: TWallpaperMode = wmFill);
    procedure SetWallpaperMode(AMode: TWallpaperMode);
    procedure SetSolidColor(R, G, B: Double);

    property Window: TFtWindow read FWindow;
    property DrawingArea: TFtDrawingArea read FDrawingArea;
    property WallpaperPath: string read FWallpaperPath;
    property WallpaperBitmap: TFtBitmap read FWallpaperBitmap;
    property WallpaperMode: TWallpaperMode read FWallpaperMode write SetWallpaperMode;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property IsVisible: Boolean read FIsVisible;
  end;

implementation

function libc_system(cmd: PChar): cint; cdecl; external 'c' name 'system';

// -----------------------------------------------------------------------------
// TShellDesktop Implementation
// -----------------------------------------------------------------------------

constructor TShellDesktop.Create(AWidth: Integer = 0; AHeight: Integer = 0);
begin
  inherited Create();
  FIsVisible := False;
  FWallpaperBitmap := nil;
  FWallpaperPath := '';
  FWallpaperMode := wmFill;

  // Default elegant Samarinda dark slate / Catppuccin Mocha base (#1e1e2e)
  FBgColorR := 30 / 255;
  FBgColorG := 30 / 255;
  FBgColorB := 46 / 255;

  if (AWidth > 0) and (AHeight > 0) then
  begin
    FWidth := AWidth;
    FHeight := AHeight;
  end
  else if FtIsLibLoaded() and Assigned(ft_screen_get_width) then
  begin
    FWidth := FtApp().ScreenWidth;
    FHeight := FtApp().ScreenHeight;
  end
  else
  begin
    FWidth := 1920;
    FHeight := 1080;
  end;

  SetupWindow();
  LoadConfig();
end;

destructor TShellDesktop.Destroy();
begin
  if Assigned(FWallpaperBitmap) then
  begin
    FWallpaperBitmap.Free();
    FWallpaperBitmap := nil;
  end;

  if Assigned(FContextMenu) then
  begin
    FContextMenu.Free();
    FContextMenu := nil;
  end;

  FDrawingArea := nil;

  if Assigned(FWindow) then
  begin
    FWindow.Free();
    FWindow := nil;
  end;

  inherited Destroy();
end;

procedure TShellDesktop.SetupWindow();
begin
  if not FtIsLibLoaded() then Exit;

  FWindow := TFtWindow.Create(FWidth, FHeight, 'shellsama-desktop');
  if FWindow = nil then Exit;

  FWindow.WindowType := ftwtDesktop;
  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.SetPosition(0, 0);

  FDrawingArea := TFtDrawingArea.Create(FWindow, 0, 0, FWidth, FHeight);
  FDrawingArea.OnPaint := @HandlePaint;
  FDrawingArea.OnMouseDown := @HandleMouseDown;

  SetupContextMenu();
end;

procedure TShellDesktop.SetupContextMenu();
var
  it: TFtMenuItem;
begin
  FContextMenu := TFtPopupMenu.Create(nil);
  FContextMenu.AddItem('Change Wallpaper...', @HandleChangeWallpaperClick);
  FContextMenu.AddSeparator();

  it := FContextMenu.AddItem('Style: Fill Screen', @HandleStyleModeClick);
  if it <> nil then it.Tag := Ord(wmFill);

  it := FContextMenu.AddItem('Style: Fit (Letterbox)', @HandleStyleModeClick);
  if it <> nil then it.Tag := Ord(wmFit);

  it := FContextMenu.AddItem('Style: Stretch', @HandleStyleModeClick);
  if it <> nil then it.Tag := Ord(wmStretch);

  it := FContextMenu.AddItem('Style: Center', @HandleStyleModeClick);
  if it <> nil then it.Tag := Ord(wmCenter);

  it := FContextMenu.AddItem('Style: Tile', @HandleStyleModeClick);
  if it <> nil then it.Tag := Ord(wmTile);

  it := FContextMenu.AddItem('Style: Solid Color', @HandleStyleModeClick);
  if it <> nil then it.Tag := Ord(wmSolidColor);

  FContextMenu.AddSeparator();
  FContextMenu.AddItem('Open Terminal', @HandleOpenTerminalClick);
end;

procedure TShellDesktop.HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  sw, sh, bw, bh: Integer;
  scale: Double;
  dw, dh, dx, dy, tx, ty: Integer;
begin
  if Canvas = nil then Exit;
  sw := FWidth;
  sh := FHeight;

  // 1. Draw solid background color
  Canvas.DrawRect(0, 0, sw, sh, FBgColorR, FBgColorG, FBgColorB, 1.0);

  // 2. Draw wallpaper bitmap if present
  if (FWallpaperBitmap <> nil) and (FWallpaperMode <> wmSolidColor) then
  begin
    bw := FWallpaperBitmap.Width;
    bh := FWallpaperBitmap.Height;

    if (bw > 0) and (bh > 0) then
    begin
      case FWallpaperMode of
        wmFill:
        begin
          scale := Max(sw / bw, sh / bh);
          dw := Round(bw * scale);
          dh := Round(bh * scale);
          dx := (sw - dw) div 2;
          dy := (sh - dh) div 2;
          Canvas.DrawImageScaled(dx, dy, dw, dh, FWallpaperBitmap, 1.0);
        end;

        wmFit:
        begin
          scale := Min(sw / bw, sh / bh);
          dw := Round(bw * scale);
          dh := Round(bh * scale);
          dx := (sw - dw) div 2;
          dy := (sh - dh) div 2;
          Canvas.DrawImageScaled(dx, dy, dw, dh, FWallpaperBitmap, 1.0);
        end;

        wmStretch:
        begin
          Canvas.DrawImageScaled(0, 0, sw, sh, FWallpaperBitmap, 1.0);
        end;

        wmCenter:
        begin
          dx := (sw - bw) div 2;
          dy := (sh - bh) div 2;
          Canvas.DrawImage(dx, dy, FWallpaperBitmap, 1.0);
        end;

        wmTile:
        begin
          ty := 0;
          while ty < sh do
          begin
            tx := 0;
            while tx < sw do
            begin
              Canvas.DrawImage(tx, ty, FWallpaperBitmap, 1.0);
              Inc(tx, bw);
            end;
            Inc(ty, bh);
          end;
        end;

        wmSolidColor:
          ; // Already drawn base solid color
      end;
    end;
  end
  else
  begin
    // Out-of-the-box ambient backdrop gradient/radial accent if no custom wallpaper image is set
    Canvas.DrawCircle(sw div 2, sh div 2, Min(sw, sh) div 3, 40 / 255, 42 / 255, 62 / 255, 0.45);
    Canvas.DrawCircle(sw div 2, sh div 2, Min(sw, sh) div 5, 48 / 255, 52 / 255, 78 / 255, 0.35);
  end;
end;

procedure TShellDesktop.HandleMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
begin
  if Button = 3 then // Right click
  begin
    if FContextMenu <> nil then
      FContextMenu.Show(X, Y);
  end;
end;

procedure TShellDesktop.HandleChangeWallpaperClick(Sender: TFtMenuItem);
var
  chosenFile: string;
begin
  if not Assigned(ft_file_dialog_create) then Exit;

  chosenFile := TFtFileDialog.OpenFile(
    'Select Desktop Wallpaper',
    '',
    'Image Files (*.png;*.jpg;*.jpeg;*.svg)|*.png;*.jpg;*.jpeg;*.svg|All Files (*.*)|*.*'
  );

  if (chosenFile <> '') and FileExists(chosenFile) then
    SetWallpaper(chosenFile, FWallpaperMode);
end;

procedure TShellDesktop.HandleStyleModeClick(Sender: TFtMenuItem);
begin
  if Assigned(Sender) then
    SetWallpaperMode(TWallpaperMode(Sender.Tag));
end;

procedure TShellDesktop.HandleOpenTerminalClick(Sender: TFtMenuItem);
var
  pid: pid_t;
begin
  pid := fpFork();
  if pid = 0 then
  begin
    fpSetsid();
    libc_system('x-terminal-emulator || konsole || gnome-terminal || xfce4-terminal || xterm &');
    fpExit(0);
  end;
end;

procedure TShellDesktop.Show();
begin
  if Assigned(FWindow) and not FIsVisible then
  begin
    FWindow.Show();
    FIsVisible := True;
  end;
end;

procedure TShellDesktop.Hide();
begin
  if Assigned(FWindow) and FIsVisible then
  begin
    FWindow.Hide();
    FIsVisible := False;
  end;
end;

procedure TShellDesktop.SetWallpaper(const APath: string; AMode: TWallpaperMode = wmFill);
var
  newBmp: TFtBitmap;
begin
  FWallpaperMode := AMode;
  if (APath <> '') and FileExists(APath) then
  begin
    try
      newBmp := TFtBitmap.CreateFromFile(APath);
      if Assigned(FWallpaperBitmap) then
        FWallpaperBitmap.Free();
      FWallpaperBitmap := newBmp;
      FWallpaperPath := APath;
    except
      on E: Exception do
      begin
        // Keep existing wallpaper or fallback to solid color on load failure
      end;
    end;
  end
  else
  begin
    if Assigned(FWallpaperBitmap) then
    begin
      FWallpaperBitmap.Free();
      FWallpaperBitmap := nil;
    end;
    FWallpaperPath := '';
  end;

  SaveConfig();

  if Assigned(FWindow) then
    FWindow.Repaint();
end;

procedure TShellDesktop.SetWallpaperMode(AMode: TWallpaperMode);
begin
  if FWallpaperMode <> AMode then
  begin
    FWallpaperMode := AMode;
    SaveConfig();
    if Assigned(FWindow) then
      FWindow.Repaint();
  end;
end;

procedure TShellDesktop.SetSolidColor(R, G, B: Double);
begin
  FBgColorR := EnsureRange(R, 0.0, 1.0);
  FBgColorG := EnsureRange(G, 0.0, 1.0);
  FBgColorB := EnsureRange(B, 0.0, 1.0);
  if Assigned(FWindow) then
    FWindow.Repaint();
end;

function TShellDesktop.GetConfigFilePath(): string;
var
  configDir: string;
begin
  configDir := GetEnvironmentVariable('HOME') + '/.config/shellsama';
  if not DirectoryExists(configDir) then
    ForceDirectories(configDir);
  Result := configDir + '/desktop.conf';
end;

procedure TShellDesktop.LoadConfig();
var
  confPath, line, key, val: string;
  lines: TStringList;
  i, eqPos, modeVal: Integer;
begin
  confPath := GetConfigFilePath();
  if not FileExists(confPath) then Exit;

  lines := TStringList.Create();
  try
    lines.LoadFromFile(confPath);
    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if (line = '') or (line[1] = '#') or (line[1] = ';') or (line[1] = '[') then
        Continue;
      eqPos := Pos('=', line);
      if eqPos > 1 then
      begin
        key := LowerCase(Trim(Copy(line, 1, eqPos - 1)));
        val := Trim(Copy(line, eqPos + 1, Length(line)));

        if key = 'wallpaper' then
        begin
          if (val <> '') and FileExists(val) then
            SetWallpaper(val, FWallpaperMode);
        end
        else if key = 'mode' then
        begin
          modeVal := StrToIntDef(val, -1);
          if (modeVal >= Ord(Low(TWallpaperMode))) and (modeVal <= Ord(High(TWallpaperMode))) then
            FWallpaperMode := TWallpaperMode(modeVal)
          else if LowerCase(val) = 'fill' then FWallpaperMode := wmFill
          else if LowerCase(val) = 'fit' then FWallpaperMode := wmFit
          else if LowerCase(val) = 'stretch' then FWallpaperMode := wmStretch
          else if LowerCase(val) = 'center' then FWallpaperMode := wmCenter
          else if LowerCase(val) = 'tile' then FWallpaperMode := wmTile
          else if LowerCase(val) = 'solid' then FWallpaperMode := wmSolidColor;
        end;
      end;
    end;
  finally
    lines.Free();
  end;
end;

procedure TShellDesktop.SaveConfig();
var
  confPath: string;
  lines: TStringList;
begin
  confPath := GetConfigFilePath();
  lines := TStringList.Create();
  try
    lines.Add('# shellsama desktop wallpaper configuration');
    lines.Add('wallpaper=' + FWallpaperPath);
    case FWallpaperMode of
      wmFill: lines.Add('mode=fill');
      wmFit: lines.Add('mode=fit');
      wmStretch: lines.Add('mode=stretch');
      wmCenter: lines.Add('mode=center');
      wmTile: lines.Add('mode=tile');
      wmSolidColor: lines.Add('mode=solid');
    end;
    lines.SaveToFile(confPath);
  except
    // Non-fatal if config save fails
  end;
  lines.Free();
end;

end.
