{ Unit ShellSama.LibFt — C ABI dynamic bindings for Floria Toolkit (libft.so) }

unit ShellSama.LibFt;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DynLibs, ctypes;

const
  FT_WINDOW_TYPE_NORMAL        = 0;
  FT_WINDOW_TYPE_DIALOG        = 1;
  FT_WINDOW_TYPE_POPUP_MENU    = 2;
  FT_WINDOW_TYPE_DROPDOWN_MENU = 3;
  FT_WINDOW_TYPE_TOOLTIP       = 4;
  FT_WINDOW_TYPE_UTILITY       = 5;
  FT_WINDOW_TYPE_DOCK          = 6;

  FT_TEXT_ALIGN_LEFT           = 0;
  FT_TEXT_ALIGN_CENTER         = 1;
  FT_TEXT_ALIGN_RIGHT          = 2;

type
  FtWidget = Pointer;
  FtBitmap = Pointer;

  FtClickCallback = procedure(widget: FtWidget; user_data: Pointer); cdecl;
  FtHoverCallback = procedure(widget: FtWidget; hovered: cint32; user_data: Pointer); cdecl;
  FtEntryChangeCallback = procedure(widget: FtWidget; text: PChar; user_data: Pointer); cdecl;
  FtEntrySubmitCallback = procedure(widget: FtWidget; text: PChar; user_data: Pointer); cdecl;
  FtEventFilterFunc = function(event: Pointer): Boolean; cdecl;
  FtTickCallback = procedure(user_data: Pointer); cdecl;

var
  ft_init: procedure(); cdecl = nil;
  ft_main_loop: procedure(); cdecl = nil;
  ft_quit: procedure(); cdecl = nil;

  ft_window_create: function(width, height: cint32; title: PChar): FtWidget; cdecl = nil;
  ft_window_set_title: procedure(window: FtWidget; title: PChar); cdecl = nil;
  ft_window_set_borderless: procedure(window: FtWidget; borderless: cint32); cdecl = nil;
  ft_window_set_skip_taskbar: procedure(window: FtWidget; skip_taskbar: cint32); cdecl = nil;
  ft_window_set_window_type: procedure(window: FtWidget; window_type: cint32); cdecl = nil;
  ft_window_set_position: procedure(window: FtWidget; x, y: cint32); cdecl = nil;
  ft_window_bring_to_front: procedure(window: FtWidget); cdecl = nil;
  ft_window_grab_input: procedure(window: FtWidget); cdecl = nil;
  ft_window_ungrab_input: procedure(window: FtWidget); cdecl = nil;
  ft_window_get_native_handle: function(window: FtWidget): Pointer; cdecl = nil;
  ft_window_set_strut_partial: procedure(window: FtWidget;
    left, right, top, bottom: cint32;
    left_start_y, left_end_y: cint32;
    right_start_y, right_end_y: cint32;
    top_start_x, top_end_x: cint32;
    bottom_start_x, bottom_end_x: cint32); cdecl = nil;

  ft_widget_show: procedure(widget: FtWidget); cdecl = nil;
  ft_widget_hide: procedure(widget: FtWidget); cdecl = nil;
  ft_widget_invalidate: procedure(widget: FtWidget); cdecl = nil;
  ft_widget_set_focus: procedure(widget: FtWidget); cdecl = nil;
  ft_widget_set_bounds: procedure(widget: FtWidget; x, y, w, h: cint32); cdecl = nil;
  ft_widget_destroy: procedure(widget: FtWidget); cdecl = nil;

  ft_text_create: function(parent: FtWidget; x, y, w, h: cint32; text: PChar): FtWidget; cdecl = nil;
  ft_text_set_text: procedure(text_widget: FtWidget; text: PChar); cdecl = nil;
  ft_text_get_text: function(text_widget: FtWidget): PChar; cdecl = nil;
  ft_text_set_alignment: procedure(text_widget: FtWidget; alignment: cint32); cdecl = nil;
  ft_text_set_color: procedure(text_widget: FtWidget; r, g, b: Double); cdecl = nil;

  ft_entry_create: function(parent: FtWidget; x, y, w, h: cint32; text: PChar): FtWidget; cdecl = nil;
  ft_entry_set_text: procedure(entry: FtWidget; text: PChar); cdecl = nil;
  ft_entry_get_text: function(entry: FtWidget): PChar; cdecl = nil;
  ft_entry_set_placeholder: procedure(entry: FtWidget; placeholder: PChar); cdecl = nil;
  ft_entry_on_change: procedure(entry: FtWidget; callback: FtEntryChangeCallback; user_data: Pointer); cdecl = nil;
  ft_entry_on_submit: procedure(entry: FtWidget; callback: FtEntrySubmitCallback; user_data: Pointer); cdecl = nil;

  ft_button_create: function(parent: FtWidget; x, y, w, h: cint32; caption: PChar): FtWidget; cdecl = nil;
  ft_button_set_caption: procedure(button: FtWidget; caption: PChar); cdecl = nil;
  ft_button_on_click: procedure(button: FtWidget; callback: FtClickCallback; user_data: Pointer); cdecl = nil;
  ft_button_on_hover: procedure(button: FtWidget; callback: FtHoverCallback; user_data: Pointer); cdecl = nil;
  ft_button_set_toggle: procedure(button: FtWidget; can_toggle: cint32); cdecl = nil;
  ft_button_set_toggled: procedure(button: FtWidget; toggled: cint32); cdecl = nil;
  ft_button_set_corner_radius: procedure(button: FtWidget; radius: Double); cdecl = nil;

  ft_screen_get_width: function(): cint32; cdecl = nil;
  ft_screen_get_height: function(): cint32; cdecl = nil;
  ft_register_event_filter: procedure(filter: FtEventFilterFunc); cdecl = nil;
  ft_set_tick_callback: procedure(callback: FtTickCallback; user_data: Pointer); cdecl = nil;
  ft_backend_get_connection: function(): Pointer; cdecl = nil;
  ft_backend_get_screen: function(): Pointer; cdecl = nil;
  ft_backend_get_key_symbols: function(): Pointer; cdecl = nil;

function LoadLibFt(const ALibPath: string = ''): Boolean;
procedure UnloadLibFt();
function IsLibFtLoaded(): Boolean;

implementation

var
  GLibHandle: TLibHandle = NilHandle;

function TryLoad(const APath: string): Boolean;
begin
  Result := False;
  if (APath <> '') and FileExists(APath) then
  begin
    GLibHandle := LoadLibrary(APath);
    Result := (GLibHandle <> NilHandle);
  end;
end;

function LoadLibFt(const ALibPath: string): Boolean;
var
  CandidatePaths: array[0..4] of string;
  i: Integer;
begin
  if GLibHandle <> NilHandle then
    Exit(True);

  // If explicit path given, try that first
  if (ALibPath <> '') and TryLoad(ALibPath) then
  begin
    // loaded
  end
  else
  begin
    // Search plausible locations
    CandidatePaths[0] := '/home/afumi/Documents/projects/kirana/floria-toolkit/target/libft.so';
    CandidatePaths[1] := '../../floria-toolkit/target/libft.so';
    CandidatePaths[2] := '../floria-toolkit/target/libft.so';
    CandidatePaths[3] := 'libft.so';
    CandidatePaths[4] := '/usr/local/lib/libft.so';

    for i := 0 to High(CandidatePaths) do
    begin
      GLibHandle := LoadLibrary(CandidatePaths[i]);
      if GLibHandle <> NilHandle then
        Break;
    end;
  end;

  if GLibHandle = NilHandle then
    Exit(False);

  // Bind function pointers
  Pointer(ft_init) := GetProcedureAddress(GLibHandle, 'ft_init');
  Pointer(ft_main_loop) := GetProcedureAddress(GLibHandle, 'ft_main_loop');
  Pointer(ft_quit) := GetProcedureAddress(GLibHandle, 'ft_quit');

  Pointer(ft_window_create) := GetProcedureAddress(GLibHandle, 'ft_window_create');
  Pointer(ft_window_set_title) := GetProcedureAddress(GLibHandle, 'ft_window_set_title');
  Pointer(ft_window_set_borderless) := GetProcedureAddress(GLibHandle, 'ft_window_set_borderless');
  Pointer(ft_window_set_skip_taskbar) := GetProcedureAddress(GLibHandle, 'ft_window_set_skip_taskbar');
  Pointer(ft_window_set_window_type) := GetProcedureAddress(GLibHandle, 'ft_window_set_window_type');
  Pointer(ft_window_set_position) := GetProcedureAddress(GLibHandle, 'ft_window_set_position');
  Pointer(ft_window_bring_to_front) := GetProcedureAddress(GLibHandle, 'ft_window_bring_to_front');
  Pointer(ft_window_grab_input) := GetProcedureAddress(GLibHandle, 'ft_window_grab_input');
  Pointer(ft_window_ungrab_input) := GetProcedureAddress(GLibHandle, 'ft_window_ungrab_input');
  Pointer(ft_window_get_native_handle) := GetProcedureAddress(GLibHandle, 'ft_window_get_native_handle');
  Pointer(ft_window_set_strut_partial) := GetProcedureAddress(GLibHandle, 'ft_window_set_strut_partial');

  Pointer(ft_widget_show) := GetProcedureAddress(GLibHandle, 'ft_widget_show');
  Pointer(ft_widget_hide) := GetProcedureAddress(GLibHandle, 'ft_widget_hide');
  Pointer(ft_widget_invalidate) := GetProcedureAddress(GLibHandle, 'ft_widget_invalidate');
  Pointer(ft_widget_set_focus) := GetProcedureAddress(GLibHandle, 'ft_widget_set_focus');
  Pointer(ft_widget_set_bounds) := GetProcedureAddress(GLibHandle, 'ft_widget_set_bounds');
  Pointer(ft_widget_destroy) := GetProcedureAddress(GLibHandle, 'ft_widget_destroy');

  Pointer(ft_text_create) := GetProcedureAddress(GLibHandle, 'ft_text_create');
  Pointer(ft_text_set_text) := GetProcedureAddress(GLibHandle, 'ft_text_set_text');
  Pointer(ft_text_get_text) := GetProcedureAddress(GLibHandle, 'ft_text_get_text');
  Pointer(ft_text_set_alignment) := GetProcedureAddress(GLibHandle, 'ft_text_set_alignment');
  Pointer(ft_text_set_color) := GetProcedureAddress(GLibHandle, 'ft_text_set_color');

  Pointer(ft_entry_create) := GetProcedureAddress(GLibHandle, 'ft_entry_create');
  Pointer(ft_entry_set_text) := GetProcedureAddress(GLibHandle, 'ft_entry_set_text');
  Pointer(ft_entry_get_text) := GetProcedureAddress(GLibHandle, 'ft_entry_get_text');
  Pointer(ft_entry_set_placeholder) := GetProcedureAddress(GLibHandle, 'ft_entry_set_placeholder');
  Pointer(ft_entry_on_change) := GetProcedureAddress(GLibHandle, 'ft_entry_on_change');
  Pointer(ft_entry_on_submit) := GetProcedureAddress(GLibHandle, 'ft_entry_on_submit');

  Pointer(ft_button_create) := GetProcedureAddress(GLibHandle, 'ft_button_create');
  Pointer(ft_button_set_caption) := GetProcedureAddress(GLibHandle, 'ft_button_set_caption');
  Pointer(ft_button_on_click) := GetProcedureAddress(GLibHandle, 'ft_button_on_click');
  Pointer(ft_button_on_hover) := GetProcedureAddress(GLibHandle, 'ft_button_on_hover');
  Pointer(ft_button_set_toggle) := GetProcedureAddress(GLibHandle, 'ft_button_set_toggle');
  Pointer(ft_button_set_toggled) := GetProcedureAddress(GLibHandle, 'ft_button_set_toggled');
  Pointer(ft_button_set_corner_radius) := GetProcedureAddress(GLibHandle, 'ft_button_set_corner_radius');

  Pointer(ft_screen_get_width) := GetProcedureAddress(GLibHandle, 'ft_screen_get_width');
  Pointer(ft_screen_get_height) := GetProcedureAddress(GLibHandle, 'ft_screen_get_height');
  Pointer(ft_register_event_filter) := GetProcedureAddress(GLibHandle, 'ft_register_event_filter');
  Pointer(ft_set_tick_callback) := GetProcedureAddress(GLibHandle, 'ft_set_tick_callback');
  Pointer(ft_backend_get_connection) := GetProcedureAddress(GLibHandle, 'ft_backend_get_connection');
  Pointer(ft_backend_get_screen) := GetProcedureAddress(GLibHandle, 'ft_backend_get_screen');
  Pointer(ft_backend_get_key_symbols) := GetProcedureAddress(GLibHandle, 'ft_backend_get_key_symbols');

  Result := Assigned(ft_init) and Assigned(ft_main_loop) and Assigned(ft_window_create);
end;

procedure UnloadLibFt();
begin
  if GLibHandle <> NilHandle then
  begin
    UnloadLibrary(GLibHandle);
    GLibHandle := NilHandle;
  end;
end;

function IsLibFtLoaded(): Boolean;
begin
  Result := (GLibHandle <> NilHandle);
end;

end.
