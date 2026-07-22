# 钢琴演奏与专业质量边界

本文维护 HappyPianist 在曲谱解释、参考回放、输入观察、练习判定、虚拟琴和专业演奏评价方面的当前事实。它不是开发流水账，也不记录已经被当前实现取代的历史缺口。

## 当前产品定位

HappyPianist 当前是：

> **以找键、和弦完成和小节练习为核心，具备可审查乐谱驱动回放、多来源输入观察、客观演奏分析和小节级成熟度事实的空间钢琴练习系统。**

当前可以安全宣称：

- 导入 MusicXML / MXL，并为常见双谱表钢琴谱生成练习步骤、五线谱投影和演奏计划。
- 使用同一 `ScorePerformancePlan` 驱动本地 sampler、外部 MIDI、示范本节与显示投影。
- 通过 Bluetooth MIDI、定向麦克风和已校准手部接触接收不同能力等级的练习证据。
- 将连续 observation 对齐到 score event 与 performed occurrence，并按输入能力生成可追溯客观指标。
- 记录小节级练习事实、恢复点、录制 take、输出可靠性指标和安全诊断。

当前不能安全宣称：

- 专业级钢琴演奏评分或等同钢琴教师的诊断。
- 对所有 MusicXML 钢琴作品的无损解释。
- 机械回放等同钢琴家参考演奏。
- 麦克风、MIDI 与手部追踪提供等价证据。
- 应用内五线谱等同原出版谱面。

## 当前事实链

### 曲谱与声音

```text
MusicXML / MXL
-> MusicXMLScore（source written facts）
-> logical instrument / performed order / timing interpretation
-> ScorePerformancePlan（唯一演奏事实）
-> local sampler / external MIDI
-> PracticeStep / highlight / notation projection
```

关键边界：

- `MusicXMLScore` 保留 part、staff、voice、written pitch、source identity 和记谱语义。
- `ScorePerformancePlan` 保存 performed occurrence、note/controller/pause、tempo、velocity、provenance 与 approximation。
- `PracticeStep` 只负责即时练习判定；它不是声音、记谱或完整评价真源。
- staff 与 hand 是不同事实。无法可靠确定的手别保留 `unknown`，不把谱表编号伪装成左右手。
- written order 与 performed order 由调用场景显式选择。

### 输入与练习

```text
MIDI / target audio / real or virtual piano contact
-> PerformanceObservation
-> current-step matcher / recording / hand gate / transient alignment + assessment
-> PracticeAttemptReducer
-> source-measure facts
```

`PerformanceObservation` 统一表达 source、capabilities、generation、单调时钟、事件、channel/group、confidence 与 calibration reference。能力模型明确区分 observed、degraded 和 unavailable；未知或低置信度不能当作用户弹错。

手部触键链已保留每次 contact 的 hand、finger、稳定 identity、单调时间、置信度、位置、键面距离、法向速度、独立 velocity 和 calibration ID。palm 不参与琴键命中；ambiguous/unknown 键位不按相邻半音容差改写为正确音。

## 已建立的专业基础

| 维度 | 当前事实 |
| --- | --- |
| 谱面真值 | source note 与 performed occurrence identity 分离；written pitch 与 sounding MIDI 分离。 |
| 声音真值 | 所有参考声音消费者共享 `ScorePerformancePlan`。 |
| 动态 | MusicXML 数值 dynamics 按相对 forte 90 的十进制百分比换算；mark、wedge 与 provenance 可审查。 |
| 控制器 | damper、sostenuto、soft pedal 使用 0...100 到 MIDI 0...127 的连续值模型。 |
| 范围回放 | range/seek 重建 controller、held note 与 pedal-latched note 状态。 |
| MIDI 输出 | look-ahead scheduler 发送带 host-time timestamp 的批次，并用 generation guard 取消旧输出。 |
| 虚拟琴力度 | 每次触键按法向速度和版本化校准曲线生成独立 velocity。 |
| 输入契约 | MIDI、音频和手部共享 `PerformanceObservation`，但保留各自能力限制。 |
| 录制 | take 保存来源、时钟、能力、校准与 observation，回放投影与原始证据分离。 |
| 可靠性 | stop、seek、interruption、route change 和失败共享 reset 状态机与聚合指标。 |

这些基础证明系统已经能保留和重放更多音乐事实，但不自动证明参考演奏自然、评价正确或教学有效。

## 当前剩余质量边界

### 1. MusicXML 解释不是通用出版与演奏引擎

当前实现覆盖普通钢琴谱的核心结构，以及一部分 grace、arpeggio、fermata、wedge、tempo words、ornament、pedal 和结构跳转。以下仍需要按目标曲库和真实 exporter corpus 验证：

- additive meter、复杂 metric modulation、swing、senza misura。
- transpose、octave shift 与微分音的完整播放/显示一致性。
- grace previous/following/make-time 的跨声部和边界案例。
- 独立与跨谱表 arpeggio 的 number/voice/group 语义。
- niente、瞬态 dynamics、复杂 hairpin 与风格化动态。
- 高级 ornament、tremolo、glissando、breath/caesura 和非常用 notehead。
- 多谱表、当代记谱和原出版版面的完整保真。

不支持的语义必须保留 source identity、kind、reason 和 approximation/unsupported 状态；不能静默生成看似合理的错误事实。

### 2. 参考回放仍是确定性解释，不是钢琴家示范

默认 articulation、fermata、arpeggio spread、tempo ramp 和 ornament shaping 使用集中、可审查的 interpretation profile。它适合一致的乐谱试听与练习示范，但实际演绎还依赖风格、和声、声部、触键、乐句和教师意图。

在通过真实曲目事件对照、指定音源真机测量和多名钢琴家盲听前，不使用“钢琴家级”“替代真人示范”等措辞。

### 3. 连续演奏分析是客观证据，不是专业结论

`PerformanceAlignmentEngine` 与有界增量状态机已处理连续演奏中的 missing、extra、重复音、同音多声部、performed occurrence 和 controller，并保留 score/observation identity、候选证据、ambiguous、provisional 与 unknown。`PerformanceAssessmentService` 从该证据生成带单位、置信度和适用条件的 pitch、timing、duration、velocity、voicing 与 pedal 等客观维度；没有能力或证据不足的维度保持 unavailable/insufficient，不用默认零分填补。

完整 alignment、逐音证据和 take assessment 只存在于运行期；进度 JSON 只保存经过批准的小节级 maturity、rubric version、证据覆盖率和 metric summaries，不保存 observation identity、原始输入或逐音对齐。现有 rubric 尚未通过足够的真实设备、授权曲目和钢琴专家一致性验证，因此仍不能把阈值解释为艺术质量、身体技术或等同教师的诊断，rubato、风格表达与真正错误的边界仍需专家证据。

### 4. 三类输入不能共用一个准确率

| 输入 | 当前可靠证据 | 当前不应评价 |
| --- | --- | --- |
| Bluetooth MIDI | pitch、onset、release、velocity、controller、polyphony | hand、finger、姿势 |
| 定向麦克风 | 目标音集合与有限 onset/confidence | 逐音 release、velocity、复杂复调、踏板、声部 |
| 手部接触 | 已校准键位候选、onset/release、hand/finger、位置、估算 velocity | 未经真机验证的精确力度、姿势质量、踏板 |

产品 UI、测试和后续评分必须按 capability 裁剪结论。低置信度、tracking loss、输入不可用和校准失效属于未知或不可用，不属于错误。

### 5. 真机和音乐证据仍是发布门

自动化可以证明字段、顺序、状态机和确定性，不能证明真实发声时延、追踪精度、听感或教学效果。仍需独立完成：

- Vision Pro 本地发声、手部触键和外部 MIDI 的 p50 / p95 / p99 延迟与 jitter。
- 快速重复音、密集和弦、长 sustain、半踏板、route/interruption 的漏触发与卡音测试。
- 不同 exporter 的授权 MusicXML corpus 与人工事件对照。
- 钢琴家盲听，区分谱面忠实度与风格自然度。
- 教学建议的教师审查和前后测。

具体运行规则见 [钢琴演奏专业化验证手册](testing/piano-performance-validation.md)。

## 产品模式与承诺

| 模式 | 可以承诺 | 不可以承诺 |
| --- | --- | --- |
| 找键 / step 练习 | 当前目标音或和弦是否被观察到 | 专业节奏、力度、踏板评分 |
| 麦克风辅助练习 | 目标音集合与有限 onset 辅助 | 复杂复调转录和完整踏板评价 |
| 手部空间练习 | 已校准键位、接触与有限手/指提示 | 低置信度下的正确手法结论 |
| 乐谱驱动示范 | 可审查、可重复的 plan 事件回放 | 未经盲听验证的钢琴家诠释 |
| AI 对弹 | 用户选择后端的创意响应与伴奏 | 原谱忠实示范和评分基准 |
| MIDI 客观分析 | 可解释的 pitch/timing/duration/velocity/pedal 指标 | 唯一艺术解释和身体技术诊断 |

## 后续优先级

1. 用真实 exporter corpus 关闭剩余 MusicXML 正确性与 unsupported 报告缺口。
2. 在指定 Vision Pro、音频路由与 MIDI 设备上建立触键、输出、重复音和踏板基线。
3. 用授权 MIDI take 与专家标注验证 alignment、rubric 阈值和证据不足边界。
4. 只在可靠 metric、confidence、适用前提和退出条件齐全时增加 coaching rule。
5. 最后再做风格化参考 profile、教师参考演奏或更高级生成模型。

## 必须保留的架构边界

- `PracticeStep` 继续只负责即时判定。
- source measure 继续是正式练习事实的持久化单位。
- cue、summary、恢复地图、RealityKit 表现和原始逐帧传感数据不写入 progress JSON。
- score alignment、逐音 assessment evidence 与完整 take assessment 保持运行期数据；progress JSON 只接受批准的小节级聚合事实。
- AI 后端严格使用用户选择，失败即停止本次生成，不自动切换。
- 新实现替换旧实现时，同一 task 删除旧 API、旧状态、旧测试和双轨分支。

## 完成定义

只有满足对应证据门后，才升级产品措辞：

- **乐谱忠实示范**：golden corpus、事件 dump、unsupported 报告、输出等价性和盲听通过。
- **MIDI 演奏评价**：alignment 可追溯，metric 有单位，未知不计错，专家一致性达到预设门槛。
- **虚拟琴具有表现力**：每音 velocity、release、重复音、和弦、踏板和真机时延达到批准阈值。
- **专业虚拟指导**：每条建议有可靠证据、置信度、教师审查和用户前后测。
