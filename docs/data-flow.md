# 数据流

本页描述跨模块事实如何流动；具体符号、文件和调用者使用 CodeGraph 查询。

## 曲谱到练习

```text
MusicXML / MXL → Library 导入事务 → Practice preparation
→ ScorePerformancePlan + measure spans → steps / guides / notation / playback
```

- 仅接受 `.musicxml`、`.xml`、`.mxl`。导入在 security scope 内完成安全校验、同卷暂存、校验与 index 提交；失败不留下部分曲谱，恢复不能把损坏的非空 index 当作空库覆盖。
- MusicXML/MXL 在解析或解包前验证普通文件、archive 路径、条目数、大小和压缩比。每个普通 note/rest 必须有标准 `MusicXMLNoteType`；非 grace note 必须有显式 duration；整小节 rest 的例外由语义字段决定。
- `PracticePreparationService` 先生成唯一的 `ScorePerformancePlan`，再单向投影 steps、琴键引导、notation、时间线和 sequence。没有 steps 或 measure spans 的结果是 typed failure，不存在 legacy/fallback 练习模式。
- preparation 将正式 logical instrument / structural part 事实接到 runtime。Notation 接收完整 projection、小节结构、attribute timeline 与这些来源事实；projection 已映射到显示 staff，不再重复 normalizer。
- Notation owner 在非主 Actor 异步构建唯一的 staff-space 绝对布局与 canonical PagePlan，保留完整边界、source beam provenance、spanner 与墨迹边界；换谱/关闭取消任务并拒绝迟到 generation。所有 occurrence（含空休止）唯一分配到 system/page/spread；分谱表上下文按正式 original part/staff 查询。首/末边界、source beam 连通组与 continuation 使用原始来源，完整墨迹决定二维 fit。tick、hand、active range 和 overlay 只更新局部 presentation，不重建全谱；范围外内容变淡但不删除。高亮和辅助显示不写入 progress。Practice 以完整 score 驱动双页，放大阅读纵向显示同一分页；离散导航复用唯一 transport 的 scheduled tick（包含小节边界），休止期间不插值、不优先旧 guide。
- 共用 Spread 仅根据目标双页驱动单张纸的实时正反面；相邻翻动，大跳或翻动期间新目标直接收敛。原生动画完成核对谱身份与 generation，关闭/换谱拒绝旧完成；不缓存位图、不增加时钟。用户显式放大阅读直接换页。
- 界面文字使用系统语义字体。谱内文本使用系统 caption 字体，测量与绘制共用 engraving metrics，按 staff-space 几何比例缩放；音符使用 Bravura 音乐字体。不能把记谱几何字号换成窗口字号，否则会破坏墨迹边界与分页。

曲库窗口通过 Book Flow 乐谱册浏览曲目：系统滚动绑定只在停稳时提交 selection；几何测量只驱动倾斜与层级。导入事务、删除资格、选择持久化和独立试听仍由原曲库业务 owner 决策。

- 邻册点击只选曲，中央已选册或“打开乐谱”按钮打开真实双页预览。预览与练习共用 canonical 分页；只替换窗口内容，不重建试听条、导入器或外层 owner。预览通过正式 resolver/preparation（written order、双手）读取，不安装练习、不绑定 recorder、不写 progress。
- 预览只保留当前一份准备结果和 PagePlan；解析前后都核对 song ID、文件版本与请求 generation。关闭、换曲、删除、导入开始、窗口离开或 scene 非 active 取消并清理，迟到结果不能恢复旧谱。重新打开重新准备，没有永久缓存。
- 曲库历史仍只读取一次 snapshot；同一当前 revision 的真实小节事实共同派生汇总与逐 source 标记，双手稳定或左右分别稳定合并为已稳定。预览再核对 selection/file version 与准备结果的 revision，并按正式 occurrence 映射到分页 rect（包括空休止）；未知 revision 不伪装成未练习。标记、继续位置与重点可叠加，不改变分页或持久化数据。
- 预览仅保存当前 target spread；首次 ready 从匹配 selection/file version/revision 的精确 resume occurrence 打开，否则首双页。迟到历史只更新标记，不夺走浏览位置；focus 不自动跳转。外页缘 Button 驱动导航，前后边界停止；关闭清空目标，重开重新准备，不持久化自由浏览页码，也不改变试听。
- Practice 复用同一页缘按钮，但翻页移动会话的正式 notation position tick，而非独立浏览页码。目标受当前练习范围约束，更新下一演奏步骤与 checkpoint，不把跳过的小节记为成功或失败。纯休止页保留目标位置；手动模式等待继续，自动模式从该 tick 重建既有 transport，旧代采样不能夺回页面。显式暂停后翻页仍暂停，继续后恢复原自动跟随；关闭、换谱和步骤前进清理旧定位。AI 演奏接管时不接受手动定位。
- 历史加载、邀请、摘要与失败提示位于谱面详情，不再挂右侧历史面板。损坏记录需明确确认后调用现有原子备份/重置；确认绑定原 selection 身份，备份失败保留原文件与损坏状态。历史失败不阻止阅读曲谱。

## 会话与输入

```text
platform adapter → typed PerformanceObservation → matcher / alignment
→ capability-aware assessment → one CoachingAction → source-measure facts
```

- 麦克风、Bluetooth MIDI、手部接触共享 observation 契约，但每种来源保留 capability 与 unknown 边界。系统/AI playback、旧 generation 和后台事件不能成为用户 observation。
- 会话 controller 是 range、attempt、feedback、assessment/coaching 和 measure facts 的唯一 non-spatial owner；host 仅装配展示与平台 adapter。结束顺序为：失效输入、停止输入、flush 输出和 recorder、写入 facts、终结 session。
- 未观察、低置信度、`unknown`、`insufficient` 与 degraded capability 不能改写成错误。每次指导最多选择一个有范围和完成条件的动作。

## 空间引导与示范手

- AR service 将真实骨骼作为运行期快照发布；授权拒绝、能力不支持或手部不完整时隐藏，绝不伪造为练习证据。Simulator 合成姿态只能用于条件编译的渲染路径。
- 荧光手套、示范手骨骼、键面贴片、cue 和恢复地图均是当前 guide 与 transport 的派生状态，不进入输入、reducer 或 progress。示范手 clip 在首个 onset 前进入准备姿态，且逐段验证 held contact、接触残差与碰撞；缺资产、规划、coverage 或质量校验时只回退对应键面贴片。

## 持久化、回放与 AI

- progress 只保存已批准的小节级聚合事实；metadata 与 session concern 独立更新，checkpoint 以 song identity、round generation 和 progress generation 阻止旧任务回写。完整 schema 与隐私规则见[存储](storage.md)。
- take 记录可重放 observation；停止时先关闭未结束的音符，再原子写入 host 自己的 `TakeLibrary`。用户导出时才取得目的 URL，且不保存 URL、bookmark 或逐事件内容。
- AI 后端严格遵从用户选择；响应是运行期创意内容，不是谱面真值、assessment target 或评分依据。失败后提示并结束本次请求，不自动切换后端。
- Companion 播放状态由 Queue 单向发布 `idle → preparing → playing → idle`。用户 observation 会立即淘汰旧 generation 和未开始窗口，但不会直接停止已经发声的 AI；当前播放是否让位只由 Companion action 决定：`listen` 清 future，`yield` stop current + clear future，其余动作保留当前播放。只有用户来源、发生在真实 `playing` 之后的新 note-on 才可构成 re-entry；note-off 与 system playback 不参与。
- 所有业务诊断通过 `DiagnosticsReporting` 进入系统日志；仅显式标记为 exportable 的低频事件进入七天诊断文件，且不得含原谱、原始输入、绝对路径、AI 正文或凭据。
