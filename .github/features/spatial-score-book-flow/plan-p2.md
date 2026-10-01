# Plan P2 — 原生空间 Book Flow 与真实曲库

**Goal:** 把 P1 的空间壳接为完整真实曲库，直接在世界坐标浏览、选择与打开书册。
**Non-goals:** 不改/删除 2D Vinyl UI，不做正式分页，不重新实现导入/删除/音频。
**Approach:** 复用唯一 SongLibraryViewModel；已验证的 folio 实体承载元数据与局部操作，实体/附件只保留当前有界邻域。
**Acceptance:** D02 正式空间浏览、大库定位、选择/打开意图与试听独立；管理往返不丢选择、不重置空间。
**Rules:** 无第二 selected index/曲库 JSON，hover 不写业务选择；import-active 门禁与 bundled 保护仍在原 owner。详情正式读谱属于 P3，不以假谱临时冒充。

依赖：P1 空间性和入口/所有权 Gate。此 phase 继续修改 P1 的实体路径，不再建一套平行 Book Flow。

## P2-T1 接入真实 folio、空间选择与有界大库浏览

**当前行为/要保持的 invariant：**
- `SongLibraryViewModel.entries/selectedEntryID/selectEntry` 是真实曲库与选择。
- `loadLibrary` 每次加载都 installBootstrapSelection；原窗重开加空间 consumer 可把新选曲覆盖成历史选择。
- `startPractice(entryID:perform:)` 持有 import-active/entry-exists gate；不绕过。
- 原 `LibraryRecordCarousel` 的 scrollTarget 只是 2D 导航，不可拿来当 3D 的实体米制坐标。

**Files：**
- Modify: `HappyPianistAVP/ViewModels/Spatial/SpatialExperienceViewModel.swift`、`Views/Spatial/SpatialExperienceView.swift`。
- Add: `HappyPianistAVP/Services/Spatial/SpatialBookFlowSceneController.swift`（同 task 由现有 3D View 使用，不为单实现造 protocol）。
- Modify: `HappyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` 的 bootstrap 安装边界。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialBookFlowTests.swift`、`SpatialBookFlowEntityTests.swift`，现 `Library/SongLibraryBootstrapLoadingTests.swift`、`SongLibrarySelectionPersistenceTests.swift`。
- Docs: `docs/data-flow.md`。

**实施：**
1. Folio 实际 entity 布局由 P1 米制参数、signed relative index 与 selectedEntryID 派生，不复用旧窗口 perspective/zIndex 值。每本有薄封面/书芯/书脊，真实标题/来源；无作者事实不编造，纸面排版不变彩色 app card。
2. 只保留选中项与有限邻册、必要翻动对象。前后、可选横拖和局部查找可到任何曲目；查找用 localizedStandardContains，与现 entries 同源，清过滤/返回不制造新 selection owner。
3. entity-targeted gesture 配 InputTargetComponent/CollisionComponent；文本/Button 局部 attachment 不被大碰撞平面吞点击；使用平台 hover，不采 gaze 原始坐标。
4. 邻册点击只选中/居中；中心明确打开意图，等待 P3 的真谱详情；试听单独用既有 bindAudio/didTapListen/stopListening 路径。首/末/单首/空库有清楚可达动作。
5. selection 改变时原生可中断 move/rotation，不每次 update 重启；拖动可直接跟随，结束只提交一次真实选择。快速切换从当前姿态收敛最新目标；detach/suspend 停动画与旧 completion。
6. owner 内只在首次成功 bootstrap 安装历史 selection，合并并发首次加载；失败允许重试，已有 initialSnapshot 明确视为已安装。导入后的 index reload 保持原事务刷新行为，不能把“一次 bootstrap”误用于所有刷新。
7. 空库/失败有导入/重试/返回，不生成假 folio。import-active 期间如实显示管理状态，不发正式 practice request。

**验证：**
- 0/1/少量/大曲库，首尾、搜索命中/无结果、删除当前选择后的真实修复、邻册选择和独立试听。
- entity 数量上界与总条目数无关；正/斜/侧视看到 Z 后退，邻册命中准确。
- bootstrap 并发一次成功安装；重复加载不盖未持久化选择；失败重试；原 2D selection debounce/恢复正常。
- 快速选曲/拖动/退出无过期姿态归位、无动画队列和 detach 后动画。
- 音频 fake + 实际既有 playback consumer 验证试听 start/stop，不仅验证 UI closure。
- 真实 Simulator 场景 D02 与定向 xcodebuild test/build；真机 world stability/远距捏合与纸面尺度延续 P1 证据。

**Gate / 原子提交：** 空间实体、业务选择/试听及旧 2D 回归通过；`feat: P2-T1 - 接入真实空间书册与大曲库浏览`。

## P2-T2 接通空间曲库与原管理窗口的明确往返

**根因/边界：** fileImporter、事务冲突/删除/恢复已经在原 Library owner 和 Window 中实现；无需复制到 3D。隐藏窗口后必须能主动回去，回来不能重新启动空间或覆盖选曲。

**Files：**
- Modify: `HappyPianistAVP/Views/Library/LibraryWindowView.swift`、`Views/Spatial/SpatialExperienceView.swift`、`ViewModels/Spatial/SpatialExperienceViewModel.swift`。
- 现 action：`SongLibraryViewModel.didTapImportMusicXML/importMusicXML/confirmPendingImport/cancelAllImports/deleteEntry`。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialLibraryManagementRouteTests.swift`，现 `Library/SongLibraryImportTransactionTests.swift`、`SongLibraryTransactionRecoveryIntegrationTests.swift`、`SongLibraryProgressCleanupTests.swift`。
- Docs: `docs/data-flow.md`。

**实施：**
1. 3D Library 提供局部“导入与管理/返回 2D”出口；明确离开空间曲库到原 Library Window，沿 P1 owner 收回 scene 后再恢复原窗，不把整页管理 attachment 放在书后。
2. 使用原 fileImporter、事务确认、删除 hold/bundled gate；不改变 2D 视觉/手势，不新增第二 import queue。
3. 原窗仍有用户主动的“进入 3D”；导入进行中不给进入，结束后用户选择重进，刷新实际 entries，保留合法 selectedEntryID/不还原旧 selection。
4. 在 3D 尚未实践的此 phase 只处理 Library 往返；练习中的高级设置辅助窗口由 P5 处理，不能拿“关空间去管理”结束未保存练习。
5. 系统直接关空间恢复入口；后台/回库与窗口再现不会重复调用 bootstrap 或产生第二 spatial root。

**验证：**
- 空库→原导入→提交/取消/冲突/失败恢复→主动重进 3D；显示真实新增/删除曲目。
- 删除当前项验证文件/index/progress 最终副作用，bundled 删除无副作用；不只验证事件发出。
- import-active 进入拒绝、原窗重建/后台与连续往返；空间没有旧管理玻璃窗口挡书。
- 原曲库试听/准备/练习入口仍可用，Library/import 定向测试与 build，实际 Simulator 往返 D01/D02/D10。

**Gate / 原子提交：** 管理最终结果和入口恢复成立；`feat: P2-T2 - 接通空间曲库与原二维管理往返`。

## Phase Audit

P2 完成后创建新版 `audit-p2.md`；检查有界实体、单一选择、可中断运动、bootstrap 与原事务最终效果。此时不宣称真谱/练习闭环完成。
