# 钢琴演奏、专业指导与示范质量审查

本文是 HappyPianist 在曲谱解释、钢琴演奏生成、虚拟琴发声、演奏观察、练习评价与空间指导方面的长期质量基线。它取代此前较窄的“曲谱解析与虚拟指导”审查，并作为后续代码改造的事实输入。

这不是开发流水账，也不是一次性功能清单。相关实现、产品承诺或验收证据发生变化时，应直接更新对应结论、问题状态和验收门槛。

## 审查范围与证据边界

### 本次覆盖

- MusicXML / MXL 导入、规范化、主 part 选择与演奏顺序。
- 音高、时值、力度、速度、踏板、装饰音、发音法与乐句语义。
- `PreparedPractice`、高亮指南、五线谱投影与自动示范之间的数据流。
- 本地三角钢琴采样、外部 MIDI 和手动提示的事件调度。
- 蓝牙 MIDI、麦克风、真实钢琴手部追踪与虚拟琴接触输入。
- 即时判定、小节进度、反馈策略、AI 对弹与录制回放。
- 测试体系、真机测量、音乐家主观评价与专业产品宣称。

### 本次没有完成

- 没有在 Xcode、visionOS Simulator 或 Apple Vision Pro 上运行 `xcodebuild test`。
- 没有实际试听产品方使用的三角钢琴采样，也没有检查其采样层、release sample、循环点、共鸣或授权。
- 没有连接真实蓝牙 MIDI 钢琴、麦克风、踏板或外部 MIDI 音源。
- 没有进行专业钢琴家的盲听、跟弹、评分一致性或教学有效性实验。

因此本文区分三类结论：

| 标签 | 含义 |
| --- | --- |
| **代码确认** | 可从当前源码和测试直接确认。 |
| **规范确认** | 可由 MusicXML、MIDI 或 Apple 平台规范确认。 |
| **待实测** | 必须经过真机、硬件、听感或用户研究，不能由静态代码推出。 |

### 关于钢琴采样的前提

产品方确认当前使用的是高质量专业三角钢琴采样，本文接受这一前提，不把“立刻更换音源”列为优先事项。

专业音色素材与专业演奏系统是两件事。优质采样只有在上游提供正确的 velocity、note-off、踏板、控制器、时序和声部关系时，才会表现出完整价值。当前主要瓶颈位于这些上游事件，而不是采样品牌或文件体积。

## 总体结论

HappyPianist 已经超过“把 MusicXML 音符映射到 88 键”的原型阶段。项目具备明确的准备管线、分层服务、速度图、力度事件、踏板时间线、音符区间、自动播放、三类练习输入、小节进度和较广的单元测试。

但按专业钢琴产品的标准，当前仍是：

> **以音高和步骤完成为核心、具有部分乐谱表现力回放的空间钢琴练习系统。**

它目前不能可靠地完成两项更高承诺：

1. **不能证明用户弹得是否专业。** 当前成功判定主要回答“目标音是否在允许窗口内出现”，并未可靠观察和评价节奏、音长、力度、声部、踏板、发音、乐句或风格。
2. **不能生成足以替代真人示范的参考演奏。** 自动播放包含力度、速度和部分踏板/装饰时序，但仍会丢失或启发式处理关键谱面语义，而且播放事件由 UI 高亮投影反推，而不是由独立的规范演奏计划生成。

### 当前可以安全宣称

- 支持 MusicXML / MXL 钢琴谱的导入与练习准备。
- 能把大部分普通音符映射到对应 MIDI 琴键。
- 能按当前步骤进行找音、和弦集合与小节练习。
- 能生成带部分力度、速度、发音法、倚音、琶音、延长记号和二值踏板的乐谱驱动回放。
- 能通过蓝牙 MIDI、定向麦克风识别和空间手部接触提供不同置信度的练习输入。
- AI 对弹可作为响应式即兴或伴奏功能。

### 当前不应宣称

- “专业级钢琴演奏评分”或“像钢琴教师一样判断演奏”。
- “忠实还原所有 MusicXML 钢琴作品”或“替代钢琴家参考示范”。
- “可靠判断左右手、指法、跨谱表和双手交叉”。
- “麦克风、手部追踪与 MIDI 提供等价的演奏证据”。
- “应用内五线谱等价于权威原谱或专业制谱输出”。
- “虚拟琴已经具备真实钢琴的触键层次、半踏板和声部控制”。

## 专业质量模型

“专业”不能由一个总分代表。至少应拆成八个互不替代的维度：

| 维度 | 专业标准 | 当前状态 |
| --- | --- | --- |
| 曲谱真值 | 保留原始记谱身份、结构、声部、拼写、控制与演奏顺序 | 基础可用，高级语义和规范化仍有损失 |
| 参考演奏 | 从独立演奏计划稳定生成 onset、offset、velocity、pedal、tempo 与结构 | 局部可用，尚未成为唯一真源 |
| 实时琴感 | 每音独立力度、可靠释放、低延迟、踏板和可恢复音频生命周期 | 虚拟琴仍以固定力度为主 |
| 观察可信度 | 每种输入明确说明能观察什么、置信度和时钟来源 | 尚无统一能力与证据契约 |
| 演奏评价 | 将演奏与谱面可靠对齐，并评价可解释的音乐维度 | 尚未建立 |
| 教学指导 | 根据可靠证据选择具体、可执行且不过度宣称的练法 | 当前是确定性流程控制，不是教师诊断 |
| 记谱呈现 | 原谱拼写、休止、连线、声部、谱号、节奏组和符号保持一致 | 当前是练习投影，不是专业制谱 |
| 实证验证 | 通过真实导出谱、硬件测量、盲听和专家一致性验证 | 单元测试广，专业 golden corpus 与真机证据不足 |

关键判断是：

> 当前最重要的缺口不是“再接一个更大的 AI 模型”，而是先停止丢失音乐事实、停止混用不同输入证据，并建立可验证的规范演奏和评价契约。

## 当前真实数据流

### 曲谱准备

```text
MusicXML / MXL bytes
-> MusicXMLParser
-> MusicXMLPianoGrandStaffNormalizer
-> optional MusicXMLStructureExpander
-> preferredPrimaryPartID + filtering(toPartID:)
-> MusicXMLHandRouter
-> PracticeStepBuilder
-> tempo / pedal / fermata / attribute timelines
-> MusicXMLNoteSpanBuilder
-> PianoHighlightGuideBuilderService
-> PreparedPractice
```

`PreparedPractice` 当前保存：

- steps
- tempo map
- pedal timeline
- fermata timeline
- attribute timeline
- highlight guides
- measure spans
- unsupported-note count

它没有保存完整解析谱面，也没有保存独立、规范化的 performance plan。`MusicXMLNoteSpanBuilder` 生成的音符区间在构建高亮后被丢弃。

### 自动播放

```text
PreparedPractice.highlightGuides
-> AutoplayPerformanceTimeline
-> PracticeSequencerSequenceBuilder / CoreMIDI scheduler
-> local sampler or external MIDI
```

这意味着当前的声音事实由高亮 UI 投影反推。UI 去重、声部折叠、相同音高合并或范围裁剪都可能改变演奏事件。

### 练习输入

```text
Bluetooth MIDI -----------┐
Targeted microphone ------+-> input-specific accumulator / matcher
Hand tracking / contacts -┘
                         -> step outcome
                         -> round / measure reducer
                         -> feedback policy
                         -> per-measure persisted facts
```

三类输入的实际观测能力差异很大，但最终大多汇入相同的“当前 step 是否通过”语义。

## 三个架构级阻塞点

### ARCH-001：缺少唯一的谱面与演奏真源

**严重度：P0｜证据：代码确认**

当前 `MusicXMLScore` 已经丢失部分原始记谱信息，`PreparedPractice` 又丢失 note spans 和完整谱面，自动播放再从高亮指南重建事件。

结果：

- 曲谱解释、声音、高亮和五线谱不是同一事实的稳定投影。
- 修复 UI 可能意外改变声音。
- 无法可靠生成可审查的“乐谱事件 dump”。
- 无法把用户演奏对齐到稳定的参考音符身份。

专业目标不是盲目新增多层模型，而是建立最小且唯一的事实链：

```text
保留足够记谱信息的规范谱面
-> 唯一 ScorePerformancePlan
-> 声音 / 高亮 / 练习 step / 记谱分别投影
```

现有 `MusicXMLScore` 可以演进为规范谱面；不要求为了命名再复制一层。`ScorePerformancePlan` 则是当前确实缺失且有多个消费者的稳定边界。

### ARCH-002：输入能力、来源和置信度没有统一契约

**严重度：P0｜证据：代码确认**

MIDI 可以提供 velocity、note-off 和 CC；麦克风只能在当前算法下提供定向音高/onset 证据；手部追踪理论上可提供手、指、位置和运动，但当前只输出 MIDI note 集合。系统没有统一表达：

- 来源类型与设备。
- 设备时间戳和接收时间戳。
- 能否观察 velocity、release、pedal、hand、finger。
- 置信度、校准状态与延迟估计。
- “未知”与“错误”的区别。

没有该契约时，任何统一“专业评分”都会把不可观察的维度误判为零分或成功。

### ARCH-003：产品模式共用同一个成功语义

**严重度：P0｜证据：代码确认**

以下任务并不等价：

- 找到正确琴键。
- 按节拍弹对一段。
- 完整演奏评价。
- 试听乐谱。
- 参考钢琴家示范。
- 创意 AI 对弹。

当前多个路径仍围绕 `PracticeStep` 和 step match 展开。后续改造必须先分产品模式，再决定可用证据和验收标准；不能把所有指标继续塞进 `PracticeStep`。

## 输入证据能力矩阵

下表区分“输入理论上能提供”与“当前代码实际消费”。

| 维度 | 蓝牙 MIDI | 麦克风 | 手部追踪 / 虚拟琴 |
| --- | --- | --- | --- |
| 音高 | 原生可靠；当前消费 | 定向谐波估计；当前消费 | 由空间键位映射；当前消费 |
| onset | MIDI event timestamp；当前未形成统一校准时钟 | detector timestamp；仅定向 onset | 接触开始；当前以调用时刻为主 |
| note-off / 音长 | 原生可得；当前练习判定默认不要求 | 当前无可靠 release | 接触结束可得，但没有统一评价语义 |
| velocity | MIDI 1 / 2 可得；当前判定丢弃 | 不能直接等价为 MIDI velocity | 可由触键前运动估计；当前固定发声力度 |
| damper pedal | CC64 可得；当前练习输入基本忽略 | 难以可靠分离 | 当前没有踏板追踪输入 |
| sostenuto / una corda | CC66 / CC67 可得 | 当前不可可靠识别 | 当前不可观察 |
| 声部平衡 | 可由多音 velocity 计算 | 复调与音量分离不足 | 需每指独立速度；当前没有 |
| 手 / 指身份 | MIDI 通常不可知 | 不可知 | 理论可知；当前结果被合并为 MIDI set |
| 复调快速织体 | 高 | 当前只适合目标导向检测 | 受追踪帧率、遮挡和空间校准影响 |
| 可用于专业评分 | 最适合作为第一阶段 | 仅限明确声明的音高/onset 辅助 | 先做校准与可信接触，再限定维度 |

原则：

> 每种输入只评价它实际观察到的维度。不可观察或低置信度结果必须返回“未知 / 需要重试”，不能伪装成“正确”或“错误”。

## 详细问题清单

### A. 曲谱真值与 MusicXML 语义

#### SCORE-001：数值 dynamics 的 MusicXML 语义错误

**严重度：P0｜证据：规范确认 + 代码确认**

`MusicXMLParserDelegate.parseMIDIVelocity(_:)` 当前把 `dynamics="64"` 直接解析为 MIDI velocity 64，并只接受整数。

MusicXML 4.0 将该值定义为相对默认 forte 90 的非负十进制百分比。`100` 应表示约 velocity 90，而不是 100；`72.5` 也是合法值。

影响：

- 来自不同制谱软件的动态会系统性偏差。
- 小数值被丢弃。
- 当前测试会固化错误语义。

验收：

- 使用 `Double` 解析。
- 按 `90 * percentage / 100` 换算并明确舍入规则。
- 同时验证 `<sound dynamics>` 与 note dynamics。
- 增加 0、100、141.1、小数和越界 fixture。

#### SCORE-002：direction `<offset>` 没有一致移动全部方向事件

**严重度：P0｜证据：代码确认，最终标准语义需 fixture 复核**

parser state 为 dynamics、wedge、fermata、words 记录了 direction 起始索引，但 offset 应用路径主要移动 tempo、sound directive 和 pedal。`<sound>` 中的 dynamics 也没有随 sound offset 一致移动。

影响：力度、渐强、文字速度、延长记号可能落在错误 tick；在普通短样例中不一定暴露。

验收：

- 为 direction offset 建立统一定位函数。
- 对 tempo、dynamics、wedge、pedal、fermata、words 和结构 sound directive 分别建立正/负 offset fixture。
- 用 MuseScore、Dorico、Sibelius、Finale 至少各一份真实导出文件核对事件 tick。

#### SCORE-003：两 part “大谱表归一化”会丢事件并可能误合并乐器

**严重度：P0｜证据：代码确认**

`MusicXMLPianoGrandStaffNormalizer` 在“恰好两个有音符的 part、一个最早 G 谱号、一个最早 F 谱号、没有 staff >= 2”时，把低音 part 的 note `partID` 改成高音 part。

当前没有同步合并或重写低音 part 的：

- tempo / dynamics / wedge
- pedal / fermata / words
- time / key / clef attributes
- measures / repeats / endings / sound directives

随后 `filtering(toPartID:)` 会删除仍属于低音 part 的事件。

此外，仅凭一 G 一 F 两个 part 无法证明它们是一架钢琴；大提琴与小提琴等双乐器谱可能被误合并。

验收：

- 先解析 score-part / instrument 元数据，只有明确满足钢琴契约时才归一化。
- 归一化必须重写所有 part-scoped 事件和 measure identity，而不只重写 notes。
- 归一化后低音材料应进入 staff 2 或保留明确的原始 staff / part provenance。
- 加入“分离双 part 钢琴”和“非钢琴 G+F duet”反例。

#### SCORE-004：主 part 选择依赖 P1 或音符数量启发式

**严重度：P1｜证据：代码确认**

`preferredPrimaryPartID` 优先 P1，否则选择非休止音符最多的 part。当前模型没有使用 score-part 名称、MIDI instrument、group 或 piano identity。

影响：多乐器 MusicXML、四手联弹、钢琴协奏或 exporter 特殊布局可能选错主 part。

验收：解析并保留 part 元数据；产品只支持独奏钢琴时，无法证明是独奏钢琴的文件应给出明确不支持原因，而不是静默选最大 part。

#### SCORE-005：staff 被当作确定的左右手

**严重度：P0｜证据：规范确认 + 代码确认**

`ScoreHand.fromStaff(_:)` 基本等价于 staff 1 = 右手、staff 2+ = 左手；单谱表作品由 `MusicXMLHandRouter` 按音域和中位数改写 staff。

MusicXML staff 是 part 内从上到下的谱表编号，不是手别。以下情况会误导：

- cross-staff notation
- 双手交叉
- 一只手跨两谱表
- 同一谱表双手分奏
- 三谱表作品
- 复调作品中的声部与手别不一致

验收：

- 将 `hand` 改为可选结果并携带来源：explicit / userConfirmed / inferred / unknown。
- 不再把启发式推断写回 staff 真值。
- 未知时不用于严格手别判定；UI 可显示“建议手”而不是“正确手”。

#### SCORE-006：原始音名拼写和微分音信息被过早压缩为 MIDI note

**严重度：P1｜证据：代码确认**

parser state 的 `noteAlter` 为 `Int?`，最终 note 只保留 `midiNote`，不保留 step、alter、octave、accidental、courtesy/cautionary、enharmonic spelling 等原始身份。

影响：

- D-flat 与 C-sharp 在记谱层不可区分。
- 双升降、异名同音、临时记号取消和微分音无法忠实显示。
- 后续五线谱只能从 MIDI 反推拼写。

验收：保留原始 written pitch 与 sounding MIDI pitch；不要求立即支持所有微分音发声，但必须能明确标记“解析保留、播放降级”或“不支持”。

#### SCORE-007：note identity 缺少 staff / voice，复杂同音可能冲突

**严重度：P1｜证据：代码确认**

`MusicXMLNoteEvent.id` 包含 part、measure、tick、midi、duration 等，但不包含 staff 和 voice。相同 tick、音高、时值的同音在两个声部或谱表中可能得到相同 ID。

影响：grace / arpeggio schedule、去重、对齐与诊断可能把两个记谱音合并。

验收：建立稳定 source-note identity，至少包含 source part、measure occurrence、voice、staff、ordinal；不要用演奏属性拼接字符串代替身份。

#### SCORE-008：节拍、速度标记与移调语义覆盖不足

**严重度：P1｜证据：代码确认**

当前模型主要支持整数 `beats` / `beatType`，metronome beat-unit 覆盖有限且只有单附点。尚未形成完整支持：

- additive meter，例如 `3+2/8`
- interchangeable / senza-misura 等复杂 meter
- 多附点 beat unit、metric modulation
- swing / beat-unit relation
- transpose
- octave-shift

影响：当这些信息改变实际发声音高或节拍解释时，不只是“少显示一个符号”，而是演奏事件会错。

验收：先按真实目标曲库排序；transpose、octave-shift 和 additive meter 进入专业导入 P1，纯排版属性可延后。

#### SCORE-009：grace 的 previous / following / make-time 语义不完整

**严重度：P0｜证据：规范确认 + 代码确认**

`steal-time-previous` 与 `steal-time-following` 当前被统一用于缩短后续主体音；`make-time` 未进入完整模型。slash 仅通过固定比例缩短。

影响：倚音 onset、前后主体音时值及小节时间可能错误。

验收：

- previous 从前音取时。
- following 从后音取时。
- make-time 增加时间并同步 performance plan。
- 多个 grace、跨声部、无明确属性和首音 grace 分别有 fixture。

#### SCORE-010：arpeggiate 分组、方向与跨谱表语义不完整

**严重度：P1｜证据：规范确认 + 代码确认**

step builder 和 note-span builder 的 key 主要由 part + staff + tick 组成，没有完整消费 number、voice 和跨谱表连接。只要同 key 中部分音标记 arpeggiate，其他音也可能被纳入。

当前 matcher 只看音高集合，不验证：

- upward / downward 顺序
- 展开时长
- 分组边界
- 同时存在的独立琶音

验收：由 source-note identity + arpeggiate number 建组；明确跨谱表规则；演奏计划与评价共享同一展开定义。

#### SCORE-011：力度事件的时间优先级和 wedge 语义不够可靠

**严重度：P1｜证据：代码确认**

`MusicXMLVelocityResolver` 会优先寻找已有 sound dynamics，再寻找 printed direction dynamics。旧 sound dynamics 可能长期覆盖更新、更晚的印刷力度；正确逻辑应先比较 tick，再只在同 tick 定义来源优先级。

wedge 主要依赖未来显式 dynamic 才能确定终点，尚未完整处理 niente、spread、continue 与无终点 hairpin。accent / marcato 仍是固定 velocity 增量。

验收：

- 所有候选先按时间选最新，再按同 tick 来源规则解决冲突。
- wedge 形成可审查的动态曲线，不依赖隐式全局默认。
- 对 sfz / fp 等瞬态与后续动态分别建模。

#### SCORE-012：常用钢琴演奏符号仍未形成事件契约

**严重度：P2；当目标曲库需要时升级为 P1｜证据：代码确认**

尚缺或不完整：

- slur / phrase hierarchy
- trill、mordent、turn
- measured / unmeasured tremolo
- glissando
- breath / caesura
- sf、sfp、fp、rfz、sfz、fz、n、pf、other-dynamics
- sostenuto 与 una corda
- half-pedal depth 与渐进抬踏

原则：只实现产品曲库实际需要的语义；但在未支持时应明确报告，不得静默生成看似合理的错误演奏。

#### SCORE-013：书写顺序与演奏顺序没有成为显式产品模式

**严重度：P1｜证据：代码确认**

`MusicXMLRealisticPlaybackDefaults.shouldExpandStructure` 当前为 false。虽然已有 repeat、ending、D.C.、D.S. 和 Coda 结构模型，正式准备仍默认按书写顺序。

逐小节学习可以按书写顺序；完整参考播放通常应按演奏顺序。两者必须由调用场景显式选择，不能由全局 default 混用。

#### SCORE-014：step 与 note-span 各自实现 grace / arpeggio 调度

**严重度：P1｜证据：代码确认**

`PracticeStepBuilder` 与 `MusicXMLNoteSpanBuilder` 重复计算装饰时序。重复已经达到会产生语义漂移的程度。

验收：提取一个最小、纯 Swift、可测试的 performance scheduling 核心；step 只投影即时练习需求，note span / performance plan 承担声音时序。

### B. 参考演奏与声音事件

#### PERF-001：note spans 不是持久的准备结果

**严重度：P0｜证据：代码确认**

note spans 只作为 `PianoHighlightGuideBuilderService` 输入，随后从 `PreparedPractice` 消失。自动播放无法直接使用最接近演奏事实的结果。

验收：`PreparedPractice` 保存一个独立、不可由 UI 反推的 `ScorePerformancePlan`；其音符、控制器和结构事件可稳定 dump、比较和重放。

#### PERF-002：高亮构建与自动播放会折叠同音声部

**严重度：P0｜证据：代码确认**

高亮 builder 和 autoplay 以 midi / staff / voice / tick 或 onTick + midi 等 key 建字典和分组，部分路径保留 first / longest / max velocity。同音重叠、不同声部同音和重击 retrigger 可能被合并或截断。

影响：复调、重复音、延音中的同音重击和跨声部同音无法保持原始身份。

验收：演奏计划按 source-note identity 保存事件；到具体音源层才处理同通道同音重触发策略，并为该策略建立测试。

#### PERF-003：从中间范围开始时没有完整重建正在发声的音

**严重度：P1｜证据：代码确认**

focused range 可以注入初始 sustain 状态，但没有统一恢复在范围下界之前已 onset、下界之后仍应发声的 tie / sustained notes。

验收：range seek 生成初始 controller state 和 sounding-note state；与从头播放后跳到同一位置的事件结果一致。

#### PERF-004：fermata 可能同时延长 note-off 又插入 pause

**严重度：P1｜证据：代码确认，需事件 fixture 验证最终效果**

note-span builder 会扩展 offTick，autoplay timeline 还可能在下一 step 前插入 pause。当前需要用 event dump 确认是否对同一 fermata 双重计时。

验收：fermata 的“保持发声”和“全局时间延长”由一个统一规则生成；每个 fermata 只产生一次总时长影响。

#### PERF-005：发音法、fermata 和 arpeggio 使用固定比例启发式

**严重度：P1｜证据：代码确认**

当前近似包括：

- staccatissimo 25%
- staccato 50%
- detached-legato 75%
- marcato 75%
- fermata 增加约原值 50%，并有固定上限
- arpeggio 总展开量有较窄固定上限

这些可以作为机械回放 default，但不是专业解释。实际值依赖速度、风格、声部、乐句和音源响应。

验收：先确保所有固定规则集中、可审查、可按 style profile 替换；没有经过盲听验证前，不宣称为“钢琴家演绎”。

#### PERF-006：速度文字和 tempo ramp 覆盖有限

**严重度：P1｜证据：代码确认**

words interpreter 主要识别 rit / ritardando、accel / accelerando、a tempo 和有限 pedal 文字。rallentando、ritenuto、stringendo、rubato、meno/più mosso、tempo primo 等未形成契约。

还需验证 `easeInOut` tempo ramp 是否真的产生足够中间控制点；只有端点时，积分结果可能仍接近线性。

验收：文字语义必须保留原文和推导来源；推导失败时不静默伪造。常见词表按目标曲库增加，不做无限自然语言解析。

#### PERF-007：手动重播是音高预览，不是参考演奏

**严重度：P1｜证据：代码确认**

`PracticeManualReplaySequenceBuilder` 对 step 使用近似固定音长并在 step 间发送 All Notes Off，没有复用完整 note spans、踏板、结构、grace、arpeggio 和 fermata。

产品语义应分开：

- “试听当前音 / 音高提示”：可保留轻量实现。
- “示范本节”：必须消费同一个 `ScorePerformancePlan`。

#### PERF-008：虚拟琴实时 note-on 使用固定 velocity

**严重度：P0｜证据：代码确认**

`KeyContactResult` 只有 down / started / ended，`startLiveNotes(midiNotes:)` 只接收音高集合，本地与外部服务使用默认 velocity。

这会让轻触、重击、慢压、快速触键和和弦内声部全部趋于同一动态。对高质量三角钢琴采样而言，这是当前最大的实时表现力损失。

验收：

- 每个触键产生独立 velocity。
- velocity 来自触键前法向速度或更稳定的短窗模型。
- 曲线可校准，具有 dead zone、最小/最大值和饱和保护。
- 同一和弦每指独立，不用单个集合 velocity。
- 记录汇总诊断，不导出逐帧手部数据。

#### PERF-009：踏板从 MusicXML 到输出仍是二值

**严重度：P1｜证据：规范确认 + 代码确认**

`MusicXMLPedalEvent.isDown` 和 timeline change 只表示 Bool，最终发送 CC64 0 / 127。MusicXML `<sound damper-pedal>` 允许 0...100 的半踏值，`<pedal>` 也可表示 damper 与 sostenuto 语义。

验收：保留 0...1 或 0...100 的规范深度，再在输出层映射 0...127；只有音源支持时再接 damper resonance / una corda 等扩展，不创建空控制器抽象。

#### PERF-010：外部 MIDI 逐事件 `Task.sleep`，packet timestamp 为“现在”

**严重度：P1｜证据：规范确认 + 代码确认**

CoreMIDI scheduler 在每个目标时间点唤醒 Task 再发送，packet timestamp 使用 0。Apple 文档说明发送 packet 的非零 timestamp 表示实际播放时刻，0 表示立即播放。

影响：密集和弦、快速重复音、踏板与音符同步受系统唤醒抖动影响。

验收：按短时间窗提前构建带 host-time timestamp 的 packet batch；停止、seek 和路由切换有明确取消语义。

#### PERF-011：音频会话与停止恢复不够可诊断

**严重度：P1｜证据：代码确认**

当前部分 `AVAudioSession` 设置使用 `try?`，引擎或会话失败可能被弱化或被映射为不精确错误。停止路径没有在所有输出上统一发送 sustain up、reset controllers 和 all sound off。

专业目标：

- 明确处理 route change、interruption、media services reset。
- 会话配置失败进入结构化诊断和用户可恢复状态。
- stop / seek 统一复位 CC64、CC66、CC67、CC121、CC120/123 中实际需要的集合。
- 避免卡音和残留踏板。

#### PERF-012：没有端到端时延、抖动和漏触发指标

**严重度：P0（专业宣称前）｜证据：代码确认**

当前没有可证明的：

- 事件到发声延迟分布。
- 手指运动到虚拟琴发声延迟。
- 外部 MIDI 调度 jitter。
- 快速重复音漏触发率。
- 多音同时触发偏差。
- 路由恢复成功率。

验收不能写成“听起来没问题”。必须在指定 Vision Pro、音频路由、蓝牙 MIDI 设备和曲目上记录 p50 / p95 / p99、丢失率和复现条件；绝对门槛在取得基线后由真机体验决定。

### C. 记谱显示

#### NOTATION-001：当前五线谱是 MIDI 练习投影，不是原谱渲染

**严重度：P0（若对外称为权威谱面）｜证据：代码确认**

`GrandStaffNotationLayoutService` 从 MIDI note 和 guide 时序反推音符。原始 pitch spelling 已丢失，黑键音通常统一显示为升号。

影响：Db/C#、和声拼写、临时记号取消、双升降与调号上下文可能错误。

正确定位：滚动音高提示和键盘指导，而不是专业制谱或原谱校对。

#### NOTATION-002：显示时值来自表现后 on/off，而非记谱时值

**严重度：P1｜证据：代码确认**

note value 由 `offTick - onTick` 推断，而该区间已经受 staccato、release、fermata 等演奏语义影响。四分音符 staccato 可能被画成更短的音符值。

验收：记谱投影消费 written duration；演奏投影消费 performed duration，二者不能共用一个字段。

#### NOTATION-003：休止、谱号、连梁和复杂声部未保持原谱

**严重度：P1｜证据：代码确认**

当前 layout 不生成真实 rests，谱号位置和符干/连梁多由固定规则推断，staff 3+ 被压缩，原始 beam、tuplet、slur、dynamic、pedal 和 phrase 也不是完整谱面事实。

若专业五线谱不是产品核心，最简单的正确方案是明确“练习简谱化视图”的边界，而不是自研完整制谱引擎。

#### NOTATION-004：fingering 仅是单个文本，不足以支撑专业指法指导

**严重度：P2｜证据：代码确认**

当前只保留有限 `fingeringText`，没有替换指、滑指、同音换指、左右手来源、多个候选、用户版本和编辑者来源。

在手别真值未解决前，不应自动把该字段扩展成“专业指法纠正”。

### D. 演奏观察与即时判定

#### OBS-001：MIDI 输入拥有的演奏数据被主动丢弃

**严重度：P0｜证据：代码确认**

`PracticeMIDIInputService` 对 note-on velocity 不进入评价，note-off 默认不要求，CC 除 reset 类外不进入练习事实。MIDI 2.0 高分辨率输入虽然被解码，评价链仍主要消费音高。

验收：先建立原始、轻量且可回放的 `PerformanceObservation`，保留 note-on、velocity、note-off、channel、CC64/66/67、设备时间和接收时间；当前找音模式可继续只消费音高。

#### OBS-002：MIDI chord matcher 允许宽窗内串行按键通过

**严重度：P0（若称节奏/和弦评价）｜证据：代码确认**

默认 chord window 约 0.55 秒，matcher 使用 expected pitch set。四音和弦可以在窗口内依次按下并通过；也不评价 onset spread、方向、release、velocity 或 pedal。

该行为适合初学者“收集和弦音”，但模式名和 UI 必须明确。专业和弦评价需要独立阈值和 onset clustering。

#### OBS-003：麦克风是目标导向谐波检测，不是复调演奏转录

**严重度：P0（产品边界）｜证据：代码确认**

当前算法围绕 expected / wrong candidate 音高建立 harmonic templates，输出 midi、confidence、onset score、isOnset、timestamp 等。它没有可靠输出每音 release、velocity、pedal、voice 和连续节奏事实。

适合：

- 当前目标音是否出现。
- 有限制的 onset 证据。
- 无 MIDI 设备时的逐步练习。

不适合：

- 复杂复调的完整转录。
- 声部平衡评分。
- 半踏板和换踏评价。
- 以毫秒级精度评价快速织体。

#### OBS-004：palm 被当作 tracked tip 参与接触与按键逻辑

**严重度：P0｜证据：代码确认**

`TrackedFingerTip` 包含 `.palm`，公共遍历又把 palm 送入 contact tracker、press detector 和 activity gate。手掌靠近键盘时可能触发按键、接近或向下运动判断。

验收：触键候选只允许明确指尖 joint；palm 可用于手掌姿态或活动门控，但不能映射到琴键 note-on。

#### OBS-005：手部结果丢失手、指、时间、置信度和速度

**严重度：P0｜证据：代码确认**

`KeyContactResult` 只保存 MIDI set，没有：

- left / right hand
- finger identity
- contact position / key-local depth
- source timestamp
- confidence / tracking state
- pre-contact velocity
- calibration version

一旦压缩为 set，后续无法恢复和弦内力度、手别验证、指法和接触质量。

验收：接触事件应是每次触键的结构化 observation；集合仅作为找音 matcher 的投影。

#### OBS-006：固定阈值、无 delta-time 的运动判断不能跨设备稳定

**严重度：P1｜证据：代码确认**

虚拟琴、真实琴接触使用固定毫米阈值；部分 downward motion 以相邻帧位移判断，没有归一化 delta time。帧率、追踪质量、手型、校准误差和琴键几何都会改变结果。

验收：

- 使用 sensor timestamp 计算速度。
- 校准键面与容差。
- 根据 tracking confidence 和遮挡进入 unknown。
- 阈值通过真机数据确定并可版本化，不使用无限用户配置。

#### OBS-007：相邻半音容差会把空间误差重写为正确音

**严重度：P0｜证据：代码确认**

手部路径默认 `noteMatchTolerance = 1`，可能允许相邻半音作为匹配。空间追踪不确定性不等于音乐音高等价性。

正确处理：

- 追踪不确定时返回 unknown / retry。
- 只有明确产品模式（例如儿童粗定位）才允许宽容，并在 UI 中说明。
- 专业模式 MIDI 音高不应有半音容差。

#### OBS-008：所谓 hand-separated 判定仍消费合并后的 pressed set

**严重度：P0｜证据：代码确认**

当前手部接触先合并为 MIDI 音高集合；左右手 gate 随后看的是同一集合，并不能证明某音由指定手触发。

在 ARCH-002 与 OBS-005 修复前，不能宣称“检测到左手/右手正确演奏”。

#### OBS-009：输入时钟与延迟没有统一

**严重度：P0（节奏评价前）｜证据：代码确认**

部分 AR / contact 调用使用 `Date.now` 或接收时刻，MIDI 和音频又有各自时间源。没有统一 host clock、设备时间、接收时间和延迟校准，就不能比较毫秒级 onset。

验收：定义单调时钟域；每个 observation 保留 source timestamp、host receive timestamp 和估计 latency；所有 score alignment 在同一时基上完成。

### E. 演奏评价与教学指导

#### ASSESS-001：尚无 score-performance alignment

**严重度：P0｜证据：代码确认**

系统没有把一段连续用户演奏中的 note identity 与谱面 source-note identity 对齐。当前 matcher 只围绕“当前 step”工作。

没有 alignment，无法可靠处理：

- 漏音、加音、重弹和跳过。
- rubato 下的局部节奏。
- tie / repeated note identity。
- 旋律与伴奏声部。
- 踏板覆盖的 release。
- 回头重练与小节内错误恢复。

第一版专业评价应只针对 MIDI，先完成单段、单曲谱、可解释的离线或准实时 alignment；不要同时解决麦克风复调转录。

#### ASSESS-002：当前进度代表“步骤稳定”，不是“演奏成熟”

**严重度：P0（产品语言）｜证据：代码确认**

小节稳定主要来自所有 step 在无失败轮次中匹配若干次。持久化问题类型集中在 wrong note、missed note、incomplete chord。

它没有观察：

- pulse / rhythm stability
- articulation / duration
- voicing / balance
- dynamics shape
- pedal timing
- phrasing
- fingering
- posture / tension
- sight-reading / memory

因此当前进度条和“稳定”应解释为当前找音练习的完成事实，不是整体钢琴能力评分。

#### ASSESS-003：反馈政策是流程控制，不是教师诊断

**严重度：P1｜证据：代码确认**

当前反馈大致在 hotspot、重试、降速约 10% 和扩大范围之间选择。这种确定性 policy 简单、可解释，也适合当前证据；但不能据此给出“手指紧张”“旋律没有唱出来”“换踏太晚”等结论。

正确演进：

```text
可靠 observation
-> 可解释 metric
-> 明确 confidence
-> 受限的 coaching rule
-> 用户可执行动作
```

不能从一个 wrong-note 结果直接跳到开放式大模型教学建议。

#### ASSESS-004：错误、未知和证据不足没有稳定分开

**严重度：P0｜证据：代码确认**

手部 / 音频 accumulator 常见结果是 matched 或 insufficient；部分 issue enum 存在，但不同输入不一定稳定产生 missing / incomplete / wrong 的同义事实。

专业指导需要至少区分：

- correct
- incorrect
- incomplete
- not observed
- low confidence
- input unavailable
- calibration invalid

只有 incorrect 才应进入负面演奏事实；未知不应惩罚用户。

#### ASSESS-005：没有按输入能力裁剪评分 rubric

**严重度：P0｜证据：代码确认**

同一首曲子通过 MIDI、麦克风或手部输入时，能够评分的维度不同。后续 `PerformanceAssessment` 必须携带 evaluated / unavailable / uncertain 维度，不允许用默认零分填补缺失数据。

#### GUIDE-001：尚未建立从音乐问题到练法的专业映射

**严重度：P2；进入专业指导模式时为 P0｜证据：产品缺口**

专业指导不是堆更多文字，而是只在证据支持时给出具体练法，例如：

- onset spread 大：和弦落键同步练习。
- 节拍漂移：节拍脉冲或分层速度练习。
- 旋律声部 velocity 低于伴奏：声部突出练习。
- note overlap 与目标 articulation 不符：慢速触键/离键练习。
- pedal release 晚于和声变化：无踏板、分区换踏练习。

每条建议必须有触发指标、适用前提、退出条件和置信度。没有数据的姿势、放松和指法建议不应由模型臆测。

#### GUIDE-002：手别与指法建议必须显示来源

**严重度：P0｜证据：代码确认**

UI 至少应区分：

- 原谱明确提供。
- 用户 / 教师确认。
- 系统启发式建议。
- 未知。

推断手别或指法不得用与原谱事实相同的视觉权威级别。

#### GUIDE-003：需要“教师目标”而不是唯一理想演奏

**严重度：P2｜证据：专业产品要求**

同一作品可以存在多种合理 tempo、rubato、articulation、pedal 和 voicing。专业评价不能把机械 MusicXML playback 当成唯一答案。

后续至少支持：

- score-required constraints：音高、节拍结构、明确符号。
- reference profile：教师或示范演奏的可选目标。
- tolerance profile：按水平、速度和练习目标调整。
- interpretation metrics：描述差异，不轻易判错。

### F. AI 对弹与生成

#### AI-001：AI 对弹是创意响应，不是忠实示范

**严重度：P0（产品语义）｜证据：代码确认**

AI 对弹链保留部分 velocity、duration 和控制器，也遵守用户选择的后端；这些是优点。但生成结果的目标是响应性与音乐性，不是忠实执行导入谱面。

它不能替代：

- 当前曲谱的参考演奏。
- 教师示范。
- 用户演奏评分基准。

#### AI-002：手部来源进入 AI phrase 时仍被固定力度扁平化

**严重度：P1｜证据：代码确认**

MIDI phrase 可以带 velocity / duration / CC，而 key-contact phrase 使用固定 velocity 且没有 sustain。不同输入会导致 AI 对用户表现力的感知不对等。

修复依赖 OBS-005 和 PERF-008，不需要单独再造一套力度推断。

#### AI-003：当前质量门只覆盖有限的结构性问题

**严重度：P1｜证据：代码确认**

候选质量检查主要关注密度、重复、音区冲突、碎片化和极端跳进，并对 velocity 做一定 shaping。它没有证明长程和声、风格、声部进行、呼吸或与用户意图一致。

验收必须使用单独的 AI duet 盲听 rubric；不要与 score-faithful playback 共用一个“专业”标签。

### G. 录制与回放证据

#### RECORD-001：录制适合回放/导出，尚不适合正式评价证据

**严重度：P1｜证据：代码确认**

录制事件可保存 note-on velocity、note-off、CC、pitch bend、program 和 pressure，这是良好基础。但当前仍存在：

- MIDI 2.0 高分辨率值下转换。
- key-contact 录制固定 velocity、无 pedal / finger / source confidence。
- open notes 主要按 MIDI note 关联，channel 身份不足。
- take 缺少 score identity、输入来源、校准版本、时钟质量和 latency correction。
- 没有 score-performance alignment。

在加入评价前，先让录制成为可重放的 observation log；不要直接把现有 take 当作专业评分真值。

## 最小目标架构

以下是后续改造所需的最小边界，不要求一次性重写全部代码。

```text
MusicXML bytes
-> MusicXMLScore（保留 written pitch、source identity、part metadata 与原始语义）
-> 经过可证明规则的 piano normalization
-> ScorePerformancePlan
   - performed structure order
   - source-note identity
   - written timing + performed timing
   - note-on / note-off / velocity
   - tempo / pedal / controller
   - provenance / approximation flags
-> local sampler / external MIDI
-> highlight projection
-> notation projection
-> PracticeStep projection

MIDI / microphone / hand tracking
-> PerformanceObservation
   - source + capabilities
   - source timestamp + host timestamp
   - confidence + calibration
   - note / velocity / release / controller / hand / finger（按能力可选）
-> ScorePerformanceAlignment
-> PerformanceAssessment
   - measured metrics
   - unavailable / uncertain dimensions
-> CoachingDecision
-> 现有按小节持久化的练习事实
```

### 必须保留的现有边界

- `PracticeStep` 继续只负责即时练习判定，不承载完整演奏评分。
- 小节仍是正式练习事实的持久化单位。
- cue、summary、恢复地图、RealityKit 点亮和原始逐帧传感数据不写入进度 JSON。
- 第一阶段不新增第二套持久化体系；alignment 和 assessment 可先保持 session 内存数据。
- AI 后端继续严格使用用户选择，失败即提示并停止，不自动切换。
- 新实现替换旧实现时，同一 task 删除旧 API、旧状态、旧测试和双轨分支。

## 产品模式与承诺分层

| 模式 | 主要输入 | 可承诺 | 不可承诺 |
| --- | --- | --- | --- |
| 找键 / 步骤练习 | MIDI、麦克风、手部 | 当前目标音或和弦是否被观察到 | 专业节奏、力度、踏板评分 |
| 节奏与协调练习 | 优先 MIDI | onset、拍点、和弦同步、基本 duration | 手指、姿势、音色美学 |
| MIDI 演奏评价 | 完整 MIDI observation | 音高、timing、duration、velocity、pedal 的可解释指标 | 唯一艺术解释、身体技术结论 |
| 麦克风辅助练习 | 定向音高/onset | 目标音与有限 onset 辅助 | 复杂复调和踏板的完整评分 |
| 空间手部指导 | 已校准 hand tracking | 琴键位置、接触、有限手/指提示 | 在低置信度下断言正确手法 |
| 乐谱忠实示范 | ScorePerformancePlan | 可审查的谱面驱动演奏 | 未经盲听验证的“钢琴家级诠释” |
| AI 对弹 | 用户 phrase + 选定 backend | 创意响应、伴奏或轮奏 | 原谱忠实示范与评分基准 |

## 后续代码改造顺序

### Phase 0：先让问题可测量

目标：不改变用户行为，建立后续修改的证据基线。

1. 增加稳定的 MusicXML normalized-score dump 与 performance-event dump。
2. 为输入事件定义 source / capabilities / timestamp / confidence 最小模型。
3. 建立可离线重放的 MIDI 与合成 hand-contact observation fixture。
4. 给当前每个产品模式写清 safe claim。
5. 记录当前真机 latency / jitter / repeat-note baseline；没有设备时仅提交测量工具，不写“通过”。

退出条件：同一 fixture 的谱面、演奏事件和 matcher 结果可做 deterministic snapshot。

### Phase 1：修复谱面 P0 正确性

1. 修正 decimal dynamics percentage。
2. 修正 direction / sound offset 对所有事件的定位。
3. 修复两-part piano normalization，加入 part metadata 和误合并反例。
4. 分离 staff 与 hand，增加 provenance / unknown。
5. 保留 written pitch 与稳定 source-note identity。
6. 正确实现 grace previous / following / make-time。
7. 统一 grace / arpeggio scheduling 核心。

退出条件：目标 golden corpus 的规范谱面 dump 与人工标注一致。

### Phase 2：建立唯一演奏计划

1. 让 `ScorePerformancePlan` 成为声音真源。
2. `PreparedPractice` 保存演奏计划，不再从 highlight 反推声音。
3. 处理同音声部、retrigger、tie、seek/range start 和 controller state。
4. 解决 fermata 是否双重计时。
5. 明确书写顺序练习与演奏顺序示范。
6. 完整示范和本节重播共用演奏计划；音高试听保留独立轻量命名。

退出条件：本地 sampler 与外部 MIDI 对同一 plan 生成等价事件序列。

### Phase 3：提高实时演奏与输出可靠性

1. 虚拟琴每音 velocity 与校准曲线。
2. 连续 damper pedal；按实际音源能力接 sostenuto / una corda。
3. CoreMIDI timestamp batch scheduling。
4. 统一 stop / seek / interruption / route reset。
5. 建立 latency、jitter、drop、retrigger 和和弦 spread 测量。

退出条件：真机与指定硬件的测量结果达到预先批准的阈值，且没有卡音、残留踏板或明显力度扁平化。

### Phase 4：先做 MIDI 专业评价

1. 保留完整 MIDI observation。
2. 建立 score-performance alignment。
3. 先实现客观指标：pitch、onset、duration、chord spread、velocity contour、pedal timing。
4. 将“谱面硬约束”与“解释性差异”分开。
5. assessment 不直接改现有进度 JSON；只将批准的小节事实交给 reducer。

退出条件：在人工标注演奏上，错误定位与专家标注达到可接受一致性；所有分数可追溯到原始 observation 和谱面 note identity。

### Phase 5：按能力扩展麦克风与手部指导

1. 移除 palm 触键和相邻半音默认容差。
2. 保留 hand / finger / timestamp / confidence / velocity observation。
3. 建立校准与 unknown 状态。
4. 麦克风继续限定目标音/onset；只有新的转录模型经 corpus 验证后才扩大承诺。
5. hand-separated 只有在物理手身份证据存在时才能判定。

退出条件：每种输入都有独立 confusion matrix、漏检/误检率和可用场景说明。

### Phase 6：建立受证据约束的指导策略

1. 将 metric 映射到有限、可执行练法。
2. 每条建议声明触发条件、置信度、适用水平和退出条件。
3. 由钢琴教师审阅提示，不让通用大模型直接从原始事件自由发挥诊断。
4. 允许用户选择练习目标和教师参考 profile。

退出条件：指导建议在专家审查中不越过证据边界，并在用户测试中确实改善目标指标。

### Phase 7：风格化参考演奏与更高级 AI

只有 Phase 1–4 稳定后再考虑：

- style-aware articulation / rubato / voicing profiles。
- 教师或钢琴家参考 MIDI 的迁移。
- 基于 aligned score-performance 数据的表现生成。
- 多候选参考演奏，而不是唯一“正确演绎”。

这不是当前 P0，不应先于谱面真值和评价证据。

## 明确不做的捷径

- 不把高质量采样等同于专业演奏系统。
- 不通过增加 prompt 或更大模型掩盖缺失的 MIDI / 时钟 /谱面事实。
- 不把 staff、音区或颜色当作确定手别。
- 不把麦克风置信度低解释成用户弹错。
- 不用相邻半音容差伪装修复空间追踪误差。
- 不从 UI highlight 反推规范声音。
- 不把 AI duet 输出用作乐谱参考示范。
- 不为尚未进入目标曲库的每一种 MusicXML 符号预建抽象。
- 不在没有真机与钢琴家验证时写“专业级已通过”。

## 专业验收体系

### 1. MusicXML golden corpus

当前有 189 个 Swift 测试文件，其中 MusicXML 27 个、Practice 69 个；但 `HappyPianistAVPTests/Fixtures` 中真实 XML / MusicXML fixture 只有 6 份。大量 inline XML 单元测试能保护局部逻辑，却不足以证明真实作品导入正确。

最小 corpus 应包含：

- MuseScore、Dorico、Sibelius、Finale 的真实导出。
- 单 part 双谱表与分离双 part 钢琴。
- 非钢琴的一 G 一 F 双 part 反例。
- cross-staff、双手交叉、三谱表、多 voice、同音重叠。
- ties、repeated notes、grace previous/following/make-time。
- 独立和跨谱表 arpeggio。
- additive meter、pickup、cadenza、transpose、octave shift。
- dynamics decimal、复合 dynamics、wedge、niente。
- half pedal、change pedal、sostenuto、una corda。
- repeat、ending、D.C.、D.S.、Coda 与 range seek。

每个 fixture 至少验证：

1. source-note identity 与 written pitch。
2. normalized score dump。
3. performed order。
4. note / controller event dump。
5. practice projection。
6. unsupported semantic report。

### 2. 参考演奏事件验收

同一 score plan 应生成稳定、可人工审查的：

- source-note ID
- on/off tick 与 seconds
- MIDI pitch 与 written pitch
- velocity 与来源
- tempo curve
- CC64 / 66 / 67 value
- structure occurrence
- approximation flags

本地 sampler 和外部 MIDI 可有实现差异，但音乐事件语义必须等价。

### 3. 输入重放与混淆矩阵

对 MIDI、麦克风和手部分别测试，不能混成一个总准确率。

至少记录：

- true / false note onset
- missed onset
- wrong-key confusion
- chord completeness
- onset spread error
- release detection
- low-confidence / unknown rate
- hand / finger identity accuracy（仅手部）
- latency distribution

### 4. 真机声音与时序验收

指定 Vision Pro 型号、OS、音频 route、采样资源、蓝牙 MIDI 设备和外部音源。测量：

- local event-to-audio latency p50 / p95 / p99
- hand-motion-to-audio latency
- external MIDI scheduling jitter
- 10–20 Hz 重复音漏触发与重触发行为
- 8–10 音密集和弦 onset spread
- sustain release 与 stop 后卡音
- route change / interruption 恢复
- 长时间练习的 CPU、内存与音频 glitch

阈值应在首轮基线后由工程与钢琴体验共同批准，并成为回归门；不得临时凭主观感觉改变。

### 5. 钢琴家盲听与演奏测试

至少覆盖不同音乐问题：

- Bach：复调、发音和声部独立。
- Mozart / Haydn：均衡、装饰音、清晰 articulation。
- Beethoven：结构、重音、速度关系。
- Chopin：rubato、旋律突出、伴奏层次和踏板。
- Debussy / Ravel：色彩、和声换踏与连续动态。
- Liszt / Rachmaninoff：密集织体、跨谱表、重复音和大和弦。
- 当代作品：复杂节拍、特殊记谱与音区。

比较至少三种版本：

1. 当前机械默认。
2. 改造后的 score performance。
3. 钢琴家或人工整理的 reference MIDI / audio。

评审维度：谱面忠实度、节奏自然度、动态层次、voicing、articulation、pedal、乐句、整体可信度。关键结论不能只依赖单一评审。

### 6. 演奏评分有效性

专业评分上线前必须回答：

- 同一演奏重复输入，结果是否稳定。
- 同一错误由不同设备采集，结论是否一致或明确说明不可比。
- 系统指标与钢琴教师标注的一致性如何。
- 两位教师意见不一致时，系统是否把解释性差异误判为错误。
- 初学者、进阶者和专业者是否使用不同 tolerance profile。
- 用户能否从分数追溯到具体小节、音符和原始证据。

### 7. 教学有效性

“建议听起来像老师”不等于有效。对每类指导做前后测：

```text
识别问题
-> 给出练法
-> 固定时间练习
-> 重测同一 metric
-> 检查迁移到正常速度与更长段落
```

只有改善目标指标且不制造新问题的建议，才能进入正式 coaching policy。

## 专业完成定义

只有同时满足以下条件，产品才可以逐步使用更强的专业措辞：

### “乐谱忠实示范”

- golden corpus 的谱面与事件 dump 通过。
- performance plan 是声音唯一真源。
- 书写顺序和演奏顺序明确。
- unsupported 语义不会静默丢失。
- 多名钢琴家盲听确认关键风格没有系统性错误。

### “MIDI 演奏评价”

- 完整 MIDI observation 与 score alignment 可追溯。
- timing、duration、velocity、pedal 等指标有定义和单位。
- unavailable / uncertain 不计为错误。
- 与专家标注的一致性达到预先批准门槛。
- UI 不把解释差异包装成绝对对错。

### “虚拟琴具有表现力”

- 每音 velocity 可控且经校准。
- 重复音、和弦与 release 稳定。
- 延迟和 jitter 有真机证据。
- 踏板能力与产品承诺一致。
- 优质采样的动态层能被真实触发。

### “专业虚拟指导”

- 每条建议都来自可观察指标。
- 手别、指法和姿势建议有明确证据来源。
- 低置信度返回未知。
- 教师审查和用户前后测证明建议有效。
- 不以开放式大模型文本替代测量与规则。

## 当前优先级总表

| 优先级 | 必须先解决 |
| --- | --- |
| P0 | 规范 dynamics、direction offset、两-part normalization、staff/hand、grace、规范演奏计划、MIDI 数据保留、输入能力/时钟、palm 触键、相邻半音容差、score alignment 边界、产品宣称 |
| P1 | arpeggio、source-note identity、written pitch、动态优先级、同音声部、seek state、fermata、连续踏板、CoreMIDI timestamp、音频恢复、记谱 written/performed 分离、录制证据 |
| P2 | 更广装饰语义、风格 profile、教师目标、多种合理解释、AI duet 高级音乐性、专业制谱扩展 |

## 相关实现

### 曲谱与准备

- `HappyPianistAVP/Models/MusicXML/MusicXMLModels.swift`
- `HappyPianistAVP/Models/MusicXML/MusicXMLScore+PartFiltering.swift`
- `HappyPianistAVP/Models/Practice/PracticeModels.swift`
- `HappyPianistAVP/Services/MusicXML/Parser/`
- `HappyPianistAVP/Services/MusicXML/MusicXMLPianoGrandStaffNormalizer.swift`
- `HappyPianistAVP/Services/MusicXML/MusicXMLHandRouter.swift`
- `HappyPianistAVP/Services/MusicXML/MusicXMLVelocityResolver.swift`
- `HappyPianistAVP/Services/MusicXML/MusicXMLNoteSpanBuilder.swift`
- `HappyPianistAVP/Services/MusicXML/MusicXMLTempoMap.swift`
- `HappyPianistAVP/Services/MusicXML/MusicXMLPedalTimeline.swift`
- `HappyPianistAVP/Services/MusicXML/MusicXMLFermataTimeline.swift`
- `HappyPianistAVP/Services/MusicXML/MusicXMLStructureExpander.swift`
- `HappyPianistAVP/Services/PracticeStepBuilder.swift`
- `HappyPianistAVP/Services/Practice/Session/PracticePreparationService.swift`

### 演奏、显示与声音

- `HappyPianistAVP/Services/Practice/Guides/PianoHighlightGuideBuilderService.swift`
- `HappyPianistAVP/Services/Practice/Guides/GrandStaffNotationLayoutService.swift`
- `HappyPianistAVP/Services/Practice/Autoplay/AutoplayPerformanceTimeline.swift`
- `HappyPianistAVP/Services/Audio/PracticeSequencerSequenceBuilder.swift`
- `HappyPianistAVP/Services/Audio/PracticeSequencerPlaybackService.swift`
- `HappyPianistAVP/Services/Audio/CoreMIDIPracticePlaybackService.swift`
- `HappyPianistAVP/Services/Audio/PracticeManualReplaySequenceBuilder.swift`

### 输入、评价与指导

- `HappyPianistAVP/Services/Practice/Input/PracticeMIDIInputService.swift`
- `HappyPianistAVP/Services/AudioRecognition/`
- `HappyPianistAVP/Services/VirtualPiano/KeyContactDetectionService.swift`
- `HappyPianistAVP/Services/HandTracking/RealPianoContactDetectionService.swift`
- `HappyPianistAVP/Services/Practice/Matching/`
- `HappyPianistAVP/Services/Practice/Progress/PracticeAttemptReducer.swift`
- `HappyPianistAVP/Models/Practice/PracticeProgressModels.swift`
- `HappyPianistAVP/Services/Practice/Feedback/`
- `HappyPianistAVP/Services/Recording/RecordingTakeRecorder.swift`
- `HappyPianistAVP/Models/Recording/RecordingModels.swift`
- `HappyPianistAVP/Services/Practice/AI/`

## 规范与研究参考

### 官方规范

- [MusicXML 4.0](https://www.w3.org/2021/06/musicxml40/)
- [MusicXML `<staff>`](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/staff/)
- [MusicXML `<sound>`](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/sound/)
- [MusicXML `<grace>`](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/grace/)
- [MusicXML `<arpeggiate>`](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/arpeggiate/)
- [MusicXML `<pedal>`](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/pedal/)
- [CoreMIDI `MIDIPacket.timeStamp`](https://developer.apple.com/documentation/coremidi/midipacket/1495113-timestamp)

### 可用于方法研究、不能直接当产品真值的数据集

- [ASAP：Aligned Scores and Performances](https://github.com/fosfrancesco/asap-dataset)
- [ATEPP：Automatically Transcribed Expressive Piano Performance](https://zenodo.org/records/6564406)
- [PianoCoRe](https://pianocore.github.io/)

这些数据集可辅助 score-performance alignment、表现力特征和回放研究，但存在自动转录、谱面质量、版权或许可边界。产品验收仍需要自有、可授权、由钢琴家核对的精简 golden set。
