# 模块：映射引擎（Mapping Engine）

## 职责与边界

- 负责把实时 `MIDIEvent` 匹配成 `ResolvedMappingAction`。
- 支持三种触发：single key、chord、melody。
- 不负责动作执行（执行在 ViewModel 的 `execute(_:)` 中）。

## 目录范围

| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `LonelyPianist/Services/Mapping/DefaultMappingEngine.swift` | 核心实现 | 规则匹配状态机 |
| `LonelyPianist/Services/Protocols/MappingEngineProtocol.swift` | 协议与返回契约 | 可替换实现入口 |
| `LonelyPianist/Models/Mapping/*` | 规则模型 | 引擎输入配置 |
| `LonelyPianist/Utilities/MIDINoteParser.swift` | 规则文本解析 | UI 编辑器辅助 |

## 入口点与生命周期

| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| `process(event:profile:)` | `DefaultMappingEngine.swift` | 每个 MIDI 事件 | 返回动作列表 |
| `reset()` | `DefaultMappingEngine.swift` | 停止监听时 | 清空按键与历史状态 |

## 关键文件

| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `DefaultMappingEngine.swift` | single/chord/melody 统一匹配 | 业务行为差异中心 |
| `MappingRule.swift` | 规则定义 | 输入契约真值 |
| `MappingAction.swift` | 动作定义 | 输出契约真值 |

## 上下游依赖

| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 上游 | `LonelyPianistViewModel` | 传入 event + active profile | 决定匹配上下文 |
| 下游 | `KeyboardEventService`/`ShortcutService` | 通过 ViewModel 执行动作 | 影响用户可见输出 |

## 对外接口与契约

| 接口 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `MappingEngineProtocol` | `Services/Protocols/MappingEngineProtocol.swift` | ViewModel | 统一匹配接口 |
| `ResolvedMappingAction` | 同上 | ViewModel | 匹配结果容器 |
| `MappingActionType` | `Models/Mapping/MappingAction.swift` | UI + 执行层 | text/keyCombo/shortcut |

## 数据契约、状态与存储

- 内部状态：`pressedNotes`, `triggeredChordRuleIDs`, `melodyHistory`, `lastMelodyTriggerAt`。
- 配置来源：`MappingProfilePayload`。
- 不直接持久化，状态随监听会话存在。

## 配置与功能开关

| 项目 | 来源 | 作用 |
| --- | --- | --- |
| `velocityEnabled` | `MappingProfilePayload` | 启用单键力度分层 |
| `defaultVelocityThreshold` | `MappingProfilePayload` | 默认高力度阈值 |
| `maxIntervalMilliseconds` | `MelodyMappingRule` | 旋律匹配时间窗口 |

## 正常路径与边界情况

1. single key：note 匹配后按力度决定 normal/high output。
2. chord：要求按下音符集合与规则集合完全一致。
3. melody：要求后缀序列匹配且相邻间隔不超阈值。
4. 边界：旋律有冷却（`0.15s`）和历史窗口（`12s`）限制。

## 扩展点与修改热点

- 新触发模式：增加 `TriggerType`、新匹配函数、UI 编辑器与持久化字段。
- 和弦匹配策略变更（如子集匹配）会显著改变现有行为，需全量回归。

## 测试与调试

- 当前仓库对引擎本身缺少直接单测；建议补充 pure logic tests。
- 调试可借助 `Recent Events` 判断是否“有 MIDI 无命中”。

## 示例片段

```swift
// DefaultMappingEngine.swift
if let last = lastMelodyTriggerAt[rule.id],
   event.timestamp.timeIntervalSince(last) < melodyCooldownSeconds {
    continue
}
```

```swift
// DefaultMappingEngine.swift
guard requiredNotes == pressedNotes else { continue }
guard !triggeredChordRuleIDs.contains(rule.id) else { continue }
```

## Coverage Gaps（如有）

- 缺少引擎级独立测试，复杂规则变更风险较高。

## 来源引用（Source References）

- `LonelyPianist/Services/Mapping/DefaultMappingEngine.swift`
- `LonelyPianist/Services/Protocols/MappingEngineProtocol.swift`
- `LonelyPianist/Models/Mapping/MappingProfile.swift`
- `LonelyPianist/Models/Mapping/MappingRule.swift`
- `LonelyPianist/Models/Mapping/MappingAction.swift`
- `LonelyPianist/Utilities/MIDINoteParser.swift`
- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Views/Mapping/RulesEditorSectionView.swift`
