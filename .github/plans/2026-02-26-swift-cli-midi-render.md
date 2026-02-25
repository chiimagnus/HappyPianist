# Swift CLI: MIDI 合成钢琴乐（实施计划）

## 目标
- 新增一个可在 macOS 上运行的 Swift CLI，支持将 MIDI 文件渲染为钢琴音频（WAV）。
- 面向 AI 工作流：可脚本化调用，参数稳定，错误信息可读。

## 批次拆分

### Batch 1: CLI 工程骨架
- 新建 `Packages/PianoKeyCLI` Swift Package（executable）。
- 实现命令行参数解析与帮助文案。
- 定义退出码与统一错误输出。
- 验证：`swift build` 通过。

### Batch 2: MIDI -> Piano 音频渲染
- 集成 `AVAudioEngine + AVAudioUnitSampler + AVAudioSequencer`。
- 支持加载系统默认 piano 音色（DLS/SF2）。
- 输出 WAV（PCM）文件，支持可选尾音时长。
- 验证：对示例 MIDI 执行渲染命令并生成音频文件。

### Batch 3: 文档与使用说明
- 更新 `README.md`，补充 CLI 场景、命令示例与注意事项。
- 补充失败排查提示（音色库、路径、权限/文件写入）。
- 验证：命令按文档可执行。

## 风险与回滚
- 风险：不同 macOS 版本系统音色库路径可能差异。
- 缓解：内置多候选路径并给出明确报错。
- 回滚：删除 `Packages/PianoKeyCLI` 与 README 对应段落即可。

## 执行结果
- [x] Batch 1 完成：已创建 `Packages/PianoKeyCLI` 并实现 `render/help` 命令。
- [x] Batch 2 完成：已实现 MIDI -> 钢琴 WAV 离线渲染（AVAudioSequencer + AVAudioUnitSampler + AVAudioEngine）。
- [x] Batch 3 完成：已更新仓库 README，补充 AI 工作流使用说明。
- 验证记录：
  - `swift build --package-path Packages/PianoKeyCLI` 通过。
  - `swift run --package-path Packages/PianoKeyCLI pianokey-cli render -i /tmp/pianokey-cli-test/one-note.mid -o /tmp/pianokey-cli-test/one-note-v2.wav --tail-seconds 0.5` 通过并生成 WAV。
  - `xcodebuild -project PianoKey.xcodeproj -scheme PianoKey -configuration Debug build` 通过。
