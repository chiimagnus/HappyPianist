# 3D 空间设计契约与完整设计稿交付

本文件把 `idea.md` 转成可走查的设计，不维护状态。D01–D10 是设计板，不是十个产品页面或十个强制新 View。完整流程见 `design/flow-boards.md`；本轮交付浏览器 3D 原型及其捕获，原生/真机证据仍独立归属 P1-T1。

## 1. 先验证空间成立，再接完整业务

**判断方法：先验证最影响结果的假设。** 当前最重要的未知不是颜色，而是多视角下是否真像独立空间对象、双页是否可读、远距捏合是否舒适、谱能否自然移到琴上。先用有边界的空间原型取证，不把截图精美当作产品成立。

三张已有图片只支持书册构图、双页结构和琴上关系，不提供尺度、侧面、命中区、运动或异常流程。旧审计还暴露“换册跳位”“彩色卡片像平面卡”“窗口挡书后”的问题；新版拿它们作反证，不继承通过结论。

### 四个空间性条件

1. 每本书有独立实体、world transform、hit target，不画在一个整块 carousel 上。
2. 邻册有实际 Z 后退与 Y 旋转；侧视可辨薄书芯/书脊，不全体 billboard 跟头。
3. 选中书从封面→双页→琴上→结果→合拢保持同一曲目与分页 owner；可变姿态/父节点，不复制业务 session。
4. gaze + pinch 可远距完成选择/翻页；不必站起、探身、绕书走、悬臂才能完成主流程。

薄封面/书芯/页由 RealityKit 表达深度；谱字与文字可用独立动态 attachment。平面纸张不是问题，整页 2D 产品移植才是。**不做厚书物理，不把每个音符造为 mesh。** attachment 尺度/清晰度、双面朝向与 mesh 重叠由原型验证，不能预设零失真。

## 2. 世界与对象结构

```text
SpatialRoot（本次 3D 会话）
├─ LibraryRoot（会话 world-fixed）
│  ├─ Folio(songID) × 有界邻域
│  └─ 局部前后/查找/管理/退出
├─ OpenBookRoot（唯一当前书；detail/practice/result 连续变换）
│  ├─ 封面 / 薄书芯 / 轻书脊
│  ├─ 左页 / 右页 / 当前翻动 sheet
│  ├─ 谱面 / 当前小节 / 练习标记
│  └─ 页缘交互 / 按需控制
└─ KeyboardRoot（仅有效定位的准备/练习）
   ├─ calibration reticle / A0 / C8 或 Piano Guide
   └─ Companion Hands（真实教学/陪弹）
```

这是职责示意，不要求每个节点一个类或新增中央分发器。实体数量有界；打开详情时 Flow 退让禁交互，不让背景书册挡谱。

| 对象 | 坐标/朝向 | 出现时机 | 禁止 |
| --- | --- | --- | --- |
| Flow | 进入时由有效 device pose 放当前自然前方，之后 world-fixed；邻册相对 LibraryRoot | 浏览、返回曲库 | 每帧追头、环形走动书架、保存会话 world pose |
| Detail Spread | 所选 folio 附近展开，朝初始阅读方向；可显式重新摆到面前 | 详情、准备时暂存 | 永久 LookAt、换曲留旧页 |
| Practice Spread | worldFromKeyboard × keyboardLocalScoreTransform，面向确认的演奏者侧 | 练习、结果 | 从 ±Z 猜方向、高亮变化重摆谱 |
| A0/C8、Guide、Hands | 既有有效琴坐标；各 mode 按职责互斥 | 相应准备/练习 | 第二台真实模式琴、假物理压键 |
| 控制/错误 | 谱缘或琴旁 world/object-relative | 用户唤出或必须处理时 | 全局 HUD、巨型 glass dashboard、常驻 toolbar |

world-fixed 仅指当前有效追踪会话。当前 ARTrackingService 重启会清理/重建 providers，不能用旧 transform 冒充连续定位。Library 提示重新摆放；Practice 等待既有锚点恢复，再显示对齐内容。

### 尺度与阅读

- P1 记录实际米制宽高、阅读距离、倾角、邻册间距/Z 后退、远距 hit 范围，连同测量条件；本文件不虚构已验证数值。
- 同时核对坐姿/站姿、稀疏/密集谱、实际键盘宽度。不能为每页四行而缩到不可读。
- 双页为默认；systems 数由真实 ink bounds 与可读尺度决定，不硬编码四行。阅读放大仍基于同一 PagePlan，必要时放大同页区域，不生成第二套页码。
- 谱不挡真实手/琴键，移动柄在外缘，只在明确编辑态生效，不让整页任意误拖。
- 保存偏好只存有限 local offset，完成编辑再写；world pose 不保存。保留微调/重置，硬件需要真实调校。

## 3. 两条产品流与所有权

```text
默认：2D Library → 原 Preparation → 原 Practice
           │ 主动“进入 3D”
           ▼
3D Library → Detail → 必要空间准备/校准 → Practice
    ▲           ▲                        │
    │           └─准备取消/失败保留书     ▼
    └─原 folio ← 合拢 ← 同谱 Result / Focus / Retry
    │ 主动“返回 2D”
    ▼
原 2D Library
```

- Library.onAppear 不自动开空间；有效挂载/摆放后才隐藏原窗，失败/取消原窗可用，正常退出恢复。
- 原窗隐藏不改 selection，不当成业务结束。重新打开窗口也不重新 bootstrap 覆盖空间选曲。
- legacy practice/calibration 占用时不能进入 3D；3D active 时恢复的 2D Window 不得启动第二 practice/calibration。明确提示先结束，不“最后调用者赢”。
- 不支持 live practice 直接 2D↔3D 换壳；先安全结束，再走另一入口。
- 管理/设置是辅助窗口，不是新 session；显式返回，不依赖多层 pushWindow。
- scene/练习生命周期属于活动路径，不属于恰好可见的窗口。legacy onDisappear 不得关闭新 3D space 或 flush/discard 它的 session。

## 4. 完整状态与转场

下列是设计词汇，优先映射现有状态，不要求造巨大 enum。

| 状态/触发 | 所见与动作 | 目标/保护 |
| --- | --- | --- |
| 2D / request | 原曲库 + 3D 入口 | import-active、legacy practice/calibration 占用不抢 scene |
| Opening / pose pending | 原窗等待、取消；无假 world-fixed 书 | opened ≠摆放成功；pose 不可用给重试/返回 |
| Library / normal / large | 中心书、Z 后退/Y 倾斜邻册；前后/查找/管理/退出 | 有界邻域；可中断换册，不积压 |
| Empty / load failure / import | 去 2D 导入、重试/返回；不造假书 | 原事务；返场刷新 entries，不重置未持久化选择 |
| Select / confirm / listen | 邻册先选中；中心明确打开；试听独立 | selectedEntryID 唯一，hover 不选曲、不读原始 gaze |
| Detail loading/failed/ready | 书仍在；加载/重试/关闭；ready 显示真实双页 | 迟到不改新曲，失败不沿用旧谱 |
| Browse / resume / focus | 外缘翻页、合法定位、关闭回中心书 | 晚到历史不抢手动导航；页码不影响试听 |
| Choose input / permission / MIDI | 谱旁暂存、最小选择/权限/连接提示 | 不替换输入/backend，未 Ready 不判定 |
| A0 → C8 → Ready | reticle、真实端点、确认/重做/取消 | 真 provider/端点/存储/定位完成才 Ready；取消保留原有效校准 |
| Localization waiting/failed | 原书、恢复/重试/重校准；失配 Guide/Hands 隐藏 | stored ≠runtime ready，不贴假键盘 |
| Handoff / Ready | 同一谱移琴上，Flow 禁交互 | launch identity/revision/有效 frame 合法才启用；动画不是声音时钟 |
| Practice / pause / seek / range | 真实手、谱、局部 Guide；按需控制 | 真实 session/tick；pause/seek 清过期表现 |
| Teaching / Companion | 同一手通过触键/密度/退让表达 | actual playback 驱动；不展示内部 action/backend 标签 |
| Cue / unknown / insufficient | 一个当前小节范围内反馈；未知不画错 | 真 assessment/coaching，不从 UI 点击推断演奏 |
| Complete / Result / Retry | 谱上事实、一个复测建议、重练/继续/返回 | 重练修改真实 passage/config，结果不等于保存成功 |
| Saving / failure / discard | 原谱、重试/留在练习/明确 discard | flush + recorder finalize 成功才离开，失败不合拢 |
| Return Library / Exit 3D | 回原 folio 或关空间恢复 2D | 回库不关 scene；退出清音频/动作/renderer |
| System dismiss / background/resume | 停输入输出/动作，按既有策略保存，恢复重新定位 | 不自动重启声音；旧任务/窗口回调不写新会话 |

scene 不卸载的 mode 切换不会再触发 onAppear。必须显式完成旧 mode exit、新 mode enter、provider requirements 切换，不能只改 enum 等 View 回调。

## 5. 动作与可发现性

### 选书、打开、关闭
- 邻册在 LibraryRoot 内移动/转正，用户与世界不动。横向 targeted drag 可辅助，也提供前后按钮。
- 中心书打开成为主体、邻册退让；封面沿书脊打开。未准备好显示局部加载，不播假成功空白谱。
- 关闭详情回原 folio；换曲清旧页与任务。快速选择从当前实际姿态重定最新目标；退出停止原生动画，不留 completion 归位旧书。

### 双页翻动
- 向前翻当前右 sheet：正面当前右页、背面目标左页、底层目标右页；向后反向。文字不镜像，奇数末页空白合法。
- 只保留当前/目标必要页层，不缓存全书截图。相邻可动画，大跳或翻动中 retarget 直接最新目标。
- Detail 页码只为阅读；Practice 真位置决定目标，跳练须明确 passage/seek，不能捏页自动改音乐位置。

### 准备、琴上谱与编辑
- 校准优先 reticle 操作，谱暂退不消失；页缘不抢确认 hit。
- 定位后同一 root 移琴上；Guide 仅有效几何，动画不决定 input start。
- 明确编辑态唤外缘柄，有限 local drag、完成/取消/重置；练习中先按 session 策略暂停，不边改坐标边误判。
- 结果停实时动作，事实贴原小节；先真实保存，再合拢回库。

### 控制
- 返回/退出永远可发现，暂停/停止可快速唤出，不藏在秘密手势里。
- 节拍器、录音、示范、Companion、范围、手模式/速度用谱旁局部控件；复杂 backend/诊断/录音库走明确辅助入口。
- 复用原 autoplay/AI/recording/take playback 互斥，不能仅隐藏按钮代替业务 gate。

## 6. 必须补齐的设计板与动态证据

本轮先用 HTML + Three.js 交付可操作浏览器 3D 原型，从实际原型捕获多视角设计板；不以 AI 效果图替代可操作流程。浏览器鼠标不是 gaze + pinch，示意钢琴不是现实定位、占位谱不是 MusicXML、演练保存不是业务落盘。原生阶段仍须 RealityView 捕获和 physical AVP 验证；图片不作音乐/硬件正确性证据。

| ID | 板/片段 | 核对重点 | owning phase |
| --- | --- | --- | --- |
| D01 | 2D 入口→等待/取消→摆放→退出恢复 | 窗口隐藏时机、失败入口、占用拒绝 | P1 |
| D02 | Flow 正/斜/侧视/俯视尺寸板、换册片段 | 书芯/书脊、真 Z、清晰字、捏合、快速 retarget | P1 原型，P2 正式 |
| D03 | 展开/合拢分镜、双页正侧视、加载/失败/空页 | 同一书、纸页层次、背面、无卡片/窗口壳 | P1 几何，P3 真实谱 |
| D04 | 手翻/自动页界/反复/快速 seek、末页板 | 正背面、真 target、不丢读谱 | P3，P4 演奏接入 |
| D05 | 输入/权限/MIDI、A0/C8/Ready/失败/取消 | 原校准、不造琴、未 Ready 禁止开始 | P4 |
| D06 | 详情→琴上分镜、坐站姿、编辑/重置板 | 连续姿态/尺度/距离、真手可见、定位中断 | P1 几何，P4 正式 |
| D07 | 正常/暂停、唤出控制、录音/不可用、局部 cue | 高频可发现、未知不画错、无常驻 toolbar | P4 基础，P5 完整 |
| D08 | 教学/陪弹、respond→yield、motion 失败短片 | 同一身份、真音画、Guide 恢复、不假压键 | P5 |
| D09 | 完成→focus→重练→复测完成分镜 | 小节事实、一个复测动作、无旧 Window Alert | P5 |
| D10 | 保存失败/重试/discard、回库/2D、系统退出恢复 | 真保存、无重复/误关、管理往返 | P4 安全，P6 完整 |

P1 先完成**全流程低保真板**以及 D01/D02/D03/D06 空间几何原型。其他板进入 owning phase 前补实际可操作状态；不先造完整 App 再审设计，也不永远用占位称完成。

每份板包含状态、进入/离开动作、世界/钢琴基准、米制尺度/hit/遮挡、失败动作、证据/未知。高保真静帧不替代动态片段。

## 7. Gate、反证与更新条件

- P1 空间性：多视角/动态操作、尺寸与坐站阅读证据，证明不是窗口搬家；无真机证据明确 pending，不称视觉已确认。
- P3 记谱：真实密集谱/休止/跨系统连线/反复/末页、overlay 与分页 invariant；原 2D 回归。
- P4 闭环：不回旧 Practice Window 可开始/结束，文件与 session facts 真实保存，失败留会话，legacy teardown 不误关。
- P5 伙伴：动作/声音同源、Guide 恢复、yield/seek/退出无残留；真机对齐/同步另验证。
- P6 共存：两条完整流、辅助窗口、中断，既不删 2D，也不重复副作用。

attachment 不可读或双面/遮挡不成立时，修改 3D 表面实现并重过 P1/P3，不回去先重做 2D，不用更精美图片掩盖。provider 切换破坏 world continuity 时核对合法 SDK 契约并重新定位，不能旧 pose 假装 Ready；不无证据搭整套增量 provider 框架。

## 8. 平台依据与设计决定

2026-10-01：本机 xcdocs 定位主题/符号，部分 get 只返回元数据，正文由 Apple 官方页面补证。
- [Immersive spaces](https://developer.apple.com/documentation/swiftui/immersive-spaces)：mixed 保留 passthrough，系统同时只显示一个 space；两产品不能各抢一个并行空间。
- [Combining 2D and 3D views in an immersive app](https://developer.apple.com/documentation/realitykit/combining-2d-and-3d-views-in-an-immersive-app)：局部 attachment 可相对 3D 实体摆放，不表示整页移植是合适产品设计。
- [Spatial layout](https://developer.apple.com/design/human-interface-guidelines/spatial-layout)：深度线索、尺度与重要性影响舒适；独立薄书与实测参数是本项目设计决定，不是 Apple 指定书本模板。
- [Design for spatial input](https://developer.apple.com/videos/play/wwdc2023/10073/)：舒适视野与空间输入支持本项目无需探身/悬臂的验收。

visionOS 26 部署目标不变。具体 hover/manipulation/attachment overload 在 owning task 用本机 SDK 核对、编译，不顺手提高部署版本。
