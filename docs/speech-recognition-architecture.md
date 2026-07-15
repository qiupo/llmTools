# llmTools 语音识别架构与 FunASR 接入说明

更新时间：2026-07-14

## 结论

Fun-ASR-Nano 可以用于带说话人标签的转写，但需要准确理解官方能力边界：

- `Fun-ASR-Nano` 是转写模型。
- 官方 FunASR 示例另外加载 `fsmn-vad`、`cam++` 和 `ct-punc`。
- 最终说话人编号来自组合管线输出的 `sentence_info[].spk`，不是 Nano 权重单独输出。
- llmTools 已让原版 Nano 复用同一隔离 runtime：实时字幕/会议走常驻 Torch/MPS，文件字幕与离线会议走 Nano + FSMN-VAD + CAM++ + CT-Punc。
- Fun-ASR-Nano / Fun-ASR-MLT-Nano 的 MLX 与 GGUF 路径仍只负责 ASR，所以不能标记为“原生说话人”。

这套 FunASR 组合链路在 llmTools 中属于“可返回 speaker 的文件 ASR runtime”，不是可任意挂在 Qwen3、Whisper 等模型后的通用说话人后端。现有 pyannote 仍是独立后处理与失败回退。两者不复用环境，诊断分别记录 ASR runtime、ASR model 和 speaker model 来源。

官方依据：

- [FunASR 中文文档](https://modelscope.github.io/FunASR/zh/)说明工具箱覆盖 ASR、VAD、标点和说话人分离等能力。
- [FunASR README 中文版](https://github.com/modelscope/FunASR/blob/main/README_zh.md)的说话人示例明确同时配置 `vad_model="fsmn-vad"` 与 `spk_model="cam++"`。
- [Fun-ASR 官方仓库](https://github.com/FunAudioLLM/Fun-ASR)在 2026 年 5 月更新的 Nano 示例中，同时配置 Nano、FSMN-VAD、CAM++、CT-Punc，并从 `sentence_info` 读取 speaker。
- [Fun-ASR-Nano-2512 模型卡](https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-2512)描述 Nano 的语音识别、时间戳与多语言能力；说话人分离仍由 FunASR 组合管线完成。

## 统一结构

语音功能统一拆成三层，设置页、健康检查和诊断都按这三层表达：

```text
音频输入
  -> 转写模型（Fun-ASR / Qwen3-ASR / SenseVoice / Whisper / VibeVoice）
  -> 本地运行时（MLX / 官方 FunASR 组合 / GGUF / whisper.cpp / 自定义命令）
  -> 可选说话人处理（runtime 已返回 speaker / pyannote / 仅转写）
  -> SubtitleSegment / MeetingSegment
```

这三层不能合并为一个“模型”概念：同一个 Nano 模型可以由不同运行时执行；同一个 ASR 结果也可以选择不同的说话人后端。

## 当前模型矩阵

| 模型族 | 实时字幕 | 文件转写 | 当前运行路径 | 当前说话人策略 | 主要定位 |
| --- | --- | --- | --- | --- | --- |
| Qwen3-ASR | 支持 | 支持 | MLX sidecar | 独立 pyannote | 当前 Apple Silicon 中英混合质量/延迟候选 |
| Fun-ASR-MLT-Nano | 支持 | 支持 | MLX sidecar | 独立 pyannote | 多语言覆盖 |
| Fun-ASR-Nano（原版 `model.pt`） | 支持 | 支持 | 常驻 Torch/MPS；文件模式使用官方 FunASR 组合 runtime | 实时字幕仅转写；文件模式 CAM++ 优先 | 中文、英文、日文实时字幕及多人文件/会议 |
| Fun-ASR-Nano（MLX/GGUF） | 支持 | 支持 | MLX 或 GGUF sidecar | 独立 pyannote | 低延迟中文、英文、日文方向 |
| SenseVoiceSmall | 支持 | 支持 | MLX 或 sherpa-onnx sidecar | 独立 pyannote | 短窗口、低延迟备选 |
| whisper.cpp Core ML | 支持 | 支持 | whisper-server / whisper-cli | 独立 pyannote | 成熟通用备选 |
| VibeVoice-ASR | 不支持 | 支持 | MLX 或显式自定义命令 | runtime 返回 speaker 时直接使用 | 长文件 rich transcription |
| Custom local ASR | 取决于能力声明 | 取决于能力声明 | 自定义命令 | 取决于 JSON 是否返回 speaker | 兼容外部本地运行时 |

当前规则：

1. 实时字幕只选择声明支持 realtime 的模型，绝不等待说话人分离后再显示文本。
2. 文件字幕优先使用 ASR/runtime 已返回的 speaker；没有 speaker 时才运行独立说话人后端。
3. VibeVoice 的 `canEmitSpeakerLabels` 表示 runtime 可能返回 speaker；若实际没有返回，诊断必须明确记录能力缺失。
4. Fun-ASR-Nano 的静态 `canEmitSpeakerLabels` 继续为 `false`，因为 speaker 属于组合 runtime 能力；实时来源记录为 `funASRTorchStreaming`，文件 speaker 来源记录为 `funASRCompositePipeline`。
5. ASR 始终本地运行，不增加远程 ASR 或云端 fallback。

## 模型选择建议

- 中英混合实时字幕：先使用当前已实测的 Qwen3-ASR-0.6B bf16；量化版本作为资源更紧张时的备选。
- 多语言实时字幕：使用 Fun-ASR-MLT-Nano，并通过实际音频集验证语言覆盖和延迟。
- 中文、英文、日文实时字幕：可使用原版 Fun-ASR-Nano Torch/MPS；不推荐用于实时会议 speaker 分离，会议采集优先选择 Qwen3 或其他已验证模型。
- 中文、英文、日文或方言文件，并需要同一条本地链路输出 VAD/说话人：使用原版 Fun-ASR-Nano-2512 官方组合管线。
- 长文件且需要模型直接给 speaker/timestamp：使用 VibeVoice-ASR；接受它是 file-only 重型模型。
- 仅需稳定通用 ASR：保留 SenseVoiceSmall 与 whisper.cpp Core ML，不再给它们扩展额外产品角色。

设置页不再把任何单个模型写成全局“最佳模型”。模型选择器只展示事实：模型族、支持模式、运行路径和说话人策略；质量与延迟结论由健康检查和基准报告给出。

## FunASR 接入状态（五步）

### 第一步：能力与基准契约（已完成架构契约）

- 保持 Nano/MLT 的 ASR 能力和 CAM++ 说话人能力分离。
- 准备中文、英文、中英混合、粤语、多人重叠和长静音样本。
- 记录 WER/CER、首条结果延迟、文件实时率、峰值内存和说话人 DER。
- 实时转写保持 transcript-first；pyannote 与 VibeVoice 路径继续独立存在。

完成标准：相同音频可在现有模型与官方 Nano 管线间重复对比，指标与失败原因可追踪。

### 第二步：隔离的官方 FunASR 运行时（已完成）

- 新增独立的官方 FunASR Python 环境，不复用现有 MLX venv。
- 固定 FunASR/ModelScope/Torch/Transformers 包版本；模型 checkpoint 哈希写入 `runtime-manifest.json`。
- 模型全部缓存到 `Application Support/llmTools`，运行阶段禁止静默联网下载。
- 输入使用本地 16 kHz mono WAV；stdout 只输出 `llmtools.asr/v1` JSON，依赖日志进入 stderr。

完成标准：断网条件下可完成单人和多人文件转写，运行时安装/缺失/模型缺失有独立健康状态。

### 第三步：统一 speaker 输出契约（已完成）

- 解析官方 `sentence_info[].spk`、时间戳与文本。
- 转换为现有 `SubtitleSegment` / `SpeakerTurn`，保持 speaker ID 稳定并支持用户重命名、合并。
- 通过 `funASRCompositePipeline`、`funasr-nano+cam++` 分开记录 runtime 与 speaker 来源，避免只出现一个模糊的“FunASR”。
- 对官方已说明的时间戳限制做样本验证；时间戳不可靠时不得伪造精确字幕边界。

完成标准：FunASR + CAM++ 输出能走现有字幕导出、会议编辑和诊断链，且不会被误记为 Nano 原生 speaker。

### 第四步：产品接入顺序（实时字幕与文件完成，会议按效果路由）

- Settings 提供原版 Nano + CAM++ 一键安装；安装后将原版 Nano 注册为 realtime + file 模型。
- 文件字幕和离线会议自动识别该 runtime，优先使用其 speaker 片段。
- 实时字幕复用常驻 Torch/MPS 进程，按官方方式累积重解码并回滚末尾 5 个不稳定 token；原版 Nano 不进入实时会议采集，避免低质量 speaker 标签影响会议记录。
- CAM++ 失败时按显式策略 fallback 到 pyannote 或 transcript-only，不静默改变结果来源。

完成标准：用户能看到当前后端、健康状态和实际结果来源；失败不阻塞已有 ASR 文本。

### 第五步：收敛与发布（本轮完成工程验收，长期基准待扩充）

- 在同一基准集上比较 FunASR + CAM++、pyannote、VibeVoice 原生 speaker。
- 根据语言、文件长度、设备内存和实时/离线场景确定自动路由条件。
- VibeVoice 自动发现只保留当前实际使用的 MLX 运行时；旧 PyTorch runner 不再打包，显式自定义命令仍兼容。
- 通过 `swift run LLMToolsChecks`、本地 ASR 检查脚本、打包、签名和 packaged app 重启验收。

完成标准：文档、设置页、健康检查、诊断和实际 runtime 对同一模型能力给出一致结论。

## 当前 runtime 目录

| 目录 | 责任 | 主要模型 |
| --- | --- | --- |
| `asr-runtime/venv` | 共享 MLX ASR | Qwen3-ASR、mlx-community VibeVoice-ASR |
| `asr-runtime/funasr-venv` | Fun-ASR-MLT MLX | Fun-ASR-MLT-Nano |
| `asr-runtime/funasr-nano-venv` | Nano MLX | safetensors Fun-ASR-Nano |
| `asr-runtime/sensevoice-venv` | SenseVoice MLX | SenseVoiceSmall |
| `asr-runtime/whisper-cpp` | whisper.cpp/Core ML | Whisper |
| `asr-runtime/funasr-pipeline` | 官方 Torch/MPS 实时进程、文件组合管线与四个模型资产 | 原版 Nano、FSMN-VAD、CAM++、CT-Punc |
| `diarization-runtime/venv` | 独立说话人后处理 | pyannote |

`LLMTOOLS_ASR_RUNTIME_ROOT` 可整体迁移 ASR 根目录；官方组合管线还可用 `LLMTOOLS_FUNASR_PIPELINE_ROOT` 单独覆盖。`LLMTOOLS_FUN_ASR_VENV` 只表示 MLT MLX 环境，不会被官方组合管线复用。

## 2026-07-13 本机 smoke

- 官方中文样例约 5.6 秒：输出 1 个带时间边界和 speaker 的 segment；sidecar 内部延迟约 20.3 秒，含进程启动总耗时约 23.8 秒。
- 两种中文系统音色、三轮发言、约 32.9 秒：输出 3 个 segment，speaker 序列为 `0 / 1 / 0`；内部延迟约 27.5 秒，含进程启动总耗时约 30.5 秒。
- `LLMToolsMeetingSmoke` 通过真实 `TaskEngine` 路径复测同一音频：`segments=3`、`speakers=2`、`asr=funASRCompositePipeline`、`strategy=compositeSpeakerASR`、`diarization=funasr-nano+cam++`。
- stdout 单独验证为一行合法 `llmtools.asr/v1` JSON；模型加载和依赖提示只进入 stderr。

## 2026-07-14 MPS 实时 smoke

- M5 Pro 上原版 Nano 通过 Torch 2.9.0 成功选择 `device=mps`，模型常驻冷加载约 8.1-10.8 秒。
- 常驻 NDJSON sidecar 对 2.16 秒累积音频返回 partial 约 481 ms，对 2.88 秒累积音频返回 final 约 319 ms。
- sidecar 使用官方 `prev_text` 机制，非 final 结果回滚末尾 5 个 token；final 后清空上下文，下一句不会串接旧文本。

这只是功能 smoke，不等同于 DER/CER 基准。FunASR 1.3.14 在 Nano 已返回时间戳时会跳过独立 CT-Punc 推理，当前明确使用 `vad_segment` 做 speaker 聚类；CT-Punc 仍作为官方组合资产安装和校验，但不能把它描述成每次 Nano 推理都实际参与分句。

## 本轮已完成

- 模型族增加稳定展示名，设置页和 Quick Action 不再显示内部枚举值。
- 模型选择器统一展示模型族、实时/文件用途和说话人策略。
- Settings -> Media 增加“转写模型 -> 本地运行时 -> 可选说话人处理”总览。
- 已注册语音模型可展开查看当前用途、运行路径和说话人策略。
- 六组自定义 ASR 命令模板收进高级折叠项，原配置与优先级保持不变。
- Fun-ASR-Nano / MLT 的元数据和测试明确保持 `canEmitSpeakerLabels == false`。
- 新增隔离安装器、离线 sidecar、模型 checkpoint manifest、设置安装入口和 runtime health 来源。
- 文件字幕与离线会议已消费 `sentence_info[].spk`；无有效 speaker 时回退现有 pyannote/仅转写路径。
- 原版 Nano 自动标记为 realtime/file：实时字幕走 Torch/MPS、文件走组合管线；会议采集明确排除原版 `model.pt`，MLX/GGUF Nano 保持 realtime/file ASR-only。
- 统一 ASR、pyannote、LID、Fast MT 的 Swift runtime 根目录覆盖逻辑。
- VibeVoice 自动路径收敛为 MLX；旧 PyTorch runner 不再打入 app。
