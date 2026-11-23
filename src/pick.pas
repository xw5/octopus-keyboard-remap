unit pick;

{ Manual key-picker dialog: the list-based alternative to click-to-capture.
  Needed when the key to record cannot be pressed at all (a broken key as
  the target) - capture reserves no key any more, its control is
  mouse-driven. All controls
  are built in code like the rest of the app.

  Single mode returns one key triple (VK/SC/Ext). Scancodes come from
  MapVirtualKeyW at dialog open (fresh for the current layout); media keys
  keep SC = 0 and inject by VK via the existing InjectKey fallback.

  Combo mode keeps an ordered selection list with up/down/remove buttons.
  "Press together" builds a chord: downs in the chosen order, then ups in
  reverse - exactly the balanced steps FinishRecording produces. "Press in
  order" builds a per-key down+up tap sequence. Both are ordinary
  TComboSteps for rule kind RK_COMBO, so the engine and the config schema
  need no changes. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, Classes, Forms, Controls, StdCtrls, Dialogs,
  keymap, remap, langstrings;

type
  TKeySel = record
    VK, SC: Word;
    Ext: Boolean;
    Cat: Integer;     // catalog category (ignored by step synthesis)
    Name: string;     // display name, resolved at dialog open
  end;

{ ordered selection -> balanced step list for rule kind RK_COMBO }
procedure BuildPickSteps(const keys: array of TKeySel; chord: Boolean;
  out steps: TComboSteps);

function PickKeyDialog(out VK, SC: Word; out Ext: Boolean): Boolean;
function PickComboDialog(out steps: TComboSteps): Boolean;

implementation

const
  KC_ALPHA = 0;   // letters and digits
  KC_FUNC  = 1;   // F1-F24
  KC_MOD   = 2;   // modifiers (L/R variants kept apart, like recording does)
  KC_NAV   = 3;   // navigation / control keys
  KC_NUM   = 4;   // numpad
  KC_MEDIA = 5;   // media / browser keys
  KC_OEM   = 6;   // punctuation (labels follow the user's layout)

type
  TPickKeyForm = class(TForm)
  public
    constructor Create(AOwner: TComponent); override;
  private
    FSingle: Boolean;          // single-key pick vs ordered combo pick
    FCatalog: array of TKeySel;
    FShown: array of Integer;  // catalog index per lbKeys row
    FSel: array of TKeySel;    // combo mode: the ordered selection
    FPicked: TKeySel;          // single mode: the picked key

    cbCat: TComboBox;
    lbKeys: TListBox;
    lblSel: TLabel;
    lbSel: TListBox;
    rbChord, rbSeq: TRadioButton;
    lblPrev: TLabel;
    btnAdd, btnUp, btnDown, btnDel, btnClr: TButton;
    btnOk, btnCancel: TButton;
    procedure BuildCatalog;
    procedure BuildUI;
    procedure SetMode(single: Boolean);
    procedure RefillKeys(Sender: TObject);
    procedure KeysDblClick(Sender: TObject);
    procedure AddClicked(Sender: TObject);
    procedure UpClicked(Sender: TObject);
    procedure DownClicked(Sender: TObject);
    procedure DelClicked(Sender: TObject);
    procedure ClrClicked(Sender: TObject);
    procedure SelClicked(Sender: TObject);
    procedure ModeChanged(Sender: TObject);
    procedure OkClicked(Sender: TObject);
    procedure RenumberSel;
    procedure UpdateSelButtons;
    procedure UpdatePreview;
    function ShownKey(out sel: TKeySel): Boolean;
  end;

{ ---------- step synthesis ---------- }

procedure BuildPickSteps(const keys: array of TKeySel; chord: Boolean;
  out steps: TComboSteps);

  procedure Push(const sel: TKeySel; isDown: Boolean);
  var
    n: Integer;
  begin
    n := Length(steps);
    SetLength(steps, n + 1);
    steps[n].VK := sel.VK;
    steps[n].SC := sel.SC;
    steps[n].Ext := sel.Ext;
    steps[n].IsDown := isDown;
  end;

var
  i, j: Integer;
  dup: Boolean;
begin
  steps := nil;
  if chord then
  begin
    // downs in selection order; a key held twice is meaningless, drop repeats
    for i := 0 to High(keys) do
    begin
      dup := False;
      for j := 0 to i - 1 do
        if (keys[j].VK = keys[i].VK) and (keys[j].Ext = keys[i].Ext) then
        begin
          dup := True;
          Break;
        end;
      if not dup then
        Push(keys[i], True);
    end;
    // ups in reverse press order, mirroring FinishRecording
    for i := High(keys) downto 0 do
    begin
      dup := False;
      for j := 0 to i - 1 do
        if (keys[j].VK = keys[i].VK) and (keys[j].Ext = keys[i].Ext) then
        begin
          dup := True;
          Break;
        end;
      if not dup then
        Push(keys[i], False);
    end;
  end
  else
    for i := 0 to High(keys) do
    begin
      Push(keys[i], True);
      Push(keys[i], False);
    end;
end;

{ ---------- catalog ---------- }

procedure TPickKeyForm.BuildCatalog;

  procedure Add(VK: Word; Ext: Boolean; Cat: Integer);
  var
    n: Integer;
    e: TKeySel;
  begin
    e.VK := VK;
    e.SC := Word(MapVirtualKeyW(VK, MAPVK_VK_TO_VSC));
    e.Ext := Ext;
    e.Cat := Cat;
    e.Name := KeyNameOf(VK, e.SC, Ext);
    n := Length(FCatalog);
    SetLength(FCatalog, n + 1);
    FCatalog[n] := e;
  end;

var
  vk: Integer;
begin
  FCatalog := nil;
  for vk := Ord('A') to Ord('Z') do
    Add(Word(vk), False, KC_ALPHA);
  for vk := Ord('0') to Ord('9') do
    Add(Word(vk), False, KC_ALPHA);
  for vk := VK_F1 to VK_F24 do
    Add(Word(vk), False, KC_FUNC);
  // extended flags must match the real hardware events: source matching
  // keys on (VK, Ext) and injection sends the extended-key prefix
  Add(VK_LSHIFT, False, KC_MOD);
  Add(VK_RSHIFT, False, KC_MOD);
  Add(VK_LCONTROL, False, KC_MOD);
  Add(VK_RCONTROL, True, KC_MOD);
  Add(VK_LMENU, False, KC_MOD);
  Add(VK_RMENU, True, KC_MOD);
  Add(VK_LWIN, True, KC_MOD);
  Add(VK_RWIN, True, KC_MOD);
  Add(VK_ESCAPE, False, KC_NAV);
  Add(VK_TAB, False, KC_NAV);
  Add(VK_SPACE, False, KC_NAV);
  Add(VK_RETURN, False, KC_NAV);
  Add(VK_BACK, False, KC_NAV);
  Add(VK_CAPITAL, False, KC_NAV);
  Add(VK_INSERT, True, KC_NAV);
  Add(VK_DELETE, True, KC_NAV);
  Add(VK_HOME, True, KC_NAV);
  Add(VK_END, True, KC_NAV);
  Add(VK_PRIOR, True, KC_NAV);    // PgUp
  Add(VK_NEXT, True, KC_NAV);     // PgDn
  Add(VK_LEFT, True, KC_NAV);
  Add(VK_UP, True, KC_NAV);
  Add(VK_RIGHT, True, KC_NAV);
  Add(VK_DOWN, True, KC_NAV);
  Add(VK_SNAPSHOT, True, KC_NAV); // PrtSc
  Add(VK_SCROLL, False, KC_NAV);
  Add(VK_PAUSE, False, KC_NAV);
  Add(VK_APPS, True, KC_NAV);     // menu key
  Add(VK_NUMLOCK, False, KC_NUM);
  for vk := VK_NUMPAD0 to VK_NUMPAD9 do
    Add(Word(vk), False, KC_NUM);
  Add(VK_MULTIPLY, False, KC_NUM);
  Add(VK_ADD, False, KC_NUM);
  Add(VK_SUBTRACT, False, KC_NUM);
  Add(VK_DECIMAL, False, KC_NUM);
  Add(VK_DIVIDE, True, KC_NUM);
  Add(VK_RETURN, True, KC_NUM);   // Num Enter, told apart by Ext
  Add(VKR_MEDIA_NEXT, False, KC_MEDIA);
  Add(VKR_MEDIA_PREV, False, KC_MEDIA);
  Add(VKR_MEDIA_STOP, False, KC_MEDIA);
  Add(VKR_MEDIA_PLAYPAUSE, False, KC_MEDIA);
  Add(VKR_VOLUME_MUTE, False, KC_MEDIA);
  Add(VKR_VOLUME_DOWN, False, KC_MEDIA);
  Add(VKR_VOLUME_UP, False, KC_MEDIA);
  Add(VKR_BROWSER_BACK, False, KC_MEDIA);
  Add(VKR_BROWSER_FORWARD, False, KC_MEDIA);
  Add(VK_OEM_1, False, KC_OEM);   // ;:
  Add(VK_OEM_PLUS, False, KC_OEM);
  Add(VK_OEM_COMMA, False, KC_OEM);
  Add(VK_OEM_MINUS, False, KC_OEM);
  Add(VK_OEM_PERIOD, False, KC_OEM);
  Add(VK_OEM_2, False, KC_OEM);   // /?
  Add(VK_OEM_3, False, KC_OEM);   // `~
  Add(VK_OEM_4, False, KC_OEM);   // [{
  Add(VK_OEM_5, False, KC_OEM);   // \|
  Add(VK_OEM_6, False, KC_OEM);   // ]}
  Add(VK_OEM_7, False, KC_OEM);   // '"
end;

{ ---------- form ---------- }

constructor TPickKeyForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildCatalog;
  BuildUI;
  RefillKeys(nil);
  SetMode(True);
end;

procedure TPickKeyForm.BuildUI;
begin
  Position := poScreenCenter;
  BorderStyle := bsDialog;

  cbCat := TComboBox.Create(Self);
  cbCat.Parent := Self;
  cbCat.Left := 12;
  cbCat.Top := 12;
  cbCat.Width := 180;
  cbCat.Style := csDropDownList;
  cbCat.Items.Add(S(SID_PICK_CAT_ALL));
  cbCat.Items.Add(S(SID_PICK_CAT_ALPHA));
  cbCat.Items.Add(S(SID_PICK_CAT_FUNC));
  cbCat.Items.Add(S(SID_PICK_CAT_MOD));
  cbCat.Items.Add(S(SID_PICK_CAT_NAV));
  cbCat.Items.Add(S(SID_PICK_CAT_NUM));
  cbCat.Items.Add(S(SID_PICK_CAT_MEDIA));
  cbCat.Items.Add(S(SID_PICK_CAT_OEM));
  cbCat.ItemIndex := 0;
  cbCat.OnChange := @RefillKeys;

  lbKeys := TListBox.Create(Self);
  lbKeys.Parent := Self;
  lbKeys.Left := 12;
  lbKeys.Top := 44;
  lbKeys.Width := 180;
  lbKeys.Height := 260;
  lbKeys.OnDblClick := @KeysDblClick;

  lblSel := TLabel.Create(Self);
  lblSel.Parent := Self;
  lblSel.Left := 204;
  lblSel.Top := 14;
  lblSel.Caption := S(SID_PICK_SELECTED);

  lbSel := TListBox.Create(Self);
  lbSel.Parent := Self;
  lbSel.Left := 204;
  lbSel.Top := 34;
  lbSel.Width := 208;
  lbSel.Height := 176;
  lbSel.OnClick := @SelClicked;
  lbSel.OnDblClick := @DelClicked;

  btnUp := TButton.Create(Self);
  btnUp.Parent := Self;
  btnUp.SetBounds(204, 216, 48, 26);
  btnUp.Caption := S(SID_PICK_UP);
  btnUp.OnClick := @UpClicked;

  btnDown := TButton.Create(Self);
  btnDown.Parent := Self;
  btnDown.SetBounds(256, 216, 48, 26);
  btnDown.Caption := S(SID_PICK_DOWN);
  btnDown.OnClick := @DownClicked;

  btnDel := TButton.Create(Self);
  btnDel.Parent := Self;
  btnDel.SetBounds(308, 216, 48, 26);
  btnDel.Caption := S(SID_PICK_REMOVE);
  btnDel.OnClick := @DelClicked;

  btnClr := TButton.Create(Self);
  btnClr.Parent := Self;
  btnClr.SetBounds(360, 216, 52, 26);
  btnClr.Caption := S(SID_REC_CLEAR);
  btnClr.OnClick := @ClrClicked;

  rbChord := TRadioButton.Create(Self);
  rbChord.Parent := Self;
  rbChord.SetBounds(204, 252, 208, 22);
  rbChord.Caption := S(SID_PICK_MODE_CHORD);
  rbChord.Checked := True;

  rbSeq := TRadioButton.Create(Self);
  rbSeq.Parent := Self;
  rbSeq.SetBounds(204, 276, 208, 22);
  rbSeq.Caption := S(SID_PICK_MODE_SEQ);
  rbSeq.OnChange := @ModeChanged;
  rbChord.OnChange := @ModeChanged;

  btnAdd := TButton.Create(Self);
  btnAdd.Parent := Self;
  btnAdd.SetBounds(12, 272, 180, 28);
  btnAdd.Caption := S(SID_PICK_ADD);
  btnAdd.OnClick := @AddClicked;

  lblPrev := TLabel.Create(Self);
  lblPrev.Parent := Self;
  lblPrev.Left := 12;
  lblPrev.Top := 310;
  lblPrev.Width := 400;

  btnOk := TButton.Create(Self);
  btnOk.Parent := Self;
  btnOk.SetBounds(204, 340, 96, 28);
  btnOk.Caption := S(SID_OK);
  btnOk.OnClick := @OkClicked;
  btnOk.Default := True;

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := Self;
  btnCancel.SetBounds(316, 340, 96, 28);
  btnCancel.Cancel := True;
  btnCancel.Caption := S(SID_CANCEL);
  btnCancel.ModalResult := mrCancel;
end;

{ single mode: a compact one-list dialog; combo mode: add the ordered
  selection column, the mode radios and the live preview }
procedure TPickKeyForm.SetMode(single: Boolean);
begin
  FSingle := single;
  if single then
    Caption := S(SID_PICK_TITLE_SINGLE)
  else
    Caption := S(SID_PICK_TITLE_COMBO);
  lblSel.Visible := not single;
  lbSel.Visible := not single;
  btnUp.Visible := not single;
  btnDown.Visible := not single;
  btnDel.Visible := not single;
  btnClr.Visible := not single;
  rbChord.Visible := not single;
  rbSeq.Visible := not single;
  btnAdd.Visible := not single;
  lblPrev.Visible := not single;
  if single then
  begin
    ClientWidth := 224;
    ClientHeight := 356;
    lbKeys.Height := 260;
    btnOk.SetBounds(12, 316, 96, 28);
    btnCancel.SetBounds(116, 316, 96, 28);
  end
  else
  begin
    ClientWidth := 424;
    ClientHeight := 380;
    lbKeys.Height := 220;
    btnOk.SetBounds(204, 340, 96, 28);
    btnCancel.SetBounds(316, 340, 96, 28);
  end;
end;

procedure TPickKeyForm.RefillKeys(Sender: TObject);
var
  cat, i: Integer;
begin
  cat := cbCat.ItemIndex - 1;   // row 0 = "All" -> cat < 0 shows everything
  SetLength(FShown, 0);
  lbKeys.Items.BeginUpdate;
  try
    lbKeys.Items.Clear;
    for i := 0 to High(FCatalog) do
      if (cat < 0) or (FCatalog[i].Cat = cat) then
      begin
        lbKeys.Items.Add(FCatalog[i].Name);
        SetLength(FShown, Length(FShown) + 1);
        FShown[High(FShown)] := i;
      end;
  finally
    lbKeys.Items.EndUpdate;
  end;
end;

{ lbKeys selection -> key triple; FShown translates the filtered row }
function TPickKeyForm.ShownKey(out sel: TKeySel): Boolean;
var
  i: Integer;
begin
  i := lbKeys.ItemIndex;
  if (i >= 0) and (i <= High(FShown)) then
  begin
    sel := FCatalog[FShown[i]];
    Result := True;
  end
  else
    Result := False;
end;

procedure TPickKeyForm.KeysDblClick(Sender: TObject);
var
  sel: TKeySel;
begin
  if FSingle then
  begin
    if ShownKey(sel) then
    begin
      FPicked := sel;
      ModalResult := mrOK;
    end;
  end
  else
    AddClicked(Sender);
end;

procedure TPickKeyForm.AddClicked(Sender: TObject);
var
  n: Integer;
  sel: TKeySel;
begin
  if not ShownKey(sel) then
    Exit;
  n := Length(FSel);
  SetLength(FSel, n + 1);
  FSel[n] := sel;
  lbSel.Items.Add(Format('%d. %s', [n + 1, sel.Name]));
  lbSel.ItemIndex := n;
  UpdateSelButtons;
  UpdatePreview;
end;

procedure TPickKeyForm.UpClicked(Sender: TObject);
var
  i: Integer;
  t: TKeySel;
begin
  i := lbSel.ItemIndex;
  if i <= 0 then
    Exit;
  lbSel.Items.Exchange(i, i - 1);
  t := FSel[i];
  FSel[i] := FSel[i - 1];
  FSel[i - 1] := t;
  lbSel.ItemIndex := i - 1;
  RenumberSel;
  UpdatePreview;
end;

procedure TPickKeyForm.DownClicked(Sender: TObject);
var
  i: Integer;
  t: TKeySel;
begin
  i := lbSel.ItemIndex;
  if (i < 0) or (i >= lbSel.Items.Count - 1) then
    Exit;
  lbSel.Items.Exchange(i, i + 1);
  t := FSel[i];
  FSel[i] := FSel[i + 1];
  FSel[i + 1] := t;
  lbSel.ItemIndex := i + 1;
  RenumberSel;
  UpdatePreview;
end;

procedure TPickKeyForm.DelClicked(Sender: TObject);
var
  i, j: Integer;
begin
  i := lbSel.ItemIndex;
  if i < 0 then
    Exit;
  lbSel.Items.Delete(i);
  for j := i to High(FSel) - 1 do
    FSel[j] := FSel[j + 1];
  SetLength(FSel, Length(FSel) - 1);
  RenumberSel;
  UpdateSelButtons;
  UpdatePreview;
end;

procedure TPickKeyForm.ClrClicked(Sender: TObject);
begin
  lbSel.Clear;
  SetLength(FSel, 0);
  UpdateSelButtons;
  UpdatePreview;
end;

procedure TPickKeyForm.SelClicked(Sender: TObject);
begin
  UpdateSelButtons;
end;

procedure TPickKeyForm.ModeChanged(Sender: TObject);
begin
  UpdatePreview;
end;

procedure TPickKeyForm.OkClicked(Sender: TObject);
var
  sel: TKeySel;
begin
  if FSingle then
  begin
    if not ShownKey(sel) then
    begin
      ShowMessage(S(SID_PICK_NONE));
      Exit;
    end;
    FPicked := sel;
  end
  else if Length(FSel) = 0 then
  begin
    ShowMessage(S(SID_PICK_NONE));
    Exit;
  end;
  ModalResult := mrOK;
end;

{ the "1. " prefixes go stale after exchange/delete - rewrite them all }
procedure TPickKeyForm.RenumberSel;
var
  i: Integer;
begin
  for i := 0 to lbSel.Items.Count - 1 do
    lbSel.Items[i] := Format('%d. %s', [i + 1, FSel[i].Name]);
end;

procedure TPickKeyForm.UpdateSelButtons;
var
  i: Integer;
begin
  i := lbSel.ItemIndex;
  btnUp.Enabled := i > 0;
  btnDown.Enabled := (i >= 0) and (i < lbSel.Items.Count - 1);
  btnDel.Enabled := i >= 0;
  btnClr.Enabled := lbSel.Items.Count > 0;
end;

procedure TPickKeyForm.UpdatePreview;
var
  steps: TComboSteps;
begin
  BuildPickSteps(FSel, rbChord.Checked, steps);
  lblPrev.Caption := S(SID_PICK_PREVIEW) + ComboSummary(steps);
end;

{ ---------- dialog entry points ---------- }

function PickKeyDialog(out VK, SC: Word; out Ext: Boolean): Boolean;
var
  dlg: TPickKeyForm;
begin
  dlg := TPickKeyForm.Create(nil);
  try
    dlg.SetMode(True);
    Result := dlg.ShowModal = mrOK;
    if Result then
    begin
      VK := dlg.FPicked.VK;
      SC := dlg.FPicked.SC;
      Ext := dlg.FPicked.Ext;
    end;
  finally
    dlg.Free;
  end;
end;

function PickComboDialog(out steps: TComboSteps): Boolean;
var
  dlg: TPickKeyForm;
begin
  dlg := TPickKeyForm.Create(nil);
  try
    dlg.SetMode(False);
    Result := dlg.ShowModal = mrOK;
    if Result then
      BuildPickSteps(dlg.FSel, dlg.rbChord.Checked, steps);
  finally
    dlg.Free;
  end;
end;

end.
