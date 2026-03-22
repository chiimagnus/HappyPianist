# 测试

## 测试策略

| 维度 | 方法 | 自动化程度 | 目标 |
| --- | --- | --- | --- |
| 录制逻辑正确性 | Swift Testing 单元测试 | 中 | 验证 note on/off 转换与自动闭合 |
| ViewModel Recorder 状态机 | Swift Testing + Test Doubles | 中 | 验证 Rec/Play/Stop 状态与副作用 |
| UI 与权限流程 | 手工冒烟 | 中低 | 验证授权、监听、映射、回放实际可用 |

## 测试层次

| 层次 | 位置 | 覆盖对象 | 备注 |
| --- | --- | --- | --- |
| 单元测试 | `PianoKeyTests/Recording/DefaultRecordingServiceTests.swift` | 录制事件转换 | 使用 `ClockMock` 控制时间 |
| 单元测试 | `PianoKeyTests/ViewModels/PianoKeyViewModelRecorderStateTests.swift` | 录制/回放状态机 | 验证不触发键盘注入副作用 |
| 测试替身 | `PianoKeyTests/TestDoubles/RecorderTestDoubles.swift` | 各类协议 mock | 解耦系统框架依赖 |
| 包测试（占位） | `Packages/MenuBarDockKit/Tests/...` | 当前仅 placeholder | 需要补实质断言 |

## 命令与执行顺序

| 命令 | 位置 | 用途 | 何时执行 |
| --- | --- | --- | --- |
| `xcodebuild -project PianoKey.xcodeproj -scheme PianoKey -configuration Debug build` | 仓库根目录 | 构建主应用 | 每次提交前 |
| `xcodebuild -project PianoKey.xcodeproj -scheme PianoKeyTests -configuration Debug test` | 仓库根目录 | 执行单元测试（若本地环境可用） | 改动 ViewModel/Service 后 |

## 高风险回归区

1. 权限状态与监听状态的组合分支（有 MIDI 但无注入）。
2. Recorder stop 时自动闭合未 release 音符的时值计算。
3. seek + play 的异步任务取消时序。
4. 和弦等值匹配与旋律冷却逻辑。

## 测试数据、fixture 与 mock

- `ClockMock`：控制录制时间基准，避免真实等待。
- `MIDIInputServiceMock` / `MIDIPlaybackServiceMock`：隔离硬件与音频系统。
- `KeyboardEventServiceMock`：保证“回放不触发注入”可断言。
- `RecordingTakeRepositoryMock`：模拟保存/删除/重命名与失败路径。

## 人工冒烟流程

1. 启动应用，验证授权提示与状态刷新。
2. 连接 MIDI（实体或虚拟），验证 `Sources` 与 `MIDI Events` 变化。
3. 在 Mappings 页分别验证 Single/Chord/Melody 至少各一条规则。
4. 在 Recorder 页执行 Rec -> Stop -> Play -> Stop。
5. 重启应用，确认 Profile 与 Takes 仍可恢复。

## CI / 质量门禁

- 当前仓库未发现 `.github/workflows` 自动化流水线文件。
- 质量门禁主要来自：本地构建、单元测试、手工冒烟清单、PR 描述中的验证步骤。

## 常见失败点

| 失败现象 | 可能原因 | 首查位置 |
| --- | --- | --- |
| `Listening MIDI` 但无输入效果 | 辅助功能未授权/未生效 | Runtime Status + 系统设置 |
| Recorder 保存为空 | 录制期间未收到 note 事件 | `Recent Events` 与 `MIDI Events` |
| 回放失败 | 系统音色库不可用/音频引擎失败 | `AVSamplerMIDIPlaybackService` 错误文案 |

## 示例片段

```swift
// PianoKeyTests/Recording/DefaultRecordingServiceTests.swift
#expect(take?.notes.count == 1)
#expect(abs(durationSec - 0.7) < 0.001)
```

```swift
// PianoKeyTests/ViewModels/PianoKeyViewModelRecorderStateTests.swift
#expect(context.playback.playedTakes.count == 1)
#expect(context.keyboard.typedTexts.isEmpty)
#expect(context.keyboard.keyCombos.isEmpty)
```

## Coverage Gaps（如有）

- UI 自动化测试缺失（Runtime/Mapping/Recorder 交互尚未自动化）。
- MenuBarDockKit 测试仍为占位。

## 来源引用（Source References）

- `PianoKeyTests/Recording/DefaultRecordingServiceTests.swift`
- `PianoKeyTests/ViewModels/PianoKeyViewModelRecorderStateTests.swift`
- `PianoKeyTests/TestDoubles/RecorderTestDoubles.swift`
- `Packages/MenuBarDockKit/Tests/MenuBarDockKitTests/MenuBarDockKitTests.swift`
- `AGENTS.md`
- `README.md`
- `PianoKey/ViewModels/PianoKeyViewModel.swift`
- `PianoKey/Services/Recording/DefaultRecordingService.swift`
- `PianoKey/Services/Playback/AVSamplerMIDIPlaybackService.swift`
