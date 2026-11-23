unit inject;

{ SendInput wrappers for synthesized keyboard events.
  Scancode injection is preferred (games and DirectInput apps ignore plain
  VK events); when MapVirtualKey yields no scancode the event falls back to
  VK mode. Every event carries EXINFO_MAGIC in dwExtraInfo as a second
  loop-guard next to the LLKHF_INJECTED flag the OS sets for us.

  The Win32 input structs are mirrored locally because FPC's Windows unit
  does not reliably expose SendInput/TInput across versions. }

{$mode objfpc}{$H+}

interface

uses
  Windows;

const
  EXINFO_MAGIC = $4F43524D;   // 'OCRM'

procedure InjectKey(VK, SC: Word; Ext, IsDown: Boolean);

implementation

const
  INPUT_KEYBOARD         = 1;
  KEYEVENTF_EXTENDEDKEY  = $0001;
  KEYEVENTF_KEYUP        = $0002;
  KEYEVENTF_SCANCODE     = $0008;
  MAPVK_VK_TO_VSC        = 0;

type
  TKeybdInputRec = record
    wVk: Word;
    wScan: Word;
    dwFlags: DWORD;
    time: DWORD;
    dwExtraInfo: PtrUInt;
  end;

  TInputRec = record
    Itype: DWORD;
    case Integer of
      0: (ki: TKeybdInputRec);
      1: (pad: array[0..(4 * 8) - 1] of Byte);   // union must fit MOUSEINPUT
  end;

function SendInput(cInputs: UINT; var pInputs: TInputRec;
  cbSize: Integer): Integer; stdcall; external 'user32.dll';
function MapVirtualKeyW(uCode: UINT; uMapType: UINT): UINT; stdcall;
  external 'user32.dll';

procedure InjectKey(VK, SC: Word; Ext, IsDown: Boolean);
var
  inp: TInputRec;
  scan: DWORD;
  flags: DWORD;
begin
  inp := Default(TInputRec);
  inp.Itype := INPUT_KEYBOARD;
  scan := SC;
  if scan = 0 then
    scan := MapVirtualKeyW(VK, MAPVK_VK_TO_VSC);
  flags := 0;
  if scan <> 0 then
    flags := flags or KEYEVENTF_SCANCODE;
  if Ext then
    flags := flags or KEYEVENTF_EXTENDEDKEY;
  if not IsDown then
    flags := flags or KEYEVENTF_KEYUP;
  inp.ki.wVk := VK;
  inp.ki.wScan := Word(scan);
  inp.ki.dwFlags := flags;
  inp.ki.time := 0;
  inp.ki.dwExtraInfo := EXINFO_MAGIC;
  SendInput(1, inp, SizeOf(inp));
end;

end.
