# llmTools 代码审查与五期优化计划

审查日期：2026-07-13

## 1. 目标与固定边界

本次审查覆盖原生应用、核心模型层、本地 bridge、Provider 请求、OCR、快捷操作、ASR/说话人分离 runtime、安装脚本和打包链路。目标分为两部分：

1. 直接修复能够确认、能够验证且不会破坏现有产品能力的问题。
2. 将需要协议升级、兼容迁移或真实环境验收的工作整理成五期任务清单。

以下约束是后续实现必须保持的产品决定：

- **不使用 macOS Keychain。** Provider API key 继续保存在现有本地 `model-registry.json` 中。
- `apiKeyKeychainAccount` 只保留为旧数据解码字段，不读取、不写入系统钥匙串，也不作为密钥回退来源。
- `~/Library/Application Support/llmTools` 使用 `0700`，注册表、历史和注册表备份使用 `0600`。
- 本地优先；自动触发流程不能在用户未确认时把选中文本发送给远程 Provider。
- 验收以打包后的 `dist/llmTools.app` 为准，不能只依赖 `swift build`。

## 2. 本轮已修复

| 领域 | 原问题 | 已完成修复 | 自动验证 |
| --- | --- | --- | --- |
| Provider 密钥 | 代码仍包含 Keychain 读写路径，与当前产品决定冲突 | 删除 Security/Keychain 访问，只解析注册表内联密钥；旧字段仅兼容解码 | Provider credential policy checks |
| 本地文件权限 | 注册表、历史和备份可能继承 `0755/0644` | 每次读写主动迁移为目录 `0700`、文件 `0600`；修复脚本也设置备份权限 | private store permission checks |
| Provider 传输 | 远程 Provider 可配置明文 HTTP，30x 可能把认证头带到其他源 | 远程仅允许 HTTPS，本机 loopback 可用 HTTP；认证请求只接受同协议、同主机、同端口重定向 | endpoint/redirect policy checks |
| 本地 bridge | `Content-Length` 可用负数、重复值、溢出或超大请求绕过解析前限制 | 增加 64 KiB header、2 MiB request 硬上限，拒绝重复/非法长度并在解析前返回 400/413 | bridge framing checks |
| 远程 OCR | 任意 URL、直接私网访问、一次性无界下载和像素乘法溢出 | 仅允许 HTTPS，拒绝直接私网/本机地址和解析结果中的私网地址；要求 image MIME；按数据块下载并限制 32 MB、16 MB 编码图和 1 亿像素 | URL policy/limit checks |
| 安装器进程 | `waitUntilExit()` 之前未排空 stdout/stderr，日志较大时可能死锁 | 共用并发管道收集器，保留有界日志尾部，并把 Task cancellation 传给子进程 | 200 KiB 双管道与 cancellation checks |
| 说话人分离 Token | `{hf_token}` 可被展开进 shell 命令和进程参数 | 禁止该占位符，只允许通过 `PYANNOTE_AUTH_TOKEN` 环境变量传递 | command resolution checks |
| 快捷操作并发 | 旧选区捕获、旧 OCR 下载或旧模型结果可能覆盖新的用户操作 | 为捕获、下载和运行任务增加 revision/cancellation；新输入、关闭窗口和重复触发会使旧结果失效 | build + state-path checks |
| 自动划词隐私 | 自动划词可直接调用当前远程模型 | 远程模型只展示待确认状态，必须由用户主动选择操作后才发送 | source review + packaged manual gate |
| 替换原文 | 激活旧应用后用剪贴板和 Cmd+V，存在选区变化后的误替换风险 | 保存 AX 元素、PID、选区范围、原文和 capture ID；仅在全部仍匹配时直接写 AX 选区；失败则复制结果，不模拟粘贴 | build + packaged cross-app gate |
| 快捷键注册 | Carbon 注册错误被忽略，用户只看到“按键无效” | 显示注册失败与 OSStatus；三组快捷键全有或全无，新组合冲突时恢复并持久化上一组可用快捷键；启动时无历史集合则回退默认组合 | build + packaged conflict gate |
| 窗口关闭/Esc | 关闭快捷操作窗口不取消后台工作，输入法 marked text 的 Esc 可能误关窗口 | 关闭即取消；IME 有 marked text 时 Esc 交给输入法处理 | build + packaged IME gate |

## 3. 仍需处理的风险

这些问题没有在本轮直接修改，因为它们需要兼容迁移、统一协议或真实模型矩阵，不能用局部补丁安全解决。

### P0

- `scripts/llmtools-pyannote-diarization-sidecar.py` 为兼容 PyTorch 2.6 全局设置 `torch.load(weights_only=False)`。任意被替换的 pickle checkpoint 可能执行代码。需要受信模型清单、哈希或安全格式迁移，不能只删除补丁导致现有 pyannote 3.1 runtime 全部失效。
- 常驻 ASR/Fast MT sidecar 缺少统一的 ready deadline、单次请求 deadline、健康探针和自动重启协议；个别锁持有期间等待 I/O，可能让 stop/cancel 卡住。
- 本地 bridge 的 live subtitle session、并发 job、PCM chunk 和累计音频仍需要统一配额，避免认证后的本地客户端无限占用内存和模型队列。
- OCR hostname 预检与 URLSession 实际连接之间仍存在 DNS rebinding TOCTOU；严格边界需要绑定已验证 endpoint 与实际 TLS/SNI 连接，或在完成该连接层前收缩 hostname URL 功能。

### P1

- 模型/runtime 下载缺少统一的 `.part -> 校验 -> 原子替换` 流程，部分安装器没有 checksum、断点清理和失败回滚。
- 子进程取消主要终止直接子进程，shell 派生的进程树需要统一 process-group 终止和超时升级策略。
- 长音频和会议缓存仍存在整段 `Data` 常驻内存路径；应改为有界 ring buffer、临时文件或分块流水线。
- 配置迁移、注册表备份和 app 打包不是完整事务；中途失败可能留下部分新状态或不可运行的 bundle。

### P2

- `AppState.swift` 和 `Views.swift` 体积过大，文本、OCR、媒体、实时字幕、会议、runtime repair 状态共享同一对象，增加跨模式污染和回归概率。
- 错误、取消和资源使用缺少统一的可观测事件；目前很多故障只能从 UI 文案或 sidecar stderr 反推。

## 4. 五期主线任务清单

语音识别专项采用同一条五期主线，不另建相互冲突的路线图；当前模型矩阵、FunASR 官方能力边界和逐步完成标准见 [`speech-recognition-architecture.md`](speech-recognition-architecture.md)。

### 第一期：安全闭环与输入边界

目标：关闭仍可导致代码执行、越界资源占用或敏感数据错误路由的 P0 风险。

- [ ] 为 pyannote checkpoint 建立受信来源策略：固定 repo/revision、文件清单与 SHA-256；本地自定义模型默认拒绝 unsafe pickle。
- [ ] 评估 pyannote/PyTorch 新版本或 safetensors 迁移；只有受信旧 checkpoint 才允许显式兼容模式。
- [ ] 给 bridge 增加每连接超时、最大并发连接、每 token 最大 active job、最大 live session 数和闲置回收。
- [ ] 校验 live PCM 的 sample rate、channel、位深、chunk 大小、累计时长和 session 所有权。
- [ ] 对 Provider、OCR、native bridge 做 redirect、SSRF、超长 header/body、慢速请求和取消的失败注入测试。
- [ ] 为远程 OCR 实现可绑定已验证 IP 与原 hostname/SNI 的连接层；加入公网/回环地址交替解析的 DNS rebinding 测试。
- [ ] 增加日志脱敏断言：API key、HF token、原文、音频路径不得进入普通诊断。

完成定义：安全测试全部自动化；不可信 pyannote checkpoint 无法进入 unsafe load；本地 bridge 在配额压力下可预测地返回错误且内存稳定。

### 第二期：Runtime 与进程生命周期

目标：所有 sidecar、安装器和模型进程具有一致、可取消、可恢复的生命周期。

- [ ] 定义 sidecar 协议：`starting -> ready -> busy -> unhealthy -> stopping -> stopped`。
- [ ] 统一 ready deadline、request deadline、heartbeat、最大重启次数和退避策略。
- [ ] 禁止持锁等待阻塞 I/O；stop/cancel 必须能够抢占 read/write，并在 deadline 后强制终止。
- [ ] 使用 process group 管理 shell/子进程树，按 `TERM -> grace -> KILL` 收敛。
- [ ] 把 ASR、Fast MT、LID、diarization 的启动/关闭/错误映射收敛到共享 runtime supervisor。
- [x] 为 Fun-ASR-Nano + FSMN-VAD + CAM++ + CT-Punc 建立独立官方 FunASR runtime，不复用当前 MLX venv；包版本固定、模型 checkpoint 哈希写入 manifest，断网运行时禁止静默下载。
- [x] 原版 Fun-ASR-Nano 复用该隔离 runtime 建立常驻 Torch/MPS 实时字幕进程；根据 speaker 实测结果不进入实时会议，避免为会议保留无效的 partial/分离路径。
- [ ] 安装器输出继续保持有界；进度、失败阶段和可重试状态写入结构化事件。

完成定义：模拟不输出 ready、请求挂死、stderr 洪泛、子进程忽略 TERM 等场景时，UI 不冻结，取消在约定时间内完成，runtime 可重新启动。

### 第三期：数据完整性与资源治理

目标：下载、配置、历史、音频和模型内存在异常中保持一致且有硬上限。

- [ ] 统一下载器：`.part`、Content-Length/流量上限、checksum、断点策略、原子 rename 和失败清理。
- [x] 将 Nano、FSMN-VAD、CAM++、CT-Punc 作为四个可独立校验的 runtime 资产下载和缓存，不把组合管线伪装成一个模型文件。
- [ ] 注册表迁移采用 `read -> validate -> write temp -> fsync -> atomic replace -> backup`，并保留可验证的上一版本。
- [ ] 打包脚本改为 staging bundle，全部资源和签名验证通过后再替换 `dist/llmTools.app`。
- [ ] 长音频、会议和 live subtitle 使用磁盘分块或 ring buffer，定义每会话/全局内存预算。
- [ ] 统一模型租约：引用计数、idle unload、取消后的释放和多工作流并发优先级。
- [ ] 为缓存、临时音频、恢复草稿和模型下载建立容量/TTL/一键清理策略。

完成定义：强制中断下载、保存、打包、长音频处理后没有半成品被当作 ready；压力测试峰值内存和磁盘增长符合预算。

### 第四期：架构拆分与性能基线

目标：降低跨功能耦合，以可测的 coordinator/store 替代巨型状态对象中的隐式联动。

- [ ] 从 `AppState` 拆出 Quick Action、OCR、Media Subtitle、Live Subtitle、Meeting 和 Runtime Repair coordinator。
- [ ] 从 `Views.swift` 拆出按功能归属的视图文件，保持现有 UI 和 binding 行为，不做同步视觉重构。
- [x] 统一语音三层契约：ASR 模型、本地 runtime、说话人后端分别记录；解析 FunASR `sentence_info[].spk` 到现有 segment，并保留独立 ASR/speaker 来源。
- [x] 原版 Nano 文件转写自动使用 FunASR + CAM++，无 speaker 时回退 pyannote/仅转写，并复用到离线会议；实时字幕继续 transcript-first，不等待 speaker。
- [x] 原版 Nano 保留实时字幕与文件处理；根据实时会议 speaker 实测结果，从会议采集模型中排除，避免低质量标签污染会议记录。
- [ ] 将 mode-specific output/error/loading 状态封装，禁止文本、图片、媒体模式互相覆盖。
- [ ] 把网络、进程、文件和模型调用放到可注入协议后，增加取消、超时、乱序完成的单元测试。
- [ ] 建立性能基线：启动时间、首个 Quick Action 展示、选区捕获、首 token、OCR 下载/预处理、ASR partial、内存峰值。
- [ ] 增加脱敏结构化诊断和单次工作流 trace ID，串联 UI、engine、sidecar 和 bridge。

完成定义：主要 coordinator 可独立测试；乱序/取消测试不依赖真实 UI；关键性能指标有基线、阈值和回归报告。

### 第五期：打包验收与发布门禁

目标：把当前依赖人工经验的验收变成可重复的 packaged-app release gate。

- [ ] 每次候选版本执行 release build、`package-app.sh`、严格 codesign、资源清单和可执行权限检查。
- [ ] 在全新 Application Support 目录和升级目录各跑一遍启动/迁移/退出/重启测试。
- [ ] 覆盖 Accessibility、麦克风、Screen Recording、Launch at Login 的允许/拒绝/撤销状态。
- [ ] 完成 Chrome packaged bridge smoke；Edge 可用时执行同一套真实扩展验收。
- [ ] 为 GGUF、MLX、远程 Provider、OCR、ASR、Fast MT、diarization 建立最小模型矩阵和可跳过条件。
- [ ] 用同一中文、英文、中英混合、粤语、多人重叠和长静音样本比较 FunASR + CAM++、pyannote 与 VibeVoice，记录 CER/WER、首条延迟、实时率、峰值内存和 DER。
- [ ] 增加故障注入：无网、DNS 变化、磁盘满、只读目录、损坏注册表、runtime 崩溃、模型文件被移动。
- [ ] release checklist 必须记录自动检查、人工项目、已知风险、版本文档和回滚方式。

完成定义：同一 commit 可以由自动命令生成、验证并重启 `dist/llmTools.app`；未完成的外部/人工门禁会明确阻止“已验收”状态。

## 5. 快捷操作专项（独立于五期主线）

快捷操作是高频入口，单独管理，不并入某一期的杂项。

### 本轮已经完成

- [x] 全局快捷键选区捕获、划词悬浮捕获统一使用 revision，最后一次用户操作获胜。
- [x] 新输入、切换输入来源、关闭窗口、Esc 和重复快捷键会取消旧推理/OCR 下载。
- [x] 运行或图片准备中不允许无意切换模式；旧异步结果不能写入新模式。
- [x] 自动划词遇到远程模型只展示待确认状态，不自动上传选中文本。
- [x] 替换原文绑定 PID + AX 元素 + capture ID + 选区范围 + 原文；任一变化即安全失败。
- [x] AX 替换失败时复制结果；不再修改剪贴板后模拟 Cmd+V。
- [x] Cmd+C 捕获回退串行执行；取消仍做所有权清理，从内部 marker 计数，并用独立用户输入监听保留菜单、右键或其他应用写入的新剪贴板内容。
- [x] 输入法 marked text 的 Esc 不关闭面板。
- [x] Carbon 快捷键集合全有或全无；注册失败可见，并恢复、持久化上一组可用组合；启动时无历史集合则回退默认组合。

### 后续专项任务

- [ ] **QA-1 统一事件状态机（P0）：** 明确定义 capture、prepare、run、cancel、close、replace、copy 的合法转移；所有入口只派发事件，不直接改散落字段。
- [ ] **QA-2 远程发送确认（P0）：** 对全局选区、划词悬浮、剪贴板和拖入内容显示一致的本地/远程目标提示；自动触发永远不绕过确认。
- [ ] **QA-3 快捷键冲突体验（P1）：** 设置页即时检测全局组合冲突、应用内重复和常用编辑键覆盖，显示失败的具体动作并提供恢复默认。
- [ ] **QA-4 跨应用替换矩阵（P1）：** TextEdit、Notes、Safari/Chrome contenteditable、VS Code、Office、Electron 各验证 capture/copy/AX replace；不支持 AX 写回的应用明确降级为复制。
- [ ] **QA-5 可访问性与输入法（P1）：** 中文/日文 IME、VoiceOver、键盘导航、焦点恢复、多显示器/Spaces、置顶和 Esc 行为形成固定回归集。
- [ ] **QA-6 模式状态隔离（P1）：** 文本/OCR/媒体分别持有 input/output/error/loading；切换后恢复对应状态，错误不会跨模式残留。
- [ ] **QA-7 性能与诊断（P2）：** 记录不含原文的 capture source、capture latency、model route、cancel reason、replace fallback；设定面板展示和本地模型首 token 阈值。
- [ ] **QA-8 快捷动作管理（P2）：** 在现有五个文本任务稳定后，再评估排序、显隐、自定义 prompt action；不先引入工作流引擎。

### 快捷操作专项验收矩阵

| 场景 | 必须满足 |
| --- | --- |
| 连续快速触发两次 | 第二次输入/结果获胜，第一次不回写、不替换、不复制 |
| 运行中关闭窗口 | 请求取消，spinner 清理，模型按 idle 策略释放 |
| OCR 下载中清除/换图 | 旧下载取消，旧图片不能重新出现 |
| 自动划词 + 远程模型 | 只展示确认 UI，没有网络请求 |
| 原选区发生变化 | 不替换新选区，结果复制并显示明确降级状态 |
| 不支持 AX 写回的应用 | 不模拟 Cmd+V，不误激活其他窗口，结果仍可复制 |
| 输入法候选状态按 Esc | 先关闭候选/marked text，不关闭 Quick Action |
| 快捷键被系统占用 | 设置立即显示失败，上一组有效快捷键继续工作 |

## 6. 验证基线

每期都必须保留以下基础门禁，并按改动范围追加专项检查：

```sh
swift build --product llmTools
swift run LLMToolsChecks
node scripts/check-browser-extension-dom.mjs
node scripts/check-phase4-media-subtitles.mjs
node scripts/check-phase4x-language-routing.mjs
node scripts/check-phase4x-fast-mt.mjs
node scripts/check-phase4x-speaker-diarization.mjs
./scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 dist/llmTools.app
```

浏览器扩展是否已加载、真实模型是否存在、系统权限是否授予仍属于环境相关门禁，报告必须明确写出“未执行/被阻塞”，不能用源代码检查替代。
