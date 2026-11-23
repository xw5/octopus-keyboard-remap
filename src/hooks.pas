unit hooks;

{ Low-level keyboard hook with synchronous remap decisions.
  The callback consults the remap engine and either lets the event through,
  swallows it (returning 1 without CallNextHookEx), or replaces it by
  injecting the mapped key via SendInput before returning. No queueing -
  a message hop would add latency and interleave fast typing.

  Injected events (ours and third-party) are never remapped, which breaks
  the SendInput loop and leaves input made by other software alone. }

{$mode objfpc}{$H+}

interface

uses
  Windows, remap, inject;

procedure InstallKbHook;
procedure UninstallHooks;   // releases held virtual keys first, then unhooks

implementation

const
  WM_KEYBOARD_DOWN = $0100;
  WM_KEYBOARD_UP   = $0101;
  WM_SYSKEY_DOWN   = $0104;
  WM_SYSKEY_UP     = $0105;
  WH_KEYBOARD_LL   = 13;   // not declared by FPC's Windows unit
  LLKHF_EXTENDED          = $01;
  LLKHF_LOWER_IL_INJECTED = $02;
  LLKHF_INJECTED          = $10;
  INJ_MASK = LLKHF_INJECTED or LLKHF_LOWER_IL_INJECTED;

type
  TKbLLRec = packed record
    vkCode: DWORD;
    scanCode: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: PtrUInt;
  end;
  PKbLLRec = ^TKbLLRec;

var
  KbHook: HHOOK = 0;

function KbdHookProc(nCode: LongInt; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  rec: PKbLLRec;
  vk: Word;
  ext, isDown: Boolean;
  i: Integer;
  r: TRemapResult;
begin
  if nCode < 0 then
    Exit(CallNextHookEx(KbHook, nCode, wParam, lParam));
  rec := PKbLLRec(lParam);
  if (rec^.flags and INJ_MASK) <> 0 then
    Exit(CallNextHookEx(KbHook, nCode, wParam, lParam));
  case wParam of
    WM_KEYBOARD_DOWN, WM_SYSKEY_DOWN: isDown := True;
    WM_KEYBOARD_UP, WM_SYSKEY_UP:     isDown := False;
  else
    Exit(CallNextHookEx(KbHook, nCode, wParam, lParam));
  end;
  vk := Word(rec^.vkCode);
  ext := (rec^.flags and LLKHF_EXTENDED) <> 0;

  r := RemapDecideKb(vk, ext, isDown);
  case r.Action of
    RA_BLOCK:
      Result := 1;   // swallow without injecting
    RA_KEY:
      begin
        InjectKey(r.VK, r.SC, r.Ext, r.Down);
        Result := 1; // swallow the original event
      end;
    RA_STEPS:
      begin
        // replay the recorded burst; each injected event carries the
        // INJECTED flag, so this hook never re-remaps them (no loop)
        for i := 0 to High(r.Steps) do
          InjectKey(r.Steps[i].VK, r.Steps[i].SC, r.Steps[i].Ext,
            r.Steps[i].IsDown);
        Result := 1; // swallow the original event
      end;
  else
    Result := CallNextHookEx(KbHook, nCode, wParam, lParam);
  end;
end;

procedure InstallKbHook;
begin
  if KbHook = 0 then
    KbHook := SetWindowsHookEx(WH_KEYBOARD_LL, TFNHookProc(@KbdHookProc),
      HInstance, 0);
end;

procedure UninstallHooks;
var
  steps: TComboSteps;
  i: Integer;
begin
  // release keys the engine still holds down so apps never see a stuck key
  RemapCollectReleases(steps);
  for i := 0 to High(steps) do
    InjectKey(steps[i].VK, steps[i].SC, steps[i].Ext, False);
  if KbHook <> 0 then
  begin
    UnhookWindowsHookEx(KbHook);
    KbHook := 0;
  end;
end;

end.
