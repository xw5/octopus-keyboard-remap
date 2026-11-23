unit config;

{ TConfig + JSON persistence. The live rule table lives in the remap engine;
  this unit only serializes it to %APPDATA%\OctopusKeyRemap\config.json.
  Corrupted or missing files fall back to defaults silently. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, jsonparser, remap;

const
  // language: -1 = follow system, 0 = zh, 1 = en
  LANG_SYSTEM = -1;
  LANG_ZH     = 0;
  LANG_EN     = 1;

type
  TConfig = record
    Lang: Integer;
    Enabled: Boolean;     // remapping master switch
    Autostart: Boolean;
  end;

var
  Cfg: TConfig;
  ConfigDir: string;
  FirstRun: Boolean;

procedure LoadConfig;
procedure SaveConfig;

implementation

const
  CONFIG_FILE = 'config.json';

function ConfigPath: string;
begin
  Result := ConfigDir + PathDelim + CONFIG_FILE;
end;

procedure SetDefaults;
begin
  Cfg.Lang      := LANG_SYSTEM;
  Cfg.Enabled   := True;
  Cfg.Autostart := False;
end;

procedure LoadRule(o: TJSONObject; out r: TRule);
var
  j: TJSONData;
  arr: TJSONArray;
  st: TJSONObject;
  i: Integer;
begin
  FillChar(r, SizeOf(r), 0);
  r.Combo := nil;
  r.Text := '';
  r.App := '';
  r.Enabled  := o.Get('on', True);
  r.SrcMouse := o.Get('srcMouse', 0);
  r.SrcVK    := o.Get('srcVK', 0);
  r.SrcSC    := o.Get('srcSC', 0);
  r.SrcExt   := o.Get('srcExt', False);
  r.SrcMods  := o.Get('srcMods', 0);   // absent = legacy plain source
  r.Kind     := o.Get('kind', RK_KEY);
  r.DstVK    := o.Get('dstVK', 0);
  r.DstSC    := o.Get('dstSC', 0);
  r.DstExt   := o.Get('dstExt', False);
  r.Text     := o.Get('text', '');
  r.App      := o.Get('app', '');
  j := o.Find('combo');
  if (j is TJSONArray) then
  begin
    arr := TJSONArray(j);
    SetLength(r.Combo, arr.Count);
    for i := 0 to arr.Count - 1 do
      if arr.Objects[i] is TJSONObject then
      begin
        st := arr.Objects[i];
        r.Combo[i].VK := st.Get('vk', 0);
        r.Combo[i].SC := st.Get('sc', 0);
        r.Combo[i].Ext := st.Get('ext', False);
        r.Combo[i].IsDown := st.Get('down', True);
      end;
  end;
end;

procedure LoadConfig;
var
  j: TJSONData;
  o: TJSONObject;
  jr: TJSONData;
  arr: TJSONArray;
  fs: TFileStream;
  rules: TRules;
  i, n: Integer;
begin
  SetDefaults;
  RemapClearRules;
  ConfigDir := GetEnvironmentVariable('APPDATA') + '\OctopusKeyRemap';
  FirstRun := True;
  try
    ForceDirectories(ConfigDir);
  except
  end;
  if not FileExists(ConfigPath) then
    Exit;
  try
    fs := TFileStream.Create(ConfigPath, fmOpenRead or fmShareDenyWrite);
    try
      j := GetJSON(fs);
    finally
      fs.Free;
    end;
    try
      if not (j is TJSONObject) then Exit;
      o := TJSONObject(j);
      FirstRun := False;
      Cfg.Lang      := o.Get('lang', Cfg.Lang);
      Cfg.Enabled   := o.Get('enabled', Cfg.Enabled);
      Cfg.Autostart := o.Get('autostart', Cfg.Autostart);
      jr := o.Find('rules');
      if jr is TJSONArray then
      begin
        arr := TJSONArray(jr);
        n := 0;
        SetLength(rules, arr.Count);
        for i := 0 to arr.Count - 1 do
          if arr.Objects[i] is TJSONObject then
          begin
            LoadRule(arr.Objects[i], rules[n]);
            Inc(n);
          end;
        SetLength(rules, n);
        RemapSetRules(rules);
      end;
    finally
      j.Free;
    end;
  except
    // corrupted config -> fall back to defaults
    SetDefaults;
    RemapClearRules;
  end;
end;

procedure SaveRule(o: TJSONObject; const r: TRule);
var
  arr: TJSONArray;
  st: TJSONObject;
  i: Integer;
begin
  o.Add('on', r.Enabled);
  o.Add('srcMouse', r.SrcMouse);
  o.Add('srcVK', r.SrcVK);
  o.Add('srcSC', r.SrcSC);
  o.Add('srcExt', r.SrcExt);
  if r.SrcMods <> 0 then
    o.Add('srcMods', r.SrcMods);   // omit the plain-source default
  o.Add('kind', r.Kind);
  o.Add('dstVK', r.DstVK);
  o.Add('dstSC', r.DstSC);
  o.Add('dstExt', r.DstExt);
  if r.Text <> '' then
    o.Add('text', r.Text);
  if r.App <> '' then
    o.Add('app', r.App);
  if (r.Kind = RK_COMBO) and (Length(r.Combo) > 0) then
  begin
    arr := TJSONArray.Create;
    for i := 0 to High(r.Combo) do
    begin
      st := TJSONObject.Create;
      st.Add('vk', r.Combo[i].VK);
      st.Add('sc', r.Combo[i].SC);
      st.Add('ext', r.Combo[i].Ext);
      st.Add('down', r.Combo[i].IsDown);
      arr.Add(st);
    end;
    o.Add('combo', arr);
  end;
end;

procedure SaveConfig;
var
  o, ro: TJSONObject;
  arr: TJSONArray;
  fs: TFileStream;
  json: AnsiString;
  i: Integer;
begin
  try
    ForceDirectories(ConfigDir);
    o := TJSONObject.Create;
    try
      o.Add('lang', Cfg.Lang);
      o.Add('enabled', Cfg.Enabled);
      o.Add('autostart', Cfg.Autostart);
      arr := TJSONArray.Create;
      for i := 0 to RemapRuleCount - 1 do
      begin
        ro := TJSONObject.Create;
        SaveRule(ro, RemapRuleAt(i));
        arr.Add(ro);
      end;
      o.Add('rules', arr);
      fs := TFileStream.Create(ConfigPath, fmCreate);
      try
        json := UTF8Encode(o.AsJSON);
        if json <> '' then
          fs.WriteBuffer(json[1], Length(json));
      finally
        fs.Free;
      end;
    finally
      o.Free;
    end;
  except
    // never let saving config crash the app
  end;
end;

end.
