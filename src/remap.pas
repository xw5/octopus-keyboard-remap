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

  Modifier-combo sources (SrcMods <> 0): a rule can require Ctrl/Alt/Shift/
  Win held when the source key lands. Matching is exact - the held modifier
  set must equal SrcMods, so "Ctrl+A" never fires while Alt is also held;
  legacy plain rules (SrcMods = 0) still fire regardless of modifiers, so
  existing configs keep their old behaviour. The engine tracks physical
  modifier holds itself (the hook feeds it every physical event, injected
  ones never re-enter). Two per-VK flags drive that: ModHeld, and ModPassed
  ("held AND reached applications unmapped") - a modifier that is itself a
  source key was swallowed by its own rule, so combos must not inject
  ghost suppress/restore steps for it.

  The app has already seen the held modifiers by the time the combo fires,
  so every injected target event is wrapped in suppress/restore steps
  (TRemapResult.PreSteps/PostSteps): ups for the held passed modifiers,
  the target event, then the downs re-asserted. The app therefore receives
  the target key alone, and later physical keys with the modifier still
  work. Source-up pairing uses LastRule - the rule matched on the way down
  stays authoritative on the way up even if the user released the modifier
  first (plain re-matching would miss and strand the held target).

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

  // source modifier bits (TRule.SrcMods); side-agnostic - either L/R counts
  MODB_SHIFT   = 1;
  MODB_CONTROL = 2;
  MODB_ALT     = 4;
  MODB_WIN     = 8;

  // the physical modifier VKs the LL hook delivers, with ext flag and bit;
  // iteration order doubles as the suppress/restore injection order
  MOD_VK_COUNT = 8;
  MOD_VKS:  array[0..MOD_VK_COUNT - 1] of Word =
    (VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL,
     VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN);
  MOD_EXTS: array[0..MOD_VK_COUNT - 1] of Boolean =
    (False, False, False, True, False, True, True, True);
  MOD_BITS: array[0..MOD_VK_COUNT - 1] of Word =
    (MODB_SHIFT, MODB_SHIFT, MODB_CONTROL, MODB_CONTROL,
     MODB_ALT, MODB_ALT, MODB_WIN, MODB_WIN);

function ModBitOfVK(VK: Word): Word;

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
    SrcMods: Word;        // MODB_* bits required held (0 = no modifiers)
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
    PreSteps: TComboSteps;   // RA_KEY: inject before the key (modifier ups)
    PostSteps: TComboSteps;  // RA_KEY: inject after the key (modifier downs)
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

{ true when some other enabled rule already claims the same keyboard source
  (same key, ext flag and modifier set) }
function  RemapSrcTaken(VK: Word; Ext: Boolean; Mods: Word;
  skipIdx: Integer): Boolean;

implementation

{ forward: used by RemapResetTransientState's OS re-sync }
function FindRuleAny(VK: Word; Ext: Boolean): Integer; forward;

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
  LastRule: array[0..255] of Integer; // rule matched on the last source down
  ModHeld: array[0..255] of Boolean;   // physical holds on modifier VKs
  ModPassed: array[0..255] of Boolean; // held AND reached apps unmapped

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

function RemapSrcTaken(VK: Word; Ext: Boolean; Mods: Word;
  skipIdx: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FRules) do
    if (i <> skipIdx) and FRules[i].Enabled and (FRules[i].SrcMouse = 0) and
       (FRules[i].SrcVK = VK) and (FRules[i].SrcExt = Ext) and
       (FRules[i].SrcMods = Mods) then
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
var
  k, vk: Integer;
begin
  FillChar(PhysCount, SizeOf(PhysCount), 0);
  FillChar(VirtCount, SizeOf(VirtCount), 0);
  FillChar(VirtSent, SizeOf(VirtSent), 0);
  FillChar(SrcHeld, SizeOf(SrcHeld), 0);
  FillChar(LastRule, SizeOf(LastRule), $FF);   // all -1
  FillChar(ModHeld, SizeOf(ModHeld), 0);
  FillChar(ModPassed, SizeOf(ModPassed), 0);
  { re-sync modifier holds from the OS: keys held since before the engine
    was (re)enabled must count; a held modifier that a rule claims as its
    own source never reached apps, so it is not "passed" }
  for k := 0 to MOD_VK_COUNT - 1 do
  begin
    vk := MOD_VKS[k];
    ModHeld[vk] := (Word(GetAsyncKeyState(vk)) and $8000) <> 0;
    ModPassed[vk] := ModHeld[vk] and (FindRuleAny(vk, MOD_EXTS[k]) < 0);
  end;
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

{ bit for a modifier VK; generic VK_SHIFT/CONTROL/MENU never arrive from the
  LL hook but are mapped anyway for robustness }
function ModBitOfVK(VK: Word): Word;
var
  k: Integer;
begin
  for k := 0 to MOD_VK_COUNT - 1 do
    if MOD_VKS[k] = VK then
      Exit(MOD_BITS[k]);
  case VK of
    VK_SHIFT:   Result := MODB_SHIFT;
    VK_CONTROL: Result := MODB_CONTROL;
    VK_MENU:    Result := MODB_ALT;
  else
    Result := 0;
  end;
end;

{ OR of the bits of all physically held modifiers }
function ModsHeldNow: Word;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to MOD_VK_COUNT - 1 do
    if ModHeld[MOD_VKS[k]] then
      Result := Result or MOD_BITS[k];
end;

{ any enabled keyboard rule claiming this key as source, whatever its
  modifier set }
function FindRuleAny(VK: Word; Ext: Boolean): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FRules) do
    with FRules[i] do
      if Enabled and (SrcMouse = 0) and (SrcVK = VK) and (SrcExt = Ext) then
        Exit(i);
  Result := -1;
end;

{ refresh the per-VK modifier flags for one physical event. On down, the
  modifier counts as "passed" only when no rule claims that very key as its
  own source - otherwise the rule swallows it and apps never see it. }
procedure TrackMods(VK: Word; Ext, IsDown: Boolean);
begin
  if ModBitOfVK(VK) = 0 then
    Exit;
  if IsDown then
  begin
    ModHeld[VK] := True;
    ModPassed[VK] := FindRuleAny(VK, Ext) < 0;
  end
  else
  begin
    ModHeld[VK] := False;
    ModPassed[VK] := False;
  end;
end;

{ still a valid rule for this source key (used to trust LastRule on the up) }
function RuleClaims(ri: Integer; VK: Word; Ext: Boolean): Boolean;
begin
  Result := (ri >= 0) and (ri <= High(FRules)) and FRules[ri].Enabled and
    (FRules[ri].SrcMouse = 0) and (FRules[ri].SrcVK = VK) and
    (FRules[ri].SrcExt = Ext);
end;

{ first enabled keyboard rule claiming this key with this modifier set.
  Pass 1 is exact: a combo rule needs exactly its modifiers held. Pass 2
  keeps the legacy behaviour for plain rules (SrcMods = 0): they fire
  whatever modifiers are held. App filters are ignored until M3. }
function FindRule(VK: Word; Ext: Boolean; Mods: Word): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FRules) do
    with FRules[i] do
      if Enabled and (SrcMouse = 0) and (SrcVK = VK) and (SrcExt = Ext) and
         (SrcMods = Mods) then
        Exit(i);
  if Mods <> 0 then
    for i := 0 to High(FRules) do
      with FRules[i] do
        if Enabled and (SrcMouse = 0) and (SrcVK = VK) and (SrcExt = Ext) and
           (SrcMods = 0) then
          Exit(i);
  Result := -1;
end;

{ suppress (ups) and restore (downs) steps for the rule's modifiers that
  are physically held and actually reached apps. Injecting the ups before
  a target event makes it land alone; the downs afterwards re-assert the
  holds so later physical keys still see the modifier. Both are empty when
  there is nothing to do (plain rules, or the modifier is itself remapped
  and never reached apps). }
procedure BuildModSteps(SrcMods: Word; out pre, post: TComboSteps);
var
  k, j, n: Integer;
begin
  pre := nil;
  post := nil;
  n := 0;
  for k := 0 to MOD_VK_COUNT - 1 do
    if ((MOD_BITS[k] and SrcMods) <> 0) and ModPassed[MOD_VKS[k]] then
      Inc(n);
  if n = 0 then
    Exit;
  SetLength(pre, n);
  SetLength(post, n);
  j := 0;
  for k := 0 to MOD_VK_COUNT - 1 do
    if ((MOD_BITS[k] and SrcMods) <> 0) and ModPassed[MOD_VKS[k]] then
    begin
      pre[j].VK := MOD_VKS[k];
      pre[j].SC := 0;
      pre[j].Ext := MOD_EXTS[k];
      pre[j].IsDown := False;
      post[j].VK := MOD_VKS[k];
      post[j].SC := 0;
      post[j].Ext := MOD_EXTS[k];
      post[j].IsDown := True;
      Inc(j);
    end;
end;

{ var, not out: an out record parameter is cleared on call entry in FPC,
  which would wipe PreSteps/PostSteps built by the caller beforehand }
procedure FillKey(var r: TRemapResult; VK, SC: Word; Ext: Boolean; down: Boolean);
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
  mods: Word;
  rep: Boolean;
begin
  Result := Default(TRemapResult);   // managed Steps fields: no FillChar
  Result.Action := RA_PASS;
  Result.RuleIdx := -1;

  if (not FEnabled) or FSuspended then
    Exit;   // master off / capture suspension: untouched passthrough, no tracking

  TrackMods(VK, Ext, IsDown);   // keep the modifier picture current
  mods := ModsHeldNow;

  rep := SrcHeld[VK] and IsDown;   // down while still held = auto-repeat
  if IsDown then
  begin
    ri := FindRule(VK, Ext, mods);
    LastRule[VK] := ri;   // the up pairs with this rule even if the user
  end                     // drops a modifier before releasing the key
  else
  begin
    ri := LastRule[VK];
    if not RuleClaims(ri, VK, Ext) then
      ri := FindRule(VK, Ext, mods);
  end;

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
        // every injected target event lands alone: suppress the held rule
        // modifiers first, re-assert them afterwards (plain rules: no-op)
        BuildModSteps(FRules[ri].SrcMods, Result.PreSteps, Result.PostSteps);
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
        // the recorded burst lands alone: suppress held rule modifiers
        // before it, re-assert them after it
        BuildModSteps(FRules[ri].SrcMods, Result.PreSteps, Result.PostSteps);
      end;
    RK_TEXT:
      Result.Action := RA_PASS;      // handled from M4 text on; never swallow
  end;

  SrcHeld[VK] := IsDown;
end;

end.
