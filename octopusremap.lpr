program octopusremap;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Windows, SysUtils,
  config, langstrings, keymap, remap, inject, hooks, capture, main;

{$R res/appicon.res}
{$R res/versioninfo.res}
{$R res/manifest.res}

procedure SetProcessDPIAware; stdcall; external 'user32.dll';
function MessageBoxW(hWnd: HWND; lpText, lpCaption: PWideChar;
  uType: DWORD): Integer; stdcall; external 'user32.dll';
function CreateMutexW(lpAttributes: Pointer; bInitialOwner: LongBool;
  lpName: PWideChar): THandle; stdcall; external 'kernel32.dll';

const
  SINGLE_MUTEX = 'OctopusKeyRemap_Singleton';

{ append an unhandled-exception report (with -gl line info) to crash.log }
procedure LogCrash(E: Exception);
var
  f: Text;
  dir, path: string;
  i: Integer;
begin
  dir := ConfigDir;
  if dir = '' then
    dir := GetEnvironmentVariable('APPDATA') + '\OctopusKeyRemap';
  try
    ForceDirectories(dir);
  except
  end;
  path := dir + '\crash.log';
  Assign(f, path);
  if FileExists(path) then
    Append(f)
  else
    Rewrite(f);
  try
    writeln(f, '[' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '] ' +
      E.ClassName + ': ' + E.Message);
    writeln(f, '  at ' + BackTraceStrFunc(ExceptAddr));
    for i := 0 to ExceptFrameCount - 1 do
      writeln(f, '  frame ' + IntToStr(i) + ': ' +
        BackTraceStrFunc(ExceptFrames[i]));
  finally
    CloseFile(f);
  end;
end;

var
  mtx: THandle;
  msg: UnicodeString;

begin
  SetProcessDPIAware;
  mtx := 0;
  try
    LoadConfig;   // settings + rule table; S() needs Cfg.Lang below

    mtx := CreateMutexW(nil, False, PWideChar(UTF8Decode(SINGLE_MUTEX)));
    if mtx = 0 then
      Exit;   // mutex could not be created; give up quietly
    if GetLastError = ERROR_ALREADY_EXISTS then
    begin
      msg := UTF8Decode(S(SID_MSG_SINGLE));
      if msg = '' then
        msg := 'OctopusKeyRemap is already running';
      MessageBoxW(0, PWideChar(msg), 'OctopusKeyRemap', MB_ICONINFORMATION);
      Exit;
    end;

    Application.Title := 'OctopusKeyRemap';
    Application.ShowMainForm := False;
    RequireDerivedFormResource := False;
    Application.Initialize;
    RemapSetEnabled(Cfg.Enabled);
    InstallKbHook;
    Application.CreateForm(TSettingsForm, SettingsForm);
    SettingsForm.PrepareTray;
    if FirstRun or ((ParamCount > 0) and (ParamStr(1) = '--show-settings')) then
      SettingsForm.Show;   // first launch or explicit request
    Application.Run;
  except
    on E: Exception do
      LogCrash(E);
  end;
  UninstallHooks;        // releases held virtual keys first, then unhooks
  if mtx <> 0 then
    ReleaseMutex(mtx);
end.
