# 模块：PianoKeyCLI

## 职责与边界

- 负责将 `.mid` 文件离线渲染为钢琴 `.wav`。
- 提供参数解析、错误码、JSON 输出，便于脚本/AI 链路消费。
- 不负责主 App 的实时监听、映射执行与 SwiftData 持久化。

## 目录范围

| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `Packages/PianoKeyCLI/Package.swift` | 包定义 | executable product |
| `Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift` | CLI 主逻辑 | parser + renderer + main |
| `Packages/PianoKeyCLI/README.md` | 使用说明 | 构建与参数文档 |

## 入口点与生命周期

| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| `@main struct PianoKeyCLI` | `main.swift` | 进程启动 | 解析命令与退出码 |
| `CLIParser.parse(arguments:)` | `main.swift` | 接收参数后 | 返回 `.help` 或 `.render` |
| `PianoMIDIRenderer.render(options:)` | `main.swift` | render 分支 | 生成 WAV 输出 |

## 关键文件

| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `main.swift` | 所有 CLI 功能入口 | 参数契约、失败路径、渲染细节都在这里 |
| `README.md` | 用户命令示例 | 对外接口文档 |
| `Package.swift` | 平台与产物定义 | 构建与分发基础 |

## 上下游依赖

| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 上游 | shell / AI 脚本 | 传入 `render` 参数 | 参数合法性决定执行结果 |
| 下游 | AVAudioEngine + AVAudioSequencer | 离线渲染音频 | 音频引擎稳定性关键 |
| 下游 | 文件系统 | 读取 MIDI、写入 WAV | 路径错误直接失败 |

## 对外接口与契约

| 接口 / 命令 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `pianokey-cli render` | `CLIParser.usage()` | 用户/脚本 | 渲染命令 |
| `--input` / `--output` | `CLIParser.parse` | 用户/脚本 | 必选项 |
| `--tail-seconds` / `--sample-rate` / `--sound-bank` / `--json` | `CLIParser.parse` | 用户/脚本 | 可选调优项 |
| JSON 输出 | `main.swift` | 自动化链路 | 机器可读结果 |

## 数据契约、状态与存储

- `RenderOptions`：输入参数集合。
- `RenderSummary`：渲染结果摘要。
- 输出是本地 WAV 文件，不写入数据库。

## 配置与功能开关

| 项目 | 默认值 | 影响 |
| --- | --- | --- |
| `tailSeconds` | `1.5` | 决定尾音长度 |
| `sampleRate` | `44100` | 决定输出采样率 |
| `--json` | `false` | 控制 stdout 格式 |

## 正常路径与边界情况

1. 正常：解析参数 -> 检查路径 -> 加载 MIDI -> 离线渲染 -> 输出摘要。
2. 边界：缺少内置音色库时必须提供 `--sound-bank`。
3. 边界：输出目录不存在会自动创建；输出路径非法会失败。

## 扩展点与修改热点

- 新子命令：扩展 `Command` 枚举与 `CLIParser.parse`。
- 新输出格式：修改 `RenderSummary` 与 main 输出逻辑。
- 渲染算法优化：`renderOffline` 循环与 buffer 策略。

## 测试与调试

- 当前模块未见独立测试 target；建议至少补参数解析测试。
- 调试优先使用 `--json`，便于脚本断言关键字段。

## 示例片段

```swift
// main.swift
guard let inputPath else {
    throw CLIError.missingRequiredOption("--input")
}
guard let outputPath else {
    throw CLIError.missingRequiredOption("--output")
}
```

```swift
// main.swift
if options.outputJSON {
    let payload: [String: Any] = [
        "ok": true,
        "midiDurationSeconds": summary.midiDuration,
        "renderedDurationSeconds": summary.renderedDuration,
        "outputPath": summary.outputPath
    ]
}
```

## Coverage Gaps（如有）

- 缺少 CLI 自动化测试与基准数据集。

## 来源引用（Source References）

- `Packages/PianoKeyCLI/Package.swift`
- `Packages/PianoKeyCLI/README.md`
- `Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift`
- `README.md`
