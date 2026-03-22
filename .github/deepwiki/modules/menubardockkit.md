# 模块：MenuBarDockKit

## 职责与边界

- 负责菜单栏工具类 App 的 Dock/菜单栏图标显示策略与主窗口桥接。
- 提供可复用的 `WindowReader` 与 `MainWindowDockVisibilityController`。
- 不负责 PianoKey 的 MIDI、映射和录制业务。

## 目录范围

| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `Packages/MenuBarDockKit/Sources/MenuBarDockKit/AppIconDisplayMode.swift` | 显示模式定义 | UserDefaults 真值 |
| `.../DockPresenceService.swift` | Dock 显示策略 | 窗口展示前后切换策略 |
| `.../MainWindowDockVisibilityController.swift` | 主窗口生命周期观察 | 绑定窗口通知 |
| `.../WindowReader.swift` | SwiftUI -> NSWindow 桥接 | 读取当前承载窗口 |

## 入口点与生命周期

| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| `AppIconDisplayMode.current` | `AppIconDisplayMode.swift` | 读取/写入设置时 | 持久化显示策略 |
| `prepareForPresentingMainWindow()` | `DockPresenceService.swift` | 打开主窗口前 | 必要时把 activationPolicy 切为 `.regular` |
| `hideDockIfAllowedWhenNoVisibleWindows()` | `DockPresenceService.swift` | 主窗口关闭后 | `menuBarOnly` 模式下隐藏 Dock |
| `attachWindow(_:)` | `MainWindowDockVisibilityController.swift` | 主窗口绑定时 | 监听窗口主态/关闭通知 |

## 关键文件

| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `AppIconDisplayMode.swift` | 模式与本地化名称 | 显示策略单一来源 |
| `DockPresenceService.swift` | activationPolicy 调整 | 用户可见行为关键 |
| `MainWindowDockVisibilityController.swift` | 通知绑定与清理 | 防止观察者泄漏 |
| `WindowReader.swift` | NSWindow 读取 | SwiftUI 集成入口 |

## 上下游依赖

| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 上游 | `PianoKey` Settings/MenuBar | 调用模式切换与窗口显示函数 | 决定图标行为 |
| 下游 | AppKit `NSApplication`/`NSWindow` | 改 activation policy、监听通知 | 影响窗口与 Dock 可见性 |

## 对外接口与契约

| 接口 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `public enum AppIconDisplayMode` | `AppIconDisplayMode.swift` | `AppIconDisplayViewModel` | 图标显示模式 |
| `public enum DockPresenceService` | `DockPresenceService.swift` | AppCommands/MenuBar | Dock 显示管理 |
| `public final class MainWindowDockVisibilityController` | `MainWindowDockVisibilityController.swift` | `MainWindowView` | 主窗口通知控制器 |
| `public struct WindowReader` | `WindowReader.swift` | SwiftUI View | 注入 NSWindow 引用 |

## 数据契约、状态与存储

- `appIconDisplayMode` 存于 `UserDefaults`。
- `MenuBarOnly` / `DockOnly` / `Both` 三态映射到 activationPolicy。
- 控制器内部状态包括 window 弱引用与两个通知观察者句柄。

## 配置与功能开关

- `AppIconDisplayMode.userDefaultsKey` 是唯一持久化键。
- `showsMenuBarIcon` / `showsDockIcon` 决定 UI 插入与 Dock 可见行为。

## 正常路径与边界情况

1. 正常：用户切换显示模式 -> 立即更新 activation policy。
2. 边界：`menuBarOnly` 下打开窗口时需临时显示 Dock，关闭后恢复隐藏。
3. 边界：通知观察者必须及时移除，避免重复回调。

## 扩展点与修改热点

- 新显示模式会影响：`displayName`、`shows*`、activationPolicy 逻辑、Settings Picker。
- 窗口行为改动需同步 `WindowReader` 与 controller 绑定流程。

## 测试与调试

- 当前包测试为 placeholder，需要补充 activationPolicy 与通知行为测试。
- 调试时重点看窗口关闭后 Dock 是否按模式恢复。

## 示例片段

```swift
// AppIconDisplayMode.swift
public static var current: AppIconDisplayMode {
    get {
        let rawValue = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return AppIconDisplayMode(rawValue: rawValue) ?? .both
    }
    set {
        UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
    }
}
```

```swift
// DockPresenceService.swift
if AppIconDisplayMode.current == .menuBarOnly, app.activationPolicy() != .regular {
    app.setActivationPolicy(.regular)
}
```

## Coverage Gaps（如有）

- 缺少实质单元测试覆盖窗口状态切换。

## 来源引用（Source References）

- `Packages/MenuBarDockKit/Package.swift`
- `Packages/MenuBarDockKit/README.md`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/AppIconDisplayMode.swift`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/DockPresenceService.swift`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/MainWindowDockVisibilityController.swift`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/WindowReader.swift`
- `Packages/MenuBarDockKit/Tests/MenuBarDockKitTests/MenuBarDockKitTests.swift`
- `PianoKey/ContentView.swift`
