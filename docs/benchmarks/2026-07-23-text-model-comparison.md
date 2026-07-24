# MiniCPM5-1B 与 Qwen3.5-0.8B 文本功能对比

日期：2026-07-23

## 结论

- `MiniCPM5-1B-MLX` 已能作为 llmTools 的本地 MLX 文本模型正常运行，自动归类为 `fast`，并正确读取其 131,072 token 上下文。
- 在本次 6 项固定文本任务中，MiniCPM5 的推理耗时为 1.285 秒，Qwen3.5-0.8B 为 6.341 秒；MiniCPM5 的平均单项耗时约为 Qwen 的五分之一。
- Qwen3.5-0.8B 的翻译、待办拆分和摘要信息保留更好，但技术解释没有遵守“三句话”约束，并出现了不必要的术语延展。MiniCPM5 的解释更短且遵守长度约束，但技术细节较弱；它的待办提取没有把三项发布任务拆开。
- 默认建议：保留 Qwen3.5-0.8B 作为需要更完整指令遵循与待办拆分的文本模型；将 MiniCPM5-1B 提供给重视低延迟的翻译、润色、短摘要和快速操作。此轮测试不支持把 MiniCPM5 自动提升为所有文本任务的全局默认。

## 测试环境

| 项目 | 值 |
| --- | --- |
| 机器 | MacBook Pro，Apple M5 Pro，18 核，64 GB 内存 |
| 系统 | macOS 26.5 (25F71) |
| Qwen | `lmstudio-community/Qwen3.5-0.8B-MLX-8bit`，读取到 262,144 token 上下文 |
| MiniCPM | `openbmb/MiniCPM5-1B-MLX`，4-bit MLX，读取到 131,072 token 上下文 |
| 运行策略 | 本地 MLX、temperature 0、每个模型单独临时注册表、一次不计时预热后串行执行 |
| 历史/网络 | 不保存历史；任务执行期间没有远程模型或网络回退 |

实际命令：

```sh
.build/debug/LLMToolsTranslationBench --text-suite \
  /Users/po/code/models/lmstudio-community/Qwen3.5-0.8B-MLX-8bit \
  /Users/po/Documents/llmTools/dist/benchmarks/text-suite-2026-07-23/qwen3.5-0.8b.json

.build/debug/LLMToolsTranslationBench --text-suite \
  /Users/po/code/models/openbmb/MiniCPM5-1B-MLX \
  /Users/po/Documents/llmTools/dist/benchmarks/text-suite-2026-07-23/minicpm5-1b.json
```

原始逐项输出与耗时保存在：

- `dist/benchmarks/text-suite-2026-07-23/qwen3.5-0.8b.json`
- `dist/benchmarks/text-suite-2026-07-23/minicpm5-1b.json`

## 耗时

以下耗时从预热完成后的单个任务开始计时，包含该任务的本地推理和输出处理，不包含模型第一次加载。

| 任务 | Qwen3.5-0.8B 8bit | MiniCPM5-1B | 观察 |
| --- | ---: | ---: | --- |
| 英译中 | 357 ms | 102 ms | 两者语义正确；MiniCPM5 更简短。 |
| 中译英 | 485 ms | 222 ms | Qwen 更自然；MiniCPM5 有重复的 `and` 连接。 |
| 中文润色 | 398 ms | 137 ms | 两者可用；Qwen 语气更正式完整。 |
| 中文摘要 | 1,260 ms | 331 ms | Qwen 保留文件模式信息；MiniCPM5 省略该信息。 |
| 中文技术解释 | 3,230 ms | 238 ms | Qwen 内容较多但明显超出三句话；MiniCPM5 简短但技术解释较浅。 |
| 待办提取 | 611 ms | 255 ms | Qwen 拆出四个行动项；MiniCPM5 合并了前三个行动项。 |
| **总计** | **6,341 ms** | **1,285 ms** | MiniCPM5 快约 4.9 倍。 |
| **单项平均** | **1,057 ms** | **214 ms** | 仅用于此固定小样本。 |

## 输出质量观察

### 翻译与润色

两种模型都正确保留了“本地处理”和“不上传音频”的关键语义。Qwen 的中译英为 `once the local model is complete`，MiniCPM5 为 `the translation should be completed by the local model`；后者可理解但语法更重复。中文润色中，两者均消除了口语化连写，Qwen 的“建议用户稍作等待后再尝试”更适合产品文案。

### 摘要与解释

Qwen 摘要保留了实时缓存、文件模式、本地数据和设置生效边界，但额外添加了并不存在的“行动项”。MiniCPM5 的三点摘要更紧凑，却遗漏了文件模式的独立转写用途。

技术解释是本轮差异最大的任务。MiniCPM5 严格给出三点，但“有助于并行处理多个音频流”没有解释连续分块为什么需要保留解码器状态。Qwen 说明了连续语音上下文，却用四段长文本违反了题设长度，也把“记忆帧”表述为一个看似固定的术语。两者都不应在没有额外质量约束或人工复核时用于高要求技术说明。

### 待办提取

Qwen 正确拆分出下载权重、跑测试、保存报告和下周确认文案四项。MiniCPM5 保留了文本内容，但把前三项并为一个条目。因此快速操作若需要可执行的逐项清单，应优先使用 Qwen 或增加结构化 JSON 输出约束。

## 限制

- 每类任务只有一个固定输入；本报告不是通用能力排行榜。
- 未使用人工盲评或参考译文打分。质量结论基于可审计的原始输出、信息保留和明确的指令约束。
- 时间结果是本机单次热模型运行，不代表首次加载、长上下文、并发或电池供电下的吞吐量。
- Qwen3.5-0.8B 是已注册的视觉语言模型，但本轮仅通过其文本路径测试；GLM-OCR 不在此文本对比范围。
