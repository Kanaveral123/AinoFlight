# 爱乃初次飞行（Aino's First Flight）· SSSU 构建包

本文件夹包含小游戏的全部场景源码、新增素材、构建脚本和离线测试。用 SSSU（siglus-ssu）编译后，得到游戏直接可用的 `Scene.pck`。

- 所有路径都相对于本文件夹，整个文件夹可以随意移动。
- 默认把游戏文件夹视为 `..\game`；如果游戏不在那里，可以用 `-GameDir` 另行指定。

玩法、操作见 [docs/飞行小游戏说明.md](docs/飞行小游戏说明.md)。

## 目录

| 路径 | 内容 |
|---|---|
| `build.cmd` | 双击构建；也可以带参数运行，例如 `build.cmd -Deploy` |
| `build.ps1` | 构建脚本，各参数见下文 |
| `scene\` | 完整的场景源码（570 个文件），即 SSSU 编译的输入目录：542 个 `.ss`、26 个 `.inc`，以及 `Gameexe.ini` 和 `暗号.dat` |
| `assets\g00\` | 9 张地标贴图 `FL_lm_*.g00`，由原游戏背景图裁切而成 |
| `assets\wav\` | 2 个引擎声 `FL_engine_low.ogg` / `FL_engine_high.ogg`，由原游戏的发动机循环音改变播放速率而成 |
| `save\` | 900 号测试存档（`0900.sav`、`0900.png`），读取后从首次飞行前开始 |
| `original\_start.ss` | 游戏原版的启动脚本；制作测试存档后用它恢复 |
| `tools\` | 素材生成、运行包转换和离线测试脚本（Python） |
| `docs\` | 玩法说明与更新记录 |
| `build\` | 构建时自动生成，可以随时删除 |

## 与小游戏相关的文件

`scene\` 中其余脚本都是原游戏的原样副本。小游戏只涉及下面这些文件：

| 类别 | 文件 | 作用 |
|---|---|---|
| 新增 | `zzz_flight.inc` | 小游戏的全局变量 |
| 新增 | `zzz_flight.ss` | 入口、简报、暂停菜单、结算、退出确认，键盘与手柄输入 |
| 新增 | `zzz_flight_sim.ss` | 飞行模型、引导框、接地与评分 |
| 新增 | `zzz_flight_draw.ss` | 3D 场景、地标、HUD、姿态仪、小地图和文字，菜单按钮的手柄高亮与按键提示 |
| 新增 | `zzz_flight_audio.ss` | 引擎声、刹车声、语音 |
| 修改原脚本 | `030_愛乃0813.ss` | 首次飞行剧情：调用小游戏、测试存档入口、降落后的剧情分支 |
| 修改原脚本 | `__lib_debug.ss` | 飞行中把 Q 键让给油门，不触发快速存档 |
| 修改原脚本 | `__sys_mwbtn.ss` | 飞行中停用消息框按钮 |
| 修改原脚本 | `__sys_sidebar.ss` | 飞行中停用并隐藏侧栏（存读档、翻页） |
| 新素材 | `assets\g00\FL_lm_*.g00` ×9、`assets\wav\FL_engine_*.ogg` ×2 | 安装到游戏的 `g00\` 和 `wav\` |

## 准备 SSSU

构建需要：

- anemoi 日文原版（根目录须含Scene.pck）；
- Windows PowerShell 5.1（Windows 自带）；
- 一个装有 **siglus-ssu 0.5.4** 的 Python（本包用 Python 3.12.15 验证）；
- 只有使用 `-RegenerateAssets` 时才需要 Pillow。

`build.ps1` 按以下顺序查找这个 Python，用第一个能导入 siglus-ssu 的：

1. 参数 `-Python <python.exe>`；
2. 环境变量 `SIGLUS_SSU_PYTHON`；
3. 按 SSSU 部署目录的结构找 `.venv\Scripts\python.exe`，依次尝试 `..\..\sssu_main`、`..\sssu_main` 和本文件夹内的 `sssu_main`；
4. PATH 上的 `python`，然后是 `py`。

按现在的目录布局（本包在 `anemoi` 文件夹里，SSSU 部署在与 `anemoi` 并列的 `sssu_main` 里），第 3 步就能找到，不需要任何设置。

如果要在本包里新装一份 SSSU（需要联网），在本文件夹中运行：

```powershell
py -3.12 -m venv sssu_main\.venv
sssu_main\.venv\Scripts\python.exe -m pip install siglus-ssu==0.5.4 Pillow
```

## 构建方法

### 一键构建

双击 `build.cmd`，或在 PowerShell 中进入本文件夹后运行：

```powershell
.\build.ps1
```

脚本依次完成：

1. 查找 SSSU，并显示所用的 Python 和 siglus-ssu 版本。
2. 确认 `scene\_start.ss` 是原版；如果不是，用 `original\_start.ss` 恢复。
3. 用 SSSU 编译 `scene\`，得到 `build\Scene.compiled.pck`。编译固定为串行，并设置 `PYTHONHASHSEED=0`，同一份源码每次都得到逐字节相同的结果。
4. 用 `tools\runtime_pack.py` 去掉 SSSU 输出中额外的 exe 层 XOR，得到 `build\Scene.pck`。
   - 已安装的游戏只读取不含这层 XOR 的场景包。
   - 转换只改动这一层和包头里的一个标志；脚本会逐个场景核对，确认解码后的内容不变。
5. 显示 `build\Scene.pck` 的 SHA256。同一份源码每次构建都得到相同的哈希，可以用来核对两次构建是否一致。

默认只编译，不改动游戏文件夹。整个构建不到一分钟。

### 安装到游戏

```powershell
.\build.ps1 -Deploy
```

- 安装前请先关闭游戏。
- 编译后会把 `build\Scene.pck` 复制为游戏的 `Scene.pck`，并把 `assets\g00` 和 `assets\wav` 中的 11 个文件复制到游戏的 `g00\`、`wav\`。
- 游戏里原有的 `Scene.pck` 如果与新包不同，会先备份为 `build\Scene.previous.pck`。要撤销安装，把这个备份复制回游戏文件夹即可。
- 加上 `-InstallSave` 会同时把 900 号测试存档复制到游戏的 `savedata\`；原有的 900 号存档会先备份到 `build\savedata-previous\`。

也可以手动安装：

- `build\Scene.pck` → 游戏文件夹的 `Scene.pck`
- `assets\g00\*` → 游戏的 `g00\`
- `assets\wav\*` → 游戏的 `wav\`

SSSU 还会顺带生成 `build\Gameexe.dat`。它不需要安装，游戏继续使用自己原有的 `Gameexe.dat`。

### 参数

| 参数 | 作用 |
|---|---|
| `-Python <路径>` | 指定装有 siglus-ssu 的 Python；相对路径以本文件夹为起点 |
| `-GameDir <路径>` | 游戏文件夹（含 `SiglusEngine.exe`），默认 `..\game` |
| `-Deploy` | 编译后安装 `Scene.pck` 和 11 个新素材 |
| `-InstallSave` | 安装 900 号测试存档 |
| `-Test` | 编译后运行全部离线测试 |
| `-RegenerateAssets` | 从游戏原有的 `g00\`、`wav\` 重新生成 11 个素材，写回 `assets\` |
| `-CreateTestSave` | 仅供制作测试存档，见下文 |

参数可以组合，例如 `.\build.ps1 -Test -Deploy`。用 `build.cmd` 时写法相同：`build.cmd -Test -Deploy`。

### 只用 SSSU 命令构建

不用脚本时，在 PowerShell 中进入本文件夹后，依次运行下面的命令，与一键构建的结果相同。示例中的 SSSU 位于 `..\..\sssu_main`，请按实际位置替换：

```powershell
$env:PYTHONHASHSEED = '0'
..\..\sssu_main\siglus-ssu.cmd -c --serial scene build\Scene.compiled.pck
..\..\sssu_main\.venv\Scripts\python.exe -X utf8 tools\runtime_pack.py build\Scene.compiled.pck build\Scene.pck
Remove-Item Env:PYTHONHASHSEED
```

## 修改后重新构建

- 改动 `scene\` 下的脚本后，直接重新运行 `.\build.ps1`。
- 小游戏的新全局变量只能追加在 `zzz_flight.inc` 末尾，否则已有的 900 号存档会读错变量。
- 编辑时请保持文件原来的编码：
  - 原游戏脚本大多是 Shift-JIS（cp932）编码，包括 `__sys_mwbtn.ss`、`__sys_sidebar.ss`、`_start.ss` 和 `Gameexe.ini`；
  - `zzz_flight*`、`030_愛乃0813.ss` 和 `__lib_debug.ss` 是 UTF-8。
- 改动小游戏后，建议运行 `.\build.ps1 -Test`，确认离线测试仍然通过。

## 重新生成素材

```powershell
.\build.ps1 -RegenerateAssets
```

- `tools\prepare_flight_landmarks.py` 解出原游戏的背景图（BG707、BG021、BG301、BG202、BG101、BG016、BG206、BG506、BG702），按轮廓裁切并去掉天空，再写成新的 `FL_lm_*.g00`。
- `tools\prepare_flight_audio.py` 只改动原游戏 `ANB_airplane_motor_LOOP.ogg` 的采样率字段，得到低转速和高转速两个变体。
- 原游戏文件只读不改；对照图和报告保存在 `build\`。
- 用本游戏的原素材重新生成时，结果与 `assets\` 中的文件逐字节一致。

## 制作测试存档（开发用）

`save\` 里已经有现成的 900 号存档，一般不需要重新制作。

如果要重新制作：

1. 运行 `.\build.ps1 -CreateTestSave -Deploy`。编出的包启动后，会直接沿原剧情流程进入首次飞行之前。
2. 在游戏里存到 900 号槽。
3. 再运行一次普通的 `.\build.ps1 -Deploy`，恢复正常的标题流程。

构建结束后 `scene\_start.ss` 会自动恢复为原版，源码不会留下改动。

## 离线测试

`.\build.ps1 -Test` 会依次运行下列脚本，各自的日志和报告写在 `build\`：

| 脚本 | 检查内容 |
|---|---|
| `test_flight_sim.py` | 以 32 位整数执行实际的 SS 飞行代码：失速、爬升、滑翔、转弯、离地、地面效应、地面转向、刹车、评分，以及完整的左航线 |
| `test_flight_render.py` | 沿参考航线逐帧执行渲染器的投影和裁剪代码|
| `test_flight_controls.py` | 菜单、暂停、退出确认、手柄操作和剧情输入隔离（手柄按钮松开前不回到剧情） |
| `test_flight_audio.py` | 引擎声、刹车声、接地声和语音的时序 |
| `audit_text_layout.py` | 固定位置的文字与相邻元素的间距（至少 30 px） |

这些测试只读取 `scene\` 中的源码，不需要启动游戏。

## 常见问题

- **提示找不到装有 siglus-ssu 的 Python**：用 `-Python` 指定路径，或按「准备 SSSU」安装。
- **SSSU 编译失败**：脚本会显示 `build\build.log` 的最后 60 行，完整日志在该文件中。
- **PowerShell 不允许运行脚本**：改用 `build.cmd`，它会以 `-ExecutionPolicy Bypass` 启动 `build.ps1`。
- **提示请先关闭游戏**：`-Deploy` 和 `-InstallSave` 在游戏运行时不会复制任何文件。
- **SSSU 版本不同**：脚本会给出提醒。换用其他版本的 siglus-ssu 时，运行包仍可使用，但哈希可能与 0.5.4 编出的不同。
- **手柄没有反应**：游戏引擎只读取 XInput（Xbox 规格）手柄，游戏原有的菜单也是如此。PS5 DualSense、PS4 等手柄需要先转换成 Xbox 手柄：把 `SiglusEngine.exe` 添加为 Steam 的非 Steam 游戏、开启 Steam 输入并从 Steam 启动，或使用 DS4Windows。
