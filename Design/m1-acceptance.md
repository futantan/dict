# M1 验收记录

本文逐条列出 `Design/architecture.md` 第 15.1 节的 8 条验收，写明当前状态、证据，以及还没验证的条目由谁、用哪条命令或哪些步骤来验证。
记录时间：2026-10-04，main 分支（基于 `5c5e990` 的工作区）。
第一轮记录时屏幕锁定；本次更新在解锁的真实屏幕上跑了不需要用户授权的部分（见下文「解锁后的真实屏幕验证」）。
此时 Dict Dev 还没有辅助功能授权，英语和简体中文翻译语言包也还没下载，依赖这两项的条目标为「等用户」。

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

`make e2e` 和 `make matrix` 用 `open -g -n` 启动 Dict Dev，走的是应用自己的签名身份，不借用终端的辅助功能授权。
所以在完成上面第 2 步之前，它们会报 `noAccessibilityPermission`，这不是代码缺陷。

所有会显示窗口、抢焦点、合成按键或占用剪贴板的脚本运行，前后都要加全机互斥锁：
`until mkdir /private/tmp/dict-ui.lock 2>/dev/null; do sleep 2; done; <命令>; rmdir /private/tmp/dict-ui.lock`。
`make e2e`、`make matrix` 和 `scripts/e2e-selftest.sh` 的驱动自己持锁，不要在外面再套一层，否则会等死。

## 8 条验收

### 1. `make lint test` 通过

状态：已通过（2026-10-04；本次改动只涉及测试和驱动，改动后重跑 `make generate build test lint` 仍通过，零警告；Release 构建没有重跑）。
命令：`make generate build test lint`，以及 `CONFIG=Release make build`。
结果：构建零警告；`make lint` 无输出；`test-core` 的 Swift Testing 145 个测试全部通过；`test-app`（`xcodebuild test`）退出码 0；`smoke` 输出 `smoke-test: PASS: "Dict Dev" … launched, showed its menu bar item, quit`；Release 构建退出码 0。
复验：任何人或脚本在仓库根目录运行同样的命令。

### 2. `make e2e` 通过

状态：等用户（完成前置条件 2：给 Dict Dev 授权辅助功能）。
驱动自检已通过：`scripts/e2e-selftest.sh` 输出 `selftest: PASS`（夹具 70 项检查全过，驱动对正确、错误、无入口三个假应用的判定都对，剪贴板已恢复）。
`make e2e` 实际结果：`e2e: --e2e entry point present`，13 个场景都失败在同一行原因上，例如 `FAIL  plain text view (capture 0.2 ms): expected success, got failure noAccessibilityPermission`，这是缺授权，不是代码缺陷。
验证者：脚本，用户授权后由 agent 或人运行。
命令：先跑驱动自检 `scripts/e2e-selftest.sh`，再跑 `make e2e`。
通过标准：夹具的 `NSTextView`、`NSTextField`、`WKWebView` 三种控件经无障碍取到的文字与预期一致、来源是 `accessibility`、拷贝事件数为 0；自绘控件经菜单栏拷贝项取到文字；密码框返回 `secureField` 且没有任何拷贝事件；所有场景前后剪贴板哈希一致。
说明：`make e2e` 走 `--e2e` 调试入口和 M1.4 的读取器，不经过本次新增的会话协调者；本次改动只让 `--e2e` 启动时不启动快捷键、权限监听和引导窗口。

### 3. `make matrix` 输出并人工确认

状态：等用户（同第 2 条，需要 Dict Dev 的辅助功能授权；授权前没有运行）。
借终端授权直接执行 `Dict Dev --e2e` 的实测已覆盖其中三个应用，见下文「解锁后的真实屏幕验证」第 2 项。
验证者：脚本跑矩阵，人确认输出。
命令：`make matrix`，结果写进 `Design/app-matrix.json` 并与上次比较。
人工确认：Chrome 热状态经无障碍取词，第一段耗时不超过 150 ms；Chrome 冷状态（隔离实例）第一次走菜单栏拷贝项且剪贴板原样，约 2 s 后同一页面走无障碍；Safari 只读文字经文本标记取到；VS Code 隔离实例第一次走兜底、之后走无障碍；TextEdit 走无障碍。

### 4. TextEdit 里读一句英文（零配置）

状态：等用户（需要前置条件 1–4 和真实按键）。
已在真实屏幕上分段验证（都不是真实按键）：TextEdit 取词走无障碍；面板不激活 Dict 也能成为 key 窗口、菜单栏仍属前台应用、Esc 隐藏后焦点交回；语言包缺失时真实面板约 0.7 s 内显示「Translation languages aren’t downloaded」和「Download Languages…」，没有转圈；日志里没有 `apple translation: panel session` 或 `direct session`，说明没有创建翻译会话，因此不会触发系统下载提示。
会话协调者的整条链路（按键 → 取词 → 面板 → 翻译）没有在真实屏幕上跑过：应用内取词需要 Dict Dev 自己的辅助功能授权。
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

状态：等用户（同第 4 条）。
不依赖屏幕的部分已验证：模型客户端和提示词由 `make eval` 覆盖（见第 8 条，首个内容 p50 0.76 s、p90 1.04 s）；降级逻辑由 `TranslationEngineTests` 和 `SessionCoordinatorTests` 用桩覆盖。
验证者：人。
步骤：

1. 完成前置条件 5。
2. 在 TextEdit 选中同一句英文，按「读」键：译文应逐步出现（流式），而不是一次性出现。
3. 连续做 10 次（每次可以换一句），然后运行 `log show --last 10m --info --predicate 'subsystem == "au.ibra.dict.dev"' | grep "first text"`，取 10 个毫秒数的中位数，应小于 1500。
4. 关掉 Wi-Fi（或拔网线），再选中一句按「读」键：面板应显示 Apple 翻译的译文，译文下方有一行说明「模型出错（网络错误），已改用 Apple 翻译。」。
5. 恢复网络。

### 6. 日志只有耗时、没有用户文字和 Key

状态：部分验证，完整检查等第 4、5 条的真实运行。
已做：本次真实屏幕运行后执行 `/usr/bin/log show --last 50m --info --predicate 'subsystem == "au.ibra.dict.dev"'`，共 80 行，其中 `panel shown` 51 行、`translation engine: appleTranslation` 1 行、取词模块 `capture failed:noAccessibilityPermission app=- … first=-1.0ms second=-1.0ms fallback=-1.0ms total=…` 13 行；用测试里用过的句子词和 `sk-` 去 grep 无命中（`second` 只命中字段名 `second=`）。
还缺：会话协调者的 `capture … via …`、`first text …`、`ended in result after …` 要等真实按键才会出现。
注意：在 fish 或 zsh 里 `log` 可能是内建命令，用 `/usr/bin/log`；info 级别日志只在内存里保留几分钟，要在操作后立即运行。
代码层面已检查：新增日志只插值会话代号、耗时、途径名、阶段名和状态名，全部是非用户数据；Key 从不进日志。
验证者：人或脚本，在第 4、5 条之后立即运行。
命令：`log show --last 10m --info --predicate 'subsystem == "au.ibra.dict.dev"'`。
通过标准：能看到每个会话的 `capture … via …`、`panel shown …`、`first text …`、`ended in result after …`，以及取词模块的 `capture accessibility app=… first=…ms` 和翻译引擎的 `translation engine: …`。
再运行 `log show --last 10m --info --predicate 'subsystem == "au.ibra.dict.dev"' | grep -iE "weather|lovely|sk-"`，应没有任何输出（把第 4、5 条用过的句子里的词和 Key 的前缀代进去）。

### 7. 没有 `dict-en-zh.sqlite` 时以上全部成立

状态：按构造成立；本次运行前后 `find ~/Library /Users/ttfu/d/dict -name 'dict-en-zh.sqlite'` 均无输出；M1 没有任何代码读取词典数据库，仓库和构建目录里也没有这个文件（`find . -name 'dict-en-zh.sqlite'` 无输出）。
验证者：做第 2–6 条时顺带确认：运行前执行 `find ~/Library /Users/ttfu/d/dict -name 'dict-en-zh.sqlite' 2>/dev/null`，应无输出。

### 8. `make eval SUITE=direction RUNS=10` 方向不变量通过率不低于 95%

状态：已通过（2026-10-04，`gpt-6-luna`，260 次调用，花费 0.0116 美元）。
结果：`targetLanguage` 259/259（100%）、`keepsQuestion` 259/259、`noPromptLeak` 259/259、`sameLineCount` 259/259、`noAnswer` 257/259（99.2%）、`keepsVerbatim` 48/50（96%）、`completed` 259/260（1 次首个事件超时）；脚本结论 `PASS`。
复验：`make eval SUITE=direction RUNS=10`（Key 由脚本从 `.env` 读取，不打印）。

## 解锁后的真实屏幕验证（2026-10-04）

只借终端的辅助功能授权，不需要用户操作；每次运行都持全机互斥锁。

1. 驱动自检 `scripts/e2e-selftest.sh`：`selftest: PASS`。
   修掉一个自检缺陷：前面的选择测试把 `textView.plain` 和 `web.textarea` 的内容换掉了，后面的拷贝、粘贴检查还按原文选择，选不中，焦点留在上一个控件上，于是报 4 项失败；现在每一步自己设定内容并检查选择成功。
2. 真实应用取词：直接执行 `"build/DerivedData/Build/Products/Debug/Dict Dev.app/Contents/MacOS/Dict Dev" --e2e scenario.json --e2e-out result.json`，结果写进 JSON。
   TextEdit 与 Safari 用场景 `{"steps":[{"capture":{"policy":"allowed"}},{"capture":{"policy":"never"}}]}`；Chrome 冷状态在前面加一次取词和 `{"wait":{"ms":2500}}`。
   TextEdit 打开一个两句英文的文稿并用无障碍选中一个词；网页用 `python3 -m http.server 8765 --bind 127.0.0.1 --directory spikes/fixtures` 提供的 `http://127.0.0.1:8765/page.html?mode=readonly&sel=word`。
   TextEdit 两次都走 `accessibility`，28.8 ms 和 1.1 ms，`warmup=notNeeded`。
   Safari 只读网页文字两次都走 `accessibility`（文本标记），44.5 ms（第一段 40.8 ms）和 1.3 ms；剪贴板前后哈希一致。
   Chrome 冷状态第一次走 `menuCopy`，71.9 ms（兜底 38 ms），`warmup=justEnabled`；等 2.6 s 后同一页面走 `accessibility`，7.6 ms 和 1.6 ms，`warmup=warm`；剪贴板内容哈希前后一致（`changeCount` 加 2，即兜底拷贝后已原样写回）。
   测后把 Chrome 的 `AXEnhancedUserInterface` 恢复为原值 0，Chrome 标签页总数与测前一致，只关了测试页。
3. 面板上屏演示 `TEST_RUNNER_DICT_PANEL_DEMO=1 xcodebuild test … -only-testing:'DictAppTests/PanelGalleryTests/demoOnScreen()'`：通过。
   每个状态下面板都是 key 窗口，前台应用和菜单栏都仍是 Finder，面板顶边位于选区下方 8 pt；流式增长时顶边不动；Esc 隐藏、回调 `.escape`，之后 Dict 不再持有 key 窗口。
   Esc 是用 `window.sendEvent` 送入的合成 `NSEvent`，不是真实按键；「接收键盘」的证据是面板为 key 窗口且按键路由正确，真实键盘输入要在第 4 条人工确认。
   修掉一个测试缺陷：非激活面板成为 key 窗口时 `NSApp.isActive` 为真，但前台应用和菜单栏不变；原断言 `!NSApp.isActive` 因此在真实屏幕上必然失败，现改为断言 `menuBarOwningApplication` 不变，`AppleTranslationLiveTests` 里的同类断言一并改正。
4. 设置窗口上屏演示 `TEST_RUNNER_DICT_SETTINGS_DEMO=1 xcodebuild test … -only-testing:'DictAppTests/SettingsWindowTests/demoOnScreen()'`：通过（窗口成为 key、切换标签页时顶边不动、标题跟随、关闭后不可见）。
   修掉一个测试缺陷：测试宿主在后台启动，macOS 会忽略它的 `NSApp.activate()`，窗口成不了 key；演示现在先经 Launch Services 激活自己，相当于真实应用里用户点菜单栏图标。
   深色模式选中标签页：离屏渲染（`DICT_SETTINGS_RENDER_DIR`）里选中项是一块白色、文字看不见，但浅色模式同样是一块白色，只是与背景同色；在屏上把窗口切到深色后检查视图树，选中项背景是系统的 `NSGlassView`，外观为 `NSAppearanceNameVibrantDark`，没有纯色图层。
   结论：白块是玻璃材质无法离屏渲染的退化，视图树里没有找到缺陷；屏上像素需要人眼确认（不允许截屏）。
5. Apple 翻译：`reportsLanguageStatus()` 报 `en → zh-Hans: supported`、`zh-Hans → en: supported`（未安装），所以 `AppleTranslationLiveTests` 的翻译用例等用户下载语言包；`engineWithoutAModelUpdatesThePanel()` 在真实面板上得到的是 `needsSetup`「Translation languages aren’t downloaded」，与语言包缺失时的预期一致。

## 本次串联的其他人工检查（解锁后）

- 面板里只选中译文的一部分再按 ⌘C，粘贴出来应只有选中的部分；什么都不选按 ⌘C 应复制整段译文。
  单测 `PanelSelectionCopyTests` 只验证了按键路由，真实点选没有验证。
- 默认中英配对下选中日文 `会議は明日の午後三時に開始します。` 按「读」键，应译成中文而不是英文。
- 按「写」键：M1 没有动作，面板不出现，日志里有一行 `write shortcut pressed`。
- 撤销 Dict Dev 的辅助功能授权（在系统设置里关掉开关）后按「读」键：面板说明需要辅助功能权限，按快捷键时不应弹出任何系统对话框；点「打开系统设置」才可能出现系统提示并跳转。
- 在「系统设置 → 通用 → 语言与地区 → 翻译语言」删除简体中文后按「读」键：面板应立刻显示「翻译语言尚未下载」和「下载语言…」，不应一直转圈；点按钮打开引导窗口的语言步骤。
- 首次引导窗口里来回切换三个步骤，并在第 2 步录一个会被拒绝的组合（例如 ⌥A）：窗口高度应跟着内容变化，说明文字和按钮都不被裁掉。
- 把某个快捷键改成会冲突的组合（或切换到会冲突的键盘布局）后打开菜单栏菜单：最上面应有警告项，点击打开设置的快捷键页。
- 设置窗口在深色模式下：选中的标签页文字清晰可读，没有被白块盖住（只能人眼看，见上文第 4 项）。
- 屏幕演示（都要持锁，都会抢焦点）：`TEST_RUNNER_DICT_PANEL_DEMO=1`、`TEST_RUNNER_DICT_SETTINGS_DEMO=1`、`TEST_RUNNER_DICT_TRANSLATION_LIVE=1`，分别配 `-only-testing:'DictAppTests/PanelGalleryTests/demoOnScreen()'`、`'DictAppTests/SettingsWindowTests/demoOnScreen()'`、`DictAppTests/AppleTranslationLiveTests` 运行 `xcodebuild test`。
  Swift Testing 的用例名要带 `()`，否则 `xcodebuild` 静默执行 0 个测试。
  `AppleTranslationLiveTests` 要在语言包下载完之后跑。

## 已知差异

- 面板出现时机：M1 在 `capture` 整个返回（含剪贴板兜底）后才显示面板；走兜底的应用面板会晚于 150 ms，详见架构文档第 11.1 节。
- 「授权后自动继续」：只有在权限说明面板仍然可见时授权，才会自动重新取词；点「打开系统设置」会切到系统设置，面板随之隐藏、会话结束，回到原应用后需要再按一次快捷键。
  引导窗口的辅助功能步骤在授权后会自动进入下一步。
