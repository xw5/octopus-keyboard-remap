unit langstrings;

{ Bilingual UI strings, compiled in (no external language files), following
  the OctopusKey scheme: SID_* constants, ZH/EN tables, S(id) lookup.
  New strings go at the end of the table with the next free id. }

{$mode objfpc}{$H+}

interface

const
  SID_TITLE          = 1;
  SID_ENABLE_REMAP   = 2;
  SID_COL_SRC        = 3;
  SID_COL_DST        = 4;
  SID_COL_ON         = 5;
  SID_ADD            = 6;
  SID_EDIT           = 7;
  SID_DELETE         = 8;
  SID_AUTOSTART      = 9;
  SID_LANGUAGE       = 10;
  SID_ADMIN_HINT     = 11;
  SID_TRAY_SETTINGS  = 12;
  SID_TRAY_ON        = 13;   // caption while running: action = disable
  SID_TRAY_OFF       = 14;   // caption while stopped: action = enable
  SID_TRAY_ADMIN     = 15;
  SID_TRAY_EXIT      = 16;
  SID_CLOSE          = 17;
  SID_STATUS_ON      = 18;
  SID_STATUS_OFF     = 19;
  SID_DISABLED       = 20;   // grid text for a key with no target
  SID_CAP_HINT       = 21;   // capture box placeholder
  SID_DISABLE_THIS   = 22;   // edit dialog checkbox
  SID_MSG_DUP_SRC    = 23;
  SID_MSG_NO_SRC     = 24;
  SID_MSG_NO_DST     = 25;
  SID_MSG_DELETE_Q   = 26;
  SID_MSG_SINGLE     = 27;
  SID_CONFIRM        = 28;
  SID_OK             = 29;
  SID_CANCEL         = 30;
  SID_ED_SRC         = 31;
  SID_ED_DST         = 32;
  SID_ED_MULTI       = 33;  // edit dialog: multi-key target mode checkbox
  SID_CAP_REC        = 34;  // combo recorder placeholder
  SID_REC_CLEAR      = 35;  // combo recorder clear button
  SID_MSG_NO_STEPS   = 36;
  SID_BTN_PICK       = 37;  // "pick from list" button beside each capture box
  SID_PICK_TITLE_SINGLE = 38;
  SID_PICK_TITLE_COMBO  = 39;
  SID_PICK_CAT_ALL   = 40;  // category filter: show everything
  SID_PICK_CAT_ALPHA = 41;
  SID_PICK_CAT_FUNC  = 42;
  SID_PICK_CAT_MOD   = 43;
  SID_PICK_CAT_NAV   = 44;
  SID_PICK_CAT_NUM   = 45;
  SID_PICK_CAT_MEDIA = 46;
  SID_PICK_CAT_OEM   = 47;
  SID_PICK_ADD       = 48;
  SID_PICK_UP        = 49;
  SID_PICK_DOWN      = 50;
  SID_PICK_REMOVE    = 51;
  SID_PICK_SELECTED  = 52;  // ordered selection list caption
  SID_PICK_MODE_CHORD = 53;
  SID_PICK_MODE_SEQ   = 54;
  SID_PICK_PREVIEW   = 55;  // live ComboSummary prefix
  SID_PICK_NONE      = 56;  // OK with nothing selected
  SID_CAP_REC_ARMED  = 57;  // combo recorder placeholder while armed
  SID_REC_UNDO       = 58;  // combo recorder "undo last key" button
  SID_PICK_MODS      = 59;  // pick dialog: modifier checkbox group caption

function S(id: Integer): string;

implementation

uses
  SysUtils, config;

function GetUserDefaultUILanguage: Word; stdcall;
  external 'kernel32.dll';

var
  SysLang: Integer = -2;   // resolved once: 0 = zh, 1 = en

// resolve "follow system" to zh or en
function EffectiveLang: Integer;
var
  prim: Word;
begin
  if Cfg.Lang = LANG_SYSTEM then
  begin
    if SysLang < 0 then
    begin
      prim := GetUserDefaultUILanguage and $03FF;
      if prim = $04 then      // Chinese
        SysLang := LANG_ZH
      else
        SysLang := LANG_EN;   // everything else falls back to English
    end;
    Result := SysLang;
  end
  else
    Result := Cfg.Lang;
end;

const
  LAST_SID = 59;

  ZH: array[1..LAST_SID] of string = (
    'OctopusKeyRemap 设置',                        // 1
    '启用改键',                                    // 2
    '源键',                                        // 3
    '目标键',                                      // 4
    '启用',                                        // 5
    '添加',                                        // 6
    '编辑',                                        // 7
    '删除',                                        // 8
    '开机自动启动',                                // 9
    '语言 Language',                               // 10
    '管理员权限的窗口需以管理员身份运行本程序才能改键',  // 11
    '显示设置',                                    // 12
    '停用改键',                                    // 13
    '启用改键',                                    // 14
    '以管理员身份重启',                            // 15
    '退出',                                        // 16
    '关闭',                                        // 17
    '改键运行中',                                  // 18
    '改键已停用',                                  // 19
    '(禁用)',                                      // 20
    '点击此处，然后按下任意键',                    // 21
    '禁用该键(不映射)',                            // 22
    '已存在相同源键的规则',                        // 23
    '请先设置源键',                                // 24
    '请设置目标键(或选择禁用)',                    // 25
    '删除选中的映射规则？',                        // 26
    'OctopusKeyRemap 已在运行',                    // 27
    '确认',                                        // 28
    '确定',                                        // 29
    '取消',                                        // 30
    '源键',                                        // 31
    '目标键',                                      // 32
    '目标为多个键(组合/序列)',                      // 33
    '点击此处录制按键序列，再点一次结束',          // 34
    '清空',                                        // 35
    '请至少录制一个按键',                          // 36
    '选择…',                                       // 37
    '选择按键',                                    // 38
    '选择组合键',                                  // 39
    '全部',                                        // 40
    '字母/数字',                                   // 41
    '功能键',                                      // 42
    '修饰键',                                      // 43
    '导航/控制键',                                 // 44
    '数字键盘',                                    // 45
    '多媒体键',                                    // 46
    '标点符号',                                    // 47
    '添加 →',                                      // 48
    '上移',                                        // 49
    '下移',                                        // 50
    '移除',                                        // 51
    '已选(按顺序)：',                              // 52
    '同时按下(组合)',                              // 53
    '依次按下(序列)',                              // 54
    '预览：',                                      // 55
    '请至少选择一个按键',                          // 56
    '录制中：再点一次结束，误录点「删上一键」',       // 57
    '删上一键',                                     // 58
    '修饰键(按住)'                                  // 59
  );

  EN: array[1..LAST_SID] of string = (
    'OctopusKeyRemap Settings',
    'Enable remapping',
    'Source key',
    'Target key',
    'On',
    'Add',
    'Edit',
    'Delete',
    'Start with Windows',
    '语言 Language',
    'Elevated windows need this program to run as administrator too',
    'Show settings',
    'Disable remapping',
    'Enable remapping',
    'Restart as administrator',
    'Exit',
    'Close',
    'Remapping active',
    'Remapping disabled',
    '(disabled)',
    'Click here, then press any key',
    'Disable this key (no mapping)',
    'A rule with the same source key already exists',
    'Set the source key first',
    'Set a target key (or choose disable)',
    'Delete the selected mapping?',
    'OctopusKeyRemap is already running',
    'Confirm',
    'OK',
    'Cancel',
    'Source key',
    'Target key',
    'Target is multiple keys (combo/sequence)',
    'Click here to record; click again to end',              // 34
    'Clear',
    'Record at least one key',
    'Pick…',
    'Pick a key',
    'Pick combo keys',
    'All',
    'Letters/Digits',
    'Function keys',
    'Modifiers',
    'Navigation/Control',
    'Numpad',
    'Media keys',
    'Punctuation',
    'Add →',
    'Up',
    'Down',
    'Remove',
    'Selected (in order): ',
    'Press together (combo)',
    'Press in order (sequence)',
    'Preview: ',
    'Select at least one key',
    'Recording: click again to end, "Undo last" helps',      // 57
    'Undo last',                                             // 58
    'Modifiers (held)'                                       // 59
  );

function S(id: Integer): string;
begin
  if (id < Low(ZH)) or (id > High(ZH)) then
    Exit('');
  if EffectiveLang = LANG_ZH then
    Result := ZH[id]
  else
    Result := EN[id];
end;

end.
