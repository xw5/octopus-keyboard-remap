unit capture;

{ TKeyCapture: a click-to-arm key capture box. Reads raw WM_KEYDOWN/
  WM_SYSKEYDOWN while armed so the scancode and the extended-key flag
  survive (LCL's OnKeyDown would drop both), and answers WM_GETDLGCODE with
  DLGC_WANTALLKEYS so Tab/Enter/Esc reach us instead of the dialog manager.
  Esc cancels the capture; key-up events always pass through untouched -
  swallowing one could stick a modifier. A disabled box is drawn washed-out
  so "disabled and inert" is visible, not a surprise (the edit dialog
  disables this box when the rule blocks the key instead of mapping it).

  TComboCapture: a click-to-arm recorder for key sequences. While armed it
  reads raw WM_KEYDOWN/UP and WM_SYSKEYDOWN/UP and records every press and
  release in real order, so plain chords (Ctrl+Shift+Esc) and macros
  (Ctrl+C, Ctrl+V) both come out as faithful step lists. Esc or losing
  focus finishes the burst; keys still held get their up events appended
  (reverse press order) so replay never sticks them. Key-ups for keys that
  were never seen down here (held since before arming) are swallowed
  unrecorded to keep the steps balanced. Clear the steps to start over. }

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
    function GetKey(out VK, SC: Word; out Ext: Boolean): Boolean;
    property Armed: Boolean read FArmed;
    property HasKey: Boolean read FHas;
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
    constructor Create(AOwner: TComponent); override;
    procedure ClearSteps;
    procedure SetSteps(const ASteps: TComboSteps);
    procedure GetSteps(out ASteps: TComboSteps);
    property Armed: Boolean read FArmed;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

{ ---------- TKeyCapture ---------- }


constructor TKeyCapture.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 240;
  Height := 40;
  TabStop := True;
end;

procedure TKeyCapture.Clear;
begin
  FHas := False;
  Invalidate;
end;

procedure TKeyCapture.SetKey(VK, SC: Word; Ext: Boolean);
begin
  FVK := VK;
  FSC := SC;
  FExt := Ext;
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

procedure TKeyCapture.Disarm;
begin
  if FArmed then
  begin
    FArmed := False;
    ImmAssociateContext(Self.Handle, FOldIMC);
  end;
end;

procedure TKeyCapture.Click;
begin
  inherited Click;
  SetFocus;
  if not FArmed then
    FOldIMC := ImmAssociateContext(Self.Handle, 0);
  FArmed := True;
  Invalidate;
end;

procedure TKeyCapture.DoExit;
begin
  inherited DoExit;
  Disarm;
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
    txt := KeyNameOf(FVK, FSC, FExt)
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
        if key = VK_ESCAPE then
        begin
          Disarm;            // cancel capture, keep the previous value
          Invalidate;
          Msg.Result := 0;
          Exit;
        end;
        sc := Word((Msg.LParam shr 16) and $FF);
        ext := (Msg.LParam and $01000000) <> 0;
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
  if not FArmed then
    FOldIMC := ImmAssociateContext(Self.Handle, 0);
  FArmed := True;   // re-arming appends to the recorded steps
  Invalidate;
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
        if key = VK_ESCAPE then
        begin
          FinishRecording;   // Esc ends the burst and commits the steps
          Msg.Result := 0;
          Exit;
        end;
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
