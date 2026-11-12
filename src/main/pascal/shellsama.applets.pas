{ Unit ShellSama.Applets — Desktop Panel Built-in Applets (Volume, Clock & Session) }

unit ShellSama.Applets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process, DateUtils,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.menus,
  ftpas.canvas, ftpas.creative, ftpas.font,
  ShellSama.Settings;

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
    procedure ApplyThemeStyle();
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
    FPrevBtn       : TFtButton;
    FNextBtn       : TFtButton;
    FClockFont     : TFtFontRef;
    FViewYear      : Word;
    FViewMonth     : Word;
    FLastClockSec  : Integer;
    FOnDismiss     : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandlePrevClick(Sender: TFtButton);
    procedure HandleNextClick(Sender: TFtButton);
    procedure HandlePlateMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    procedure UpdateClock();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property PopupWindow: TFtWindow read FPopupWindow;
    property ViewYear: Word read FViewYear;
    property ViewMonth: Word read FViewMonth;
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
    procedure HandleSettings(Sender: TFtMenuItem);
    procedure HandleLockScreen(Sender: TFtMenuItem);
    procedure HandleSuspend(Sender: TFtMenuItem);
    procedure HandleLogOut(Sender: TFtMenuItem);
    procedure HandleRestart(Sender: TFtMenuItem);
    procedure HandleShutDown(Sender: TFtMenuItem);
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    procedure SetBounds(AX, AY, AW, AH: Integer);
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    property Button: TFtButton read FButton;
    property Menu: TFtPopupMenu read FMenu;
  end;

function GetPowerIconSVG(AIsDark: Boolean): string;
function GetVolumeIconSVG(AKind: TVolumeIconKind; AIsDark: Boolean): string;

implementation

function IsDarkTheme(): Boolean;
begin
  if FtIsLibLoaded() then
    Result := FtApp().DarkMode
  else
    Result := ShellSettings().DarkMode;
end;

const
  SVG_ICON_COLOR_LIGHT = '#2c3e50';
  SVG_ICON_COLOR_DARK  = '#f0f2f5';
  SVG_ICON_COLOR       = SVG_ICON_COLOR_LIGHT;

function GetPowerIconSVG(AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  Result :=
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M18.36 6.64a9 9 0 1 1-12.73 0"/>' +
    '<line x1="12" y1="2" x2="12" y2="12"/>' +
    '</svg>';
end;

function GetVolumeIconSVG(AKind: TVolumeIconKind; AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  case AKind of
    vikMuted:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<line x1="22" y1="9" x2="16" y2="15"/>' +
        '<line x1="16" y1="9" x2="22" y2="15"/>' +
        '</svg>';
    vikLow:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
        '</svg>';
    vikMedium:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
        '<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>' +
        '</svg>';
    vikHigh:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
        '<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>' +
        '</svg>';
  end;
end;

const
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

procedure TShellVolumeApplet.ApplyThemeStyle();
begin
  UpdateUI();
  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FVolumeSlider) then
    FVolumeSlider.Invalidate();
  if Assigned(FMuteBtn) then
    FMuteBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellVolumeApplet.UpdateUI();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;

  isDark := IsDarkTheme();

  FButton.Caption := '';
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);

  if FIsMuted or (FCurVolume = 0) then
  begin
    FIconKind := vikMuted;
    FButton.SetIconSVG(GetVolumeIconSVG(vikMuted, isDark));
  end
  else if FCurVolume < 33 then
  begin
    FIconKind := vikLow;
    FButton.SetIconSVG(GetVolumeIconSVG(vikLow, isDark));
  end
  else if FCurVolume < 66 then
  begin
    FIconKind := vikMedium;
    FButton.SetIconSVG(GetVolumeIconSVG(vikMedium, isDark));
  end
  else
  begin
    FIconKind := vikHigh;
    FButton.SetIconSVG(GetVolumeIconSVG(vikHigh, isDark));
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

        if isDark then
          FVolumeLabel.SetColor(0.85, 0.88, 0.95)
        else
          FVolumeLabel.SetColor(0.12, 0.16, 0.23);
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
var
  isDark: Boolean;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();
  if isDark then
  begin
    // Dark mode plate and outline
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    // White card background with subtle rounded border
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;
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

  // Volume text label
  FVolumeLabel := TFtLabel.Create(FPopupWindow, 16, 10, popW - 32, 18, 'Volume: ' + IntToStr(FCurVolume) + '%');
  FVolumeLabel.Alignment := ftaLeft;
  if IsDarkTheme() then
    FVolumeLabel.SetColor(0.85, 0.88, 0.95)
  else
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

  ApplyThemeStyle();
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

  ApplyThemeStyle();

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
  FViewYear := 0;
  FViewMonth := 0;
  FPrevBtn := nil;
  FNextBtn := nil;
  FClockFont := TFtFontRef.Create('Sans:bold 18');

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '--:--');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.OnClick := @HandleButtonClick;

  UpdateClock();
end;

destructor TShellClockApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FClockFont) then
  begin
    FClockFont.Free();
    FClockFont := nil;
  end;
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
  curYr, curMo, curDa: Word;
  hr, mn, sc, ms: Word;
  dateStr, timeStr, monthYearStr: string;
  startCol, daysInMonth, prevDaysInMonth, d, col, row: Integer;
  cellIndex, prevYear, prevMonth: Integer;
  gridX, colW, rowH, cellX, cellY, bx, by, badgeW, badgeH: Integer;
  isToday, isDark: Boolean;
const
  DayNames: array[0..6] of string = ('Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su');
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();

  nowDt := Now();
  DecodeDate(nowDt, curYr, curMo, curDa);
  DecodeTime(nowDt, hr, mn, sc, ms);

  if FViewYear = 0 then
  begin
    FViewYear := curYr;
    FViewMonth := curMo;
  end;

  if isDark then
  begin
    // 1. Dark card plate + subtle outline
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 8.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 8.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);

    // 2. Header background band (top clock area)
    Canvas.DrawRoundedRect(1, 1, Sender.Width - 2, 65, 7.0, 36 / 255, 39 / 255, 58 / 255, 1.0);
    Canvas.DrawLine(12, 66, Sender.Width - 12, 66, 1.0, 49 / 255, 50 / 255, 68 / 255, 0.80);

    // 3. Digital Clock in bright text
    timeStr := FormatDateTime('hh:nn:ss', nowDt);
    if Assigned(FClockFont) and FClockFont.Valid then
      Canvas.DrawText(20, 18, timeStr, 0.85, 0.88, 0.95, FClockFont.Handle)
    else
      Canvas.DrawText(20, 18, timeStr, 0.85, 0.88, 0.95);

    // 4. Formatted Date subtitle
    dateStr := FormatDateTime('dddd, d mmmm yyyy', nowDt);
    Canvas.DrawText(20, 44, dateStr, 147 / 255, 153 / 255, 178 / 255);

    // 5. Month & Year Title
    monthYearStr := FormatDateTime('mmmm yyyy', EncodeDate(FViewYear, FViewMonth, 1));
    Canvas.DrawTextCentered(40, 73, Sender.Width - 80, 26, monthYearStr, 0.85, 0.88, 0.95);
  end
  else
  begin
    // 1. White card plate + subtle slate border
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 8.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 8.0, 1.0, 0.82, 0.85, 0.90, 1.0);

    // 2. Header background band (subtle light tint for top clock area)
    Canvas.DrawRoundedRect(1, 1, Sender.Width - 2, 65, 7.0, 0.97, 0.98, 0.99, 1.0);
    Canvas.DrawLine(12, 66, Sender.Width - 12, 66, 1.0, 0.88, 0.91, 0.94, 1.0);

    // 3. Digital Clock in dark slate (large font if available)
    timeStr := FormatDateTime('hh:nn:ss', nowDt);
    if Assigned(FClockFont) and FClockFont.Valid then
      Canvas.DrawText(20, 18, timeStr, 0.06, 0.09, 0.16, FClockFont.Handle)
    else
      Canvas.DrawText(20, 18, timeStr, 0.06, 0.09, 0.16);

    // 4. Formatted Date subtitle in medium slate
    dateStr := FormatDateTime('dddd, d mmmm yyyy', nowDt);
    Canvas.DrawText(20, 44, dateStr, 0.39, 0.45, 0.55);

    // 5. Month & Year Title in Navigation row (centered, click returns to Today)
    monthYearStr := FormatDateTime('mmmm yyyy', EncodeDate(FViewYear, FViewMonth, 1));
    Canvas.DrawTextCentered(40, 73, Sender.Width - 80, 26, monthYearStr, 0.12, 0.16, 0.23);
  end;

  // 6. Day of week names header
  gridX := 14;
  colW := 36;
  rowH := 26;

  for col := 0 to 6 do
  begin
    cellX := gridX + col * colW;
    if isDark then
    begin
      if col >= 5 then
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 186 / 255, 194 / 255, 222 / 255)
      else
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 147 / 255, 153 / 255, 178 / 255);
    end
    else
    begin
      if col >= 5 then
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 0.30, 0.35, 0.44)
      else
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 0.45, 0.50, 0.60);
    end;
  end;

  // 7. Days Grid: Full 6-week matrix (42 cells: 6 rows * 7 columns)
  // Monday = column 0, Sunday = column 6
  startCol := (DayOfWeek(EncodeDate(FViewYear, FViewMonth, 1)) + 5) mod 7;
  daysInMonth := MonthDays[IsLeapYear(FViewYear)][FViewMonth];

  // Previous month trailing days
  if FViewMonth = 1 then
  begin
    prevYear := FViewYear - 1;
    prevMonth := 12;
  end
  else
  begin
    prevYear := FViewYear;
    prevMonth := FViewMonth - 1;
  end;
  prevDaysInMonth := MonthDays[IsLeapYear(prevYear)][prevMonth];

  // A. Draw leading days from previous month
  for col := 0 to startCol - 1 do
  begin
    d := prevDaysInMonth - (startCol - 1 - col);
    cellX := gridX + col * colW;
    cellY := 126;
    if isDark then
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 88 / 255, 91 / 255, 112 / 255)
    else
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.70, 0.74, 0.80);
  end;

  // B. Draw current viewed month days
  badgeW := 26;
  badgeH := 24;
  for d := 1 to daysInMonth do
  begin
    cellIndex := startCol + d - 1;
    col := cellIndex mod 7;
    row := cellIndex div 7;
    cellX := gridX + col * colW;
    cellY := 126 + row * rowH;

    isToday := (FViewYear = curYr) and (FViewMonth = curMo) and (d = curDa);
    if isToday then
    begin
      bx := cellX + (colW - badgeW) div 2;
      by := cellY + (rowH - badgeH) div 2;
      if isDark then
      begin
        Canvas.DrawRoundedRect(bx, by, badgeW, badgeH, 6.0, 137 / 255, 180 / 255, 250 / 255, 1.0);
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 17 / 255, 17 / 255, 27 / 255);
      end
      else
      begin
        Canvas.DrawRoundedRect(bx, by, badgeW, badgeH, 6.0, 0.15, 0.39, 0.92, 1.0);
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 1.0, 1.0, 1.0);
      end;
    end
    else
    begin
      if isDark then
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.85, 0.88, 0.95)
      else
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.12, 0.16, 0.23);
    end;
  end;

  // C. Draw trailing days from next month up to 42 cells
  d := 1;
  for cellIndex := (startCol + daysInMonth) to 41 do
  begin
    col := cellIndex mod 7;
    row := cellIndex div 7;
    cellX := gridX + col * colW;
    cellY := 126 + row * rowH;
    if isDark then
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 88 / 255, 91 / 255, 112 / 255)
    else
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.70, 0.74, 0.80);
    Inc(d);
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
  curDt: TDateTime;
  curY, curM, curD: Word;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 280;
  popH := 300;

  curDt := Now();
  DecodeDate(curDt, curY, curM, curD);
  FViewYear := curY;
  FViewMonth := curM;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
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

  // Background drawing area (card plate, digital clock, date, calendar grid)
  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;
  FPlate.OnMouseDown := @HandlePlateMouseDown;

  // Month navigation: Prev button
  FPrevBtn := TFtButton.Create(FPopupWindow, 14, 73, 26, 26, '<');
  FPrevBtn.Flat := True;
  FPrevBtn.CornerRadius := 4.0;
  FPrevBtn.OnClick := @HandlePrevClick;

  // Month navigation: Next button
  FNextBtn := TFtButton.Create(FPopupWindow, popW - 40, 73, 26, 26, '>');
  FNextBtn.Flat := True;
  FNextBtn.CornerRadius := 4.0;
  FNextBtn.OnClick := @HandleNextClick;

  ApplyThemeStyle();
end;

procedure TShellClockApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FPrevBtn := nil;
    FNextBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellClockApplet.HandlePrevClick(Sender: TFtButton);
begin
  if FViewMonth <= 1 then
  begin
    FViewMonth := 12;
    Dec(FViewYear);
  end
  else
    Dec(FViewMonth);

  if Assigned(FPlate) then
    FPlate.Invalidate();
end;

procedure TShellClockApplet.HandleNextClick(Sender: TFtButton);
begin
  if FViewMonth >= 12 then
  begin
    FViewMonth := 1;
    Inc(FViewYear);
  end
  else
    Inc(FViewMonth);

  if Assigned(FPlate) then
    FPlate.Invalidate();
end;

procedure TShellClockApplet.HandlePlateMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
var
  curY, curM, curD: Word;
begin
  if (Y <= 102) and (FPlate <> nil) then
  begin
    DecodeDate(Now(), curY, curM, curD);
    if (FViewYear <> curY) or (FViewMonth <> curM) then
    begin
      FViewYear := curY;
      FViewMonth := curM;
      FPlate.Invalidate();
    end;
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
    begin
      if SameText(ShellSettings().ClockFormat, '12h') then
        FButton.Caption := FormatDateTime('ddd d mmm  h:nn am/pm', nowDt)
      else
        FButton.Caption := FormatDateTime('ddd d mmm  hh:nn', nowDt);
    end;
    if IsPopupOpen() and Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellClockApplet.ApplyThemeStyle();
begin
  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FPrevBtn) then
    FPrevBtn.Invalidate();
  if Assigned(FNextBtn) then
    FNextBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellClockApplet.ShowPopup();
var
  curY, curM, curD: Word;
begin
  DecodeDate(Now(), curY, curM, curD);
  FViewYear := curY;
  FViewMonth := curM;

  if not Assigned(FPopupWindow) then
    CreatePopupWindow();

  ApplyThemeStyle();

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
  ApplyThemeStyle();
  FButton.OnClick := @HandleButtonClick;

  FMenu := TFtPopupMenu.Create(FPanelWindow);
  FMenu.AddItem('System Settings...', @HandleSettings);
  FMenu.AddSeparator();
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

procedure TShellSessionApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;
  isDark := False;
  if FtIsLibLoaded() then
    isDark := FtApp().DarkMode;
  FButton.SetIconSVG(GetPowerIconSVG(isDark));
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

procedure TShellSessionApplet.HandleSettings(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('configsama');
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
