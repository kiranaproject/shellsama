{ Unit ShellSama.Applets — Desktop Panel Built-in Applets (Volume & Session) }

unit ShellSama.Applets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.menus;

type
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
    FIsUpdatingUI  : Boolean;
    FLastCheckTick : Int64;

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
  FIsUpdatingUI := False;
  FLastCheckTick := 0;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '🔊');
  FButton.CornerRadius := 6.0;
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

  // 1. Update panel button icon/text
  if FIsMuted or (FCurVolume = 0) then
    FButton.Caption := '🔇'
  else if FCurVolume < 33 then
    FButton.Caption := '🔈'
  else if FCurVolume < 66 then
    FButton.Caption := '🔉'
  else
    FButton.Caption := '🔊';

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
end;

procedure TShellVolumeApplet.Tick();
var
  nowTick: Int64;
  newVol: Integer;
  newMuted: Boolean;
begin
  nowTick := DateTimeToTimeStamp(Now()).Time;
  if Abs(nowTick - FLastCheckTick) < 1500 then Exit; // Check every 1.5 seconds
  FLastCheckTick := nowTick;

  if QueryVolume(newVol, newMuted) then
  begin
    if (newVol <> FCurVolume) or (newMuted <> FIsMuted) then
    begin
      FCurVolume := newVol;
      FIsMuted := newMuted;
      UpdateUI();
    end;
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

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '⏻');
  FButton.CornerRadius := 6.0;
  FButton.Font := 'Noto Sans Symbols2 13';
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
