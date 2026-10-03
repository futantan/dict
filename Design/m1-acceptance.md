# M1 验收记录

本文逐条列出 `Design/architecture.md` 第 15.1 节的 8 条验收，写明当前状态、证据，以及还没验证的条目由谁、用哪条命令或哪些步骤来验证。
记录时间：2026-10-04，main 工作区（M1.11 串联的改动尚未提交）。
记录时屏幕处于锁定状态（`ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` 为 true），所以需要真实屏幕的条目都没有跑。

## 前置条件（人工，一次性）

1. 构建并启动开发版：`make run`。
   首次启动会打开「欢迎使用 Dict Dev」引导窗口。
2. 给 Dict Dev 授权辅助功能：在引导窗口第 1 步点「打开系统设置」。
   系统可能先弹出自己的「Dict Dev 想要控制这台电脑」提示，选择打开系统设置。
   在「系统设置 → 隐私与安全性 → 辅助功能」里打开 Dict Dev 的开关；引导窗口会自动进入第 2 步。
   如果开关显示已打开但面板仍说需要重置，在终端运行 `tccutil reset Accessibility au.ibra.dict.dev` 后重新打开开关。
3. 在引导窗口第 2 步设置「读」「写」两个快捷键，例如 ⌃⌥D 和 ⌃⌥F（不能用只带 ⌥ 的字母组合）。
4. 下载翻译语言包：在引导窗口第 3 步点「下载语言…」，在系统弹出的对话框里确认下载英语和简体中文。
   也可以手动：「系统设置 → 通用 → 语言与地区 → 翻译语言」，下载「英语」和「中文（简体）」。
   引导窗口显示「英语和中文（简体）已就绪。」后点「完成」。
5. 验收第 5 条之前在设置里填 Key：菜单栏图标 → 设置… → 模型 → 服务商选 OpenAI → 粘贴 Key → 点「测试」应显示成功。
   第 4 条要在没有配置模型时做：服务商选「无」，或先做第 4 条再填 Key。

所有会显示窗口、抢焦点、合成按键或占用剪贴板的脚本运行，前后都要加全机互斥锁：
`until mkdir /private/tmp/dict-ui.lock 2>/dev/null; do sleep 2; done; <命令>; rmdir /private/tmp/dict-ui.lock`。
`make e2e`、`make matrix` 和 `scripts/e2e-selftest.sh` 的驱动自己持锁，不要在外面再套一层，否则会等死。

## 8 条验收

### 1. `make lint test` 通过

状态：已通过（2026-10-04，屏幕锁定时也能跑）。
命令：`make generate build test lint`，以及 `CONFIG=Release make build`。
结果：构建零警告；`make lint` 无输出；`test-core` 的 Swift Testing 145 个测试全部通过；`test-app`（`xcodebuild test`）退出码 0；`smoke` 输出 `smoke-test: PASS: "Dict Dev" … launched, showed its menu bar item, quit`；Release 构建退出码 0。
复验：任何人或脚本在仓库根目录运行同样的命令。

### 2. `make e2e` 通过

状态：未验证，原因是屏幕锁定，夹具窗口无法成为前台、取词需要真实的窗口服务。
验证者：脚本，解锁后由 agent 或人运行。
命令：先跑驱动自检 `scripts/e2e-selftest.sh`，再跑 `make e2e`。
通过标准：夹具的 `NSTextView`、`NSTextField`、`WKWebView` 三种控件经无障碍取到的文字与预期一致、来源是 `accessibility`、拷贝事件数为 0；自绘控件经菜单栏拷贝项取到文字；密码框返回 `secureField` 且没有任何拷贝事件；所有场景前后剪贴板哈希一致。
说明：`make e2e` 走 `--e2e` 调试入口和 M1.4 的读取器，不经过本次新增的会话协调者；本次改动只让 `--e2e` 启动时不启动快捷键、权限监听和引导窗口。

### 3. `make matrix` 输出并人工确认

状态：未验证，原因同上。
验证者：脚本跑矩阵，人确认输出。
命令：`make matrix`，结果写进 `Design/app-matrix.json` 并与上次比较。
人工确认：Chrome 热状态经无障碍取词，第一段耗时不超过 150 ms；Chrome 冷状态（隔离实例）第一次走菜单栏拷贝项且剪贴板原样，约 2 s 后同一页面走无障碍；Safari 只读文字经文本标记取到；VS Code 隔离实例第一次走兜底、之后走无障碍；TextEdit 走无障碍。

### 4. TextEdit 里读一句英文（零配置）

状态：未验证，原因是屏幕锁定，且需要真实按键和已授权的 Dict Dev。
验证者：人。
前提：完成前置条件 1–4，设置里没有配置模型。
步骤：

1. 打开 TextEdit，新建文稿，输入 `The weather is lovely today, so we are going for a walk.`，用鼠标选中整句。
2. 按「读」快捷键。
3. 应看到：面板出现在选区正下方约 8 pt 处，上面一行是灰色的原文，下面先短暂显示「正在翻译…」，然后显示 Apple 翻译的中文译文。
4. 应看到：菜单栏仍是 TextEdit 的菜单（TextEdit 仍是前台应用）。
5. 按 Esc：面板消失，TextEdit 里的选区仍高亮，光标位置不变；直接打字会替换选区，说明焦点回到了 TextEdit。
6. 再选中一句、按「读」键，等译文出现后再按一次「读」键：面板应隐藏。
7. 在终端运行 `log show --last 5m --info --predicate 'subsystem == "au.ibra.dict.dev"' | grep "panel shown"`，每次按键一行，形如 `session 3: capture 18.4ms via accessibility, panel shown 19.0ms after the shortcut`；`panel shown` 后的毫秒数应不超过 200。

如果第 3 步面板显示「翻译语言尚未下载」：说明语言包没下载完，点「下载语言…」完成前置条件 4 后重试。

### 5. 配置 OpenAI Key 后流式翻译与断网降级

状态：未验证，原因同第 4 条。
不依赖屏幕的部分已验证：模型客户端和提示词由 `make eval` 覆盖（见第 8 条，首个内容 p50 0.76 s、p90 1.04 s）；降级逻辑由 `TranslationEngineTests` 和 `SessionCoordinatorTests` 用桩覆盖。
验证者：人。
步骤：

1. 完成前置条件 5。
2. 在 TextEdit 选中同一句英文，按「读」键：译文应逐步出现（流式），而不是一次性出现。
3. 连续做 10 次（每次可以换一句），然后运行 `log show --last 10m --info --predicate 'subsystem == "au.ibra.dict.dev"' | grep "first text"`，取 10 个毫秒数的中位数，应小于 1500。
4. 关掉 Wi-Fi（或拔网线），再选中一句按「读」键：面板应显示 Apple 翻译的译文，译文下方有一行说明「模型出错（网络错误），已改用 Apple 翻译。」。
5. 恢复网络。

### 6. 日志只有耗时、没有用户文字和 Key

状态：未验证（需要第 4、5 条的真实运行产生日志）；代码层面已检查：新增日志只插值会话代号、耗时、途径名、阶段名和状态名，全部是非用户数据；Key 从不进日志。
验证者：人或脚本，在第 4、5 条之后立即运行。
命令：`log show --last 10m --info --predicate 'subsystem == "au.ibra.dict.dev"'`。
通过标准：能看到每个会话的 `capture … via …`、`panel shown …`、`first text …`、`ended in result after …`，以及取词模块的 `capture accessibility app=… first=…ms` 和翻译引擎的 `translation engine: …`。
再运行 `log show --last 10m --info --predicate 'subsystem == "au.ibra.dict.dev"' | grep -iE "weather|lovely|sk-"`，应没有任何输出（把第 4、5 条用过的句子里的词和 Key 的前缀代进去）。

### 7. 没有 `dict-en-zh.sqlite` 时以上全部成立

状态：按构造成立；M1 没有任何代码读取词典数据库，仓库和构建目录里也没有这个文件（`find . -name 'dict-en-zh.sqlite'` 无输出）。
验证者：做第 2–6 条时顺带确认：运行前执行 `find ~/Library /Users/ttfu/d/dict -name 'dict-en-zh.sqlite' 2>/dev/null`，应无输出。

### 8. `make eval SUITE=direction RUNS=10` 方向不变量通过率不低于 95%

状态：已通过（2026-10-04，`gpt-6-luna`，260 次调用，花费 0.0116 美元）。
结果：`targetLanguage` 259/259（100%）、`keepsQuestion` 259/259、`noPromptLeak` 259/259、`sameLineCount` 259/259、`noAnswer` 257/259（99.2%）、`keepsVerbatim` 48/50（96%）、`completed` 259/260（1 次首个事件超时）；脚本结论 `PASS`。
复验：`make eval SUITE=direction RUNS=10`（Key 由脚本从 `.env` 读取，不打印）。

## 本次串联的其他人工检查（解锁后）

- 面板里只选中译文的一部分再按 ⌘C，粘贴出来应只有选中的部分；什么都不选按 ⌘C 应复制整段译文。
  单测 `PanelSelectionCopyTests` 只验证了按键路由，真实点选没有验证。
- 默认中英配对下选中日文 `会議は明日の午後三時に開始します。` 按「读」键，应译成中文而不是英文。
- 按「写」键：M1 没有动作，面板不出现，日志里有一行 `write shortcut pressed`。
- 撤销 Dict Dev 的辅助功能授权（在系统设置里关掉开关）后按「读」键：面板说明需要辅助功能权限，按快捷键时不应弹出任何系统对话框；点「打开系统设置」才可能出现系统提示并跳转。
- 在「系统设置 → 通用 → 语言与地区 → 翻译语言」删除简体中文后按「读」键：面板应立刻显示「翻译语言尚未下载」和「下载语言…」，不应一直转圈；点按钮打开引导窗口的语言步骤。
- 首次引导窗口里来回切换三个步骤，并在第 2 步录一个会被拒绝的组合（例如 ⌥A）：窗口高度应跟着内容变化，说明文字和按钮都不被裁掉。
- 把某个快捷键改成会冲突的组合（或切换到会冲突的键盘布局）后打开菜单栏菜单：最上面应有警告项，点击打开设置的快捷键页。
- 可选的屏幕演示（都要持锁，都会抢焦点）：`TEST_RUNNER_DICT_PANEL_DEMO=1`、`TEST_RUNNER_DICT_SETTINGS_DEMO=1`、`TEST_RUNNER_DICT_TRANSLATION_LIVE=1`，分别配 `-only-testing:DictAppTests/PanelGalleryTests`、`DictAppTests/SettingsWindowTests`、`DictAppTests/AppleTranslationLiveTests` 运行 `xcodebuild test`。

## 已知差异

- 面板出现时机：M1 在 `capture` 整个返回（含剪贴板兜底）后才显示面板；走兜底的应用面板会晚于 150 ms，详见架构文档第 11.1 节。
- 「授权后自动继续」：只有在权限说明面板仍然可见时授权，才会自动重新取词；点「打开系统设置」会切到系统设置，面板随之隐藏、会话结束，回到原应用后需要再按一次快捷键。
  引导窗口的辅助功能步骤在授权后会自动进入下一步。
