# 项目开发规范与指南

## 项目结构与模块组织

本目录是 visionOS（Apple Vision Pro）端原型工程。

- App 代码：`LonelyPianistAVP/`（RealityKit / ImmersiveSpace）
- 测试：`LonelyPianistAVPTests/`（Swift Testing）
- 资源包/内容包：`Packages/RealityKitContent/`
- 当前工程目标随项目设置为 visionOS 26.0。

## 代码风格与命名规范

- 命名：类型 `PascalCase`；变量/函数 `camelCase`；协议以 `Protocol` 结尾；实现类型以 `Service` 结尾。
- 分层：View 只负责展示与交互绑定；状态与业务编排放 `ViewModels/`；副作用与基础设施放 `Services/`；依赖通过注入传递。

## 测试指南

- 测试框架：Swift Testing（`import Testing` + `@Test` + `#expect`）。
- 新增测试文件放在 `LonelyPianistAVPTests/`，命名 `*Tests.swift`。

## 开发规范（详细）

对齐说明（与下方“真源规范全文”冲突时，以本仓库为准）：
- 本仓库在 visionOS 端使用 `RealityView` / `ImmersiveSpace`。
- 本仓库单元测试使用 Swift Testing（不是 XCTest）。
- 通用 Apple/Swift 基线规范全文在仓库根目录 `AGENTS.md`。

### visionOS / RealityKit 补充规范（真源全文）

```md
# visionOS 开发补充规范

本文件是 `/Users/chii_magnus/.codex/skills/init/references/apple-app-dev-standards.md` 的 visionOS / RealityKit / spatial computing 补充规范。

优先级：
- 项目内 `AGENTS.md` / `CONTRIBUTING.md` / README 中的约束优先。
- Apple/Swift 基线规范优先于本文的通用建议。
- 本文只补充 visionOS 平台细则；不要用它覆盖项目既有架构、测试框架、最低系统版本或多平台策略。

## 项目知识

### 技术栈
- **OS:** 遵循项目当前的 deployment target。仅在项目最低版本支持时，才使用更新的 visionOS API。
- **语言:** 遵循项目的 Swift 版本与并发（Swift Concurrency）设置。
- **UI 框架:** SwiftUI 为主；仅在用户明确要求时才使用 UIKit。
- **3D 引擎:** RealityKit（Entity Component System, ECS）。

## 编码规范

### 1. SwiftUI 与窗口管理
- **WindowGroups:** 在 `App` struct 里为每个 `WindowGroup` 明确且互不冲突地定义 `id`。
- **Ornaments:** 使用 `.ornament()` 来承载附着在窗口上的工具条与控制组件。若按钮属于“窗口 chrome/外壳”，不要把标准悬浮按钮直接塞进 window content 区域。
- **玻璃背景:** 优先使用系统默认玻璃背景；需要时使用 `.glassBackgroundEffect()`。
- **Hover Effects:** 自定义交互控件必须加 `.hoverEffect()`，以支持眼动注视的 hover 高亮反馈。
- **按钮样式:** 为按钮设置 `.buttonBorderShape()` 以符合 visionOS 的空间风格（例如 `.roundedRectangle`、`.capsule`、`.circle`）。

### 2. RealityKit 与 ECS（Entity Component System）
- **RealityView:** 所有 3D 内容集成都使用 `RealityView`。
  ```swift
  RealityView { content in
      // 在这里加载并添加实体entities
      if let model = try? await Entity(named: "Scene") {
          content.add(model)
      }
  } update: { content in
      // 基于 SwiftUI 状态变化的更新逻辑
  }
  ```
- **Attachments:** 在 `RealityView` 中使用 `Attachment` 将 SwiftUI 视图嵌入 3D 空间。
- **异步加载:** 资源必须异步加载（例如 `_ = try! await Entity(named: "MyEntity")`、`async let textureA = try? TextureResource(named:"textureA.jpg")`），避免阻塞主线程。
- **Components:** 组合优于继承。自定义组件应实现 `Component` 与 `Codable`。
- **可拖拽实体:** 必须同时具备 `CollisionComponent` 和 `InputTargetComponent`。
  ```swift
  entity.components.set(CollisionComponent(shapes: [.generateBox(size: [0.1, 0.1, 0.1])]))
  entity.components.set(InputTargetComponent())
  ```
- **Mesh 资源:** 仅允许生成：`box`、`sphere`、`plane`、`cylinder`、`cone`。

### 3. 交互与输入
- **手势:**
  - **2D:** 标准 SwiftUI 手势可用于 Window。
  - **3D:** 使用面向实体的 `.gesture(...)`（targeted to entities）。

### 4. 并发与线程
- **严格并发:** Swift 6.2 默认对 View 与 UI 逻辑采用 `@MainActor` 隔离。假设严格隔离检查开启，并且一切默认在 `@MainActor` 上运行。
- **Main Actor:** UI 更新与 RealityKit 的变更默认都在 `@MainActor` 上。只有在需要增强可读性或覆盖默认行为时，才显式标注 `@MainActor`。
- **后台任务:** 重型物理/数据处理要明确移出主 actor，使用 detached tasks 或 non-isolated actors。
- **Task 管理:** 不要滥用 `Task.detached`。在 teardown 时取消长生命周期任务。

### 5. 进阶空间架构
- **基于 System 的逻辑:** 对于复杂且持续运行的行为（AI、物理、群集等），不要塞进 SwiftUI 的 `RealityView` update 闭包里。应实现自定义 `System` 并注册。

### 6. ARKit 与世界感知
- **仅 Full Space:** 只有当 app 处于 `Full Space` 时，ARKit 数据才可用。在 Shared Space（Windows/Volumes）里不可用。
- **Session 管理:** 使用 `ARKitSession` 管理 data providers，并保持对 session 的强引用。
- **授权:**
  - 只为“确实会访问的 ARKit 数据类型”添加对应的 usage descriptions:
    - `NSHandsTrackingUsageDescription`: 当你使用 hand tracking 时才需要。
    - `NSWorldSensingUsageDescription`: 只有当你使用 image tracking / plane detection / scene reconstruction 时才需要。
  - World *tracking*（例如 `WorldTrackingProvider`）不需要 world-sensing 授权。除非真的需要 world-sensing 数据，否则不要请求这类权限。
  - `NSCameraUsageDescription` / `NSMainCameraUsageDescription` 用于 camera access（例如 `ARKitSession.AuthorizationType.cameraAccess` / camera frame 相关能力）。除非你确实要请求 camera access，否则不要添加。
  - 优雅处理授权（例如检查 `await session.requestAuthorization(for:)` 的结果）。
- **Data Providers:**
  - `WorldTrackingProvider`: 用于 device pose 与 world anchors。
  - `PlaneDetectionProvider`: 用于检测桌面/地面/墙等平面。
  - `SceneReconstructionProvider`: 用于环境网格与遮挡（meshing/occlusion）。
  - `HandTrackingProvider`: 用于手部追踪（可能需要特定 entitlements）。
- **Anchors:** 使用 ARKit anchor 的 `UUID` 来关联 RealityKit entities。

### 7. Swift 语言规范
- **Observable 类:** `@Observable` 类默认就是 `@MainActor`，通常不需要再额外标注 `@MainActor`。
- **严格并发:** 假设严格 Swift 并发规则开启，并且一切默认在 `@MainActor` 上运行。
- **Swift 原生 API 优先:** 当 Swift 原生 API 可用时优先使用（例如对字符串用 `replacing("hello", with: "world")`，而不是 `replacingOccurrences(of: "hello", with: "world")`）。
- **现代 Foundation API:** 优先使用现代 Foundation API，例如用 `URL.documentsDirectory` 获取 documents 目录，用 `appending(path:)` 拼接 URL。
- **数字格式化:** 不要用 C 风格格式化（例如 `Text(String(format: "%.2f", abs(myNumber)))`）；应使用 `Text(abs(change), format: .number.precision(.fractionLength(2)))`。
- **静态成员查找:** 能用静态成员就用静态成员（例如 `.circle` 而不是 `Circle()`，`.borderedProminent` 而不是 `BorderedProminentButtonStyle()`）。
- **现代并发:** 不要使用旧式 GCD（例如 `DispatchQueue.main.async()`）。需要类似行为时使用 Swift Concurrency。
- **文本过滤:** 基于用户输入进行文本过滤时，使用 `localizedStandardContains()`，不要用 `contains()`。
- **强解包:** 避免强制解包与 `try!`，除非它确实不可恢复。

### 8. SwiftUI 规范
- **Foreground Style:** 使用 `foregroundStyle()`，不要用 `foregroundColor()`。
- **Clip Shape:** 使用 `clipShape(.rect(cornerRadius:))`，不要用 `cornerRadius()`。
- **Tab API:** 使用新的 `Tab` API，不要用 `tabItem()`。
- **Observable:** 不要使用 `ObservableObject`；优先使用 `@Observable`。
- **onChange:** 不要使用 `onChange()` 的 1 参数变体；应使用 2 参数变体或无参数变体。
- **onTapGesture:** 除非你确实需要 tap 的位置或 tap 次数，否则不要用 `onTapGesture()`；其他情况用 `Button`。
- **Task.sleep:** 不要用 `Task.sleep(nanoseconds:)`；用 `Task.sleep(for:)`。
- **UIScreen:** 不要用 `UIScreen.main.bounds` 来读取可用空间大小。使用 `GeometryReader` 或 `GeometryReader3D`。
- **视图拆分:** 不要用 computed properties 拆分视图；应创建新的 `View` struct。
- **动态字体:** 不要强制指定字体大小；使用 Dynamic Type。
- **导航:** 使用 `navigationDestination(for:)` 并统一用 `NavigationStack`，不要用旧的 `NavigationView`。
- **按钮 label:** 若用图片作为按钮 label，要同时提供文本，例如 `Button("Tap me", systemImage: "plus", action: myButtonAction)`。
- **图片渲染:** 渲染 SwiftUI 视图成图片时优先 `ImageRenderer`，不要用 `UIGraphicsImageRenderer`。
- **字重:** 没有充分理由不要用 `fontWeight()`；要加粗用 `bold()`，不要用 `fontWeight(.bold)`。
- **GeometryReader:** 若有更新替代方案可行（例如 `containerRelativeFrame()`、`visualEffect()`），不要用 `GeometryReader`。
- **ForEach + enumerated:** 用 `ForEach(x.enumerated(), id: \.element.id)`，不要先转 `Array` 再 ForEach。
- **滚动条:** 隐藏滚动条用 `.scrollIndicators(.hidden)`，不要在初始化时用 `showsIndicators: false`。
- **视图逻辑:** 把视图逻辑放进 view models 或类似层，确保可测试性。
- **AnyView:** 除非绝对必要，否则避免 `AnyView`。
- **硬编码:** 未被要求时，不要硬编码 padding 与 stack spacing。
- **UIKit Colors:** SwiftUI 代码中避免使用 UIKit 的颜色。

### 9. Swift 6+ 迁移指南

#### ⚠️ 破坏性变更（Swift 6）
| 问题 | Swift 5 | Swift 6 |
|------|---------|---------|
| 数据竞争 | Warnings | **Compile errors** |
| 缺少 `await` | Warning | **Error** |
| 非 Sendable 跨 actor | Allowed | **Error** |
| 全局可变状态 | Allowed | **必须隔离或 Sendable** |

#### 🚨 常见坑
- **Sendable:** 跨 actor 传递的 class 需要 `@unchecked Sendable`，或改成 struct/actor。
- **闭包:** escaping 闭包会捕获隔离上下文，注意 `@Sendable` 约束。
- **Actor 可重入:** `await` 之后的代码可能看到被其他任务修改过的状态，不要假设连续性。
- **全局状态:** `nonisolated(unsafe)` 仅作为兼容遗留代码的最后手段。

#### Swift 6.2 改进
- **`defaultIsolation(MainActor.self)`** — 为 UI targets 消除大量 `@MainActor` 样板。
- **`NonisolatedNonsendingByDefault`** — nonisolated async 默认继承调用方 actor；需要后台并发用 `@concurrent`。
- **Typed Throws** — `throws(MyError)` 用于更可穷举的错误处理。

#### 推荐的 Package.swift
```swift
swiftSettings: [
    .defaultIsolation(MainActor.self),
    .enableExperimentalFeature("NonisolatedNonsendingByDefault")
]
```

#### 快速模式
```swift
// Swift 6.2: Inherits caller's isolation
nonisolated func fetchData() async throws -> Data { ... }

// Explicit background execution
@concurrent nonisolated func heavyWork() async -> Result { ... }

// Typed throws
func load() throws(LoadError) { ... }
```

## RealityKit 组件参考

### 渲染与外观
| Component | 说明 |
|-----------|------|
| `ModelComponent` | 包含实体外观所需的 mesh 与 materials |
| `ModelSortGroupComponent` | 配置实体 model 的渲染顺序 |
| `OpacityComponent` | 控制实体及其子实体的不透明度 |
| `AdaptiveResolutionComponent` | 基于观察距离自适应分辨率 |
| `ModelDebugOptionsComponent` | 为 model 启用调试可视化选项 |
| `MeshInstancesComponent` | 高效渲染多种唯一变体的资产 |
| `BlendShapeWeightsComponent` | 控制 blend shape（morph target）权重 |

### 用户交互
| Component | 说明 |
|-----------|------|
| `InputTargetComponent` | 让实体可接收输入事件（手势必需） |
| `ManipulationComponent` | 提供更流畅、沉浸的交互操控行为与效果 |
| `GestureComponent` | 处理实体的手势识别 |
| `HoverEffectComponent` | 用户注视/聚焦实体时的高亮效果 |
| `AccessibilityComponent` | 配置实体的无障碍特性 |
| `BillboardComponent` | 让实体始终朝向相机/用户 |

### 呈现与 UI
| Component | 说明 |
|-----------|------|
| `ViewAttachmentComponent` | 将 SwiftUI 视图嵌入 3D 空间 |
| `PresentationComponent` | 从实体发起 SwiftUI 的 modal presentation |
| `TextComponent` | 在场景里渲染 3D 文本 |
| `ImagePresentationComponent` | 在 3D 空间中显示图片 |
| `VideoPlayerComponent` | 在实体上播放视频 |

### 传送门与环境
| Component | 说明 |
|-----------|------|
| `PortalComponent` | 创建 portal，用于渲染另一个 world |
| `WorldComponent` | 将实体标记为一个独立可渲染的 world |
| `PortalCrossingComponent` | 控制实体穿越 portal 时的行为 |
| `EnvironmentBlendingComponent` | 与真实环境进行融合渲染 |

### 锚定与空间
| Component | 说明 |
|-----------|------|
| `AnchoringComponent` | 将实体锚定到真实世界位置 |
| `ARKitAnchorComponent` | 将实体关联到 ARKit anchor |
| `SceneUnderstandingComponent` | 访问 scene understanding 数据（planes、meshes） |
| `DockingRegionComponent` | 定义内容可停靠区域 |
| `ReferenceComponent` | 引用外部实体文件以支持懒加载 |
| `AttachedTransformComponent` | 将实体 transform 附着到另一实体 |

### 相机
| Component | 说明 |
|-----------|------|
| `PerspectiveCameraComponent` | 配置透视相机参数 |
| `OrthographicCameraComponent` | 配置正交相机参数 |
| `ProjectiveTransformCameraComponent` | 自定义相机投影变换 |

### 光照与阴影
| Component | 说明 |
|-----------|------|
| `PointLightComponent` | 点光源（全向） |
| `DirectionalLightComponent` | 平行光源（类似太阳） |
| `SpotLightComponent` | 聚光灯（锥形） |
| `ImageBasedLightComponent` | 基于 HDR 的环境光照 |
| `ImageBasedLightReceiverComponent` | 让实体接收 IBL |
| `GroundingShadowComponent` | 生成/接收地面阴影以增强真实感 |
| `DynamicLightShadowComponent` | 动态光照产生的阴影 |
| `EnvironmentLightingConfigurationComponent` | 配置环境光照行为 |
| `VirtualEnvironmentProbeComponent` | 虚拟环境反射探针 |

### 音频
| Component | 说明 |
|-----------|------|
| `SpatialAudioComponent` | 3D 空间定位音频源 |
| `AmbientAudioComponent` | 无方向的环境音 |
| `ChannelAudioComponent` | 基于 channel 的音频播放 |
| `AudioLibraryComponent` | 存放多份音频资源 |
| `ReverbComponent` | 混响效果 |
| `AudioMixGroupsComponent` | 将音频分组混音 |

### 动画与角色
| Component | 说明 |
|-----------|------|
| `AnimationLibraryComponent` | 存放多份动画资源 |
| `CharacterControllerComponent` | 角色移动与物理 |
| `CharacterControllerStateComponent` | 角色控制器的运行时状态 |
| `SkeletalPosesComponent` | 骨骼动画 pose |
| `IKComponent` | 逆向运动学（IK） |
| `BodyTrackingComponent` | 全身追踪集成 |

### 物理与碰撞
| Component | 说明 |
|-----------|------|
| `CollisionComponent` | 碰撞形状（交互必需） |
| `PhysicsBodyComponent` | 为实体加入物理模拟（质量、摩擦等） |
| `PhysicsMotionComponent` | 控制速度与角速度 |
| `PhysicsSimulationComponent` | 配置物理模拟参数 |
| `ParticleEmitterComponent` | 粒子发射器 |
| `ForceEffectComponent` | 力场效果 |
| `PhysicsJointsComponent` | 物理关节 |
| `GeometricPinsComponent` | 几何附着点 |

### 网络与同步
| Component | 说明 |
|-----------|------|
| `SynchronizationComponent` | 跨网络同步实体状态 |
| `TransientComponent` | 标记实体为非持久化 |

## 边界与常见陷阱

### 🚫 禁止事项
- **Legacy ARKit:** 不要使用 `ARView`（iOS ARKit）。它在 visionOS 上已废弃/不可用。必须使用 `RealityView`。
- **“屏幕”幻觉:** 不要用 `UIScreen.main.bounds`。visionOS 没有“屏幕”。用 `GeometryReader` 或 `GeometryReader3D`。
- **阻塞主线程:** 严禁在主线程做阻塞操作。掉帧会引发眩晕不适。
- **原始眼动数据:** 不要尝试直接访问 gaze 坐标。
- **Scene 使用:** 不要在主 App target 之外依赖 `Scene`。
- **跨平台判断:** visionOS-only target 中避免不必要的 `#if`。共享 target 中仅用非常窄的 `#if os(...)` 隔离 visionOS 不可用 API，并遵循仓库的平台布局。

### ✅ 必做事项
- **Hover Effects:** 交互元素必须有 hover 状态。
- **Validation:** 以最新 Apple 文档校验函数与 API 可用性。
- **错误处理:** 对 model 加载等关键路径做合理错误处理。
- **Documentation:** public API 使用清晰命名并写必要的 doc comments。
- **交付格式:** 遵循下方约定的输出格式。

### 坐标系与校准语义（本仓库约定）

- **A0/C8 的语义是“琴键前沿线”**（keyboard-local `z = 0`），不是按键中心线。
- 按键中心线通过 `frontEdgeToKeyCenterLocalZ` 表达（通常为 `± keyDepth/2`）；偏移正负需要用 `DeviceAnchor`（`WorldTrackingProvider.queryDeviceAnchor(atTimestamp:)`）判定“用户在键盘哪一侧”。
- **KeyboardFrame 坐标轴约定**：A0 为原点，+X 指向 C8（水平投影），+Y 向上，+Z 右手系推导（满足 `cross(x, y) == z`）。
- 练习设置里可开启 `debugKeyboardAxesOverlayEnabled` 显示键盘坐标轴（含 X/Y/Z 标注），用于排查“方向反了/整体偏移”等问题。

## 推荐代码模式

### 带错误处理的 Model 加载
```swift
@State private var entity: Entity?

var body: some View {
    RealityView { content in
        do {
            let model = try await Entity(named: "MyModel", in: realityKitContentBundle)
            content.add(model)
        } catch {
            print("Failed to load model: \(error)")
        }
    }
}
```

### Volumetric Window 定义
```swift
WindowGroup(id: "VolumetricWindow") {
    ContentView()
}
.windowStyle(.volumetric)
.defaultSize(width: 1.0, height: 1.0, depth: 1.0, in: .meters)
```

### RealityView Attachment 用法
```swift
RealityView { content in
    let entity = Entity()
    let attachment = ViewAttachmentComponent(rootView: AttachmentView())
    entity.components.set(attachment)
    entity.position = [0, 1.5, -1]
    content.add(entity)
}
```

### 通过 Environment 注入的 Observable App State
用于 app 级状态管理，并与 SwiftUI Environment 集成：
```swift
@Observable
final class AppState {
    var count = 0
}

@main
struct VisionApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}

struct MyView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Text("Count: \(appState.count)")
    }
}
```

### visionOS 的按钮样式
为了正确的空间按钮风格，始终使用 `.buttonBorderShape()`：
```swift
Button(action: {
    // 在这里处理按钮动作
}, label: {
    Label("Play First Episode", systemImage: "play.fill")
        .padding(.horizontal)
})
.foregroundStyle(.black)
.tint(.white)
.buttonBorderShape(.roundedRectangle)
```
可用形状：`.roundedRectangle`、`.roundedRectangle(radius:)`、`.capsule`、`.circle`。

## 交付物
- 一份简洁计划（<= 8 条要点），并且每条都能对应到具体实现步骤。
- **假设:** 如有任何歧义，做最合理的假设，并在最后列出。
- **实现:** 输出完整、可编译的 Swift/RealityKit 代码，并遵守本文所有规则。
- **输出格式:**
  - 文件树
  - 完整文件内容（用 fenced code blocks），并标注：`// FILE: <path>`
  - Xcode 的 build/run 备注（targets、capabilities/entitlements 如有）。
  - 验证总结（RealityView 用法、组件是否正确等）。
  - 列出所有合理假设。
```
