{ Unit ShellSama.Applets — Desktop Panel Built-in Applets (Volume, Clock & Session) }

unit ShellSama.Applets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process, DateUtils,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.menus,
  ftpas.canvas, ftpas.creative;

type
  TVolumeIconKind = (vikMuted, vikLow, vikMedium, vikHigh);

  { TShellVolumeApplet — Interactive Volume Control Applet & Popup }
  TShellVolumeApplet = class
  private
    FPanelWindow   : TFtWindow;
    FButton        : TFtButton;
    FPopupWindow   : TFtWindow;
    FPlate         : TFtDrawingArea;
    FVolumeLabel   : TFtLabel;
    FVolumeSlider  : TFtSlider;
    FMuteBtn       : TFtButton;

    FCurVolume     : Integer;
    FIsMuted       : Boolean;
    FIconKind      : TVolumeIconKind;
    FIsUpdatingUI  : Boolean;
    FLastCheckTick : Int64;
    // Guards against a slow volume probe stacking up on the main loop thread.
  FQueryBusy     : Boolean;
    FOnDismiss     : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleSliderChange(Sender: TFtSlider; Value: Double);
    procedure HandleMuteClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryVolume(out APercent: Integer; out AIsMuted: Boolean): Boolean;
    procedure ApplyVolume(APercent: Integer);
    procedure SetVolumeState(APercent: Integer; AMuted: Boolean);
    procedure ToggleMute();
    procedure StepVolume(ADelta: Integer);

    procedure UpdateUI();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property CurrentVolume: Integer read FCurVolume;
    property IsMuted: Boolean read FIsMuted;
    property IconKind: TVolumeIconKind read FIconKind;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Slider: TFtSlider read FVolumeSlider;
    property MuteButton: TFtButton read FMuteBtn;
    property VolumeLabel: TFtLabel read FVolumeLabel;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellClockApplet — Interactive Clock & Calendar Applet }
  TShellClockApplet = class
  private
    FPanelWindow   : TFtWindow;
    FButton        : TFtButton;
    FPopupWindow   : TFtWindow;
    FPlate         : TFtDrawingArea;
    FLastClockSec  : Integer;
    FOnDismiss     : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    procedure UpdateClock();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property PopupWindow: TFtWindow read FPopupWindow;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellSessionApplet — Power / Session Management Applet }
  TShellSessionApplet = class
  private
    FPanelWindow : TFtWindow;
    FButton      : TFtButton;
    FMenu        : TFtPopupMenu;
    FIsOpen      : Boolean;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleLockScreen(Sender: TFtMenuItem);
    procedure HandleSuspend(Sender: TFtMenuItem);
    procedure HandleLogOut(Sender: TFtMenuItem);
    procedure HandleRestart(Sender: TFtMenuItem);
    procedure HandleShutDown(Sender: TFtMenuItem);
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    procedure SetBounds(AX, AY, AW, AH: Integer);
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    property Button: TFtButton read FButton;
    property Menu: TFtPopupMenu read FMenu;
  end;

implementation

const
  SVG_ICON_COLOR = '#2c3e50';

  SVG_POWER_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M18.36 6.64a9 9 0 1 1-12.73 0"/>' +
    '<line x1="12" y1="2" x2="12" y2="12"/>' +
    '</svg>';

  SVG_VOL_HIGH =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
    '<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>' +
    '</svg>';

  SVG_VOL_MED =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
    '</svg>';

  SVG_VOL_LOW =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '</svg>';

  SVG_VOL_MUTE =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '<line x1="22" y1="9" x2="16" y2="15"/>' +
    '<line x1="16" y1="9" x2="22" y2="15"/>' +
    '</svg>';

procedure ExecShellCmdAsync(const ACmd: string);
var
  AProcess: TProcess;
begin
  AProcess := TProcess.Create(nil);
  try
    AProcess.Executable := '/bin/sh';
    AProcess.Parameters.Add('-c');
    AProcess.Parameters.Add(ACmd);
    AProcess.Options := [poNoConsole];
    AProcess.Execute();
  finally
    AProcess.Free();
  end;
end;

// =============================================================================
// TShellVolumeApplet Implementation
// =============================================================================

constructor TShellVolumeApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FCurVolume := 100;
  FIsMuted := False;
  FIconKind := vikHigh;
  FIsUpdatingUI := False;
  FLastCheckTick := 0;
  FQueryBusy := False;
  FOnDismiss := nil;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.OnClick := @HandleButtonClick;

  QueryVolume(FCurVolume, FIsMuted);
  UpdateUI();
end;

destructor TShellVolumeApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

procedure TShellVolumeApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

function TShellVolumeApplet.QueryVolume(out APercent: Integer; out AIsMuted: Boolean): Boolean;
var
  outStr: string;
  volStr: string;
  volVal: Double;
  p, q: Integer;
begin
  APercent := 100;
  AIsMuted := False;
  Result := False;

  // Try wpctl first (modern PipeWire standard)
  if RunCommand('/usr/bin/wpctl', ['get-volume', '@DEFAULT_AUDIO_SINK@'], outStr) then
  begin
    outStr := Trim(outStr);
    p := Pos('Volume:', outStr);
    if p > 0 then
    begin
      volStr := Trim(Copy(outStr, p + 7, Length(outStr)));
      q := Pos(' ', volStr);
      if q > 0 then
        volStr := Copy(volStr, 1, q - 1);

      volVal := StrToFloatDef(volStr, 1.0);
      APercent := EnsureRange(Round(volVal * 100), 0, 150);
      AIsMuted := (Pos('[MUTED]', outStr) > 0);
      Exit(True);
    end;
  end;

  // Fallback to amixer (ALSA)
  if RunCommand('/usr/bin/amixer', ['sget', 'Master'], outStr) then
  begin
    p := Pos('[', outStr);
    if p > 0 then
    begin
      q := Pos('%]', outStr);
      if (q > p) then
      begin
        volStr := Copy(outStr, p + 1, q - p - 1);
        APercent := StrToIntDef(volStr, 100);
        AIsMuted := (Pos('[off]', outStr) > 0);
        Exit(True);
      end;
    end;
  end;
end;

procedure TShellVolumeApplet.ApplyVolume(APercent: Integer);
var
  fracStr, dummy: string;
begin
  FCurVolume := EnsureRange(APercent, 0, 150);
  fracStr := FormatFloat('0.00', FCurVolume / 100.0);

  if not RunCommand('/usr/bin/wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', fracStr], dummy) then
  begin
    RunCommand('/usr/bin/amixer', ['-q', 'sset', 'Master', IntToStr(FCurVolume) + '%'], dummy);
  end;

  UpdateUI();
end;

procedure TShellVolumeApplet.SetVolumeState(APercent: Integer; AMuted: Boolean);
begin
  FCurVolume := EnsureRange(APercent, 0, 150);
  FIsMuted := AMuted;
  UpdateUI();
end;

procedure TShellVolumeApplet.ToggleMute();
var
  dummy: string;
begin
  if not RunCommand('/usr/bin/wpctl', ['set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle'], dummy) then
  begin
    RunCommand('/usr/bin/amixer', ['-q', 'sset', 'Master', 'toggle'], dummy);
  end;

  QueryVolume(FCurVolume, FIsMuted);
  UpdateUI();
end;

procedure TShellVolumeApplet.StepVolume(ADelta: Integer);
begin
  ApplyVolume(FCurVolume + ADelta);
end;

procedure TShellVolumeApplet.UpdateUI();
begin
  if FButton = nil then Exit;

  FButton.Caption := '';
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);

  if FIsMuted or (FCurVolume = 0) then
  begin
    FIconKind := vikMuted;
    FButton.SetIconSVG(SVG_VOL_MUTE);
  end
  else if FCurVolume < 33 then
  begin
    FIconKind := vikLow;
    FButton.SetIconSVG(SVG_VOL_LOW);
  end
  else if FCurVolume < 66 then
  begin
    FIconKind := vikMedium;
    FButton.SetIconSVG(SVG_VOL_MED);
  end
  else
  begin
    FIconKind := vikHigh;
    FButton.SetIconSVG(SVG_VOL_HIGH);
  end;

  if Assigned(FPopupWindow) and not FIsUpdatingUI then
  begin
    FIsUpdatingUI := True;
    try
      if Assigned(FVolumeLabel) then
      begin
        if FIsMuted then
          FVolumeLabel.Text := 'Volume: Muted (' + IntToStr(FCurVolume) + '%)'
        else
          FVolumeLabel.Text := 'Volume: ' + IntToStr(FCurVolume) + '%';
      end;

      if Assigned(FVolumeSlider) then
        FVolumeSlider.Value := FCurVolume;

      if Assigned(FMuteBtn) then
      begin
        if FIsMuted then
          FMuteBtn.Caption := 'Unmute Audio'
        else
          FMuteBtn.Caption := 'Mute Audio';
      end;
    finally
      FIsUpdatingUI := False;
    end;
  end;
end;

procedure TShellVolumeApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;
  // White card background with subtle rounded border
  Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
  Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
end;

procedure TShellVolumeApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellVolumeApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 200;
  popH := 92;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := Max(10, FButton.X - (popW - FButton.Width) div 2);
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-volume-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  // Background plate
  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  // Volume text label in dark slate
  FVolumeLabel := TFtLabel.Create(FPopupWindow, 16, 10, popW - 32, 18, 'Volume: ' + IntToStr(FCurVolume) + '%');
  FVolumeLabel.Alignment := ftaLeft;
  FVolumeLabel.SetColor(0.12, 0.16, 0.23);

  // Volume slider
  FVolumeSlider := TFtSlider.Create(FPopupWindow, 16, 32, popW - 32, 22, ftsoHorizontal);
  FVolumeSlider.SetRange(0.0, 100.0);
  FVolumeSlider.Step := 1.0;
  FVolumeSlider.Value := FCurVolume;
  FVolumeSlider.OnChange := @HandleSliderChange;

  // Mute button
  FMuteBtn := TFtButton.Create(FPopupWindow, 16, 58, popW - 32, 24, 'Mute Audio');
  FMuteBtn.Flat := True;
  FMuteBtn.CornerRadius := 4.0;
  FMuteBtn.OnClick := @HandleMuteClick;

  UpdateUI();
end;

procedure TShellVolumeApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FVolumeLabel := nil;
    FVolumeSlider := nil;
    FMuteBtn := nil;
    FPlate := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellVolumeApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();

  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;

  Tick();
end;

procedure TShellVolumeApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellVolumeApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellVolumeApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellVolumeApplet.Tick();
var
  nowTick: Int64;
  newVol: Integer;
  newMuted: Boolean;
begin
  if not IsPopupOpen() then Exit;

  nowTick := DateTimeToTimeStamp(Now()).Time;
  if Abs(nowTick - FLastCheckTick) < 1500 then Exit;
  FLastCheckTick := nowTick;

  if FQueryBusy then Exit;
  FQueryBusy := True;
  try
    if QueryVolume(newVol, newMuted) then
    begin
      if (newVol <> FCurVolume) or (newMuted <> FIsMuted) then
      begin
        FCurVolume := newVol;
        FIsMuted := newMuted;
        UpdateUI();
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

procedure TShellVolumeApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellVolumeApplet.HandleSliderChange(Sender: TFtSlider; Value: Double);
begin
  if FIsUpdatingUI then Exit;
  ApplyVolume(Round(Value));
end;

procedure TShellVolumeApplet.HandleMuteClick(Sender: TFtButton);
begin
  ToggleMute();
end;

// =============================================================================
// TShellClockApplet Implementation
// =============================================================================

constructor TShellClockApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FLastClockSec := -1;
  FOnDismiss := nil;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '--:--:--');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.OnClick := @HandleButtonClick;

  UpdateClock();
end;

destructor TShellClockApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

procedure TShellClockApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

procedure TShellClockApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  nowDt: TDateTime;
  yr, mo, da: Word;
  hr, mn, sc, ms: Word;
  dateStr, timeStr, monthYearStr: string;
  startCol, daysInMonth, d, col, row: Integer;
  cellX, cellY: Integer;
const
  DayNames: array[0..6] of string = ('Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su');
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  nowDt := Now();
  DecodeDate(nowDt, yr, mo, da);
  DecodeTime(nowDt, hr, mn, sc, ms);

  // 1. White card plate + slate-300 border
  Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
  Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);

  // 2. Date header
  dateStr := FormatDateTime('dddd, d mmmm yyyy', nowDt);
  Canvas.DrawText(16, 12, dateStr, 0.12, 0.16, 0.23);

  // 3. Digital time in cobalt blue
  timeStr := FormatDateTime('hh:nn:ss', nowDt);
  Canvas.DrawText(16, 30, timeStr, 0.15, 0.39, 0.92);

  // 4. Divider line
  Canvas.DrawLine(14, 52, Sender.Width - 14, 52, 1.0, 0.88, 0.90, 0.94, 1.0);

  // 5. Month & Year title
  monthYearStr := FormatDateTime('mmmm yyyy', nowDt);
  Canvas.DrawText(16, 62, monthYearStr, 0.20, 0.25, 0.32);

  // 6. Day of week names: Mo Tu We Th Fr Sa Su
  for col := 0 to 6 do
  begin
    cellX := 16 + col * 29;
    Canvas.DrawTextCentered(cellX, 82, 28, 16, DayNames[col], 0.39, 0.45, 0.55);
  end;

  // 7. Days grid (Monday = column 0)
  startCol := (DayOfWeek(EncodeDate(yr, mo, 1)) + 5) mod 7;
  daysInMonth := MonthDays[IsLeapYear(yr)][mo];

  for d := 1 to daysInMonth do
  begin
    col := (startCol + d - 1) mod 7;
    row := (startCol + d - 1) div 7;
    cellX := 16 + col * 29;
    cellY := 104 + row * 20;

    if d = da then
    begin
      // Highlight today with blue badge and white text
      Canvas.DrawRoundedRect(cellX + 2, cellY, 24, 18, 4.0, 0.15, 0.39, 0.92, 1.0);
      Canvas.DrawTextCentered(cellX, cellY, 28, 18, IntToStr(d), 1.0, 1.0, 1.0);
    end
    else
    begin
      Canvas.DrawTextCentered(cellX, cellY, 28, 18, IntToStr(d), 0.20, 0.25, 0.32);
    end;
  end;
end;

procedure TShellClockApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellClockApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 240;
  popH := 232;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := Max(10, FButton.X - (popW - FButton.Width) div 2);
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-clock-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  // Drawing area renders card background and calendar grid
  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;
end;

procedure TShellClockApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellClockApplet.UpdateClock();
var
  nowDt: TDateTime;
  sec: Integer;
begin
  nowDt := Now();
  sec := DateTimeToTimeStamp(nowDt).Time div 1000;
  if sec <> FLastClockSec then
  begin
    FLastClockSec := sec;
    if Assigned(FButton) then
      FButton.Caption := FormatDateTime('hh:nn:ss', nowDt);
    if IsPopupOpen() and Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellClockApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();

  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellClockApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellClockApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellClockApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellClockApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

// =============================================================================
// TShellSessionApplet Implementation
// =============================================================================

constructor TShellSessionApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FIsOpen := False;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.SetIconSVG(SVG_POWER_ICON);
  FButton.OnClick := @HandleButtonClick;

  FMenu := TFtPopupMenu.Create(FPanelWindow);
  FMenu.AddItem('Lock Screen', @HandleLockScreen);
  FMenu.AddItem('Suspend', @HandleSuspend);
  FMenu.AddItem('Log Out...', @HandleLogOut);
  FMenu.AddSeparator();
  FMenu.AddItem('Restart...', @HandleRestart);
  FMenu.AddItem('Shut Down...', @HandleShutDown);
end;

destructor TShellSessionApplet.Destroy();
begin
  if Assigned(FMenu) then
  begin
    FMenu.Free();
    FMenu := nil;
  end;

  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;

  inherited Destroy();
end;

procedure TShellSessionApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

procedure TShellSessionApplet.ShowPopup();
var
  menuX, menuY: Integer;
begin
  if FMenu = nil then Exit;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    menuX := Max(10, FButton.X - 120);
    if FPanelWindow.Y < 100 then
      menuY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      menuY := FPanelWindow.Y - 170;
  end
  else
  begin
    menuX := 100;
    menuY := 100;
  end;

  FIsOpen := True;
  if Assigned(FButton) then
    FButton.Toggled := True;
  FMenu.Show(menuX, menuY);
end;

procedure TShellSessionApplet.HidePopup();
begin
  if Assigned(FMenu) then
    FMenu.Close();
  FIsOpen := False;
  if Assigned(FButton) then
    FButton.Toggled := False;
end;

procedure TShellSessionApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellSessionApplet.IsPopupOpen(): Boolean;
begin
  Result := FIsOpen and Assigned(FMenu) and FMenu.Visible;
  if not Result then
  begin
    FIsOpen := False;
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellSessionApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellSessionApplet.HandleLockScreen(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('xdg-screensaver lock || loginctl lock-session || xflock4');
end;

procedure TShellSessionApplet.HandleSuspend(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('systemctl suspend');
end;

procedure TShellSessionApplet.HandleLogOut(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('loginctl terminate-user $USER || pkill -u $USER');
end;

procedure TShellSessionApplet.HandleRestart(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('systemctl reboot');
end;

procedure TShellSessionApplet.HandleShutDown(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('systemctl poweroff');
end;

end.
