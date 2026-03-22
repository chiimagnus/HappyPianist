# 安全

## 安全面与威胁模型概览

| 面向 | 资产 | 主要威胁 | 现有控制 |
| --- | --- | --- | --- |
| 输入注入 | 用户系统输入能力 | 未授权注入、误触发 | 辅助功能授权前置、显式状态提示 |
| 快捷指令执行 | 本机快捷指令 | 错误指令名、恶意规则配置 | 空名校验、URL 编码 |
| 本地数据 | Profile/Take | 数据损坏或误删 | SwiftData unique/cascade，仓储封装 |
| 音频渲染 | 本地文件输出 | 非法路径或覆盖风险 | 路径检查与目录创建逻辑 |

## 权限边界

- PianoKey 关键权限：macOS 辅助功能。
- `requestAccessibilityPermission()` 失败时不执行输入注入。
- 权限状态变化通过轮询与 app 激活回调刷新。

## 输入注入安全注意事项

| 风险点 | 触发条件 | 风险等级 | 缓解建议 |
| --- | --- | --- | --- |
| 规则误配置触发危险组合键 | 用户自定义 keyCombo | 中 | 增加规则校验与预览确认（后续可增强） |
| 持续高频注入 | 高频 MIDI 输入 + 高触发规则 | 中 | 通过规则设计与冷却机制限制（melody 有冷却） |
| 权限状态漂移 | 系统设置变更未及时感知 | 低-中 | 轮询 + app 激活时刷新 |

## 数据与隐私

- 当前数据默认本地存储，无网络同步链路。
- 仓库未见 API keys / token / secrets 配置。
- Recorder 数据可能包含用户演奏行为，应在产品层明确本地存储语义。

## 安全编码实践现状

1. 协议分层 + DI，便于隔离高权限操作服务。
2. 错误分支可见化（statusMessage / recorderStatusMessage）。
3. CLI 路径与参数有基本校验。

## 建议补强项

| 建议 | 价值 | 优先级 |
| --- | --- | --- |
| 对 `keyCombo` / `shortcut` 增加 allowlist 或风险提示 | 降低误触发风险 | 中 |
| 增加规则导入/导出签名与校验（若未来支持） | 防止恶意规则注入 | 中 |
| 添加安全审计日志（权限变更、关键动作触发） | 提升问题追踪性 | 中 |

## 示例片段

```swift
// AccessibilityPermissionService.swift
func hasAccessibilityPermission() -> Bool {
    AXIsProcessTrusted() || CGPreflightPostEventAccess()
}
```

```swift
// ShortcutExecutionService.swift
guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else {
    throw ShortcutServiceError.invalidName
}
```

## Coverage Gaps（如有）

- 未发现系统化安全测试用例与威胁建模文档。
- 未发现对“高风险规则配置”的产品侧防护设计。

## 来源引用（Source References）

- `PianoKey/Services/System/AccessibilityPermissionService.swift`
- `PianoKey/Services/System/ShortcutExecutionService.swift`
- `PianoKey/Services/Input/KeyboardEventService.swift`
- `PianoKey/ViewModels/PianoKeyViewModel.swift`
- `PianoKey/Services/Storage/SwiftDataMappingProfileRepository.swift`
- `PianoKey/Services/Storage/SwiftDataRecordingTakeRepository.swift`
- `Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift`
- `README.md`
