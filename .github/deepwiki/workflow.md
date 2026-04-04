# 工作流

## 进入仓库后的判断顺序

1. 先看 [business-context.md](business-context.md) 确定“你在改哪条用户旅程”。
2. 再看 [overview.md](overview.md) 与 [architecture.md](architecture.md) 锁定修改落点。
3. 最后看 `modules/*` + [data-flow.md](data-flow.md) 确认联动范围。

## 开发循环

| 阶段 | 动作 | 产物 | 注意事项 |
| --- | --- | --- | --- |
| 需求澄清 | 明确改动属于 mapping / recorder / window shell | 变更边界说明 | 避免跨模块一次改太多 |
| 实现 | 先改协议或模型，再改服务和 UI | 原子 commit | 保持 ViewModel 状态语义稳定 |
| 验证 | 构建 + 单测 + 手工冒烟 | 验证记录 | 权限链路必须实测 |
| 文档同步 | 更新 deepwiki 与 README（必要时） | 可追溯知识 | 业务入口页链接保持可达 |

## 按模块 / 产品线的工作方式

| 范围 | 先看哪里 | 默认验证 | 关键边界 |
| --- | --- | --- | --- |
| 主应用映射链路 | `modules/mapping-engine.md` | Single/Chord/Melody 手测 | 权限与注入副作用 |
| Recorder | `modules/recording-playback.md` | Rec/Play/Stop + 恢复 | 回放不触发注入 |
| 菜单栏壳层 | `modules/menubardockkit.md` | 窗口开闭 + Dock 行为 | activationPolicy 时序 |

## 文档同步工作流

- 功能语义变化：先更新 `business-context.md`，再更新对应技术页。
- 模块边界变化：同步更新 `architecture.md`、相关 `modules/*.md` 和 `INDEX.md`。
- 若调整规范，优先更新 `references/开发规范.md` 与本页“变更清单”。

## 构建、测试与发布工作流

| 阶段 | 推荐动作 | 结果 |
| --- | --- | --- |
| 本地构建 | `xcodebuild ... build` | 验证主 target 构建健康 |
| 本地测试 | `xcodebuild ... test`（可用时） | 验证录制与状态机回归 |
| 发布准备 | 更新版本号 + release 文档 | 形成可发布产物 |

## 变更清单

1. 是否影响权限文案与授权路径？
2. 是否影响 MappingAction 分支和规则编辑 UI？
3. 是否影响 Recorder 持久化结构与兼容性？
4. 是否影响 MenuBar/Dock 可见性行为？
5. 是否同步更新了 deepwiki 相关页面和 `INDEX.md`？

## 协作与评审关注点

- Review 优先看：状态机是否引入竞态、失败路径是否可见、用户可见行为是否与文档一致。
- 高风险改动：权限流程、输入注入、播放调度、SwiftData 实体字段变更。

## 示例片段

```swift
// LonelyPianist/ViewModels/LonelyPianistViewModel.swift
permissionPollingTask = Task { [weak self] in
    for attempt in 0..<120 {
        try? await Task.sleep(for: .milliseconds(500))
        // ... 轮询授权状态
    }
}
```

```swift
// AGENTS.md 中推荐的构建命令
xcodebuild -project LonelyPianist.xcodeproj -scheme LonelyPianist -configuration Debug build
```

## Coverage Gaps（如有）

- 缺少仓库内 CI workflow，PR 质量门禁依赖手工执行。
- 缺少正式发布自动化，版本切换流程需人工校验。

## 来源引用（Source References）

- `AGENTS.md`
- `README.md`
- `LonelyPianist/LonelyPianistApp.swift`
- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Views/Settings/Commands/AppCommands.swift`
- `LonelyPianist/Views/MenuBar/MenuBarMenuContentView.swift`
- `LonelyPianist/Views/Recording/RecorderTransportBarView.swift`
- `LonelyPianist.xcodeproj/project.pbxproj`
