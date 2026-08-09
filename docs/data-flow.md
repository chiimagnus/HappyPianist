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
- Notation 只接收 projection、overlay、measure spans 与 context；高亮、VoiceOver 和辅助显示是派生表现，不写入 progress。

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
- 所有业务诊断通过 `DiagnosticsReporting` 进入系统日志；仅显式标记为 exportable 的低频事件进入七天诊断文件，且不得含原谱、原始输入、绝对路径、AI 正文或凭据。
