# 用 ChatGPT 登录：实现记录

2026-10-24 写。
设计依据是 `docs/reviews/chatgpt-login.md`（第 4 节设计、第 6 节文件清单），加上 manager 对照官方文档给的修正。
全部代码自己写，没有拷贝 Codex CLI、Sign in with ChatGPT DevKit 或 `research/` 里任何项目的代码，它们只作协议参考。
没有做真实的 OAuth 登录，也没有调用任何真实的模型接口；所有测试都打本机 mock 或 `URLProtocol` 桩。

## 1. 结果

新增服务商 `chatgpt`（分段控件「不使用 · OpenAI · ChatGPT · Ollama · 自定义」）。
它不用 API Key，而是在系统浏览器里走 Sign in with ChatGPT 开源通道，请求打 `https://api.openai.com/v1/responses`，消耗用户 ChatGPT 套餐的额度。
`make generate build test lint` 全部通过。
屏幕处于锁定状态（`IOConsoleLocked` 为 true），没有在真实界面上点完 mock 端到端；替代做法见第 5 节。

## 2. 结构

DictCore（纯逻辑，iOS 可复用）：

- `ChatGPT/ChatGPTEndpoints.swift`：issuer、authorize、token、revoke、api 五个地址；`production` 和 `mock(baseURL:)`。
- `ChatGPT/ChatGPTCredential.swift`：`ChatGPTCredential`（令牌、过期时间、授予的 scope、`canUsePlan`）、`ChatGPTRegistration`（本机 host id、签发的 client id、上次的邮箱）、`CredentialStore` 协议。
- `ChatGPT/ChatGPTAuth.swift`：PKCE、`AuthorizationAttempt`（授权 URL、回调解析）、换码 / 刷新 / 吊销的表单请求、令牌响应解析、ID token 声明校验、`exchangeAuthorizationCode`。
- `ChatGPT/ChatGPTSession.swift`：actor，持有凭据，单飞刷新，`AccessTokenSource` 协议。
- `Model/ResponsesBody.swift`、`Model/ResponsesStreamDecoder.swift`、`Model/ResponsesModel.swift`：请求映射、SSE 解码、错误映射、`TextModel` 实现和 `listChatGPTModels`。
- 改动：`ModelError` 加 `signInRequired`、`planUsageNotGranted`、`planNotEligible`、`planLimitReached`；`ProviderPreset` 加 `wire`（`chatCompletions` / `chatGPT`）；`ModelListStyle` 加 `chatGPT`；`ModelSetupIssue` 加 `notSignedIn`；`ModelConfiguration` 带上 `wire`；预设表加 `chatgpt` 一行。

DictApp：

- `Settings/ChatGPTAccount.swift`：`KeychainCredentialStore`、`RegistrationStore`（都建在现有 `SecretStore` 上），和进程内唯一的 `ChatGPTAccount.app`（共享一个 `ChatGPTSession`）。
- `Settings/ChatGPTSignIn.swift`：登录编排和 `LoopbackReceiver`（`NWListener`）。
- `Settings/ChatGPTSettingsViews.swift`、`Settings/ChatGPTStrings.swift`：账号行、按钮、模型菜单、首次说明弹窗和文案。
- 改动：`ModelSetup.swift`（`makeTextModel` 按 `wire` 选客户端，四个工厂共用）、`SettingsModel.swift`（登录状态、登录 / 取消 / 退出、模型列表）、`ModelSettingsSection.swift` 和 `SettingsPanes.swift`（设置页卡片和引导页表单）、`SettingsStrings.swift`、`TranslationStrings.swift`、`SessionCoordinator.swift`（面板的「Manage usage」动作）、两个 String Catalog。

没有改 `MainWindowController.swift`、`MainWindowView.swift`、`SettingsPage.swift`、`WindowComponents.swift`、`WindowTheme.swift`、`MainWindowTests.swift`、`Design/app-matrix.json`。

## 3. 协议实现要点

授权：

- 在系统浏览器打开 `https://auth.openai.com/api/accounts/authorize`。
- 首次登录带 `client_id=dynamic_agent_client` 和 `agent_name_hint=Dict`；之后用签发的 client id，并带 `login_hint`（上次的邮箱）和 `id_token_hint`。
- 每次都带 `ext_agent_host_id`：`urn:uuid:<UUIDv4>`，每台 Mac 生成一次，存 Keychain，退出登录也不删。
- 参数：`response_type=code`、`redirect_uri`、`scope=openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`、`resource=https://api.openai.com/v1`、`state`、`nonce`、PKCE S256。
- 回调地址是 `http://127.0.0.1:<port>/auth/callback`，从不用 `localhost`；监听显式绑定 IPv4 回环。
- 先起监听、拿到端口，再开浏览器；先试 1455，被占用就让系统分配。
- 回调先校验 `state`，再看 `error`，再取 `code`；首次登录回调里签发的 `client_id` 在换码之前就写进 Keychain。
- 监听只接受 `GET /auth/callback`，其他路径（如浏览器的 favicon）回 404 并继续等；5 分钟超时。

令牌：

- 换码、刷新都是表单 POST 到 `/api/accounts/oauth/token`，带签发的 client id 和 `resource`，没有 secret；换码时的 `redirect_uri` 与授权时完全一致。
- 刷新不带 `scope`，保留原授权；访问令牌、过期时间、scope 和轮换后的刷新令牌一起替换并写回 Keychain。
- 退出登录先清本地，再向 `/api/accounts/oauth/revoke` 吊销刷新令牌；吊销没得到 2xx 时界面提示去 ChatGPT 设置里手动断开。
- 能否用套餐只看令牌响应里授予的 scope 是否含 `chatgpt.tokens.use.direct`，ID token 本身不代表可以推理。
- ID token 用 base64url 加 `JSONDecoder` 解出声明，校验 `iss`、`aud`（签发的 client id）、`exp`（留 60 秒余量）和 `nonce`；不验签，没有引入任何 JWT 或加密依赖（PKCE 的 SHA-256 用系统的 CryptoKit）。

会话：

- `ChatGPTSession` 是 actor，全进程一个实例（`ChatGPTAccount.app`），设置、翻译、纠错、卡片共用，避免并发刷新触发 `refresh_token_reused`。
- 距过期不足 5 分钟、且已过 `earliest_refresh_at` 时刷新；已过期则不管 `earliest_refresh_at` 直接刷新。
- 刷新单飞：进行中的刷新是一个 `Task`，并发调用者等同一个结果。
- 请求收到 401：`rejected(token)` 后刷新一次、重试一次；第二次 401 报 `unauthorized`。
- 刷新得到 `invalid_grant`、`invalid_refresh_token`、`token_expired`、`refresh_token_expired`、`refresh_token_invalidated`、`refresh_token_reused` 或 `invalid_client`：清掉凭据，报 `signInRequired`，界面回到「Continue with ChatGPT」并说明登录已失效。
- 网络错误和 5xx：凭据不动，照常报错。
- 取令牌放在看门狗计时之前，刷新慢不算模型首字慢。

推理：

- `POST <api>/responses`，`Authorization: Bearer <access token>`。
- 恒带 `store: false`、`stream: true`；系统提示放 `instructions`；`input` 只有一条 user 消息。
- 从不发送 `max_output_tokens`、`temperature`、`top_p`、`metadata`、`user`、`truncation`、`previous_response_id`、`prompt_cache_retention`、`safety_identifier`。
- `reasoning.effort` 和 `text.format` 的 `json_schema` 严格模式照 OpenAI 线路发送：思考片段写在 `chatgpt` 预设里，形状是 `{"reasoning": {"effort": "none"}}`。
- 服务端若以 400 拒绝，错误按 `ModelError.badRequest` 原样显示服务端消息，并附上 `error.param`（例如「Unsupported parameter (reasoning.effort)」）；不做丢参重试，也没有其他推测性的降级。
- 流事件：`response.output_text.delta` 是正文，`response.reasoning_*_text.delta` 只算思考，`response.completed` 是唯一的成功，`response.incomplete` 按原因映射成截断或拒绝，`response.failed` 和 `error` 按 `error.code` 抛错。
- 错误码先按 `error.code` 映射（额度用尽 → `planLimitReached`，不合格或授权上下文不允许 → `planNotEligible`，额度或用户信息暂不可用 → 503，`invalid_user` → `unauthorized`，`unsupported_capability` → `badRequest`），再按 HTTP 状态；`{"detail": …}` 形状也能读。

模型列表：

- `GET <api>/models`，带访问令牌；只取 `visibility == "list"` 的 `slug`，保留服务器顺序。
- 没有白名单，也不写死默认模型；登录后自动拉列表：当前模型在列表里就保留，否则选 OpenAI 预设的默认模型（`gpt-6-luna`）如果它在列表里，再否则选第一项。
- 已登录状态下启动应用，也会自动拉列表。

## 4. 与设计文档的偏离

- 不验 ID token 签名，按 manager 的修正只校验声明；因此没有 `JWKSVerifier.swift`，mock 发的是不签名的 JWT。
- 不做 400 丢参重试（设计文档 4.4 的候选列表），拒绝就原样报给人看。
- 流在没有终态事件时结束：有过事件就当作 `.finished(.unknown)`（界面显示「连接中断」，与 Chat Completions 路径一致），一个事件都没有才是 `emptyResponse`；设计文档写的是 `malformedResponse`。
- `invalid_client` 也算刷新终态错误；授权回调或换码遇到 `invalid_client` 时清掉保存的 client id，下次重新走 `dynamic_agent_client` 注册，避免「重新连接」一直用一个失效的 client id。
- `earliest_refresh_at` 的格式文档没写，Unix 秒和 ISO 8601 都接受。
- 模型菜单显示 `slug`，没有显示 `display_name`：这样 `ModelListStatus` 和现有菜单不用改形状。
- 设置页分段控件多了一段，为了在最窄的窗口里放得下，段内边距从设计稿的 14 改成 12（`ModelSettingsSection.swift`）。
- 引导页（`OnboardingModel`）没有单独改：它显示的就是 `ModelSections`，选中 ChatGPT 时同样出现账号行和按钮。
- `docs/decisions.md` 在 git 之外，没有改；决定记录在本文和 `Design/architecture.md` 2.2。

## 5. 测试

DictCore（`swift test`，490 个）：

- `ChatGPTAuthTests`：RFC 7636 附录 B 的 PKCE 向量、首次和之后两种授权 URL、mock 地址、回调的 state / error / code、三种表单请求、令牌响应解析、scope 判断、ID token 各声明失败的用例、用桩换码。
- `ChatGPTSessionTests`：未过期不刷新、临近过期刷新并写回轮换令牌、`earliest_refresh_at`、十个并发调用只刷新一次、终态错误清凭据、5xx 和断网保留凭据、`rejected` 之后刷新、退出登录吊销、吊销未确认也清本地。
- `ResponsesBodyTests`、`ResponsesStreamDecoderTests`、`ResponsesModelTests`：请求体快照和禁发字段、事件解码、拆在两块之间的 UTF-8、设计文档 2.7 节每个错误码、401 刷新重试一次、第二次 401、400 不丢参只发一次、流中 `response.failed`、慢刷新不触发看门狗、模型列表。
- `MockChatGPTWireTests`：真实客户端对 `scripts/fake-model.py`，走授权 302、回调解析、换码、列表、流式翻译和严格 schema 的纠错。

mock（`make test-mock`）：`scripts/fake-model.py` 新增 `/auth/api/accounts/authorize`、`/auth/api/accounts/oauth/token`、`/auth/api/accounts/oauth/revoke`、`/chatgpt/v1/models`、`/chatgpt/v1/responses`。
它用 SHA-256 校验 PKCE，校验回调地址必须是 `127.0.0.1`，拒绝 `store` 不为 false、`stream` 不为 true、system 角色输入项和所有不支持的字段（返回 `subscription_sharing_unsupported_capability` 和 `param`），模型 `mock-limit` 返回额度用尽。
`scripts/fake-model-test.py` 加了 8 个对应用例。

DictApp（`make test-app`）：

- `ChatGPTSignInTests`：真实回环监听，测试扮演浏览器；首次注册、复用注册、伪造 state、拒绝授权、`invalid_client` 清 client id、端口被占用时换端口、超时、请求行解析。
- `KeychainCredentialStoreTests`：凭据往返、注册在退出登录后保留、mock 用独立的 Keychain 账号（`chatgpt-mock`、`chatgpt-mock-host`）。
- `ChatGPTSettingsTests`、`ChatGPTModelSetupTests`：设置页状态机、自动选模型、首次说明只弹一次、未授权额度、登录失败、退出登录、`DICT_MOCK_MODEL` 下 ChatGPT 仍走自己的线路。
- `ChatGPTMockSignInTests`：应用进程内的完整路径，相当于没有点击的 `make run-mock`。
  它启动 `fake-model.py`，用真实的 `SettingsModel`、`ChatGPTSignIn`、`NWListener`、令牌交换、模型列表和 `ResponsesModel` 走「登录 → 列表 → 测试按钮的翻译和严格 schema 两个请求 → 退出登录（吊销得到确认）」，只有浏览器由测试扮演；通过。
- `SettingsGalleryTests` 加了 ChatGPT 的六种状态（未登录、登录中、登录失败、已登录可用、额度用尽、未授权额度），浅色和深色都渲染检查过。

真实界面的 mock 端到端没有跑：检查时屏幕是锁定的。
屏幕解锁后的手动步骤：`make run-mock`，打开主窗口「设置 → 模型」，选 ChatGPT，点「Continue with ChatGPT」；默认浏览器会打开 `127.0.0.1:8767/auth/…` 并立刻跳回 Dict，显示「Signed in as mock@example.com」、模型 `mock`；点「测试」两项都应通过；`build/mock-model.log` 应依次出现 `302 authorize`、`200 token authorization_code`、`200 chatgpt models`、`200 responses translation`、`200 responses proofread`，退出登录后是 `200 revoke`。
mock 的令牌只存在进程内存里，mock 重启后旧令牌失效，应用会提示重新登录，这是预期行为。

## 6. 界面与文案

文案照 `https://developers.openai.com/siwc/ui-ux-guidelines`：

- 未登录：标题「Use your ChatGPT plan」，说明「Complete eligible AI requests in this app with usage included in your ChatGPT plan or credits balance.」，按钮「Continue with ChatGPT」。
- 已登录：「Signed in as …」，下面是「Using ChatGPT plan」和「Manage usage」链接（`https://chatgpt.com/settings/usage`），右边「Sign Out」。
- 首次带额度登录成功后弹一次：「You’re using your ChatGPT plan」/「Eligible usage in this app uses your ChatGPT plan. Manage usage in your ChatGPT settings.」/「Got it」，之后不再弹。
- 额度用尽：测试结果写「Usage limit reached. Review your plan or this app’s limit in ChatGPT settings.」；查词面板的错误标题是「Usage limit reached」，主按钮「Manage usage」；回退到 Apple 翻译时附注也带「Manage usage」。
- 登录了但没授权额度：说明原因，给「Continue with ChatGPT」重新授权，或改用 OpenAI 的 API Key。
- 登录中：「Finish signing in in your browser.」和「Cancel」。
- 浏览器回调页只写「You can close this tab and return to Dict.」。
- 隐私说明：文字发给 OpenAI、计入 ChatGPT 套餐、要求 OpenAI 不保存（`store: false`）、登录信息在钥匙串。
- 中文由我们翻译；按钮「Continue with ChatGPT」在中文界面也保留英文，因为它是官方批准的按钮格式之一。
- 按钮是黑底白字的胶囊，没有 ChatGPT 标志：官方素材在 DevKit 的非商业许可下，不能放进 GPL 仓库。

## 7. 沙盒与权限

应用目标 `ENABLE_APP_SANDBOX: NO`，起本机监听不需要 `com.apple.security.network.server`；以后若开沙盒需要加上。
凭据、host id、签发的 client id 都在 Keychain（服务名 `<bundle id>.model`，账号 `chatgpt` 和 `chatgpt-host`），不进 UserDefaults、日志或诊断。
日志只记端口、是否授予额度、失败的错误码，不记令牌、邮箱或授权 URL。

## 8. 只有真人用真实 ChatGPT Plus 账号才能验证的

- 一次真实登录：同意页的样子、首次注册是否必须用 1455 端口、回调里是否真的带签发的 `client_id`。
- `text.format` 的 `json_schema` 严格模式在套餐线路上是否被接受；如果被拒，测试按钮「Structured output」一项会显示服务端消息和被拒的参数名。
- `reasoning.effort`（`none` / `minimal`）是否被接受；如果被拒，「Translation」一项会显示同样的信息。
- `/v1/models` 实际列出哪些 slug，`gpt-6-luna` 在不在里面，哪个最适合查词（首字延迟、能否关思考）。
- `earliest_refresh_at` 的实际格式和含义。
- 与正在登录的 Codex CLI 同时抢 1455 端口时的表现。
- 退出登录后，ChatGPT 设置里的已连接应用是否真的消失。
- 额度用尽、套餐不合格（403）、Business / Enterprise 工作区被管理员禁用时的真实错误形状。
- 带标志的官方按钮能否在 GPL 应用里使用（品牌与许可问题，需要人来定）。

## 9. 后续

- 模型菜单显示 `display_name` 而不是 `slug`。
- 首次引导是否把 ChatGPT 设为推荐项、分段控件的位置，需设计决定。
- Dict 的订阅上线后是否仍算「开源、本机运行」，是否要先提交 OpenAI 的意向表（设计文档第 7 节）。
