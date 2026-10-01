{ Unit ShellSama.Panel — Desktop Dock & Panel Component for Samarinda DE }

unit ShellSama.Panel;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Contnrs, Math;

type
  TShellPanelPosition = (
    sppTop,
    sppBottom
  );

  TShellPanelConfig = record
    Position : TShellPanelPosition;
    Height   : Integer;
    AutoHide : Boolean;
    ThemeName: string;
    class function Create(const APosition: TShellPanelPosition = sppTop;
                          const AHeight: Integer = 38;
                          const AThemeName: string = 'Amamizu'): TShellPanelConfig; static;
  end;

  // Strut margins for _NET_WM_STRUT_PARTIAL
  TShellStrut = record
    Left        : Cardinal;
    Right       : Cardinal;
    Top         : Cardinal;
    Bottom      : Cardinal;
    LeftStartY  : Cardinal;
    LeftEndY    : Cardinal;
    RightStartY : Cardinal;
    RightEndY   : Cardinal;
    TopStartX   : Cardinal;
    TopEndX     : Cardinal;
    BottomStartX: Cardinal;
    BottomEndX  : Cardinal;
  end;

  TShellPanel = class
  private
    FConfig      : TShellPanelConfig;
    FScreenWidth : Integer;
    FScreenHeight: Integer;
    FIsVisible   : Boolean;
    FTitle       : string;
  public
    constructor Create(const AScreenWidth: Integer = 1920; const AScreenHeight: Integer = 1080); overload;
    constructor Create(const AScreenWidth: Integer; const AScreenHeight: Integer;
                       const AConfig: TShellPanelConfig); overload;
    destructor Destroy(); override;

    function ComputeStrut(): TShellStrut;
    function PanelX(): Integer;
    function PanelY(): Integer;
    function PanelWidth(): Integer;
    function PanelHeight(): Integer;

    property Config      : TShellPanelConfig   read FConfig write FConfig;
    property ScreenWidth : Integer             read FScreenWidth write FScreenWidth;
    property ScreenHeight: Integer             read FScreenHeight write FScreenHeight;
    property IsVisible   : Boolean             read FIsVisible write FIsVisible;
    property Title       : string              read FTitle write FTitle;
  end;

implementation

// -----------------------------------------------------------------------------
// TShellPanelConfig
// -----------------------------------------------------------------------------

class function TShellPanelConfig.Create(const APosition: TShellPanelPosition;
                                        const AHeight: Integer;
                                        const AThemeName: string): TShellPanelConfig;
begin
  Result.Position := APosition;
  Result.Height := AHeight;
  Result.AutoHide := False;
  Result.ThemeName := AThemeName;
end;

// -----------------------------------------------------------------------------
// TShellPanel
// -----------------------------------------------------------------------------

constructor TShellPanel.Create(const AScreenWidth: Integer; const AScreenHeight: Integer);
begin
  Create(AScreenWidth, AScreenHeight, TShellPanelConfig.Create(sppTop, 38, 'Amamizu'));
end;

constructor TShellPanel.Create(const AScreenWidth: Integer; const AScreenHeight: Integer;
                               const AConfig: TShellPanelConfig);
begin
  inherited Create();
  FScreenWidth := Max(1, AScreenWidth);
  FScreenHeight := Max(1, AScreenHeight);
  FIsVisible := True;
  FTitle := 'Samarinda Shell Panel';
  FConfig := AConfig;
end;

destructor TShellPanel.Destroy();
begin
  inherited Destroy();
end;

function TShellPanel.PanelX(): Integer;
begin
  Result := 0;
end;

function TShellPanel.PanelY(): Integer;
begin
  if FConfig.Position = sppTop then
    Result := 0
  else
    Result := FScreenHeight - FConfig.Height;
end;

function TShellPanel.PanelWidth(): Integer;
begin
  Result := FScreenWidth;
end;

function TShellPanel.PanelHeight(): Integer;
begin
  Result := FConfig.Height;
end;

function TShellPanel.ComputeStrut(): TShellStrut;
begin
  FillChar(Result, SizeOf(Result), 0);
  if not FIsVisible or FConfig.AutoHide then Exit;

  if FConfig.Position = sppTop then
  begin
    Result.Top := Cardinal(FConfig.Height);
    Result.TopStartX := 0;
    Result.TopEndX := Cardinal(FScreenWidth - 1);
  end
  else
  begin
    Result.Bottom := Cardinal(FConfig.Height);
    Result.BottomStartX := 0;
    Result.BottomEndX := Cardinal(FScreenWidth - 1);
  end;
end;

end.
