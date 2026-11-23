unit keymap;

{ VK code -> human readable key names for the mapping grid and the capture
  box. Left/right variants get distinct names; the numpad enter/digits are
  disambiguated from their main-keyboard twins. Also compresses a recorded
  combo step list into a short display summary. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, remap;

// multimedia keys are missing from some FPC Windows unit versions
const
  VKR_BROWSER_BACK      = $A6;
  VKR_BROWSER_FORWARD   = $A7;
  VKR_MEDIA_PREV        = $B1;
  VKR_MEDIA_NEXT        = $B0;
  VKR_MEDIA_PLAYPAUSE   = $B3;
  VKR_MEDIA_STOP        = $B2;
  VKR_VOLUME_MUTE       = $AD;
  VKR_VOLUME_DOWN       = $AE;
  VKR_VOLUME_UP         = $AF;

function KeyNameOf(VK, SC: Word; Ext: Boolean): string;
function IsModifierVK(VK: Integer): Boolean;

{ canonical modifier-set prefix for display, e.g. 'Ctrl+Alt+' for
  MODB_CONTROL or MODB_ALT; '' when no bits set }
function ModsPrefix(Mods: Word): string;

{ compress a recorded step sequence into a display summary: the keys pressed
  since the last all-released point form a '+'-joined group, groups chain
  with ' -> '. Ctrl,C,C-up,Ctrl-up = "Ctrl+C"; Ctrl+C, Ctrl+V = the macro
  "Ctrl+C -> Ctrl+V"; Ctrl,Shift,Esc all held = "Ctrl+Shift+Esc". }
function ComboSummary(const steps: TComboSteps): string;

implementation

// translate to a character using a neutral (zeroed) keyboard state, so the
// label follows the user's actual layout
function LayoutChar(VK, Scan: Integer; out ch: string): Boolean;
var
  st: TKeyboardState;
  buf: array[0..7] of WideChar;
  n: Integer;
  us: UnicodeString;
begin
  Result := False;
  st := Default(TKeyboardState);
  n := ToUnicode(VK, Scan, st, buf, 8, 0);
  if n <= 0 then
    Exit;
  us := '';
  SetString(us, PWideChar(@buf[0]), n);
  ch := UTF8Encode(us);   // project strings are UTF-8
  Result := Length(ch) > 0;
end;

function KeyCapTextFor(VK, Scan: Integer): string;
var
  c: string;
begin
  case VK of
    VK_LSHIFT:            Exit('Left Shift');
    VK_RSHIFT:            Exit('Right Shift');
    VK_LCONTROL:          Exit('Left Ctrl');
    VK_RCONTROL:          Exit('Right Ctrl');
    VK_LMENU:             Exit('Left Alt');
    VK_RMENU:             Exit('Right Alt');
    VK_LWIN:              Exit('Left Win');
    VK_RWIN:              Exit('Right Win');
    VK_SHIFT:             Exit('Shift');
    VK_CONTROL:           Exit('Ctrl');
    VK_MENU:              Exit('Alt');
    VK_TAB:               Exit('Tab');
    VK_ESCAPE:            Exit('Esc');
    VK_CAPITAL:           Exit('Caps');
    VK_SPACE:             Exit('Space');
    VK_PRIOR:             Exit('PgUp');
    VK_NEXT:              Exit('PgDn');
    VK_HOME:              Exit('Home');
    VK_END:               Exit('End');
    VK_INSERT:            Exit('Ins');
    VK_DELETE:            Exit('Del');
    VK_SNAPSHOT:          Exit('PrtSc');
    VK_SCROLL:            Exit('ScrLk');
    VK_PAUSE:             Exit('Pause');
    VK_NUMLOCK:           Exit('NumLk');
    VK_APPS:              Exit('Menu');
    VK_CANCEL:            Exit('Break');
    VK_NUMPAD0..VK_NUMPAD9:
      Exit('Num ' + Chr(Ord('0') + VK - VK_NUMPAD0));
    VK_MULTIPLY:          Exit('Num *');
    VK_ADD:               Exit('Num +');
    VK_SUBTRACT:          Exit('Num -');
    VK_DECIMAL:           Exit('Num .');
    VK_DIVIDE:            Exit('Num /');
    VK_F1..VK_F24:
      Exit('F' + IntToStr(VK - VK_F1 + 1));
    VKR_MEDIA_NEXT:       Exit('Media Next');
    VKR_MEDIA_PREV:       Exit('Media Prev');
    VKR_MEDIA_STOP:       Exit('Media Stop');
    VKR_MEDIA_PLAYPAUSE:  Exit('Play/Pause');
    VKR_VOLUME_MUTE:      Exit('Vol Mute');
    VKR_VOLUME_DOWN:      Exit('Vol Down');
    VKR_VOLUME_UP:        Exit('Vol Up');
    VKR_BROWSER_BACK:     Exit('Browser Back');
    VKR_BROWSER_FORWARD:  Exit('Browser Fwd');
    Ord('A')..Ord('Z'), Ord('0')..Ord('9'):
      Exit(Chr(VK));
    VK_OEM_1:            // ;:  (US)
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit(';');
    VK_OEM_PLUS:         // =+
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('=');
    VK_OEM_COMMA:
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit(',');
    VK_OEM_MINUS:
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('-');
    VK_OEM_PERIOD:
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('.');
    VK_OEM_2:            // /?
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('/');
    VK_OEM_3:            // `~
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('`');
    VK_OEM_4:            // [{
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('[');
    VK_OEM_5:            // \|
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('\');
    VK_OEM_6:            // ]}
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit(']');
    VK_OEM_7:            // '"
      if LayoutChar(VK, Scan, c) then Exit(c) else Exit('''');
  end;
  Result := 'VK' + IntToStr(VK);
end;

function KeyNameOf(VK, SC: Word; Ext: Boolean): string;
begin
  // numpad enter shares VK_RETURN with the main key; the extended flag
  // distinguishes them, so keep it visible in the name
  if (VK = VK_RETURN) and Ext then
    Exit('Num Enter');
  Result := KeyCapTextFor(VK, SC);
end;

function IsModifierVK(VK: Integer): Boolean;
begin
  case VK of
    VK_LSHIFT, VK_RSHIFT, VK_SHIFT,
    VK_LCONTROL, VK_RCONTROL, VK_CONTROL,
    VK_LMENU, VK_RMENU, VK_MENU,
    VK_LWIN, VK_RWIN: Result := True;
  else
    Result := False;
  end;
end;

function ModsPrefix(Mods: Word): string;
begin
  Result := '';
  if (Mods and MODB_CONTROL) <> 0 then
    Result := Result + 'Ctrl+';
  if (Mods and MODB_ALT) <> 0 then
    Result := Result + 'Alt+';
  if (Mods and MODB_SHIFT) <> 0 then
    Result := Result + 'Shift+';
  if (Mods and MODB_WIN) <> 0 then
    Result := Result + 'Win+';
end;

{ ---------- combo summary ---------- }

type
  THeldName = record
    Name: string;
    Active: Boolean;   // still pressed (its up has not been seen)
  end;

function ComboSummary(const steps: TComboSteps): string;
var
  grp: array of THeldName;   // keys of the group being built, hold order
  activeCnt: Integer;
  groups: array of string;
  i, j: Integer;
  nm: string;

  procedure FlushGroup;
  var
    k, gi: Integer;
    g: string;
  begin
    if Length(grp) = 0 then
      Exit;
    g := grp[0].Name;
    for k := 1 to High(grp) do
      g := g + '+' + grp[k].Name;
    gi := Length(groups);
    SetLength(groups, gi + 1);
    groups[gi] := g;
    SetLength(grp, 0);
    activeCnt := 0;
  end;

begin
  grp := nil;
  groups := nil;
  activeCnt := 0;
  for i := 0 to High(steps) do
  begin
    nm := KeyNameOf(steps[i].VK, steps[i].SC, steps[i].Ext);
    if steps[i].IsDown then
    begin
      SetLength(grp, Length(grp) + 1);
      grp[High(grp)].Name := nm;
      grp[High(grp)].Active := True;
      Inc(activeCnt);
    end
    else
    begin
      // mark the first active key of this name released; orphan ups from
      // unbalanced config are ignored
      for j := 0 to High(grp) do
        if grp[j].Active and (grp[j].Name = nm) then
        begin
          grp[j].Active := False;
          Dec(activeCnt);
          Break;
        end;
      if activeCnt = 0 then
        FlushGroup;
    end;
  end;
  FlushGroup;   // trailing holds (unbalanced hand-edited config)
  Result := '';
  for i := 0 to High(groups) do
  begin
    if Result <> '' then
      Result := Result + ' → ';
    Result := Result + groups[i];
  end;
end;

end.
