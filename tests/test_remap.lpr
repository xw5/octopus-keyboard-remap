program test_remap;

{$mode objfpc}{$H+}

{ Decision-engine assertions. Compile & run directly with FPC (no LCL):
  C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe -Fu..\src test_remap.lpr
  build.bat test wraps this. }

uses
  SysUtils, Windows, remap;

var
  Fails: Integer = 0;

procedure Check(cond: Boolean; const name: string);
begin
  if cond then
    writeln('PASS ', name)
  else
  begin
    writeln('FAIL ', name);
    Inc(Fails);
  end;
end;

function KeyRule(srcVK, dstVK: Word): TRule;
begin
  Result := Default(TRule);
  Result.Combo := nil;
  Result.Enabled := True;
  Result.SrcMouse := 0;
  Result.SrcVK := srcVK;
  Result.SrcSC := 0;
  Result.SrcExt := False;
  Result.Kind := RK_KEY;
  Result.DstVK := dstVK;
end;

{ F5 -> the recorded burst Ctrl down, C down, C up, Ctrl up }
function ComboRule(srcVK: Word): TRule;
var
  st: TComboStep;
begin
  Result := Default(TRule);
  Result.Combo := nil;
  Result.Enabled := True;
  Result.SrcMouse := 0;
  Result.SrcVK := srcVK;
  Result.SrcSC := 0;
  Result.SrcExt := False;
  Result.Kind := RK_COMBO;
  Result.DstVK := 0;
  st.SC := 0;
  st.Ext := False;
  st.VK := VK_CONTROL;
  st.IsDown := True;
  SetLength(Result.Combo, 1);
  Result.Combo[0] := st;
  st.VK := Ord('C');
  st.IsDown := True;
  SetLength(Result.Combo, 2);
  Result.Combo[1] := st;
  st.VK := Ord('C');
  st.IsDown := False;
  SetLength(Result.Combo, 3);
  Result.Combo[2] := st;
  st.VK := VK_CONTROL;
  st.IsDown := False;
  SetLength(Result.Combo, 4);
  Result.Combo[3] := st;
end;

procedure ResetEngine;
begin
  RemapClearRules;
  RemapResetTransientState;
end;

var
  r: TRemapResult;
  rel: TComboSteps;
  rule: TRule;
begin
  { T1 no rules -> passthrough }
  ResetEngine;
  r := RemapDecideKb(VK_CAPITAL, False, True);
  Check(r.Action = RA_PASS, 'T1 unknown key passes');

  { T2 simple remap F1 -> F2, with auto-repeat }
  ResetEngine;
  RemapAddRule(KeyRule(VK_F1, VK_F2));
  r := RemapDecideKb(VK_F1, False, True);
  Check((r.Action = RA_KEY) and (r.VK = VK_F2) and r.Down, 'T2 down -> F2 down');
  r := RemapDecideKb(VK_F1, False, True);
  Check((r.Action = RA_KEY) and (r.VK = VK_F2) and r.Down, 'T2 repeat -> F2 repeat');
  r := RemapDecideKb(VK_F1, False, False);
  Check((r.Action = RA_KEY) and (r.VK = VK_F2) and (not r.Down), 'T2 up -> F2 up');
  r := RemapDecideKb(VK_F2, False, True);
  Check(r.Action = RA_PASS, 'T2 target F2 itself passes (no loop)');

  { T3 disabled key: swallow down and up }
  ResetEngine;
  RemapAddRule(KeyRule(VK_INSERT, 0));
  Check(RemapDecideKb(VK_INSERT, False, True).Action = RA_BLOCK,
    'T3 disable swallows down');
  Check(RemapDecideKb(VK_INSERT, False, False).Action = RA_BLOCK,
    'T3 disable swallows up');

  { T4 toggle target: held source must not rapid-toggle the lock }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_SCROLL));
  r := RemapDecideKb(VK_CAPITAL, False, True);
  Check(r.Action = RA_KEY, 'T4 first down toggles');
  r := RemapDecideKb(VK_CAPITAL, False, True);
  Check(r.Action = RA_BLOCK, 'T4 repeat blocked for toggle key');
  r := RemapDecideKb(VK_CAPITAL, False, False);
  Check(r.Action = RA_KEY, 'T4 up pairs');

  { T5 CapsLock -> LeftCtrl basic lifecycle }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_LCONTROL));
  r := RemapDecideKb(VK_CAPITAL, False, True);
  Check((r.Action = RA_KEY) and (r.VK = VK_LCONTROL) and r.Down,
    'T5 down -> Ctrl down');
  r := RemapDecideKb(VK_CAPITAL, False, False);
  Check((r.Action = RA_KEY) and (r.VK = VK_LCONTROL) and (not r.Down),
    'T5 up -> Ctrl up');

  { T6 virtual hold survives a hardware release of the same VK }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_LCONTROL));
  r := RemapDecideKb(VK_LCONTROL, False, True);
  Check(r.Action = RA_PASS, 'T6 hardware Ctrl down passes');
  r := RemapDecideKb(VK_CAPITAL, False, True);
  Check(r.Action = RA_KEY, 'T6 virtual hold starts');
  r := RemapDecideKb(VK_LCONTROL, False, False);
  Check((r.Action = RA_KEY) and (r.VK = VK_LCONTROL) and r.Down,
    'T6 hardware up -> restore virtual Ctrl');
  r := RemapDecideKb(VK_CAPITAL, False, False);
  Check((r.Action = RA_KEY) and (r.VK = VK_LCONTROL) and (not r.Down),
    'T6 virtual up releases');

  { T7 virtual up rides on a hardware-held dst: swallow, no premature release }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_LCONTROL));
  RemapDecideKb(VK_LCONTROL, False, True);      // hardware down, pass
  RemapDecideKb(VK_CAPITAL, False, True);       // virtual down, inject
  r := RemapDecideKb(VK_CAPITAL, False, False); // virtual up
  Check(r.Action = RA_BLOCK, 'T7 virtual up swallowed while hardware holds');
  r := RemapDecideKb(VK_LCONTROL, False, False);
  Check(r.Action = RA_PASS, 'T7 hardware up passes and finishes release');

  { T8 two virtual holds on the same dst key }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_LCONTROL));
  RemapAddRule(KeyRule(VK_SCROLL, VK_LCONTROL));
  r := RemapDecideKb(VK_CAPITAL, False, True);
  Check(r.Action = RA_KEY, 'T8 first hold injects');
  r := RemapDecideKb(VK_SCROLL, False, True);
  Check(r.Action = RA_BLOCK, 'T8 second hold swallows');
  r := RemapDecideKb(VK_CAPITAL, False, False);
  Check(r.Action = RA_BLOCK, 'T8 first release keeps Ctrl down');
  r := RemapDecideKb(VK_SCROLL, False, False);
  Check((r.Action = RA_KEY) and (r.VK = VK_LCONTROL) and (not r.Down),
    'T8 last release injects Ctrl up');

  { T9 extended-key flag separates rules (Num Enter vs Return) }
  ResetEngine;
  RemapAddRule(KeyRule(VK_RETURN, VK_ESCAPE));
  r := RemapDecideKb(VK_RETURN, True, True);
  Check(r.Action = RA_PASS, 'T9 extended Return not matched');
  r := RemapDecideKb(VK_RETURN, False, True);
  Check(r.Action = RA_KEY, 'T9 main Return matched');

  { T10 duplicate source detection }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_ESCAPE));
  Check(RemapSrcTaken(VK_CAPITAL, False, 0, -1), 'T10 src reported taken');
  Check(not RemapSrcTaken(VK_CAPITAL, True, 0, -1), 'T10 ext variant free');
  Check(not RemapSrcTaken(VK_CAPITAL, False, 0, 0), 'T10 skipIdx excludes');

  { T11 flush collects and clears pending holds }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_LCONTROL));
  RemapDecideKb(VK_CAPITAL, False, True);
  RemapCollectReleases(rel);
  Check((Length(rel) = 1) and (rel[0].VK = VK_LCONTROL) and (not rel[0].IsDown),
    'T11 flush returns the held key');
  RemapCollectReleases(rel);
  Check(Length(rel) = 0, 'T11 flush clears state');

  { T12 master off passes everything }
  ResetEngine;
  RemapAddRule(KeyRule(VK_CAPITAL, VK_ESCAPE));
  RemapSetEnabled(False);
  Check(RemapDecideKb(VK_CAPITAL, False, True).Action = RA_PASS,
    'T12 disabled engine passes');
  RemapSetEnabled(True);

  { T13 combo rule replays the recorded burst on source down }
  ResetEngine;
  RemapAddRule(ComboRule(VK_F5));
  r := RemapDecideKb(VK_F5, False, True);
  Check((r.Action = RA_STEPS) and (Length(r.Steps) = 4), 'T13 down replays 4 steps');
  Check((Length(r.Steps) = 4) and (r.Steps[0].VK = VK_CONTROL) and r.Steps[0].IsDown and
    (r.Steps[1].VK = Ord('C')) and r.Steps[1].IsDown and
    (r.Steps[2].VK = Ord('C')) and (not r.Steps[2].IsDown) and
    (r.Steps[3].VK = VK_CONTROL) and (not r.Steps[3].IsDown),
    'T13 step order and down/up flags correct');

  { T14 combo repeat and release are swallowed; no virtual holds linger }
  r := RemapDecideKb(VK_F5, False, True);
  Check(r.Action = RA_BLOCK, 'T14 auto-repeat swallowed');
  r := RemapDecideKb(VK_F5, False, False);
  Check(r.Action = RA_BLOCK, 'T14 source up swallowed');
  RemapCollectReleases(rel);
  Check(Length(rel) = 0, 'T14 combo leaves no virtual holds');

  { T15 capture suspension passes everything and is reversible }
  RemapSetSuspended(True);
  r := RemapDecideKb(VK_F5, False, True);
  Check(r.Action = RA_PASS, 'T15 suspended engine passes rule key');
  RemapSetSuspended(False);
  r := RemapDecideKb(VK_F5, False, True);
  Check(r.Action = RA_STEPS, 'T15 resume restores the combo');

  { T16 empty combo keeps the key alive (hand-edited config guard) }
  ResetEngine;
  rule := ComboRule(VK_F5);
  SetLength(rule.Combo, 0);
  RemapAddRule(rule);
  Check(RemapDecideKb(VK_F5, False, True).Action = RA_PASS,
    'T16 empty combo passes');

  { T17 RK_TEXT is still a passthrough placeholder }
  ResetEngine;
  rule := ComboRule(VK_F5);
  rule.Kind := RK_TEXT;
  rule.Combo := nil;
  RemapAddRule(rule);
  Check(RemapDecideKb(VK_F5, False, True).Action = RA_PASS,
    'T17 text rule passes');

  { T18 combo source Ctrl+A -> X: fires only with exactly Ctrl held,
    and the injected target is wrapped in suppress/restore steps }
  ResetEngine;
  rule := KeyRule(Ord('A'), Ord('X'));
  rule.SrcMods := MODB_CONTROL;
  RemapAddRule(rule);
  Check(RemapDecideKb(Ord('A'), False, True).Action = RA_PASS,
    'T18 source alone does not fire');
  RemapDecideKb(Ord('A'), False, False);
  Check(RemapDecideKb(VK_LSHIFT, False, True).Action = RA_PASS,
    'T18 shift down passes');
  Check(RemapDecideKb(Ord('A'), False, True).Action = RA_PASS,
    'T18 wrong modifier does not fire');
  RemapDecideKb(Ord('A'), False, False);
  RemapDecideKb(VK_LSHIFT, False, False);
  Check(RemapDecideKb(VK_LCONTROL, False, True).Action = RA_PASS,
    'T18 ctrl down passes');
  r := RemapDecideKb(Ord('A'), False, True);
  Check((r.Action = RA_KEY) and (r.VK = Ord('X')) and r.Down,
    'T18 Ctrl+A fires X');
  Check((Length(r.PreSteps) = 1) and (r.PreSteps[0].VK = VK_LCONTROL) and
    (not r.PreSteps[0].IsDown), 'T18 suppress step releases Ctrl');
  Check((Length(r.PostSteps) = 1) and (r.PostSteps[0].VK = VK_LCONTROL) and
    r.PostSteps[0].IsDown, 'T18 restore step re-asserts Ctrl');
  r := RemapDecideKb(Ord('A'), False, False);
  Check((r.Action = RA_KEY) and (r.VK = Ord('X')) and (not r.Down),
    'T18 up pairs while Ctrl still held');
  Check(RemapDecideKb(VK_LCONTROL, False, False).Action = RA_PASS,
    'T18 ctrl up passes');

  { T19 modifier dropped before the source release: LastRule keeps the
    pairing, the target still gets its up and nothing sticks }
  ResetEngine;
  rule := KeyRule(Ord('A'), Ord('X'));
  rule.SrcMods := MODB_CONTROL;
  RemapAddRule(rule);
  RemapDecideKb(VK_LCONTROL, False, True);
  RemapDecideKb(Ord('A'), False, True);       // fire
  RemapDecideKb(VK_LCONTROL, False, False);   // Ctrl released first
  r := RemapDecideKb(Ord('A'), False, False); // then the source
  Check((r.Action = RA_KEY) and (r.VK = Ord('X')) and (not r.Down),
    'T19 late source up still releases the target');
  Check(Length(r.PreSteps) = 0, 'T19 no suppress once the modifier is gone');
  RemapCollectReleases(rel);
  Check(Length(rel) = 0, 'T19 no virtual hold left');

  { T20 legacy plain rule keeps firing with modifiers held, no suppress }
  ResetEngine;
  RemapAddRule(KeyRule(Ord('A'), Ord('Y')));
  RemapDecideKb(VK_LCONTROL, False, True);
  r := RemapDecideKb(Ord('A'), False, True);
  Check((r.Action = RA_KEY) and (r.VK = Ord('Y')),
    'T20 plain rule ignores held modifiers');
  Check(Length(r.PreSteps) = 0, 'T20 plain rule injects no suppress steps');
  RemapDecideKb(Ord('A'), False, False);
  RemapDecideKb(VK_LCONTROL, False, False);

  { T21 plain and combo sources on the same key coexist; exact wins }
  ResetEngine;
  RemapAddRule(KeyRule(Ord('A'), Ord('Y')));
  rule := KeyRule(Ord('A'), Ord('X'));
  rule.SrcMods := MODB_CONTROL;
  RemapAddRule(rule);
  RemapDecideKb(VK_LCONTROL, False, True);
  r := RemapDecideKb(Ord('A'), False, True);
  Check((r.Action = RA_KEY) and (r.VK = Ord('X')),
    'T21 combo rule wins while Ctrl held');
  RemapDecideKb(Ord('A'), False, False);
  RemapDecideKb(VK_LCONTROL, False, False);
  r := RemapDecideKb(Ord('A'), False, True);
  Check((r.Action = RA_KEY) and (r.VK = Ord('Y')),
    'T21 plain rule wins without Ctrl');
  RemapDecideKb(Ord('A'), False, False);
  Check(RemapSrcTaken(Ord('A'), False, 0, -1) and
    RemapSrcTaken(Ord('A'), False, MODB_CONTROL, -1),
    'T21 both modifier sets reported taken');
  Check(not RemapSrcTaken(Ord('A'), False, MODB_SHIFT, -1),
    'T21 a different modifier set stays free');

  { T22 combo rule with a modifier source wraps the burst }
  ResetEngine;
  rule := ComboRule(VK_F5);
  rule.SrcMods := MODB_CONTROL;
  RemapAddRule(rule);
  RemapDecideKb(VK_LCONTROL, False, True);
  r := RemapDecideKb(VK_F5, False, True);
  Check(r.Action = RA_STEPS, 'T22 burst fires with Ctrl held');
  Check((Length(r.PreSteps) = 1) and (not r.PreSteps[0].IsDown),
    'T22 suppress step before the burst');
  Check((Length(r.PostSteps) = 1) and r.PostSteps[0].IsDown,
    'T22 restore step after the burst');
  RemapDecideKb(VK_F5, False, False);
  RemapDecideKb(VK_LCONTROL, False, False);

  { T23 disable rule with a modifier source blocks only on exact match }
  ResetEngine;
  rule := KeyRule(Ord('A'), 0);
  rule.SrcMods := MODB_CONTROL;
  RemapAddRule(rule);
  RemapDecideKb(VK_LCONTROL, False, True);
  Check(RemapDecideKb(Ord('A'), False, True).Action = RA_BLOCK,
    'T23 disable swallows Ctrl+A');
  RemapDecideKb(Ord('A'), False, False);
  RemapDecideKb(VK_LCONTROL, False, False);
  Check(RemapDecideKb(Ord('A'), False, True).Action = RA_PASS,
    'T23 disable does not touch the bare key');
  RemapDecideKb(Ord('A'), False, False);

  if Fails = 0 then
    writeln('ALL OK')
  else
    writeln(IntToStr(Fails), ' FAILURES');
  if Fails > 0 then
    ExitCode := 1;
end.
