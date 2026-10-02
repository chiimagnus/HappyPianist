# Spatial Score Book Flow — 直接 3D，保留 2D

## 当前决定与权威归属

2026-10-01 用户否定“先改 2D、再迁入 3D”的路线。本 feature **新增独立空间体验，不替换当前 2D 产品**，后续优化以 3D 为主。

- `idea.md`：当前需求和验收真源。
- `spatial-design.md`：空间关系、交互、状态与完整设计稿交付。
- `plan-p1.md` 至 `plan-p6.md`：实施拆分、源码锚点、验证。
- `todo.toml`：唯一实时任务状态。
- `archive/2d-first/`：旧需求、计划、todo、审计与几何实验，仅供追溯，不执行、不继承旧 Go。

`.github/features/spatial-2026-09-30/原始需求.md` 和其视觉契约仍提供空间设计背景，但“2D 退为辅助、删除旧生产路径”“八张核心稿足够”的决定已被本次要求覆盖。真实钢琴、音乐真实性与数据安全约束继续有效。

## 为什么改路线

旧计划前三阶段先在 Window 替换唱片、连续滚谱与翻页，到 P4 才验证真实空间。窗口尺寸和平面导航先限制了产品形态，2D 截图/测试不能证明最后的 3D 成立。

新版先验证世界坐标、尺度、深度、对象关系与动态交互，再在同一条 3D 路径接入真实业务。**复用音乐与业务事实，不复用整个 2D 页面当空间外壳。**

## 保留与新增边界

| 范围 | 当前决定 |
| --- | --- |
| Library Window | 保留唱片曲库、试听、导入、删除、历史、原准备/练习入口；只增加“进入 3D”入口及必要占用提示 |
| Preparation / Practice Window | 保留原准备、连续滚谱、二维键盘、控制、设置、结果、退出；不要求迁移 |
| 3D Library / Detail / Practice | 新增独立空间呈现和路由，直接在 RealityView / 唯一 ImmersiveSpace 内设计 |
| 曲库/音乐/练习/硬件 | 共用既有 owner、repository、parser、输入输出、校准和保存语义，不复制业务系统 |
| 同时使用 | 两种产品长期可选，但一次只有一个活动练习/校准、一个沉浸空间 owner，不重复播放/录音/保存 |
| 后续方向 | 主要优化 3D；没有最终删除 2D 的任务、期限或 feature flag |

保留 2D 不禁止必要的公共底层修改，但共享改动须保持行为兼容并验证两条路径。不删、不重命名仍被 2D 使用的 UI/API/settings/tests。只删除被正式 3D 替代的临时原型，不把两种明确产品呈现误判为“旧新兼容双轨”。

## 空间世界的定义与默认假设

Book Flow 中每本 folio 是独立空间对象；中心书展开为双页谱；准备后同一本谱移到琴上；反馈、结果、重练与合拢返回都围绕相应对象，而非矩形页面。

依据用户指定的三张 MR 参考图，本版默认 **mixed reality：现实空间 + App 的 3D 对象**。这不是用户已要求全 VR 的事实；不替换房间，不在真实模式生成第二台钢琴。若另行要求全 VR，须先重新定义现实乐器可见性与安全验收，不在此计划悄悄扩张。

纸页、文字、局部系统 Button 可以是平面表面并附属于实体。禁止将整个 `LibraryContentView` / `PracticeStepView` 挂成巨型 attachment，称之为 3D。

曲名由封面/谱面承载，不另挂重复信息卡。必要操作随书的位姿变化，不能自动朝向用户；阶段说明和演练账本属于评审工具，不属于产品空间。

## 已有视觉输入与缺口

已在当前树确认并查看：
- `images/01-Book-Flow曲库.png`：中心书、邻册倾斜/后退。
- `images/02-双页Book-Spread曲目详情.png`：轻书脊、双页、多行 Grand Staff、谱上练习事实。
- `images/04-正常练习.png`：真实琴/双手、琴上谱、局部 Guide。

旧生成清单声称八张已生成，但当前仅以上三张 PNG 存在；03/05/06/07/08 有 prompt，不能当作已有设计图。单视角静帧也不证明尺度、侧面、命中区、连续动作与失败流程已经设计完。

本次补 `spatial-design.md` 的完整状态、空间契约与 D01–D10 设计板交付；它不冒充已生成的高保真图片。P1 必须先交多视角板与 RealityView 动态原型，后续 owning phase 补齐真实功能状态。

不复制示意房间、家具、琴型、曲名、错误音符/手部透视或未经授权封面画。缺真实封面资产时用纸面排版与程序化细节，不假造作者/音符，不新增 AI 封面系统。

## 必须满足的用户行为

1. **入口与返回**：App 仍默认打开原 2D 曲库，用户主动进入 3D。打开失败/取消保留原页面；有效空间挂载和摆放后才隐藏原窗。退出恢复 2D 与当前选择，不自动开始练习。
2. **空间曲库**：不依赖钢琴、不迫使走动；独立 world-locked folio，支持大库浏览/查找、选择/打开，试听独立。空库/管理可明确返回 2D，保持现有事务与删除保护。
3. **双页谱**：真实 MusicXML 排为多个 systems/page 与双页；已有记谱事实不丢。3D Detail 与 3D Practice 共享同一分页和书册身份；2D 滚谱保留，不要求两种呈现同页码。
4. **导航**：Detail 手动翻页、resume/focus；Practice 由真实执行位置自动翻页，repeat occurrence、seek/range/reset 正确。没有独立时钟；快速变化收敛最新目标。
5. **准备**：Real Audio / Bluetooth MIDI 复用现有 A0/C8 校准、连接/权限与 readiness；选择、A0、C8、Ready、失败/重试/取消都有空间表达。stored calibration 不能冒充 runtime ready；取消回同书详情。
6. **连续书册**：复用唯一 launch/preparation/applicator，正式身份与校准确认后将同一 Spread 移到琴上；可换父节点，不复制第二 practice owner，不以动画完成启动判定。
7. **位置**：谱以 keyboard-local transform 面向演奏者，位置可有限微调/重置，不跟头、不保存会话 world transform。物理尺寸、距离、倾角经空间原型/真机测量，旧窗口像素实验不作证据。
8. **伙伴**：3D 用户手保持 passthrough，只一双 Companion Hands，Teaching/AI Duet 共用真实音符与播放时序。保留的 2D Neon/VirtualPerformer 不删，但不同时进入新 3D renderer。motion/资产不足恢复对应 Guide，不伪造动作、不改音频。
9. **控制与反馈**：谱缘/琴旁按需控制，不是 HUD/常驻工具条；复用配置、播放互斥、录音、assessment/coaching。未知/低置信度不画成错误，每次最多一个有范围和完成条件的复测动作。
10. **结果与安全退出**：谱上结果、focus、重练/继续/返回。回 3D 曲库或退 2D 前必须 progress flush + session facts finalize 成功；失败留在原会话，允许重试/保留/明确 discard。回库成功不被 legacy window 消失回调关掉空间。

## 数据、兼容与安全

- 不新增业务进度 JSON schema、平行 repository/parser/playback engine、AI backend 自动切换。
- progress 仅保存批准的小节级事实；page plan、页码、实体、cue、逐音 evidence、Companion presentation 不写进去。
- 摆放偏好若保存，只存有限 keyboard-local 用户偏移，采用现有偏好机制，不混入锚点/业务进度，不存 world pose/追踪帧。
- PreparedPractice 必须有 steps 与小节结构，不新增 legacy preparation fallback。
- import-active 门禁、bundled 不可删、事务恢复、source/performed identity、revision、取消/代次隔离、DiagnosticsReporting 脱敏均保留。
- Virtual Piano 和完整小程角色不是本次 3D 新体验验收对象，原 2D 功能保留；选择该输入时明确使用原路径，不替用户改模式。
- Swift 6 严格并发检查从首个接入 task 生效。

## 非目标

不重做/下线 2D，不截图搬迁整页 UI，不做 VR 音乐室/自动琴架识别/厚书物理/环境装修/商城/封面生成，不改变正式曲谱来源、练习判定、AI 策略或录音格式。失败不能静默切 2D 假装 3D 成功，返回 2D 是明确动作或打开失败后的入口恢复。

## 最终验收

- 同一安装完整运行原 2D 流程；新增入口不改默认启动，原 Vinyl/滚谱/键盘/settings/renderer 的必要文件与测试仍在。
- 3D 主路径无整页 2D View；folios 有独立深度、世界位置、命中与遮挡，多视角与动态转场证明空间性。
- 不回旧 Practice Window 即可完成 3D 选曲→详情→必要准备→练习→结果/重练→回库；系统导入/复杂设置为明确且可返回的辅助例外。
- 同谱身份、分页、历史、音乐位置真实；repeat/seek/range/奇数末页、快速换曲与取消不回写错状态。
- 2D/3D/准备不抢同一 scene/输入输出/保存，无重复 session、声音或 renderer，无迟到关闭新场景。
- 保存失败保留增量和旧文件；重试后重新读 repository 验证真实落盘；discard 只放弃未保存增量。
- Simulator 软件 Gate 与 physical Apple Vision Pro 的 world stability、阅读/校准/舒适度、手部遮挡/音画同步分别留证，无真机证据不称 3D 体验通过。

## 实施顺序与源码基线

| Phase | 交付 |
| --- | --- |
| P1 | 完整低保真流程、多视角/动态空间验证，最小 2D 入口与 3D 世界壳 |
| P2 | 真正的 Book Flow、真实曲库/大库导航/管理往返 |
| P3 | 仅供 3D 的真实分页 Book Spread、详情和空间翻页；2D 滚谱不删 |
| P4 | 同空间准备/校准、唯一 launch、琴上谱、基础练习与安全返回闭环 |
| P5 | 同一双 Companion Hands、真实时序、空间控制/反馈/结果与重练 |
| P6 | 2D/3D 共存、真机走查与文档收口 |

本次源码读取基于 `ed77b659`：已有一个 mixed ImmersiveSpace，`AppState.ImmersiveMode` 只有 calibration/practice，Library 仍 Vinyl，Practice 仍 `GrandStaffNotationView`。旧审计描述的分页/SpatialLibrary 文件在当前树不存在；计划“新增”不表示已经实现。

当前授权包含完整流程设计、HTML + Three.js 浏览器交互原型及由原型捕获的设计板，不启动正式 App 实现、不改现有 2D。浏览器中的曲谱、设备、手部、音乐时序和保存均为明确标识的模拟；它支持产品走查，不替代 P1-T1 的 RealityView / physical AVP 空间验证。按 writing-plan 约定，计划/设计、原型及归档本地保留，不新增 Git 提交、不 push、不建分支。
