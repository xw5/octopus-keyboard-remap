# OctopusKeyRemap

<p align="center"><img src="docs/icon.png" width="160" alt="OctopusKeyRemap icon"></p>

[简体中文](#简体中文) | [English](#english)

## 简体中文

**OctopusKeyRemap** 是一个免费开源的 Windows 键盘改键工具（octopus 工具箱成员），使用 Lazarus / Free Pascal 编写，原生 Win32 实现，零运行时依赖。底层基建复用自 [OctopusKey](https://github.com/xw5/octopus-key)（低级键盘钩子、托盘、代码建窗、双语机制）。

### 功能特性

- **键 → 键映射** —— 任意键改到任意键，包括修饰键目标（如 `CapsLock → Left Ctrl`）与锁定键目标
- **一键 → 多键（组合/序列）** —— 目标勾选「多个键」后按真实顺序录制一段按键（先按 Ctrl 再按 C = 组合键 `Ctrl+C`；`Ctrl+C` 后再 `Ctrl+V` = 序列宏），回放原样重放，录制结束自动补齐未松开的键
- **禁用按键** —— 目标选「禁用」即让某个键彻底失效（如 Insert）
- **点击捕获录入** —— 设置窗里点击捕获框再按物理键即可录入，无需从下拉列表里翻找；所有键（含 `Esc`、退格）都能直接录，再点一次捕获框取消；编辑对话框打开期间改键自动暂停，已映射的源键也能重新录入
- **手动选择键** —— 每个捕获框旁的「**选择…**」按钮可从分类列表里直接挑键：坏键按不出来也能设为目标（临时用别的键顶替）；组合目标支持**多选**，「上移/下移」调整**先后顺序**，可选「同时按下(组合)」或「依次按下(序列)」，底部实时预览
- **修饰键安全** —— 虚拟修饰键与物理修饰键共存不冲突：硬件提前释放时自动恢复虚拟按下，虚拟释放时不会误伤仍按住的物理键
- **注入无回环** —— 自己 SendInput 的注入事件带 `LLKHF_INJECTED` 标记 + 魔数 `dwExtraInfo` 双保险，钩子永不二次改键
- **Scancode 注入** —— 目标键优先以 scancode 模式注入，DirectInput/游戏兼容性更好
- **托盘常驻** —— 托盘菜单：显示设置 / 启停改键 / 以管理员身份重启 / 退出；网格「启用」列可单条开关规则
- **开机自启** —— 写入 `HKCU\...\Run`，普通权限启动
- **双语界面** —— 中文 / English，默认跟随系统语言
- **隐私安全** —— 所有输入仅在本地处理，不上传任何数据

### 已知限制

- 组合/序列每按一次源键只回放一次（按住不连放）；步骤之间无延时
- 管理员权限运行的窗口（如任务管理器）收不到普通权限进程的钩子——需要通过托盘「以管理员身份重启」
- UAC 安全桌面（输密码的蓝色界面）任何用户态工具都无法改键

### 使用方法

1. 启动后托盘运行，左键托盘图标或右键「显示设置」打开设置窗
2. 「添加」→ 点击左侧捕获框按 **源键** → 点击右侧捕获框按 **目标键**（或勾选「禁用该键」）→ 确定
3. 目标想改成一段组合/序列：勾选「**目标为多个键(组合/序列)**」→ 点击录制框按真实顺序按下并松开各键 → 再点一下录制框（或点别的控件）结束录制 → 误录的点「**删上一键**」回退 → 确定；坏键/不方便按的键可点录制框旁的「**选择…**」从列表多选，「上移/下移」调序，「同时按下(组合)」或「依次按下(序列)」两种模式，底部实时预览
4. 点击列表行「启用」列可临时停用该条规则；双击行可编辑；「删除」移除
5. 顶栏复选框整体启停改键；配置实时保存到 `%APPDATA%\OctopusKeyRemap\config.json`

### 下载 / 构建

暂无预编译发布版 —— 从源码构建（零运行时依赖）:

```
git clone https://github.com/xw5/octopus-keyboard-remap.git
cd octopus-keyboard-remap
build.bat build      # 编译 bin\OctopusKeyRemap.exe（含版本信息/manifest）
build.bat test       # 决策引擎断言测试
build.bat release    # 额外打包 release\OctopusKeyRemap-v1.0.0-win64.zip
```

也可用 Lazarus IDE 直接打开 `octopusremap.lpi` 构建（`C:\lazarus\lazbuild.exe -B octopusremap.lpi`），要求 Lazarus 4.x + FPC 3.2.2（IDE 构建的 exe 不含版本信息资源）。

### 项目结构

```
src/
├── version.inc      APP_VERSION 单一来源，build.bat 解析
├── remap.pas        改键决策引擎（纯逻辑，可单元测试）
├── inject.pas       SendInput 封装（scancode 优先，魔数 dwExtraInfo）
├── hooks.pas        LL 键盘钩子：injected 放行 + 同步决策 + 吞键
├── keymap.pas       VK → 键名（L/R 区分、小键盘消歧、多媒体键）
├── config.pas       设置 + 规则表 JSON 持久化（%APPDATA%\OctopusKeyRemap）
├── langstrings.pas  编译内中英字符串表
├── capture.pas      按键捕获控件 + 序列录制控件（原始 WM_KEYDOWN/UP，保留 sc/ext 标志）
├── pick.pas         手动选择键对话框（分类键目录、组合多选排序、实时预览）
└── main.pas         设置窗 + 编辑规则对话框 + 托盘 + 自启动
tests/test_remap.lpr 决策引擎断言测试（修饰键共存/恢复/去重/flush/组合回放/挂起）
```

### 技术说明

- 改键判定在钩子回调内**同步**完成（无消息中转，零额外延迟），命中即吞键（`return 1`）并注入目标键
- 决策与执行分离：`remap.pas` 不调用任何输入 API，`tests/test_remap.lpr` 用 40 条断言覆盖修饰键生命周期与组合回放（虚拟/物理共存、硬件释放恢复、多重虚拟持有、锁定键防连发、步骤序列、捕获挂起）
- 修饰键状态机见 `remap.pas` 头注释：`PhysCount/VirtCount/VirtSent/SrcHeld` 四张表；组合步骤为一次性按下/松开对，不进虚拟持有状态机
- 「选择…」生成的组合与录制产物同构（按序 downs + 逆序 ups / 逐键 down+up），引擎与配置零改动
- 编辑对话框打开期间改键引擎自动挂起（`RemapSetSuspended`），退出与停用时自动释放所有虚拟按住的键，杜绝「Ctrl 卡死」

### 路线图

- ~~**M4a** 键 → 组合键/序列~~ **已完成**（真实顺序录制 + 原样回放）
- **M4b** 键 → 文本注入（schema 已预留 `kind: 2`）
- **M2** 鼠标侧键改键（XButton1/2、中键 ↔ 键，基建已预留）
- **M3** 规则限定应用（按前台进程切换映射，字段已入配置 schema）

### 许可证

MIT —— 见 [LICENSE](LICENSE)

### 致谢

- [OctopusKey](https://github.com/xw5/octopus-key) —— 钩子、托盘、双语与构建基建的来源
- [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) 与 [PowerToys Keyboard Manager](https://github.com/microsoft/PowerToys) —— 改键语义的参考实现

## English

**OctopusKeyRemap** is a free, open-source keyboard remapper for Windows (part of the octopus toolbox), written in Lazarus / Free Pascal with a pure native Win32 implementation and zero runtime dependencies. Core plumbing is reused from [OctopusKey](https://github.com/xw5/octopus-key) (low-level keyboard hook, tray, code-built UI, bilingual mechanism).

### Features

- **Key → key mapping** — including modifier targets (`CapsLock → Left Ctrl`) and lock-key targets
- **One key → multiple keys (combo/sequence)** — check "multiple keys" as the target, then press the keys in their real order: Ctrl first, then C records the chord `Ctrl+C`; `Ctrl+C` followed by `Ctrl+V` records the macro. Replay is a faithful re-send, and keys still held at the end of the recording are released automatically
- **Disable keys** — pick "disable" as the target to make a key inert
- **Click-to-capture input** — click a capture box and press the physical key; every key is recordable (`Esc` and Backspace included), clicking the armed box again cancels; the engine suspends while an edit dialog is open, so already-mapped keys can be re-captured
- **Manual key picking** — the "**Pick…**" button beside every capture box opens a categorized key list: a broken key can be set as the target without pressing it; combo targets support **multi-select** with **up/down reordering**, and a "press together (combo)" vs "press in order (sequence)" switch with a live preview
- **Modifier safety** — virtual and physical modifiers coexist: hardware release re-asserts virtual holds, and virtual release never cuts short a held physical key
- **No injection loop** — own SendInput events carry `LLKHF_INJECTED` plus an `dwExtraInfo` magic; the hook never re-remaps them
- **Scancode injection** — targets are injected in scancode mode when possible for better DirectInput/game compatibility
- **Tray resident** — show settings / toggle / restart as administrator / exit; per-rule toggle in the grid
- **Autostart** — `HKCU\...\Run`, normal user privileges
- **Bilingual** — Chinese / English UI, follows system language by default
- **Privacy** — input never leaves the machine

### Known limitations

- Combos fire once per physical press (holding the source does not repeat them); no inter-step delays
- Elevated windows need the tool itself to run elevated (tray → "Restart as administrator")
- The UAC secure desktop cannot be remapped by any user-mode tool

### Usage

1. The app lives in the tray; left-click the icon to open settings
2. "Add" → click the left capture box and press the **source key** → click the right box and press the **target key** (or check "Disable this key") → OK
3. For a combo/sequence target: check "**Target is multiple keys**" → click the recorder, press and release the keys in their real order → click the recorder again (or any other control) to finish → mistakes can be removed with "**Undo last**" → OK; keys that are broken or awkward to press can be added via the recorder's "**Pick…**" list instead — multi-select, up/down to reorder, combo vs sequence mode, live preview
4. Click a row's "On" cell to toggle that rule; double-click to edit
5. The top checkbox toggles remapping globally; everything persists to `%APPDATA%\OctopusKeyRemap\config.json`

### Download / Build

No prebuilt binaries yet — build from source:

```
git clone https://github.com/xw5/octopus-keyboard-remap.git
cd octopus-keyboard-remap
build.bat build      # produces bin\OctopusKeyRemap.exe (versioninfo + manifest)
build.bat test       # decision-engine assertion tests
build.bat release    # also packages release\OctopusKeyRemap-v1.0.0-win64.zip
```

Alternatively open `octopusremap.lpi` in the Lazarus IDE (`C:\lazarus\lazbuild.exe -B octopusremap.lpi`); requires Lazarus 4.x + FPC 3.2.2 (IDE builds lack the versioninfo resource).

### Project structure

```
src/
├── version.inc      single source of APP_VERSION, parsed by build.bat
├── remap.pas        remapping decision engine (pure logic, unit-testable)
├── inject.pas       SendInput wrappers (scancode-first, magic dwExtraInfo)
├── hooks.pas        LL keyboard hook: injected passthrough + sync decision + swallow
├── keymap.pas       VK -> key names (L/R split, numpad disambiguation, media keys)
├── config.pas       settings + rule table JSON persistence
├── langstrings.pas  compiled-in ZH/EN string tables
├── capture.pas      key capture + sequence recorder controls (raw WM_KEYDOWN/UP, keeps sc/ext flags)
├── pick.pas         manual key-picker dialog (categorized catalog, ordered multi-select, live preview)
└── main.pas         settings window + edit-rule dialog + tray + autostart
tests/test_remap.lpr decision-engine assertions (modifier lifecycles, dedupe, flush, combo replay, suspension)
```

### Technical notes

- Remap decisions happen **synchronously** inside the hook callback (no message hop); hits are swallowed (`return 1`) and the mapped key injected immediately
- Decision and execution are separated: `remap.pas` never calls input APIs; `tests/test_remap.lpr` covers modifier lifecycles and combo replay with 40 assertions
- The modifier state machine (`PhysCount/VirtCount/VirtSent/SrcHeld`) is documented at the top of `remap.pas`; combo steps are one-shot down/up pairs and never enter it
- "Pick…" produces the same step structure as recording (in-order downs + reverse ups, or per-key down+up), so the engine and config schema need no changes
- The engine suspends while an edit dialog is open (`RemapSetSuspended`); on exit/disable all virtually held keys are released, so no "stuck Ctrl"

### Roadmap

- ~~**M4a** key → combo / sequence~~ **done** (faithful order recording + replay)
- **M4b** key → text injection (`kind: 2` already in schema)
- **M2** mouse side-button remapping (XButton1/2, middle button ↔ keys)
- **M3** per-app rules (switch mappings by foreground process; schema field ready)

### License

MIT — see [LICENSE](LICENSE)

### Credits

- [OctopusKey](https://github.com/xw5/octopus-key) — origin of the hook/tray/i18n/build plumbing
- [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) and [PowerToys Keyboard Manager](https://github.com/microsoft/PowerToys) — reference implementations for remap semantics
