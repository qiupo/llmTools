# Nemotron 3.5 Streaming 与 Qwen3-ASR 0.6B 8bit 实时字幕对比

日期：2026-07-23

## 结论

- 两个后端均在 llmTools 的本地实时 ASR 会话中成功完成中文和英文音频的首片段与最终转写；没有云端 ASR 或网络回退。
- Nemotron 的已加载后首片段和最终推理更快：中文首片段 26 ms、最终 65 ms；英文首片段 26 ms、最终 65 ms。Qwen 对应为 147/99 ms 与 60/94 ms。
- Qwen3-ASR-0.6B 8bit 的最终中文字符错误率为 0，英文词错误率为 0。Nemotron 的最终中文字符错误率为 36.8%，英文词错误率为 20.0%。
- Nemotron 冷启动较慢（9.161 秒，Qwen 为 4.389 秒），且 FluidAudio 在本次模型包中使用了可工作的 `decoder_joint` 兼容路径而非可选的 smart-spec 资产。
- 产品决策：Nemotron 是一个可选的低延迟实时字幕模型，但新增时不能自动覆盖用户当前的实时字幕选择。Qwen3-ASR 8bit 仍是本机中英文准确性优先的默认候选；用户可在设置中主动选择 Nemotron 以换取已加载后的更低延迟。

## 测试环境与方法

| 项目 | 值 |
| --- | --- |
| 机器 | MacBook Pro，Apple M5 Pro，18 核，64 GB 内存 |
| 系统 | macOS 26.5 (25F71) |
| Qwen 模型 | `mlx-community/Qwen3-ASR-0.6B-8bit`，持久 `mlx-audio` streaming sidecar |
| Nemotron 模型 | `FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML` 的 `multilingual/1120ms` 变体，FluidAudio 0.15.5 |
| 音频格式 | macOS `say` 生成后转为 16 kHz、单声道、16-bit PCM WAV |
| 首片段 | 每条音频的前 1,120 ms，随后提交完整音频取得最终结果 |
| 中文夹具 | Tingting，4,365 ms：`本地实时字幕需要保留模型状态并降低延迟。` |
| 英文夹具 | Samantha，4,009 ms：`Local realtime captions should keep decoder state and reduce latency.` |

实际命令：

```sh
.build/debug/LLMToolsRealtimeASRBench \
  /Users/po/code/models/mlx-community/Qwen3-ASR-0.6B-8bit \
  /Users/po/code/models/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML \
  /Users/po/Documents/llmTools/dist/benchmarks/realtime-asr-2026-07-23
```

原始 JSON、可播放 WAV 夹具和最终转写保存在 `dist/benchmarks/realtime-asr-2026-07-23/`，主结果文件为 `asr-realtime-benchmark.json`。

## 延迟与准确率

启动时间测量从创建会话到后端就绪；首片段与最终时间只测对应请求的本地处理耗时。中文使用忽略标点后的字符错误率（CER）；英文使用小写词错误率（WER），并把词内连字符归一化，因此 Qwen 的 `real-time` 与参考的 `realtime` 不被误算为错误。

| 后端 | 启动 | 中文首片段 | 中文最终 | 中文 CER | 英文首片段 | 英文最终 | 英文 WER |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3-ASR-0.6B 8bit | 4,389 ms | 147 ms | 99 ms | 0.0% | 60 ms | 94 ms | 0.0% |
| Nemotron 3.5 Streaming Core ML | 9,161 ms | 26 ms | 65 ms | 36.8% | 26 ms | 65 ms | 20.0% |

最终原文如下，便于审计指标：

| 后端 | 中文最终转写 | 英文最终转写 |
| --- | --- | --- |
| Qwen3-ASR 8bit | `本地实时字幕需要保留模型状态，并降低延迟。` | `Local real-time captions should keep decoder state and reduce latency.` |
| Nemotron | `ND1 字字字母需要保留模型状态, 并降低延时` | `Local real time captions should keep decoder state and reduce latency` |

## 解释与产品落点

Nemotron 的会话保持编码器和解码器缓存，因此完成载入后的 1,120 ms 首片段明显更快；Qwen 的现有 sidecar 仍以滚动窗口重解码。这个实现差异解释了单请求延迟差异，但不抵消当前中文准确率差异。

因此本次接入遵循以下约束：

- Nemotron 仅暴露给实时字幕，不进入媒体文件字幕或会议文件转写选择器。
- 选择外层下载目录时，程序自动解析到 `multilingual/1120ms` 的完整 Core ML 资产目录。
- 新增 Nemotron 不会自动提升或替换已经选定的实时 ASR 模型；用户可以在 Settings -> Media -> Realtime ASR 中显式选择它。
- 一个语句的合成音频不能代表真人、多说话人、嘈杂环境、粤语、连续长语流或自动语言识别。后续若考虑更改默认值，应至少增加这些样本并加入人工听感核验。

## 运行时说明

FluidAudio 成功载入 `decoder_joint` 并完成 Core ML 预热。日志同时表明可选的 `joint_noencproj_batched.mlpackage` 不在该模型包中，运行时回退到 legacy inner loop；这不是失败，实际转写已完成，但应在后续变体或 FluidAudio 升级时重新测量。
