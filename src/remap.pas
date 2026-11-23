unit remap;

{ Remapping decision engine - pure logic, no SendInput calls here.
  The hook callback feeds every physical key event through RemapDecideKb and
  acts on the result: pass it on, swallow it, or inject the mapped key.

  State model (per virtual-key code):
  - PhysCount  physical (pass-through) events currently holding the key down
  - VirtCount  virtual holds on this key, driven by active source rules
  - VirtSent   we injected a down for this key and have not released it yet
  - SrcHeld    source key seen down, so the next down is auto-repeat

  Windows tracks key state per VK, so hardware LCtrl (162) and an injected
  Ctrl variant (17/163) coexist. Two rules keep lifecycles correct:
  - when a virtual hold rides on a hardware-held key and the hardware goes
    up, the down state is re-asserted for the virtual hold (restore)
  - when a virtual hold ends while hardware still holds the same VK, no up
    is injected and VirtSent is cleared, because the hardware event will
    release the state later.

  RK_COMBO rules replay a recorded sequence of raw down/up steps on source
  down (RA_STEPS); the hook injects each step in order. Combo steps are
  one-shot pairs and never enter the virtual-hold state machine, so there is
  nothing for RemapCollectReleases to flush. Source auto-repeat and release
  are swallowed - the burst fires once per physical press.

  Kept free of the input-injection API on purpose so tests/test_remap can
  exercise it as a plain unit. RK_TEXT is parsed from config but only
  handled from M4's text milestone; until then it never matches.

  While suspended (capture dialogs open) every event passes through
  untouched and no state is tracked, so already-mapped keys can be
  re-captured by the tool's own UI. }

{$mode objfpc}{$H+}

interface

uses
  Windows;

const
  // action codes returned in TRemapResult.Action
  RA_PASS  = 0;   // not our business, let the event through
  RA_BLOCK = 1;   // swallow the event, inject nothing
  RA_KEY   = 2;   // swallow the event, inject the key in the result
  RA_STEPS = 3;   // swallow the event, inject the step sequence in the result

  // rule kinds (mirrors config.json "kind")
  RK_KEY   = 0;   // src key -> dst key (DstVK = 0 disables the source key)
  RK_COMBO = 1;   // src key -> recorded down/up step sequence
  RK_TEXT  = 2;   // src key -> unicode text (handled from M4)

type
  TComboStep = record
    VK: Word;
    SC: Word;
    Ext: Boolean;
    IsDown: Boolean;
  end;
  TComboSteps = array of TComboStep;

  TRule = record
    Enabled: Boolean;
    SrcMouse: Integer;    // 0 = keyboard source, else mouse button id (M2)
    SrcVK: Word;
    SrcSC: Word;
    SrcExt: Boolean;
    Kind: Integer;        // RK_KEY / RK_COMBO / RK_TEXT
    DstVK: Word;          // RK_KEY: 0 = disable (block) the source key
    DstSC: Word;
    DstExt: Boolean;
    Combo: TComboSteps;   // RK_COMBO
    Text: string;         // RK_TEXT (UTF-8)
    App: string;          // '' = all apps; else lowercase exe name (M3)
  end;
  TRules = array of TRule;

  TRemapResult = record
    Action: Integer;      // RA_*
    VK: Word;             // key to inject (RA_KEY)
    SC: Word;
    Ext: Boolean;
    Down: Boolean;        // inject a down or an up
    RuleIdx: Integer;     // matched rule, -1 when none
    Steps: TComboSteps;   // sequence to replay (RA_STEPS)
  end;

procedure RemapSetRules(const ARules: array of TRule);   // deep copy
function  RemapRuleCount: Integer;
function  RemapRuleAt(idx: Integer): TRule;              // deep copy out
procedure RemapSetRule(idx: Integer; const ARule: TRule);
procedure RemapAddRule(const ARule: TRule);
procedure RemapDeleteRule(idx: Integer);
procedure RemapClearRules;

procedure RemapSetEnabled(AEnabled: Boolean);
function  RemapEnabled: Boolean;

{ capture-mode suspension: same passthrough as master-off, so dialogs can
  re-capture keys that active rules would otherwise swallow }
procedure RemapSetSuspended(ASuspended: Boolean);
function  RemapSuspended: Boolean;

{ drops all transient tracking (physical holds, virtual holds, repeat state);
  call when the engine is switched off/on so stale holds can't linger }
procedure RemapResetTransientState;

function  RemapDecideKb(VK: Word; Ext, IsDown: Boolean): TRemapResult;
function  IsToggleVK(VK: Word): Boolean;

{ all keys the engine currently holds down, as up-steps to inject;
  also resets the virtual state (used on disable and exit) }
procedure RemapCollectReleases(out steps: TComboSteps);

{ true when some other enabled rule already claims the same keyboard source }
function  RemapSrcTaken(VK: Word; Ext: Boolean; skipIdx: Integer): Boolean;

implementation

var
  FRules: TRules;
  FEnabled: Boolean = True;
  FSuspended: Boolean = False;
  PhysCount: array[0..255] of Integer;
  VirtCount: array[0..255] of Integer;
  VirtSent: array[0..255] of Boolean;
  SrcHeld: array[0..255] of Boolean;
  LastSC: array[0..255] of Word;      // scancode of the last injected key
  LastExt: array[0..255] of Boolean;  // ext flag of the last injected key

{ ---------- rule table (deep copies: Combo is a dynamic array) ---------- }

procedure CopyRule(const src: TRule; out dst: TRule);
var
  i: Integer;
begin
  dst := src;
  if (src.Kind = RK_COMBO) and (Length(src.Combo) > 0) then
  begin
    SetLength(dst.Combo, Length(src.Combo));
    for i := 0 to High(src.Combo) do
      dst.Combo[i] := src.Combo[i];
  end
  else
    dst.Combo := nil;   // never share the reference across rules
end;

procedure RemapSetRules(const ARules: array of TRule);
var
  i: Integer;
begin
  SetLength(FRules, Length(ARules));
  for i := 0 to High(ARules) do
    CopyRule(ARules[i], FRules[i]);
end;

function RemapRuleCount: Integer;
begin
  Result := Length(FRules);
end;

function RemapRuleAt(idx: Integer): TRule;
begin
  if (idx < 0) or (idx >= Length(FRules)) then
    Exit(Default(TRule));
  CopyRule(FRules[idx], Result);
end;

procedure RemapSetRule(idx: Integer; const ARule: TRule);
begin
  if (idx < 0) or (idx >= Length(FRules)) then
    Exit;
  CopyRule(ARule, FRules[idx]);
end;

procedure RemapAddRule(const ARule: TRule);
begin
  SetLength(FRules, Length(FRules) + 1);
  CopyRule(ARule, FRules[High(FRules)]);
end;

procedure RemapDeleteRule(idx: Integer);
var
  i: Integer;
begin
  if (idx < 0) or (idx >= Length(FRules)) then
    Exit;
  for i := idx to High(FRules) - 1 do
    FRules[i] := FRules[i + 1];
  SetLength(FRules, Length(FRules) - 1);
end;

procedure RemapClearRules;
begin
  SetLength(FRules, 0);
end;

function RemapSrcTaken(VK: Word; Ext: Boolean; skipIdx: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FRules) do
    if (i <> skipIdx) and FRules[i].Enabled and (FRules[i].SrcMouse = 0) and
       (FRules[i].SrcVK = VK) and (FRules[i].SrcExt = Ext) then
      Exit(True);
end;

{ ---------- engine state ---------- }

procedure RemapSetEnabled(AEnabled: Boolean);
begin
  FEnabled := AEnabled;
end;

function RemapEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure RemapSetSuspended(ASuspended: Boolean);
begin
  FSuspended := ASuspended;
end;

function RemapSuspended: Boolean;
begin
  Result := FSuspended;
end;

function CopySteps(const src: TComboSteps): TComboSteps;
var
  i: Integer;
begin
  SetLength(Result, Length(src));
  for i := 0 to High(src) do
    Result[i] := src[i];
end;

procedure RemapResetTransientState;
begin
  FillChar(PhysCount, SizeOf(PhysCount), 0);
  FillChar(VirtCount, SizeOf(VirtCount), 0);
  FillChar(VirtSent, SizeOf(VirtSent), 0);
  FillChar(SrcHeld, SizeOf(SrcHeld), 0);
end;

procedure RemapCollectReleases(out steps: TComboSteps);
var
  i, n: Integer;
begin
  steps := nil;
  n := 0;
  n := 0;
  for i := 0 to 255 do
    if VirtSent[i] then
    begin
      SetLength(steps, n + 1);
      steps[n].VK := Word(i);
      steps[n].SC := LastSC[i];
      steps[n].Ext := LastExt[i];
      steps[n].IsDown := False;
      VirtSent[i] := False;
      VirtCount[i] := 0;
      Inc(n);
    end;
end;

function IsToggleVK(VK: Word): Boolean;
begin
  case VK of
    VK_CAPITAL, VK_NUMLOCK, VK_SCROLL: Result := True;
  else
    Result := False;
  end;
end;

{ first enabled keyboard rule claiming this key, -1 when none.
  App filters are ignored until M3. }
function FindRule(VK: Word; Ext: Boolean): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FRules) do
    with FRules[i] do
      if Enabled and (SrcMouse = 0) and (SrcVK = VK) and (SrcExt = Ext) then
        Exit(i);
  Result := -1;
end;

procedure FillKey(out r: TRemapResult; VK, SC: Word; Ext: Boolean; down: Boolean);
begin
  r.Action := RA_KEY;
  r.VK := VK;
  r.SC := SC;
  r.Ext := Ext;
  r.Down := down;
  LastSC[VK] := SC;
  LastExt[VK] := Ext;
end;

{ ---------- decision ---------- }

function RemapDecideKb(VK: Word; Ext, IsDown: Boolean): TRemapResult;
var
  ri: Integer;
  d: Word;
  rep: Boolean;
begin
  Result := Default(TRemapResult);   // managed Steps field: no FillChar
  Result.Action := RA_PASS;
  Result.RuleIdx := -1;

  if (not FEnabled) or FSuspended then
    Exit;   // master off / capture suspension: untouched passthrough, no tracking

  rep := SrcHeld[VK] and IsDown;   // down while still held = auto-repeat
  ri := FindRule(VK, Ext);

  if ri < 0 then
  begin
    // physical event without a matching rule
    if IsDown then
      Inc(PhysCount[VK])
    else
    begin
      if PhysCount[VK] > 0 then
        Dec(PhysCount[VK]);
      // hardware release of a key that virtual holds rely on: re-assert it
      if (VirtCount[VK] > 0) and (PhysCount[VK] = 0) then
      begin
        VirtSent[VK] := True;
        FillKey(Result, VK, LastSC[VK], LastExt[VK], True);
        Exit;
      end;
    end;
    SrcHeld[VK] := IsDown;
    Exit;
  end;

  Result.RuleIdx := ri;
  case FRules[ri].Kind of
    RK_KEY:
      begin
        Result.Action := RA_BLOCK;   // a matched rule swallows by default
        d := FRules[ri].DstVK;
        if d = 0 then
          Exit;                      // disabled key: swallow down and up
        if IsDown then
        begin
          if rep and IsToggleVK(d) then
            Exit;                    // held source would rapid-toggle the lock
          if not rep then
            Inc(VirtCount[d]);
          if rep or (not VirtSent[d]) then
          begin
            // repeat passes a repeat to the target; first hold presses it
            VirtSent[d] := True;
            FillKey(Result, d, FRules[ri].DstSC, FRules[ri].DstExt, True);
          end;
          // else: dst already held by another virtual hold -> just swallow
        end
        else
        begin
          // source up
          if VirtCount[d] > 0 then
            Dec(VirtCount[d]);
          if PhysCount[d] > 0 then
            VirtSent[d] := False     // hardware covers the state from here on
          else if VirtCount[d] = 0 then
          begin
            if VirtSent[d] then
              FillKey(Result, d, FRules[ri].DstSC, FRules[ri].DstExt, False);
            VirtSent[d] := False;
          end;
          // else: another virtual hold keeps the key down -> just swallow
        end;
      end;
    RK_COMBO:
      // steps are one-shot down/up pairs, so no virtual-hold bookkeeping
      if not IsDown then
        Result.Action := RA_BLOCK    // source release: swallow
      else if rep then
        Result.Action := RA_BLOCK    // auto-repeat: fire once per press
      else if Length(FRules[ri].Combo) = 0 then
        Result.Action := RA_PASS     // corrupt/empty combo: keep the key alive
      else
      begin
        Result.Action := RA_STEPS;
        Result.Steps := CopySteps(FRules[ri].Combo);
      end;
    RK_TEXT:
      Result.Action := RA_PASS;      // handled from M4 text on; never swallow
  end;

  SrcHeld[VK] := IsDown;
end;

end.
