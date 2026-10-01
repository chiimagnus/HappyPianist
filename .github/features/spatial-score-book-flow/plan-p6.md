# Plan P6 — 共存回归、完整设计验收与证据收口

**Goal:** 证明完整 3D 产品成立，原 2D 仍可用；把设计板、软件/硬件证据与长期文档收口。
**Non-goals:** 不在此补前期遗漏的保存安全/无障碍基础，不借收口删除 2D，不修复无关基线失败。
**Approach:** 对照两条真实路径和公共职责回归；随后逐板走查 physical AVP，记录未通过项而非用图片代替结果。
**Acceptance:** D01–D10 与全部需求有可追溯证据；2D/3D 无争用/数据丢失；长期 docs 描述实际交付，而非未来计划。
**Rules:** 每个 owning task 已有自己的 tests/build/原子提交。P6 用于查遗漏和全链路验证，不替代前期理解；真机未跑不能给最终 Go。

依赖：P1–P5 软件和所属设计/真机 Gate，不能引用 archive 的 task 状态或通过数字。

## P6-T1 验证两种产品共存与真实副作用边界

**Files / 回归锚点：**
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialExperienceCoexistenceTests.swift`；已接入的 Spatial lifecycle/entity/notation/companion/control suites。
- 现 `HappyPianistAVPTests/Library/` 导入/选择/试听/删除，`Practice/PracticeLaunchLifecycleTests.swift`、`PracticeResumeLifecycleTests.swift`、`PracticeProgressRepositoryTests.swift`、`PracticeSessionRecorderTests.swift`。
- 现 `Tracking/ARGuideImmersiveLifecycleTests.swift`、`ARTrackingServiceLifecycleTests.swift`、`Piano/PianoModePreparationRouteTests.swift`、`VirtualPiano/`、`Immersive/VirtualPerformerOverlayLifecycleTests.swift`。
- 原 `Views/Library/LibraryRecordCarousel.swift`、`VinylRecordView.swift`、`TurntableTonearmView.swift`、`Views/Practice/Step/PracticeStepView.swift`、`Packages/HappyPianistCore/Sources/Notation/GrandStaffNotationView.swift` 的真实 consumer 保留。
- 如发现本 feature 引入的缺陷，在拥有该职责的最小公共源文件修复并同步新旧 caller，不在每个 Window 加重复 workaround。

**自动化与实际操作矩阵：**

| 路径/条件 | 要证明的最终行为 |
| --- | --- |
| 默认启动、从未点 3D | 原 Vinyl/试听/导入/准备/滚谱/二维键盘/结果/退出可用，无自动开空间 |
| 2D prepare/practice 活跃时点 3D | 拒绝抢 scene/session，无额外 provider/audio/metadata/progress |
| 3D 活跃、原 Window 重开/消失/非 active | 不启动第二 session，不盖 selection，不误关新 space |
| 3D 打开 pending/取消/失败/退出重进 | 原入口可恢复，无孤儿 scene/实体/迟到回写 |
| Library 管理导入/冲突/取消/删除 | 真 file/index/progress 副作用，bundled 不删，返场真实 entries |
| 真谱 repeat/rest/seek/range/loop/新 revision | 自动页不改音乐，旧 2D 滚谱/记谱不回退 |
| Audio/MIDI/Virtual Piano 原模式 | 两种现实模式新旧可用，Virtual Piano 原路径保留，不静默替换 |
| Teaching/AI/recording/take playback | 复用互斥，原后端严格选择；停止后真实声音/录音/hand root 消失 |
| flush 失败 / recorder finalize 失败 | 用户返回不离开/丢增量，重试后读到真实落盘数据 |
| 明确 discard / 已保存 checkpoint | 仅未保存增量丢弃，既有文件/小节聚合保留 |
| 后台/系统退出/恢复/快速新请求 | 无旧输入输出/tasks/动画复活；不能把 forced close 当保存成功 |
| VoiceOver/Reduce Motion/Dynamic Type/不只颜色 | 每个关键动作有等价语义，动画不是功能必要条件，无装饰重复阅读 |

**验证命令与证据规则（各 phase 同样适用）：**
1. `rtk make doctor`、`rtk make destinations` 获取实际环境，使用现有 destination；不照抄 archive 的设备 UUID/Xcode 版本。
2. package：`rtk swift test --package-path Packages/HappyPianistCore`；共享 Notation/Practice 改动先定向后全包。
3. `rtk make test:simulator ONLY_TESTING='<实际发现的测试 ID>'` 按 task 相关测试开始，选取 Swift Testing 实际枚举出的 ID，不默认文件名就是可运行 suite。
4. `rtk make build:simulator`、最终 `rtk make test:simulator`。记录真实 xcresult 的 discovered/executed/passed/failed/skipped；0 tests 不是通过，build-for-testing 不是 tests。
5. rtk 输出压缩掩盖测试选择/失败细节时用原生 xcodebuild/原日志并说明原因，不机械重试。全量失败先与**当前分支实际基线**比对；历史 audit/docs 的失败数字不是当前事实。
6. `rtk git diff --check`；只 stage 本 task 代码与长期 docs，中文原子提交。本地 feature 计划/设计/审计/截图/实验不随代码提交，除非用户另明确要求入库。
7. 无关基线失败只记录，不顺手修；任何当前 feature regression 未解决不能标 Go。

**验收深度：** Tests 追到真实 entity/rig 是否移除、actual input/output stop、文件/index 与 recorder facts 重读；仅断言 branch/event/callback 不成立。fakes 复用已有体系，新失效不变量才增加最小可控 fake，不为矩阵搭全新框架。

**Gate / 原子提交：** 关键矩阵与同根相邻路径通过，无新失败；`test: P6-T1 - 验证二维三维共存与副作用边界`。没有代码变化时记录实际证据并用合理 no-commit reason，不为提交改无关代码。

## P6-T2 完成 physical AVP 设计走查与长期文档收口

**Files：**
- 本 feature 更新 `design/flow-boards.md`、`design/spatial-prototype-report.md`；新增 `design/acceptance-evidence.md`：逐 D01–D10 证据与验收结论，不维护 task 状态。
- 长期 docs：`README.md`、`docs/overview.md`、`docs/architecture.md`、`docs/data-flow.md`、`docs/configuration.md`、`docs/storage.md`、`docs/testing.md`，只更动受实际交付影响章节。
- 各 phase 已更新长期 docs；本 task 做一致性收口，不用整篇重写掩盖前期漏更新。

**真实设备走查：**
1. D01 两条入口/返回/取消/占用；D02 正/斜/侧视与长库操作，移动头部后书仍世界固定，无旧窗口挡书。
2. D03/D04 真 MusicXML 密集谱/双页/正背面/手动与自动页/快速跳页，阅读放大、坐站姿，不以窗口像素推断物理可读性。
3. D05/D06 Audio/MIDI 实际准备/权限/连接/A0/C8、锚点恢复与琴上方向、用户微调重置；无不当遮手/键盘。
4. D07 全部高频控制与错误/未知，D08 同一 Teaching/Duet 手、Guide 降级、respond/yield/停止的实际音画同步。
5. D09 从结果选择 focus→真实重练→复测完成；D10 保存失败/重试/discard/辅助设置/回库与恢复 2D，旧窗口不误关。
6. VoiceOver/Dynamic Type/Reduce Motion/Differentiate Without Color 真实操作，不只截图控件存在。

**证据格式：** 日期、commit、Xcode/OS/device、score revision、input/output route、calibration、动作步骤、测量/结果、截图/短片、Pass/Fail/Not Run、复现与限制。只按项目允许保存聚合；不用原始音频/MIDI/手帧、绝对路径、密钥或 AI 正文写 exportable logs。

真机未提供时保留完成的软件成果，明确哪个 D/测量待验证，不给最终 Go、不反复声称“正在等待”。不因没有设备把软件测试改成硬件验收。若用户未确认实际空间视觉满意，记录待确认，不用三张概念图替代本轮实际视觉结果。

**文档收口：**
- README 默认仍 2D，加主动 3D 入口/主流程/范围；不写“2D 已退场”。
- architecture/data-flow：共享业务 owner + 独立呈现、唯一活动路径/scene、同书 lifecycle、原 renderer 仍 legacy 消费。
- configuration/storage：keyboard-local UI 偏好，业务 progress schema/小节事实不变，不保存世界 transform。
- testing：分别写实际软件/真机证据与未验证能力；不沿用 archive 通过数字，不把教学有效性写为代码验证结论。
- 检查设计板、实际功能、idea 与计划一致；当前缺陷回 owning task 修，不创建未授权“下一轮再补”尾巴。

**Gate / 原子提交：** 完整空间设计与两产品真实可观察结果成立；`docs: P6-T2 - 收口三维体验与共存验收文档`。只有 feature 本地证据变化时不提交，按 no-commit reason 记录。

## Phase Audit

真正完成本 phase 后创建新版 `audit-p6.md`。最终 Go 须有完整 3D 行为/视觉/硬件证据，不能以计划文件存在、提交产生或测试数量代替。未完成时如实列具体 D 编号与最小解阻动作，保留原 2D 路径。
