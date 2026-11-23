unit capture;

{ TKeyCapture: a click-to-arm key capture box. Reads raw WM_KEYDOWN/
  WM_SYSKEYDOWN while armed so the scancode and the extended-key flag
  survive (LCL's OnKeyDown would drop both), and answers WM_GETDLGCODE with
  DLGC_WANTALLKEYS so Tab/Enter/Esc reach us instead of the dialog manager.
  Every key is recordable, Esc included: the control flow lives on the
  mouse, clicking the armed box again (or leaving it) cancels without
  changing the value. Key-up events always pass through untouched -
  swallowing one could stick a modifier. A disabled box is drawn washed-out
  so "disabled and inert" is visible, not a surprise (the edit dialog
  disables this box when the rule blocks the key instead of mapping it).

  As a source box it also records modifier combos: a modifier keydown while
  armed only joins a live "Ctrl+..." prefix (the box stays armed - the old
  behaviour of recording on the first keydown made the modifier itself the
  capture, so combos could never be recorded). The prefix is tracked from
  the modifier key events themselves, which arrive in order - immune to the
  GetAsyncKeyState lag that makes sampling at record time miss a just-sent
  synthetic chord. Arm time seeds the prefix from the OS once so modifiers
  already held show up too. Releasing a modifier with nothing else held
  records that modifier as the source, so plain remaps of modifier keys
  keep working; that release is ignored when the modifier was already held
  when the box was armed (never pressed here). The captured key's own bit
  is excluded, so recording the Shift key itself does not read back as
  "Shift+Shift". Boxes used as a plain target set AllowMods = False: they
  keep the old record-on-first-keydown semantics and never show a prefix.

  TComboCapture: a click-to-arm recorder for key sequences. While armed it
  reads raw WM_KEYDOWN/UP and WM_SYSKEYDOWN/UP and records every press and
  release in real order, so plain chords (Ctrl+Shift+Esc) and macros
  (Ctrl+C, Ctrl+V) both come out as faithful step lists. Clicking the
  armed box again or losing focus finishes the burst; keys still held get
  their up events appended (reverse press order) so replay never sticks
  them. Key-ups for keys that were never seen down here (held since before
  arming) are swallowed unrecorded to keep the steps balanced. No key is
  reserved for control - Esc, Backspace, Tab are all recordable; undo is
  the edit dialog's non-focus-stealing button calling DeleteLastKey, so
  it works mid-burst. Clear the steps to start over. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, LMessages, Classes, SysUtils, Controls, Graphics, Forms,
  LCLType, keymap, remap, langstrings;

{ Detaching the IME context while armed keeps letter keys raw: with an IME
  active (e.g. Chinese), WM_KEYDOWN carries VK_PROCESSKEY instead of the
  letter and Esc can be eaten to cancel composition - both ruin capture. }
function ImmAssociateContext(hWnd: HWND; hIMC: THandle): THandle; stdcall;
  external 'imm32.dll';

type
  TKeyCapture = class(TCustomControl)
  private
    FArmed: Boolean;
    FHas: Boolean;
    FVK, FSC: Word;
    FExt: Boolean;
    FMods: Word;         // modifier bits OF the recorded value
    FPrefix: Word;       // transient live combo prefix while armed only
    FArmMods: Word;      // modifiers already held when the box was armed
    FAllowMods: Boolean; // False: plain single-key box (target side)
    FOldIMC: THandle;   // IME context to restore on disarm
    FOnChange: TNotifyEvent;
  protected
    procedure Click; override;
    procedure DoExit; override;
    procedure Disarm;
    procedure Paint; override;
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
    procedure WndProc(var Msg: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Clear;
    procedure SetKey(VK, SC: Word; Ext: Boolean);
    procedure SetKeyMods(VK, SC: Word; Ext: Boolean; Mods: Word);
    function GetKey(out VK, SC: Word; out Ext: Boolean): Boolean;
    function GetMods: Word;
    property Armed: Boolean read FArmed;
    property HasKey: Boolean read FHas;
    property AllowMods: Boolean read FAllowMods write FAllowMods;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TComboCapture = class(TCustomControl)
  private
    FArmed: Boolean;
    FSteps: TComboSteps;
    FHeld: array[0..255] of Boolean;
    FOldIMC: THandle;   // IME context to restore on disarm
    FOnChange: TNotifyEvent;
  protected
    procedure Click; override;
    procedure DoExit; override;
    procedure Paint; override;
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
    procedure WndProc(var Msg: TMessage); override;
    procedure FinishRecording;
    procedure AppendStep(VK, SC: Word; Ext, IsDown: Boolean);
  public
    constructor Create(AOwner: TComponent);
    procedure ClearSteps;
    procedure SetSteps(const ASteps: TComboSteps);
    procedure GetSteps(out ASteps: TComboSteps);
    procedure DeleteLastKey;   // undo the most recently pressed key
    property Armed: Boolean read FArmed;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

{ ---------- TKeyCapture ---------- }

{ OS-level held modifiers right now; the engine is suspended while a
  capture dialog is open, so physical state is unfiltered }
function SampleMods: Word;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to MOD_VK_COUNT - 1 do
    if (Word(GetAsyncKeyState(MOD_VKS[k])) and $8000) <> 0 then
      Result := Result or MOD_BITS[k];
end;

constructor TKeyCapture.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 240;
  Height := 40;
  TabStop := True;
  FAllowMods := True;   // source box default; the target box opts out
end;

procedure TKeyCapture.Clear;
begin
  FHas := False;
  FMods := 0;
  FPrefix := 0;
  Invalidate;
end;

procedure TKeyCapture.SetKey(VK, SC: Word; Ext: Boolean);
begin
  SetKeyMods(VK, SC, Ext, 0);
end;

procedure TKeyCapture.SetKeyMods(VK, SC: Word; Ext: Boolean; Mods: Word);
begin
  FVK := VK;
  FSC := SC;
  FExt := Ext;
  FMods := Mods;
  FHas := True;
  Invalidate;
end;

function TKeyCapture.GetKey(out VK, SC: Word; out Ext: Boolean): Boolean;
begin
  VK := FVK;
  SC := FSC;
  Ext := FExt;
  Result := FHas;
end;

function TKeyCapture.GetMods: Word;
begin
  Result := FMods;
end;

procedure TKeyCapture.Disarm;
begin
  if FArmed then
  begin
    FArmed := False;
    FPrefix := 0;   // the transient prefix dies with the arming session
    ImmAssociateContext(Self.Handle, FOldIMC);
  end;
end;

procedure TKeyCapture.Click;
begin
  inherited Click;
  SetFocus;
  if FArmed then
    Disarm   // armed box clicked again: cancel; the stored value survives
  else
  begin
    FOldIMC := ImmAssociateContext(Self.Handle, 0);
    FArmed := True;
    // modifiers held before arming join the live prefix but can never be
    // recorded as the captured key (their release was not a press here)
    FPrefix := SampleMods;
    FArmMods := FPrefix;
  end;
  Invalidate;
end;

procedure TKeyCapture.DoExit;
begin
  inherited DoExit;
  Disarm;   // stored value (and its FMods) untouched by losing focus
  Invalidate;
end;

procedure TKeyCapture.CMEnabledChanged(var Msg: TLMessage);
begin
  inherited;   // TWinControl: EnableWindow(Handle, Enabled) - never swallow
  Invalidate;
end;

procedure TKeyCapture.Paint;
var
  txt: string;
  tw, th: Integer;
begin
  Canvas.Pen.Width := 2;
  if not Enabled then
    Canvas.Pen.Color := clBtnFace            // washed out: box is inert
  else if FArmed then
    Canvas.Pen.Color := RGB(52, 124, 246)
  else
    Canvas.Pen.Color := clBtnShadow;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(1, 1, Width - 1, Height - 1);
  if FHas then
  begin
    if FArmed and (FPrefix <> 0) then
      txt := ModsPrefix(FPrefix) + KeyNameOf(FVK, FSC, FExt)   // live preview
    else
      txt := ModsPrefix(FMods) + KeyNameOf(FVK, FSC, FExt)
  end
  else if FArmed and (FPrefix <> 0) then
    txt := ModsPrefix(FPrefix) + '…'   // live combo prefix mid-recording
  else
    txt := S(SID_CAP_HINT);
  Canvas.Font := Font;
  if not Enabled then
    Canvas.Font.Color := clBtnShadow
  else if not FHas then
    Canvas.Font.Color := clGrayText;
  tw := Canvas.TextWidth(txt);
  th := Canvas.TextHeight(txt);
  Canvas.TextOut((Width - tw) div 2, (Height - th) div 2, txt);
  Canvas.Brush.Style := bsSolid;
end;

procedure TKeyCapture.WndProc(var Msg: TMessage);
var
  key, sc: Word;
  ext: Boolean;
begin
  if not FArmed then
  begin
    inherited WndProc(Msg);
    Exit;
  end;
  case Msg.Msg of
    WM_GETDLGCODE:
      begin
        Msg.Result := DLGC_WANTALLKEYS;
        Exit;
      end;
    WM_KEYDOWN, WM_SYSKEYDOWN:
      begin
        key := Word(Msg.WParam);
        if (Msg.LParam and $40000000) <> 0 then   // auto-repeat: ignore
        begin
          Msg.Result := 0;
          Exit;
        end;
        sc := Word((Msg.LParam shr 16) and $FF);
        ext := (Msg.LParam and $01000000) <> 0;
        if FAllowMods and (ModBitOfVK(key) <> 0) then
        begin
          // modifier press: join the live prefix and stay armed - the
          // combo finishes on the next non-modifier key, or a bare
          // modifier is recorded when it comes back up alone
          FPrefix := FPrefix or ModBitOfVK(key);
          Invalidate;
          Msg.Result := 0;
          Exit;
        end;
        // plain key (or any key on a target box): record now. The prefix
        // is the event-tracked live state - message order guarantees the
        // chord's modifier keydown arrived before this one, so a just-sent
        // synthetic Ctrl+A is captured as reliably as a physical hold
        if not FAllowMods then
          FMods := 0
        else
          FMods := FPrefix;
        FMods := FMods and not ModBitOfVK(key);
        FVK := key;
        FSC := sc;
        FExt := ext;
        FHas := True;
        Disarm;
        Invalidate;
        if FOnChange <> nil then
          FOnChange(Self);
        Msg.Result := 0;
        Exit;
      end;
    WM_KEYUP, WM_SYSKEYUP:
      begin
        key := Word(Msg.WParam);
        if FAllowMods and (ModBitOfVK(key) <> 0) then
        begin
          FPrefix := FPrefix and not ModBitOfVK(key);
          // a modifier released with nothing else held and no press before
          // arming was tapped alone: record it as the captured key
          if (FPrefix = 0) and ((ModBitOfVK(key) and FArmMods) = 0) then
          begin
            FVK := key;
            FSC := Word((Msg.LParam shr 16) and $FF);
            FExt := (Msg.LParam and $01000000) <> 0;
            FMods := 0;
            FHas := True;
            Disarm;
            Invalidate;
            if FOnChange <> nil then
              FOnChange(Self);
          end
          else
            Invalidate;
          Msg.Result := 0;
          Exit;
        end;
      end;
  end;
  inherited WndProc(Msg);
end;

{ ---------- TComboCapture ---------- }

constructor TComboCapture.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 240;
  Height := 40;
  TabStop := True;
end;

procedure TComboCapture.ClearSteps;
begin
  SetLength(FSteps, 0);
  FillChar(FHeld, SizeOf(FHeld), 0);
  Invalidate;
end;

procedure TComboCapture.SetSteps(const ASteps: TComboSteps);
begin
  FSteps := Copy(ASteps);
  FillChar(FHeld, SizeOf(FHeld), 0);   // loaded rules are balanced already
  Invalidate;
end;

procedure TComboCapture.GetSteps(out ASteps: TComboSteps);
begin
  ASteps := Copy(FSteps);
end;

procedure TComboCapture.AppendStep(VK, SC: Word; Ext, IsDown: Boolean);
var
  n: Integer;
begin
  n := Length(FSteps);
  SetLength(FSteps, n + 1);
  FSteps[n].VK := VK;
  FSteps[n].SC := SC;
  FSteps[n].Ext := Ext;
  FSteps[n].IsDown := IsDown;
  Invalidate;
  if FOnChange <> nil then
    FOnChange(Self);
end;

procedure TComboCapture.Click;
begin
  inherited Click;
  SetFocus;
  if FArmed then
    FinishRecording   // armed box clicked again: end the burst
  else
  begin
    FOldIMC := ImmAssociateContext(Self.Handle, 0);
    FArmed := True;   // re-arming appends to the recorded steps
  end;
  Invalidate;
end;

{ undo the most recently pressed key: drop its down, and its up too if it
  was released already - pairs never overlap, so removing them leaves the
  rest of the step list balanced whatever the interleaving was. A key
  still held loses only its down, and FHeld is cleared so the physical
  release gets swallowed unrecorded, like FinishRecording's leftovers. }
procedure TComboCapture.DeleteLastKey;
var
  i, j, k: Integer;
  vk: Word;
  ext: Boolean;
begin
  i := High(FSteps);
  while (i >= 0) and not FSteps[i].IsDown do
    Dec(i);   // the last down is the last key pressed
  if i < 0 then
    Exit;
  vk := FSteps[i].VK;
  ext := FSteps[i].Ext;
  j := i + 1;
  while (j <= High(FSteps)) and not (not FSteps[j].IsDown and
      (FSteps[j].VK = vk) and (FSteps[j].Ext = ext)) do
    Inc(j);   // its up, if the key was released already
  if j <= High(FSteps) then
  begin
    for k := j to High(FSteps) - 1 do
      FSteps[k] := FSteps[k + 1];
    SetLength(FSteps, Length(FSteps) - 1);
  end;
  for k := i to High(FSteps) - 1 do
    FSteps[k] := FSteps[k + 1];
  SetLength(FSteps, Length(FSteps) - 1);
  FHeld[vk] := False;
  Invalidate;
  if FOnChange <> nil then
    FOnChange(Self);
end;

procedure TComboCapture.DoExit;
begin
  inherited DoExit;
  if FArmed then
    FinishRecording;   // focus left the box: commit what was recorded
end;

procedure TComboCapture.CMEnabledChanged(var Msg: TLMessage);
begin
  inherited;   // TWinControl: EnableWindow(Handle, Enabled) - never swallow
  Invalidate;
end;

{ append ups for every key still held (most recent press first), disarm }
procedure TComboCapture.FinishRecording;
var
  i: Integer;
begin
  // the loop bound is fixed before the body, so appended ups are not re-visited
  for i := High(FSteps) downto 0 do
    if FSteps[i].IsDown and FHeld[FSteps[i].VK] then
    begin
      FHeld[FSteps[i].VK] := False;
      AppendStep(FSteps[i].VK, FSteps[i].SC, FSteps[i].Ext, False);
    end;
  if FArmed then
  begin
    FArmed := False;
    ImmAssociateContext(Self.Handle, FOldIMC);
  end;
  Invalidate;
end;

procedure TComboCapture.Paint;
var
  txt: string;
  tw, th: Integer;
begin
  Canvas.Pen.Width := 2;
  if not Enabled then
    Canvas.Pen.Color := clBtnFace
  else if FArmed then
    Canvas.Pen.Color := RGB(52, 124, 246)
  else
    Canvas.Pen.Color := clBtnShadow;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(1, 1, Width - 1, Height - 1);
  if Length(FSteps) > 0 then
    txt := ComboSummary(FSteps)
  else if FArmed then
    txt := S(SID_CAP_REC_ARMED)   // how to finish is only visible mid-recording
  else
    txt := S(SID_CAP_REC);
  Canvas.Font := Font;
  if not Enabled then
    Canvas.Font.Color := clBtnShadow
  else if Length(FSteps) = 0 then
    Canvas.Font.Color := clGrayText;
  tw := Canvas.TextWidth(txt);
  th := Canvas.TextHeight(txt);
  Canvas.TextOut((Width - tw) div 2, (Height - th) div 2, txt);
  Canvas.Brush.Style := bsSolid;
end;

procedure TComboCapture.WndProc(var Msg: TMessage);
var
  key, sc: Word;
  ext: Boolean;
begin
  if not FArmed then
  begin
    inherited WndProc(Msg);
    Exit;
  end;
  case Msg.Msg of
    WM_GETDLGCODE:
      begin
        Msg.Result := DLGC_WANTALLKEYS;
        Exit;
      end;
    WM_KEYDOWN, WM_SYSKEYDOWN:
      begin
        key := Word(Msg.WParam);
        if (Msg.LParam and $40000000) <> 0 then   // auto-repeat: ignore
        begin
          Msg.Result := 0;
          Exit;
        end;
        sc := Word((Msg.LParam shr 16) and $FF);
        ext := (Msg.LParam and $01000000) <> 0;
        FHeld[key] := True;
        AppendStep(key, sc, ext, True);
        Msg.Result := 0;
        Exit;
      end;
    WM_KEYUP, WM_SYSKEYUP:
      begin
        key := Word(Msg.WParam);
        if not FHeld[key] then     // held since before arming: not ours
        begin
          Msg.Result := 0;
          Exit;
        end;
        FHeld[key] := False;
        sc := Word((Msg.LParam shr 16) and $FF);
        ext := (Msg.LParam and $01000000) <> 0;
        AppendStep(key, sc, ext, False);
        Msg.Result := 0;
        Exit;
      end;
  end;
  inherited WndProc(Msg);
end;

end.
