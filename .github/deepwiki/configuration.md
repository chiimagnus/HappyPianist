# 配置

## 配置入口

| 配置面 | 位置 / 界面 | 写入方 | 说明 |
| --- | --- | --- | --- |
| App 图标显示模式 | Settings -> Picker | `AppIconDisplayViewModel` | `menuBarOnly` / `dockOnly` / `both` |
| 映射 Profile 配置 | Mappings 页 | `PianoKeyViewModel` + Repository | 规则、力度阈值、活动 profile |
| Recorder 数据 | Recorder 页 | `PianoKeyViewModel` + Recording Repository | Take 列表、重命名、删除 |
| 构建配置 | `PianoKey.xcodeproj/project.pbxproj` | Xcode | 部署目标、bundle id、版本号 |

## 运行时配置

| 配置项 | 位置 | 默认值 / 示例 | 影响 |
| --- | --- | --- | --- |
| `appIconDisplayMode` | `MenuBarDockKit/AppIconDisplayMode.swift` | App 启动时默认注册 `menuBarOnly` | 决定 Dock 与菜单栏显示行为 |
| `velocityEnabled` | `MappingProfilePayload` | 默认 `false`（empty payload） | 是否启用力度分层输出 |
| `defaultVelocityThreshold` | `MappingProfilePayload` | 默认 `90`（empty payload） | 单键高力度输出触发阈值 |
| Melody 间隔 | `MelodyMappingRule.maxIntervalMilliseconds` | 常见示例 `450~600` | 旋律匹配窗口 |
| 播放偏移 | `playheadSec` | 0 | Seek 与断点回放位置 |

## 构建与发布配置

| 配置项 | 位置 | 作用 | 联动项 |
| --- | --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` | `project.pbxproj` | 应用唯一标识 | 权限重置与签名流程 |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | `project.pbxproj` | 版本展示与构建号 | 发布记录、release notes |
| `MACOSX_DEPLOYMENT_TARGET` | `project.pbxproj` | 主 target 最低部署目标 | 与 Swift package 平台约束兼容 |
| `ENABLE_APP_SANDBOX` / `ENABLE_HARDENED_RUNTIME` | `project.pbxproj` | 运行安全策略 | 权限行为与系统兼容 |

## 权限、认证与敏感信息

- PianoKey 关键权限是 **辅助功能（Accessibility）**。
- 授权请求通过 `AXIsProcessTrustedWithOptions` + `CGRequestPostEventAccess`。
- 仓库中未发现 API keys / secrets / `.env` 依赖；主要是本地系统权限模型。

## 功能开关与行为差异

| 开关 | 开关位置 | 行为差异 | 生效时机 |
| --- | --- | --- | --- |
| AppIconDisplayMode | Settings Picker / UserDefaults | 决定 Dock 与菜单栏可见性 | 变更后立即应用 |
| Velocity Enabled | Mappings -> Rules | 单键输出是否按力度分流 | 保存 profile 后立即生效 |
| RecorderMode | `PianoKeyViewModel.recorderMode` | idle/recording/playing 三态约束按钮状态 | 运行时即时 |

## 配置漂移检查

1. 若调整图标显示模式语义，需同步 `SettingsView`、`MenuBarExtraVisibilityStore`、`DockPresenceService`。
2. 若新增 `MappingActionType`，需同步规则编辑 UI、解析器与执行分支。
3. 若变更 SwiftData 实体字段，需同步仓储读写和回放/渲染流程。

## 常见误配

- 授权未完成就开始监听：看起来“有 MIDI”但无跨应用输出。
- 把和弦规则当“包含匹配”：当前实现是严格等值匹配。
- 把回放当注入：回放不会触发 `KeyboardEventService`。

## 示例片段

```swift
// PianoKey/PianoKeyApp.swift
UserDefaults.standard.register(defaults: [
    AppIconDisplayMode.userDefaultsKey: AppIconDisplayMode.menuBarOnly.rawValue
])
```

```swift
// PianoKey/Services/System/AccessibilityPermissionService.swift
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: kCFBooleanTrue as Any] as CFDictionary
let axGranted = AXIsProcessTrustedWithOptions(options)
let cgGranted = CGRequestPostEventAccess()
```

## Coverage Gaps（如有）

- 没有看到“配置版本迁移”机制（尤其 SwiftData schema 演进场景）。
- 没有看到多环境（dev/staging/prod）配置分层机制。

## 来源引用（Source References）

- `PianoKey/PianoKeyApp.swift`
- `PianoKey/ViewModels/Settings/AppIconDisplayViewModel.swift`
- `PianoKey/ViewModels/MenuBar/MenuBarExtraVisibilityStore.swift`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/AppIconDisplayMode.swift`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/DockPresenceService.swift`
- `PianoKey/Models/Mapping/MappingProfile.swift`
- `PianoKey/Views/Mapping/RulesEditorSectionView.swift`
- `PianoKey/Services/System/AccessibilityPermissionService.swift`
- `PianoKey.xcodeproj/project.pbxproj`
- `AGENTS.md`
