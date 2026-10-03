# M1 任务的文件归属

本文是 M1.0 契约落地的产物，规定 M1.1–M1.11 每个任务拥有哪些文件、要实现什么、不能改什么。
目的是让同一批的任务并行开发时基本不改同一个文件。
任务内容和验收以 `Design/architecture.md` 第 15.1 节为准。

## 共享约定

### 冻结的共享文件

下面这些文件只能由 manager 改；任务觉得需要改时，先停下来说明理由，由 manager 改文档和代码。

- 契约（`DictApp`）：`App/Sources/Capture/CaptureContract.swift`、`App/Sources/Replace/ReplaceContract.swift`。
- 契约（`DictCore`）：`Text/LanguagePair.swift`、`Text/ContextSentence.swift`、`Model/JSONValue.swift`、`Model/ModelEndpoint.swift`、`Model/ModelRequest.swift`、`Model/TextModel.swift`、`Engine/Engine.swift`（都在 `Packages/DictCore/Sources/DictCore/` 下）。
- 存根文件里的函数签名也是契约：任务只替换函数体，不改签名、不改同文件里的类型。
- 日志：`App/Sources/Support/Log.swift`。
- 工程：`project.yml`、`Packages/DictCore/Package.swift`、`Makefile`、`Config/`、`.swift-format`、`.gitignore`。
- 文档：`Design/architecture.md`、本文、`README.md`。

### 已经预建好的东西

- `CaptureFixture` target（`Fixtures/CaptureFixture/Sources`，可选资源目录 `Fixtures/CaptureFixture/Resources`）已在 `project.yml` 里，随 `DictApp` scheme 一起构建，`make build` 会编译它。
- `DictEval` 可执行 target 已在 `Package.swift` 里，源码目录 `Packages/DictCore/Sources/DictEval/`。
- `DictCore` target 已声明资源目录 `Packages/DictCore/Sources/DictCore/Resources/`（`.process`），预设表是其中的 `ProviderPresets.json`，用 `Bundle.module` 读取。
- `make e2e`、`make matrix`、`make eval` 分别调用 `scripts/e2e.sh`、`scripts/matrix.sh`、`scripts/eval.sh`；任务只改脚本，不改 `Makefile`。
- `make e2e` 和 `make matrix` 先跑 `make build`，脚本的第一个参数是 `CONFIG`；`make eval` 把 `SUITE`、`RUNS` 作为环境变量传给脚本。
- 新增的 Swift 源文件只要放进 `App/Sources/`、`App/Tests/`、`Fixtures/CaptureFixture/Sources/`、`Packages/DictCore/Sources/`、`Packages/DictCore/Tests/` 下就会被构建，`make generate` 自动收进工程。

### 日志

- 只用 `Log.capture`、`Log.replace`、`Log.model`、`Log.store`、`Log.ui` 这五个 `Logger`，子系统是 bundle id。
- 记录阶段耗时、走了哪条途径、无障碍错误码、HTTP 状态、token 用量、应用 bundle id。
- 从不记录用户的文字和 Key；插值的非用户数据用 `privacy: .public`，其余保持默认的 private。
- `DictCore` 不写日志，也不 import `os`。

### 界面文案

- 每个界面区域一张 String Catalog，放在 `App/Resources/` 下，由拥有该区域的任务新建和维护。
- 代码里写 `String(localized: "…", table: "<表名>", comment: "…")`，英文是源语言，同时填好简体中文。
- 表名：`Localizable`（菜单等全局文案，M1.11）、`Capture`（M1.4）、`Hotkeys`（M1.6）、`Panel`（M1.7）、`Translation`（M1.8）、`Settings`（M1.9）、`Permissions`（M1.10）。
- `DictCore` 不含面向用户的文案。

### 测试

- `DictCore` 的测试放在 `Packages/DictCore/Tests/DictCoreTests/<区域>/`，应用测试放在 `App/Tests/<区域>/`，区域名与源码目录一致。
- 快照、SSE 夹具这类测试数据直接写成测试源码里的字符串字面量，不加测试资源，这样不用改 `Package.swift`。
- 每个 Swift 文件开头带 `// SPDX-License-Identifier: GPL-3.0-or-later`。
- 不给存根写测试；测试不能调用别的任务还没实现的存根，存根会 `fatalError`。

### 端到端接口（M1.4 与 M1.5 之间）

两边按下面的最小约定并行开发，只能增加字段，不能改已有字段的含义。

- 启动：`open -n "<Dict Dev.app>" --args --e2e <scenario.json> --e2e-out <result.json>`；这段入口只在 `#if DEBUG` 里编译。
- 场景文件：`{"steps": [<step>, …]}`，按顺序执行，任何一步出错都照常写结果并继续下一步。
- 步骤 `{"select": {"control": "<id>", "text": "<要选中的文字>"}}`：应用发出分布式通知让夹具选中文字，然后等 200 ms。
- 步骤 `{"capture": {"policy": "allowed" | "never"}}`：调用 `SelectionReader.capture(policy:)`。
- 步骤 `{"wait": {"ms": <整数>}}`：等待。
- 结果文件：`{"steps": [{"step": "capture", "ok": true, "ms": 12.5, "source": "accessibility", "text": "…", "failure": null}, …]}`，`failure` 是 `CaptureFailure` 的 case 名，`source` 是 `CaptureSource` 的 case 名。
- 夹具命令通道：分布式通知 `au.ibra.dict.fixture.command`，`userInfo` 为 `{"command": "select", "control": "<id>", "text": "…"}`。
- 夹具事件日志：启动参数 `--log <path>` 指定的 JSON Lines 文件，每行 `{"time": <秒>, "control": "<id>", "event": "copy" | "paste" | "axWrite" | "select", "detail": "…"}`。
- 控件标识（同时是无障碍标识）：`textView.plain`、`textView.rich`、`textField`、`secureField`、`swiftui.textField`、`swiftui.textEditor`、`web.paragraph`、`web.textarea`、`web.contenteditable`、`custom.noSelectedText`、`custom.empty`、`custom.copiesLine`。
- 网页控件的选中由夹具应用内的 `WKWebView` 执行脚本完成；真实浏览器的矩阵由 `scripts/matrix.sh` 用带查询参数的地址选中，不走这个通道。

## 第一批（可以同时开始）

### M1.1 方向判定

- 拥有：`Packages/DictCore/Sources/DictCore/Text/ResolveDirection.swift`、`Text/NormalizedKey.swift`。
- 拥有：`Packages/DictCore/Tests/DictCoreTests/Text/` 下新建的测试文件。
- 实现：`resolveDirection(_:pair:)`（第 5.2 节）和 `normalizedKey(_:)`（第 5.3 节），表驱动单测覆盖中英、混写、同书写系统、第三种语言。
- 可以在 `Text/` 下新建私有辅助文件，例如书写系统统计。
- 不能改：`Text/LanguagePair.swift` 和其他冻结文件。

### M1.2 模型客户端

- 拥有：`Packages/DictCore/Sources/DictCore/Model/RequestBody.swift`，以及在 `Model/` 下新建的文件（例如 `ChatCompletionsModel.swift`、`SSEParser.swift`、`ProviderPresets.swift`）。
- 拥有：`Packages/DictCore/Sources/DictCore/Resources/ProviderPresets.json`。
- 拥有：`Packages/DictCore/Tests/DictCoreTests/Model/` 下新建的测试文件。
- 实现：`requestBody(_:endpoint:rules:)`、预设表（OpenAI、Ollama、自定义）与读取函数、SSE 解析、遵循 `TextModel` 的 `ChatCompletionsModel`、错误映射、400 去参数重试、看门狗（可注入时钟）、取消。
- `JSONValue` 已在 M1.0 完整实现；需要字面量写法时在自己的新文件里加 `ExpressibleBy…Literal` 扩展，不改 `JSONValue.swift`。
- 不能改：`Model/JSONValue.swift`、`Model/ModelEndpoint.swift`、`Model/ModelRequest.swift`、`Model/TextModel.swift`、`Package.swift`。

### M1.3 翻译提示词

- 拥有：`Packages/DictCore/Sources/DictCore/Prompt/`（新建，例如 `PromptBuilder.swift`）。
- 拥有：`Packages/DictCore/Sources/DictEval/` 全部文件和 `scripts/eval.sh`。
- 拥有：`Packages/DictCore/Tests/DictCoreTests/Prompt/` 下新建的测试文件。
- 实现：`PromptBuilder` 的两种翻译提示词（已定方向、回落）、由调用方传入的随机后缀，快照测试锁住输出。
- 实现：`DictEval` 的方向和注入套件；评测部分要等 M1.2 的 `ChatCompletionsModel` 合并后再接上。
- `scripts/eval.sh` 从 `.env` 读 `OPENAI_API_KEY` 放进子进程环境，不打印。
- 不能改：`Model/` 下的任何文件、`Package.swift`、`Makefile`。

### M1.4 取词

- 拥有：`App/Sources/Capture/` 下除 `CaptureContract.swift` 以外的全部文件（新建）。
- 拥有：`App/Sources/E2E/`（新建，`--e2e` 场景执行器的取词部分）。
- 拥有：`App/Tests/Capture/`、`App/Tests/E2E/`、`App/Resources/Capture.xcstrings`。
- 实现：遵循 `SelectionReader` 的读取器、无障碍串行队列与消息超时、`AppKind` 判定（纯函数，终端和 Chromium 名单作为数据，第 3.3 节）、预热、第一段读取、选区矩形、菜单栏拷贝项、定向 ⌘C、`ClipboardGateway`、安全输入与权限失败、各阶段耗时日志。
- `ClipboardGateway` 放在 `App/Sources/Capture/ClipboardGateway.swift`，以后 `ReplaceWriter` 复用它。
- 唯一允许改的共享文件：在 `App/Sources/AppDelegate.swift` 的 `main()` 里加一处 `#if DEBUG` 的 `--e2e` 入口调用，不改其他行。
- 不能改：`CaptureContract.swift`、`ReplaceContract.swift`、`Log.swift`、`StatusMenu.swift`。

### M1.5 夹具与驱动

- 拥有：`Fixtures/` 全部文件（夹具源码、`Fixtures/CaptureFixture/Resources/`、本机 HTTP 夹具页）。
- 拥有：`scripts/e2e.sh`、`scripts/matrix.sh`，以及在 `scripts/` 下新建的辅助脚本。
- 拥有：`Design/app-matrix.json`（脚本生成，不手改）。
- 实现：`CaptureFixture` 的非撒谎控件和三种网页控件、命令通道、事件日志；`make e2e` 和 `make matrix` 的驱动。
- 场景格式和夹具接口按上面的「端到端接口」；需要新字段时与 M1.4 经 manager 约定。
- 不能改：`project.yml`、`Makefile`、`App/` 下的任何文件。

### M1.6 快捷键

- 拥有：`App/Sources/Hotkeys/`（新建）、`App/Tests/Hotkeys/`、`App/Resources/Hotkeys.xcstrings`。
- 实现：Carbon `RegisterEventHotKey` 注册与改键回滚、组合校验（纯函数加 `UCKeyTranslate` 查询）、输入源切换时重新校验、录制控件、首次引导里的选键步骤视图、两个组合的持久化。
- 选键步骤做成独立的 SwiftUI 视图，由 M1.11 放进首次引导窗口；设置窗口（M1.9）复用录制控件。
- 不能改：`AppDelegate.swift`、`StatusMenu.swift`、其他任务的目录。

### M1.7 结果面板

- 拥有：`App/Sources/Panel/`（新建）、`App/Tests/Panel/`、`App/Resources/Panel.xcstrings`。
- 实现：`NSPanel` 子类、SwiftUI 视图的各状态（读取中、生成中、结果、错误、需要设置）、定位计算（纯函数）、隐藏规则、输入法组字判断、输入框。
- 面板对外只暴露显示、更新状态、隐藏三类调用，供 M1.11 串联；「需要设置」状态接收调用方给的内容，具体文案归 M1.10。
- 不能改：`AppDelegate.swift`、契约文件、其他任务的目录。

## 第二批

### M1.8 翻译引擎

- 拥有：`App/Sources/Translation/`（新建）、`App/Tests/Translation/`、`App/Resources/Translation.xcstrings`。
- 拥有：`Packages/DictCore/Sources/DictCore/Engine/EngineSelection.swift`，以及在 `Engine/` 下新建的文件（例如用 `TextModel` 和 `PromptBuilder` 实现 `Translator` 的模型翻译器）。
- 拥有：`Packages/DictCore/Tests/DictCoreTests/Engine/`。
- 实现：`engine(for:modelConfigured:appleTranslationSupportsPair:)`、Apple 翻译框架的 `Translator`（macOS 15 用 `.translationTask`，26 起直接构造）、模型 `Translator`、模型失败时的降级。
- M1.7 合并后，允许在面板的 SwiftUI 视图上挂 `.translationTask` 修饰符，只加这一处。
- 不能改：`Engine/Engine.swift`、`Model/` 下的契约文件、`Prompt/`。

### M1.9 设置与密钥

- 拥有：`App/Sources/Settings/`（新建，含 Keychain 读写）、`App/Tests/Settings/`、`App/Resources/Settings.xcstrings`。
- 拥有：`Packages/DictCore/Sources/DictCore/Preferences/`（新建，偏好设置的 `Codable` 值类型）和对应测试目录。
- 实现：语言与口音、服务商与模型、Key 存 Keychain（service `<bundle id>.model`，account 是预设 id）、「测试」按钮。
- 唯一允许改的共享文件：在 `StatusMenu.swift` 里加「设置…」菜单项，并更新 `App/Tests/StatusMenuTests.swift` 的对应断言。
- 不能改：`Model/` 下的文件、`AppDelegate.swift`。

### M1.10 权限引导

- 拥有：`App/Sources/Permissions/`（新建）、`App/Tests/Permissions/`、`App/Resources/Permissions.xcstrings`。
- 实现：辅助功能与 PostEvent 权限检查、面板「需要设置」状态里的说明与跳转、`com.apple.accessibility.api` 通知监听（延迟 300 ms 重读）。
- 不能改：`App/Sources/Panel/`（只通过面板暴露的接口提供内容）、`Capture/` 下的文件。

## 最后

### M1.11 串联

- 拥有：`App/Sources/Session/`（新建，会话协调者）、`App/Sources/Onboarding/`（新建，首次引导窗口）。
- 拥有：`App/Sources/AppDelegate.swift`、`App/Sources/StatusMenu.swift`、`App/Resources/Localizable.xcstrings`、`App/Tests/AppBundleTests.swift`、`App/Tests/StatusMenuTests.swift`。
- 实现：会话代号与取消、读键 → 取词 → 面板 → 翻译的串联、各阶段耗时日志、首次引导窗口，跑第 15.1 节的全部验收。
- 可以更新 `README.md` 的功能说明。
- 不能改：契约文件；需要改其他任务目录里的代码时，只做串联所需的最小改动并在交付说明里列出。
