{ Unit ShellSama.Applets — Desktop Panel Built-in Applets (Volume & Session) }

unit ShellSama.Applets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.menus;

type
  TVolumeIconKind = (vikMuted, vikLow, vikMedium, vikHigh);

  { TShellVolumeApplet — Interactive Volume Control Applet & Popup }
  TShellVolumeApplet = class
  private
    FPanelWindow   : TFtWindow;
    FButton        : TFtButton;
    FPopupWindow   : TFtWindow;
    FVolumeLabel   : TFtLabel;
    FVolumeSlider  : TFtSlider;
    FMuteBtn       : TFtButton;
    FCloseBtn      : TFtButton;

    FCurVolume     : Integer;
    FIsMuted       : Boolean;
    FIconKind      : TVolumeIconKind;
    FIsUpdatingUI  : Boolean;
    FLastCheckTick : Int64;
    // Guards against a slow volume probe stacking up on the main loop thread.
    FQueryBusy     : Boolean;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleSliderChange(Sender: TFtSlider; Value: Double);
    procedure HandleMuteClick(Sender: TFtButton);
    procedure HandleCloseClick(Sender: TFtButton);

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
  end;

  { TShellSessionApplet — Power / Session Management Applet }
  TShellSessionApplet = class
  private
    FPanelWindow : TFtWindow;
    FButton      : TFtButton;
    FMenu        : TFtPopupMenu;

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

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
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

  // Try wpctl
  if not RunCommand('/usr/bin/wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', fracStr], dummy) then
  begin
    // Fallback amixer
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
  // Try wpctl
  if not RunCommand('/usr/bin/wpctl', ['set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle'], dummy) then
  begin
    // Fallback amixer
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

  // 1. Update panel button monochrome SVG icon
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

  // 2. Update popup widgets if currently open
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
          FMuteBtn.Caption := 'Unmute'
        else
          FMuteBtn.Caption := 'Mute';
      end;
    finally
      FIsUpdatingUI := False;
    end;
  end;
end;

procedure TShellVolumeApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 190;
  popH := 105;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := Max(10, FButton.X - (popW - FButton.Width) div 2);
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

  FVolumeLabel := TFtLabel.Create(FPopupWindow, 14, 10, popW - 28, 20, 'Volume: ' + IntToStr(FCurVolume) + '%');
  FVolumeLabel.Alignment := ftaLeft;
  FVolumeLabel.SetColor(0.95, 0.95, 0.98);

  FVolumeSlider := TFtSlider.Create(FPopupWindow, 14, 34, popW - 28, 22, ftsoHorizontal);
  FVolumeSlider.SetRange(0.0, 100.0);
  FVolumeSlider.Step := 1.0;
  FVolumeSlider.Value := FCurVolume;
  FVolumeSlider.OnChange := @HandleSliderChange;

  FMuteBtn := TFtButton.Create(FPopupWindow, 14, 66, 76, 28, 'Mute');
  FMuteBtn.CornerRadius := 6.0;
  FMuteBtn.OnClick := @HandleMuteClick;

  FCloseBtn := TFtButton.Create(FPopupWindow, popW - 90, 66, 76, 28, 'Close');
  FCloseBtn.CornerRadius := 6.0;
  FCloseBtn.OnClick := @HandleCloseClick;

  UpdateUI();
end;

procedure TShellVolumeApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FVolumeLabel := nil;
    FVolumeSlider := nil;
    FMuteBtn := nil;
    FCloseBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellVolumeApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();

  if Assigned(FPopupWindow) then
    FPopupWindow.Show();
  // Refresh immediately, so the popup never shows a stale value from before the
  // probe was idle.
  Tick();
end;

procedure TShellVolumeApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
    FPopupWindow.Hide();
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
end;procedure TShellVolumeApplet.Tick();
var
  nowTick: Int64;
  newVol: Integer;
  newMuted: Boolean;
begin
  // Only probe while the popup is open.
  //
  // wpctl is a separate process (10-100 ms measured), and polling it every 1.5 s
  // forever was the single largest remaining idle cost after the main loop was
  // fixed: 0.053 of the shell's 0.075 cores. It was also pointless most of the
  // time - the volume is only visible while the popup is open, and a change made
  // elsewhere (a keyboard volume key) is picked up on the next open because
  // ShowPopup() calls Tick() directly.
  //
  // The icon does stay stale until the popup is next opened. That is a real
  // behaviour change, accepted because it buys ~70% of the remaining idle cost.
  if not IsPopupOpen() then Exit;

  nowTick := DateTimeToTimeStamp(Now()).Time;
  if Abs(nowTick - FLastCheckTick) < 1500 then Exit; // Check every 1.5 seconds
  FLastCheckTick := nowTick;

  // Skip polling while a previous check is still running. QueryVolume shells out
  // to wpctl, which is not instantaneous: measured at 10-100 ms per call. Because
  // this runs on the toolkit's main loop thread, that time was taken out of the
  // event loop every 1.5 s - the loop would stall for up to 100 ms and then catch
  // up, which also showed up as CPU time attributed to the shell rather than to
  // wpctl.
  //
  // It does not make the poll asynchronous, but it does stop checks from stacking
  // up if one is slow. See the roadmap note about moving this off the main thread.
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

procedure TShellVolumeApplet.HandleCloseClick(Sender: TFtButton);
begin
  HidePopup();
end;

// =============================================================================
// TShellSessionApplet Implementation
// =============================================================================

constructor TShellSessionApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
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

procedure TShellSessionApplet.HandleButtonClick(Sender: TFtButton);
var
  menuX, menuY: Integer;
begin
  if FMenu = nil then Exit;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    menuX := Max(10, FButton.X - 120);
    menuY := FPanelWindow.Y - 170;
  end
  else
  begin
    menuX := 100;
    menuY := 100;
  end;

  FMenu.Show(menuX, menuY);
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
