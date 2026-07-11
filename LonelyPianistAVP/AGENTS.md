# 项目开发规范与指南

本目录是 visionOS（Apple Vision Pro）端原型工程。

- App 代码：`LonelyPianistAVP/`（RealityKit / ImmersiveSpace）
- 测试：`LonelyPianistAVPTests/`（Swift Testing）
- 资源包/内容包：`Packages/RealityKitContent/`
- 当前工程目标随项目设置为 visionOS 26.0。

# visionOS 开发补充规范

本文件专注 visionOS 平台本身（空间 UI / RealityKit / ARKit 世界感知等）的差异与增量规则：

- SwiftUI 的 visionOS 窗口/空间 UI 约定（Window / Volumetric / Ornament 等）
- RealityKit / RealityView / ECS 的使用边界与常见模式
- visionOS 上 ARKit 世界感知能力的可用性/授权/Provider 选择
- 与舒适性相关的性能底线（避免掉帧/阻塞）

## 技术栈
- **语言:** 遵循项目的 Swift 版本与并发（Swift Concurrency）设置。
- **UI 框架:** SwiftUI 为主；仅在用户明确要求时才使用 UIKit。
- **3D 引擎:** RealityKit（Entity Component System, ECS）。
- 务必多加调用 Apple-docs skill，如果本规范存在问题，以apple-docs skill调研得到的内容为准，并且需要更新本文档。

## 编码规范

### 1. SwiftUI 与窗口管理
- **WindowGroups:** 在 `App` struct 里为每个 `WindowGroup` 明确且互不冲突地定义 `id`。
- **Ornaments:** 使用 `.ornament()` 来承载附着在窗口上的工具条与控制组件。若按钮属于“窗口 chrome/外壳”，不要把标准悬浮按钮直接塞进 window content 区域。
- **玻璃背景:** 优先使用系统默认玻璃背景；需要时使用 `.glassBackgroundEffect()`。
- **Hover Effects:** 标准 SwiftUI `Button` 使用系统样式时已有默认 hover，无需重复添加 `.hoverEffect()`；自定义交互控件必须确保有 hover 反馈，仅在系统未提供时显式添加。
- **按钮样式:** 为按钮设置 `.buttonBorderShape()` 以符合 visionOS 的空间风格（例如 `.roundedRectangle`、`.capsule`、`.circle`）。
- **“屏幕”幻觉:** 不要用 `UIScreen.main.bounds`。visionOS 没有“屏幕”。用 `GeometryReader` 或 `GeometryReader3D`。
- 使用 `pushWindow` 前必须核对完整窗口流：它会后台保留来源窗口、让目标窗口继承来源窗口尺寸；关闭目标才恢复来源，且不能从已 pushed 的窗口再次 push。仅用于真正的单层“前进／返回”窗口栈，不能拿它修补关闭窗口导致 app 退出的问题。
- 需要始终贴附在主窗口旁、随主窗口移动的面板，使用 `.ornament`（例如 `.scene(.trailing)`）；独立 `Window` 加 `defaultWindowPlacement(.trailing(...))` 只决定首次位置，之后系统允许用户移动和调整，不能作为持久贴附行为。

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
- **主线程/主 Actor:** 严禁在主线程做阻塞操作；掉帧会引发眩晕不适。重型物理/数据处理要明确移出主 actor。
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
- **Hover Effects:** 交互元素必须有 hover 状态；系统控件的默认效果即可满足此要求。
- **Validation:** 以最新 Apple 文档校验函数与 API 可用性。
- **错误处理:** 对 model 加载等关键路径做合理错误处理。
- **Documentation:** public API 使用清晰命名并写必要的 doc comments。
- **交付格式:** 遵循下方约定的输出格式。

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
