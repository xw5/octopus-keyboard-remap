unit main;

{ Settings window, tray icon and the edit-rule dialog. All controls are
  built in code (no .lfm), following the OctopusKey house patterns:
  Tag-carried string ids for language switching, a Building guard against
  change feedback loops, live apply + persist on every change. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, Graphics, Menus, Registry, LCLType, Buttons,
  config, langstrings, keymap, remap, inject, hooks, capture, pick;

function ShellExecuteW(hWnd: HWND; Operation, FileName, Parameters,
  Directory: PWideChar; ShowCmd: Integer): HINST; stdcall;
  external 'shell32.dll';

type
  TEditRuleForm = class(TForm)
  public
    constructor Create(AOwner: TComponent); override;
    function Execute(var rule: TRule; editingIdx: Integer): Boolean;
  private
    capSrc, capDst: TKeyCapture;
    capRec: TComboCapture;
    cbCombo, cbDisable: TCheckBox;
    btnOk, btnCancel: TButton;
    // speed buttons: no focus steal, so clicking them never ends a burst
    btnDelLast, btnClear: TSpeedButton;
    btnPickSrc, btnPickDst, btnPickRec: TButton;
    FEditingIdx: Integer;
    FRule: TRule;
    procedure BuildUI;
    procedure ComboChanged(Sender: TObject);
    procedure DisableChanged(Sender: TObject);
    procedure ClearClicked(Sender: TObject);
    procedure DelLastClicked(Sender: TObject);
    procedure PickSrcClicked(Sender: TObject);
    procedure PickDstClicked(Sender: TObject);
    procedure PickRecClicked(Sender: TObject);
    procedure OkClicked(Sender: TObject);
  end;

  TSettingsForm = class(TForm)
  public
    constructor Create(AOwner: TComponent); override;
    procedure PrepareTray;
    procedure ApplyLanguage;
  private
    Tray: TTrayIcon;
    TrayMenu: TPopupMenu;
    miSettings, miToggle, miAdmin, miExit: TMenuItem;
    pnlTop: TPanel;
    cbEnabled: TCheckBox;
    cbLang: TComboBox;
    Grid: TStringGrid;
    pnlBtns: TPanel;
    btnAdd, btnEdit, btnDelete: TButton;
    cbAutostart: TCheckBox;
    pnlBottom: TPanel;
    lblStatus, lblHint: TLabel;
    btnClose: TButton;
    Building: Boolean;
    procedure BuildUI;
    procedure LoadUIFromCfg;
    procedure ReadControls;
    procedure ApplyAll;
    procedure CfgChanged(Sender: TObject);
    procedure LangChanged(Sender: TObject);
    procedure ReloadGrid;
    procedure GridResize(Sender: TObject);
    procedure AddClicked(Sender: TObject);
    procedure EditClicked(Sender: TObject);
    procedure DeleteClicked(Sender: TObject);
    procedure GridClicked(Sender: TObject);
    procedure GridDblClick(Sender: TObject);
    procedure CloseClicked(Sender: TObject);
    procedure DoFormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure TrayClicked(Sender: TObject);
    procedure TrayToggleClicked(Sender: TObject);
    procedure TrayAdminClicked(Sender: TObject);
    procedure TrayExitClicked(Sender: TObject);
    procedure UpdateStatus;
    procedure ApplyAutostart;
    procedure SetEngineEnabled(v: Boolean);
  end;

var
  SettingsForm: TSettingsForm;

implementation

const
  COL_SRC = 0;
  COL_DST = 1;
  COL_ON  = 2;

  COL_SRC_W    = 170;   // fixed: key names are short
  COL_ON_W     = 60;    // fixed: a checkmark column
  COL_DST_MIN  = 210;   // target column takes the remaining grid width

{ ---------- edit-rule dialog ---------- }

constructor TEditRuleForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  ClientWidth := 464;
  ClientHeight := 232;
  BuildUI;
end;

procedure TEditRuleForm.BuildUI;
var
  lblS, lblD: TLabel;
begin
  lblS := TLabel.Create(Self);
  lblS.Parent := Self;
  lblS.Left := 20;
  lblS.Top := 28;
  lblS.Caption := S(SID_ED_SRC);

  capSrc := TKeyCapture.Create(Self);
  capSrc.Parent := Self;
  capSrc.Left := 110;
  capSrc.Top := 16;
  capSrc.Width := 250;
  capSrc.Height := 40;

  btnPickSrc := TButton.Create(Self);
  btnPickSrc.Parent := Self;
  btnPickSrc.SetBounds(370, 16, 80, 40);
  btnPickSrc.Caption := S(SID_BTN_PICK);
  btnPickSrc.OnClick := @PickSrcClicked;

  lblD := TLabel.Create(Self);
  lblD.Parent := Self;
  lblD.Left := 20;
  lblD.Top := 86;
  lblD.Caption := S(SID_ED_DST);

  capDst := TKeyCapture.Create(Self);
  capDst.Parent := Self;
  capDst.Left := 110;
  capDst.Top := 74;
  capDst.Width := 250;
  capDst.Height := 40;
  capDst.AllowMods := False;   // target is a plain key: record on first press

  capRec := TComboCapture.Create(Self);
  capRec.Parent := Self;
  capRec.Left := 110;
  capRec.Top := 74;
  capRec.Width := 250;
  capRec.Height := 40;
  capRec.Visible := False;

  btnPickDst := TButton.Create(Self);
  btnPickDst.Parent := Self;
  btnPickDst.SetBounds(370, 74, 80, 40);
  btnPickDst.Caption := S(SID_BTN_PICK);
  btnPickDst.OnClick := @PickDstClicked;

  btnPickRec := TButton.Create(Self);
  btnPickRec.Parent := Self;
  btnPickRec.SetBounds(370, 74, 80, 40);
  btnPickRec.Caption := S(SID_BTN_PICK);
  btnPickRec.OnClick := @PickRecClicked;
  btnPickRec.Visible := False;

  cbCombo := TCheckBox.Create(Self);
  cbCombo.Parent := Self;
  cbCombo.Left := 110;
  cbCombo.Top := 126;
  cbCombo.Width := 250;
  cbCombo.Caption := S(SID_ED_MULTI);
  cbCombo.OnChange := @ComboChanged;

  cbDisable := TCheckBox.Create(Self);
  cbDisable.Parent := Self;
  cbDisable.Left := 110;
  cbDisable.Top := 152;
  cbDisable.Width := 250;
  cbDisable.Caption := S(SID_DISABLE_THIS);
  cbDisable.OnChange := @DisableChanged;

  { undo/clear only act on the combo recorder, so they sit next to the
    target controls: the row cbDisable uses in single mode is free when
    they are visible (combo mode hides cbDisable) }
  btnDelLast := TSpeedButton.Create(Self);
  btnDelLast.Parent := Self;
  btnDelLast.SetBounds(110, 152, 80, 28);
  btnDelLast.Caption := S(SID_REC_UNDO);
  btnDelLast.OnClick := @DelLastClicked;
  btnDelLast.Visible := False;

  btnClear := TSpeedButton.Create(Self);
  btnClear.Parent := Self;
  btnClear.SetBounds(200, 152, 80, 28);
  btnClear.Caption := S(SID_REC_CLEAR);
  btnClear.OnClick := @ClearClicked;
  btnClear.Visible := False;

  btnOk := TButton.Create(Self);
  btnOk.Parent := Self;
  btnOk.Left := 190;
  btnOk.Top := 188;
  btnOk.Width := 80;
  btnOk.Caption := S(SID_OK);
  btnOk.OnClick := @OkClicked;

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := Self;
  btnCancel.Left := 280;
  btnCancel.Top := 188;
  btnCancel.Width := 80;
  btnCancel.Cancel := True;
  btnCancel.Caption := S(SID_CANCEL);
  btnCancel.ModalResult := mrCancel;
end;

procedure TEditRuleForm.ComboChanged(Sender: TObject);
var
  m: Boolean;
begin
  m := cbCombo.Checked;
  capDst.Visible := not m;
  capRec.Visible := m;
  cbDisable.Visible := not m;   // a combo target cannot "disable" the key
  btnPickDst.Visible := not m;
  btnPickRec.Visible := m;
  btnDelLast.Visible := m;
  btnClear.Visible := m;
end;

procedure TEditRuleForm.DisableChanged(Sender: TObject);
begin
  capDst.Enabled := not cbDisable.Checked;
  btnPickDst.Enabled := not cbDisable.Checked;
  capDst.Invalidate;
end;

procedure TEditRuleForm.ClearClicked(Sender: TObject);
begin
  capRec.ClearSteps;
end;

procedure TEditRuleForm.DelLastClicked(Sender: TObject);
begin
  capRec.DeleteLastKey;   // focus stays in the recorder, the burst continues
end;

{ manual picking: the list-based path for keys that cannot be recorded
  (a broken key, or Esc, which capture uses to finish); results land in
  the same capture boxes, the rest of the flow is untouched. The source
  box allows modifier combos, the target stays a plain key. }
procedure TEditRuleForm.PickSrcClicked(Sender: TObject);
var
  vk, sc: Word;
  ext: Boolean;
  mods: Word;
begin
  if PickKeyDialog(vk, sc, ext, True, mods) then
    capSrc.SetKeyMods(vk, sc, ext, mods);
end;

procedure TEditRuleForm.PickDstClicked(Sender: TObject);
var
  vk, sc: Word;
  ext: Boolean;
  mods: Word;
begin
  if PickKeyDialog(vk, sc, ext, False, mods) then
    capDst.SetKey(vk, sc, ext);
end;

procedure TEditRuleForm.PickRecClicked(Sender: TObject);
var
  steps: TComboSteps;
begin
  if PickComboDialog(steps) then
    capRec.SetSteps(steps);
end;

procedure TEditRuleForm.OkClicked(Sender: TObject);
var
  n: TRule;
  steps: TComboSteps;
  i, downs: Integer;
begin
  if not capSrc.HasKey then
  begin
    ShowMessage(S(SID_MSG_NO_SRC));
    Exit;
  end;
  downs := 0;
  if cbCombo.Checked then
  begin
    capRec.GetSteps(steps);
    for i := 0 to High(steps) do
      if steps[i].IsDown then
        Inc(downs);
    if downs = 0 then
    begin
      ShowMessage(S(SID_MSG_NO_STEPS));
      Exit;
    end;
  end
  else if not cbDisable.Checked and (not capDst.HasKey) then
  begin
    ShowMessage(S(SID_MSG_NO_DST));
    Exit;
  end;
  FillChar(n, SizeOf(n), 0);
  n.Combo := nil;
  n.Enabled := FRule.Enabled;   // toggled in the grid, not here
  n.SrcMouse := 0;
  n.App := FRule.App;
  capSrc.GetKey(n.SrcVK, n.SrcSC, n.SrcExt);
  n.SrcMods := capSrc.GetMods;
  if cbCombo.Checked then
  begin
    n.Kind := RK_COMBO;
    n.Combo := steps;           // recorder hands out a private copy
  end
  else
  begin
    n.Kind := RK_KEY;
    if cbDisable.Checked then
    begin
      n.DstVK := 0;
      n.DstSC := 0;
      n.DstExt := False;
    end
    else
      capDst.GetKey(n.DstVK, n.DstSC, n.DstExt);
  end;
  if RemapSrcTaken(n.SrcVK, n.SrcExt, n.SrcMods, FEditingIdx) then
  begin
    ShowMessage(S(SID_MSG_DUP_SRC));
    Exit;
  end;
  FRule := n;
  ModalResult := mrOK;
end;

function TEditRuleForm.Execute(var rule: TRule; editingIdx: Integer): Boolean;
begin
  FEditingIdx := editingIdx;
  FRule := rule;
  capSrc.Clear;
  capDst.Clear;
  capRec.ClearSteps;
  cbDisable.Checked := False;
  capDst.Enabled := True;
  cbCombo.Checked := rule.Kind = RK_COMBO;
  ComboChanged(nil);   // visibility must match even when Checked was unchanged
  if rule.SrcVK <> 0 then
    capSrc.SetKeyMods(rule.SrcVK, rule.SrcSC, rule.SrcExt, rule.SrcMods);
  if rule.Kind = RK_COMBO then
    capRec.SetSteps(rule.Combo)
  else if (rule.Kind = RK_KEY) and (rule.DstVK = 0) and (editingIdx >= 0) then
  begin
    // a saved disable rule (AddClicked passes a zeroed rule: same signature,
    // but editingIdx = -1 marks it new, so never pre-check there)
    cbDisable.Checked := True;
    capDst.Enabled := False;
  end
  else if (rule.Kind = RK_KEY) and (rule.DstVK <> 0) then
    capDst.SetKey(rule.DstVK, rule.DstSC, rule.DstExt);
  Result := ShowModal = mrOK;
  if Result then
    rule := FRule;
end;

{ ---------- helpers ---------- }

function EditRuleDialog(var rule: TRule; editingIdx: Integer): Boolean;
var
  dlg: TEditRuleForm;
  steps: TComboSteps;
  i: Integer;
begin
  dlg := TEditRuleForm.Create(nil);
  // capture mode: suspend the engine so keys owned by active rules can be
  // recorded by the dialog, and flush any virtual holds first so nothing
  // sticks while the engine is paused
  RemapSetSuspended(True);
  RemapCollectReleases(steps);
  for i := 0 to High(steps) do
    InjectKey(steps[i].VK, steps[i].SC, steps[i].Ext, False);
  RemapResetTransientState;
  try
    Result := dlg.Execute(rule, editingIdx);
  finally
    RemapSetSuspended(False);
    RemapResetTransientState;
    dlg.Free;
  end;
end;

{ ---------- settings form ---------- }

constructor TSettingsForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := 'OctopusKeyRemap';
  Position := poScreenCenter;
  ClientWidth := 480;
  ClientHeight := 400;
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu, biMinimize];
  Building := True;
  BuildUI;
  LoadUIFromCfg;
  OnClose := @DoFormClose;
  Building := False;
  UpdateStatus;
end;

procedure TSettingsForm.BuildUI;
begin
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 34;
  pnlTop.BevelOuter := bvNone;

  cbEnabled := TCheckBox.Create(pnlTop);
  cbEnabled.Parent := pnlTop;
  cbEnabled.Left := 16;
  cbEnabled.Top := 8;
  cbEnabled.Width := 200;
  cbEnabled.OnChange := @CfgChanged;

  cbLang := TComboBox.Create(pnlTop);
  cbLang.Parent := pnlTop;
  cbLang.Style := csDropDownList;
  cbLang.Width := 150;
  cbLang.Height := 24;
  cbLang.Anchors := [akTop, akRight];
  cbLang.Left := pnlTop.Width - 166;
  cbLang.Top := 6;
  cbLang.Items.Add('跟随系统 / System');
  cbLang.Items.Add('中文');
  cbLang.Items.Add('English');
  cbLang.OnChange := @LangChanged;

  pnlBtns := TPanel.Create(Self);
  pnlBtns.Parent := Self;
  pnlBtns.Align := alTop;
  pnlBtns.Height := 36;
  pnlBtns.BevelOuter := bvNone;

  btnAdd := TButton.Create(pnlBtns);
  btnAdd.Parent := pnlBtns;
  btnAdd.Left := 16;
  btnAdd.Top := 5;
  btnAdd.Width := 80;
  btnAdd.OnClick := @AddClicked;

  btnEdit := TButton.Create(pnlBtns);
  btnEdit.Parent := pnlBtns;
  btnEdit.Left := 104;
  btnEdit.Top := 5;
  btnEdit.Width := 80;
  btnEdit.OnClick := @EditClicked;

  btnDelete := TButton.Create(pnlBtns);
  btnDelete.Parent := pnlBtns;
  btnDelete.Left := 192;
  btnDelete.Top := 5;
  btnDelete.Width := 80;
  btnDelete.OnClick := @DeleteClicked;

  cbAutostart := TCheckBox.Create(pnlBtns);
  cbAutostart.Parent := pnlBtns;
  cbAutostart.Width := 200;
  cbAutostart.Anchors := [akTop, akRight];
  cbAutostart.Left := pnlBtns.Width - 216;
  cbAutostart.Top := 8;
  cbAutostart.OnChange := @CfgChanged;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 52;
  pnlBottom.BevelOuter := bvNone;

  lblStatus := TLabel.Create(pnlBottom);
  lblStatus.Parent := pnlBottom;
  lblStatus.Left := 16;
  lblStatus.Top := 6;

  lblHint := TLabel.Create(pnlBottom);
  lblHint.Parent := pnlBottom;
  lblHint.Left := 16;
  lblHint.Top := 28;
  lblHint.Font.Color := clGray;

  btnClose := TButton.Create(pnlBottom);
  btnClose.Parent := pnlBottom;
  btnClose.Width := 90;
  btnClose.Top := 14;
  btnClose.Anchors := [akRight, akBottom];
  btnClose.Left := pnlBottom.Width - 106;
  btnClose.OnClick := @CloseClicked;

  Grid := TStringGrid.Create(Self);
  Grid.Parent := Self;
  Grid.Align := alClient;
  Grid.FixedCols := 0;
  Grid.FixedRows := 1;
  Grid.RowCount := 1;
  Grid.ColCount := 3;
  Grid.DefaultRowHeight := 24;
  Grid.ColWidths[COL_SRC] := COL_SRC_W;
  Grid.ColWidths[COL_DST] := COL_DST_MIN;
  Grid.ColWidths[COL_ON] := COL_ON_W;
  Grid.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine,
    goRowSelect];
  Grid.OnClick := @GridClicked;
  Grid.OnDblClick := @GridDblClick;
  Grid.OnResize := @GridResize;   // stretch the target column to fill
end;

{ keep the columns filling the full grid width: the target column absorbs
  whatever the grid is wider than the fixed source/On columns }
procedure TSettingsForm.GridResize(Sender: TObject);
var
  w: Integer;
begin
  w := Grid.ClientWidth - COL_SRC_W - COL_ON_W;
  if w < COL_DST_MIN then
    w := COL_DST_MIN;
  Grid.ColWidths[COL_DST] := w;
end;

procedure TSettingsForm.LoadUIFromCfg;
begin
  cbEnabled.Checked := Cfg.Enabled;
  cbAutostart.Checked := Cfg.Autostart;
  cbLang.ItemIndex := Cfg.Lang + 1;   // 0=system, 1=zh, 2=en
  ReloadGrid;
end;

procedure TSettingsForm.ReadControls;
begin
  Cfg.Enabled := cbEnabled.Checked;
  Cfg.Autostart := cbAutostart.Checked;
  Cfg.Lang := cbLang.ItemIndex - 1;   // -1=system, 0=zh, 1=en
end;

procedure TSettingsForm.ReloadGrid;
var
  i: Integer;
  r: TRule;
begin
  Grid.RowCount := RemapRuleCount + 1;
  for i := 0 to RemapRuleCount - 1 do
  begin
    r := RemapRuleAt(i);
    Grid.Cells[COL_SRC, i + 1] := ModsPrefix(r.SrcMods) +
      KeyNameOf(r.SrcVK, r.SrcSC, r.SrcExt);
    if r.Kind = RK_KEY then
    begin
      if r.DstVK = 0 then
        Grid.Cells[COL_DST, i + 1] := S(SID_DISABLED)
      else
        Grid.Cells[COL_DST, i + 1] := KeyNameOf(r.DstVK, r.DstSC, r.DstExt);
    end
    else if r.Kind = RK_COMBO then
      Grid.Cells[COL_DST, i + 1] := ComboSummary(r.Combo)
    else
      Grid.Cells[COL_DST, i + 1] := '...';   // text lands with M4
    if r.Enabled then
      Grid.Cells[COL_ON, i + 1] := '√'
    else
      Grid.Cells[COL_ON, i + 1] := '-';
  end;
end;

procedure TSettingsForm.SetEngineEnabled(v: Boolean);
var
  was: Boolean;
  steps: TComboSteps;
  i: Integer;
begin
  was := RemapEnabled;
  RemapSetEnabled(v);
  if was and not v then
  begin
    // release keys the engine still holds, then drop stale tracking
    RemapCollectReleases(steps);
    for i := 0 to High(steps) do
      InjectKey(steps[i].VK, steps[i].SC, steps[i].Ext, False);
    RemapResetTransientState;
  end
  else if v then
    RemapResetTransientState;
end;

procedure TSettingsForm.ApplyAll;
begin
  SetEngineEnabled(Cfg.Enabled);
  ApplyAutostart;
  SaveConfig;
  UpdateStatus;
end;

procedure TSettingsForm.CfgChanged(Sender: TObject);
begin
  if Building then
    Exit;
  ReadControls;
  ApplyAll;
end;

procedure TSettingsForm.LangChanged(Sender: TObject);
begin
  if Building then
    Exit;
  Cfg.Lang := cbLang.ItemIndex - 1;
  ApplyLanguage;
  SaveConfig;
end;

procedure TSettingsForm.GridClicked(Sender: TObject);
var
  pt: TPoint;
  gc: TGridCoord;
  idx: Integer;
  r: TRule;
begin
  if Building then
    Exit;
  pt := Grid.ScreenToClient(Mouse.CursorPos);
  gc := Grid.MouseCoord(pt.X, pt.Y);
  if (gc.Y > 0) and (gc.X = COL_ON) then
  begin
    idx := gc.Y - 1;
    if (idx >= 0) and (idx < RemapRuleCount) then
    begin
      r := RemapRuleAt(idx);
      r.Enabled := not r.Enabled;
      RemapSetRule(idx, r);
      ReloadGrid;
      SaveConfig;
    end;
  end;
end;

procedure TSettingsForm.GridDblClick(Sender: TObject);
begin
  EditClicked(Sender);
end;

procedure TSettingsForm.AddClicked(Sender: TObject);
var
  r: TRule;
begin
  FillChar(r, SizeOf(r), 0);
  r.Combo := nil;
  r.Enabled := True;
  r.Kind := RK_KEY;
  if not EditRuleDialog(r, -1) then
    Exit;
  RemapAddRule(r);
  ReloadGrid;
  SaveConfig;
end;

procedure TSettingsForm.EditClicked(Sender: TObject);
var
  idx: Integer;
  r: TRule;
begin
  idx := Grid.Row - 1;
  if (idx < 0) or (idx >= RemapRuleCount) then
    Exit;
  r := RemapRuleAt(idx);
  if not EditRuleDialog(r, idx) then
    Exit;
  RemapSetRule(idx, r);
  ReloadGrid;
  SaveConfig;
end;

procedure TSettingsForm.DeleteClicked(Sender: TObject);
var
  idx: Integer;
begin
  idx := Grid.Row - 1;
  if (idx < 0) or (idx >= RemapRuleCount) then
    Exit;
  if Application.MessageBox(PChar(S(SID_MSG_DELETE_Q)),
    PChar(S(SID_CONFIRM)), MB_ICONQUESTION or MB_YESNO) <> IDYES then
    Exit;
  RemapDeleteRule(idx);
  ReloadGrid;
  SaveConfig;
end;

procedure TSettingsForm.CloseClicked(Sender: TObject);
begin
  Close;
end;

procedure TSettingsForm.DoFormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  CloseAction := caHide;   // closing the window keeps the tray running
end;

{ ---------- tray ---------- }

procedure TSettingsForm.PrepareTray;
var
  bmp: TBitmap;
begin
  TrayMenu := TPopupMenu.Create(Self);
  miSettings := TMenuItem.Create(TrayMenu);
  miSettings.OnClick := @TrayClicked;
  TrayMenu.Items.Add(miSettings);
  miToggle := TMenuItem.Create(TrayMenu);
  miToggle.OnClick := @TrayToggleClicked;
  TrayMenu.Items.Add(miToggle);
  miAdmin := TMenuItem.Create(TrayMenu);
  miAdmin.OnClick := @TrayAdminClicked;
  TrayMenu.Items.Add(miAdmin);
  TrayMenu.Items.AddSeparator;
  miExit := TMenuItem.Create(TrayMenu);
  miExit.OnClick := @TrayExitClicked;
  TrayMenu.Items.Add(miExit);

  Tray := TTrayIcon.Create(Self);
  Tray.PopUpMenu := TrayMenu;
  Tray.OnClick := @TrayClicked;
  Tray.Hint := 'OctopusKeyRemap';
  // embedded exe icon (res/octopusremap.ico, resource #1); drawn tile as fallback
  bmp := nil;
  try
    try
      Tray.Icon.LoadFromResourceID(HInstance, 1);
    except
      bmp := TBitmap.Create;
      bmp.SetSize(32, 32);
      bmp.Canvas.Brush.Color := RGB(26, 26, 34);
      bmp.Canvas.FillRect(Rect(0, 0, 32, 32));
      bmp.Canvas.Brush.Color := RGB(232, 116, 59);
      bmp.Canvas.RoundRect(4, 4, 28, 28, 10, 10);
      bmp.Canvas.Font.Name := 'Segoe UI';
      bmp.Canvas.Font.Style := [fsBold];
      bmp.Canvas.Font.Size := 14;
      bmp.Canvas.Font.Color := clWhite;
      bmp.Canvas.TextOut(9, 6, 'R');
      Tray.Icon.Assign(bmp);
    end;
  finally
    bmp.Free;
  end;
  Icon.Assign(Tray.Icon);   // settings window title bar / taskbar
  Tray.Visible := True;
  ApplyLanguage;
end;

procedure TSettingsForm.TrayClicked(Sender: TObject);
begin
  Show;
  SetForegroundWindow(Handle);
end;

procedure TSettingsForm.TrayToggleClicked(Sender: TObject);
begin
  Cfg.Enabled := not Cfg.Enabled;
  cbEnabled.Checked := Cfg.Enabled;   // fires OnChange -> CfgChanged
end;

procedure TSettingsForm.TrayAdminClicked(Sender: TObject);
var
  wexe: UnicodeString;
begin
  wexe := UTF8Decode(ParamStr(0));
  ShellExecuteW(0, 'runas', PWideChar(wexe), nil, nil, SW_SHOWNORMAL);
  SaveConfig;
  Application.Terminate;   // hand over to the elevated instance
end;

procedure TSettingsForm.TrayExitClicked(Sender: TObject);
begin
  SaveConfig;
  Application.Terminate;
end;

{ ---------- language / status / autostart ---------- }

procedure TSettingsForm.ApplyLanguage;
begin
  Caption := S(SID_TITLE);
  cbEnabled.Caption := S(SID_ENABLE_REMAP);
  Grid.Cells[COL_SRC, 0] := S(SID_COL_SRC);
  Grid.Cells[COL_DST, 0] := S(SID_COL_DST);
  Grid.Cells[COL_ON, 0] := S(SID_COL_ON);
  btnAdd.Caption := S(SID_ADD);
  btnEdit.Caption := S(SID_EDIT);
  btnDelete.Caption := S(SID_DELETE);
  cbAutostart.Caption := S(SID_AUTOSTART);
  lblHint.Caption := S(SID_ADMIN_HINT);
  btnClose.Caption := S(SID_CLOSE);
  miSettings.Caption := S(SID_TRAY_SETTINGS);
  miAdmin.Caption := S(SID_TRAY_ADMIN);
  if miExit <> nil then
    miExit.Caption := S(SID_TRAY_EXIT);
  UpdateStatus;
end;

procedure TSettingsForm.UpdateStatus;
begin
  // tray menu items only exist after PrepareTray; the constructor calls this
  if Cfg.Enabled then
  begin
    if lblStatus <> nil then
    begin
      lblStatus.Caption := S(SID_STATUS_ON);
      lblStatus.Font.Color := clGreen;
    end;
    if miToggle <> nil then
      miToggle.Caption := S(SID_TRAY_ON);
  end
  else
  begin
    if lblStatus <> nil then
    begin
      lblStatus.Caption := S(SID_STATUS_OFF);
      lblStatus.Font.Color := clGray;
    end;
    if miToggle <> nil then
      miToggle.Caption := S(SID_TRAY_OFF);
  end;
end;

procedure TSettingsForm.ApplyAutostart;
var
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    if reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', False) then
    begin
      if Cfg.Autostart then
        reg.WriteString('OctopusKeyRemap', '"' + ParamStr(0) + '"')
      else if reg.ValueExists('OctopusKeyRemap') then
        reg.DeleteValue('OctopusKeyRemap');
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

end.
