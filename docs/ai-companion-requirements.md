# AI 陪伴需求

我会把 HappyPianist 的 AI 能力从“生成模式”进一步收敛成几种陪伴关系：

- **陪你弹**：用户持续演奏，AI 实时伴奏、补左手、补和声。
- **和你对话**：你弹一句，AI 回一句；这是现在 Aria 最适合的模式。
- **跟着你变**：用户突然加快、减慢、转调、改变力度，AI 跟随，而不是按预生成 MIDI 播完。
- **替你补全**：只弹右手时补左手，只弹旋律时补伴奏，卡住时接下去。
- **陪你练**：AI 根据当前练习段落参与，而不是单纯评判“对/错”；例如故意减弱伴奏、重复某个乐句、陪用户慢速合奏。
- **给你示范**：同一个乐句由 AI 演奏一次，用户再跟弹；甚至展示不同力度、速度、风格的版本。

## 产品方向

HappyPianist 的 AI 现阶段优先服务于“陪伴用户弹钢琴”，而不是把“生成一段音乐”本身作为产品。

用户选择的是“我要 AI 做什么”，而不是“我要使用哪个模型”。模型和后端属于实现细节，可以放在高级设置中；一旦用户明确选择了后端，失败时不得静默切换到其他后端。

这六种需求不是六个模型，也不应该分别做成六套互不相干的系统。更合理的方式是：**六种需求共享一个实时陪伴底座，再根据具体需求调用最合适的模型、规则、乐谱跟随或练习能力。**

## 六个需求分别怎么解决

| 需求 | HappyPianist 自己负责 | 可以直接复用的能力 |
| --- | --- | --- |
| **陪你弹** | 持续监听用户、判断什么时候加入或让位、跟随速度与力度、控制双方重叠 | 实时伴奏模型；ACCompanion、Anticipatory Music Transformer；继续验证 Aria 的实时能力 |
| **和你对话** | 判断一个乐句什么时候趋于结束、什么时候该回应、用户重新弹奏时立即让位 | Aria 负责根据最近演奏生成回应 |
| **跟着你变** | 节拍与速度跟踪、乐谱位置跟踪、力度与密度变化判断、实时调整 AI 参与程度 | 主要依赖跟随算法和伴奏系统，生成模型只是执行者 |
| **替你补全** | 明确要补左手、右手、和声、某几个小节还是继续往后弹，并把约束交给模型 | MIDI-GPT、Anticipatory Music Transformer 等补全模型 |
| **陪你练** | 使用现有练习、评估、指导、复测和乐谱上下文决定 AI 应如何陪练 | 现有 HappyPianist 练习系统为主，生成模型只负责需要实际演奏的部分 |
| **给你示范** | 根据当前乐谱和练习目标决定示范范围、速度、手别和表现方式 | 现有乐谱播放与示范能力为基础，需要变奏时再调用生成模型 |

因此，真正要解决的不是“找一个足够强的音乐大模型”，而是建立一个稳定的实时陪伴底座。

## 共同的实时陪伴底座

### 1. 持续理解用户正在弹什么

系统持续接收 MIDI、踏板和其他演奏输入，而不是等用户弹完一整段才开始处理。

至少持续维护：

- 当前按住的音符；
- 延音踏板状态；
- 最近速度与节拍；
- 音符密度；
- 力度及其变化；
- 当前音高范围和可能的和声信息；
- 用户最近是否仍在主动演奏；
- 有谱练习时的当前小节、拍点和乐谱位置。

这一层只负责形成“现在发生了什么”的实时状态，不负责生成音乐。

### 2. 决定 AI 现在应该做什么

HappyPianist 自己需要掌握这一层。

系统根据当前演奏状态判断：

- 继续听，不参与；
- 轻量陪奏；
- 稀疏陪奏，给用户留空间；
- 主动让位；
- 回应用户刚才的乐句；
- 补左手、和声或其他缺失部分；
- 进入示范；
- 取消已经过时的 AI 输出。

音乐和语音最大的区别是：音乐允许双方同时演奏，所以不能简单地只判断“现在轮到谁”。AI 应该存在不同参与程度，而不是只有“说话 / 不说话”两种状态。

### 3. 把任务交给合适的能力后端

陪伴决策确定“现在需要做什么”以后，再选择具有相应能力的后端。

后端需要声明自己支持什么，例如：

- 续奏；
- 实时增量生成；
- 伴奏；
- 左右手或声部补全；
- 小节补全；
- 根据乐谱生成；
- 力度、时值和踏板表现；
- 风格、密度、复调数量等控制。

目前可以这样理解：

- **Aria**：优先承担“和你对话、接着弹”；
- **MIDI-GPT**：优先承担“替你补全、补声部、补小节”；
- **Anticipatory Music Transformer**：重点研究“伴奏和受约束补全”；
- **Performance RNN**：保留为轻量实时基线；
- **规则系统**：承担不需要大模型的简单实时行为；
- **HappyPianist 自己的练习系统**：承担陪练和示范中大量非生成任务。

模型负责“弹什么”，HappyPianist 负责“为什么现在要弹、什么时候开始、什么时候停止、弹多少，以及用户改变以后怎么跟着变”。

### 4. 真正做到边生成边播放

实时陪伴不能只是把完整 MIDI 生成完，再一次性播放。

理想状态是：

- 后端逐步产生未来几百毫秒到几秒的音符和控制事件；
- 已经产生的短时间窗立即进入播放调度；
- 后续生成与当前播放同时进行；
- 用户重新演奏后，尚未播放的旧结果立即失效；
- 必要时取消正在进行的生成；
- 取消时正确处理音符释放、延音踏板和全部停止，不能留下挂音。

这才是真正意义上的低延迟实时陪伴。

## 六种模式的具体形态

### 陪你弹

这是最接近“真人钢琴搭档”的模式。

用户可以一直演奏，不需要停下来等待 AI。AI 根据用户当前速度、节拍、力度、音域和演奏密度实时决定是否加入。

它的核心不是续写一段 MIDI，而是：

- 持续监听；
- 实时伴奏；
- 允许双方重叠；
- 用户变快时 AI 跟着变快；
- 用户突然变强或变弱时 AI 调整力度；
- 用户演奏很密集时 AI 自动减少参与；
- 用户重新主导时 AI 主动让位。

这部分应重点参考 ACCompanion 和 Somax2，而不是单纯依靠 Aria。

### 和你对话

这是目前 Aria 最适合的模式。

基本过程是：

用户演奏 → HappyPianist 判断乐句趋于结束 → Aria 根据最近演奏生成回应 → AI 开始演奏 → 用户重新开始后 AI 立即让位或降低参与。

这里要借鉴实时语音系统的不是语音模型，而是：

- 什么时候认为用户快说完了；
- 能否提前准备回应；
- 用户重新开口后如何打断 AI；
- 如何持续保存上下文。

映射到钢琴，就是乐句边界判断、提前生成、重新演奏后的打断，以及滚动音乐上下文。

### 跟着你变

这一模式首先是“跟随问题”，其次才是“生成问题”。

系统需要实时理解：

- 当前速度；
- 当前拍点；
- 用户是否加速或减速；
- 当前力度；
- 当前乐谱位置；
- 用户是否提前、拖后或跳到了其他小节。

有谱练习时，应充分利用 MusicXML 和当前练习位置；自由演奏时，再依赖最近 MIDI 推测节奏、和声和演奏趋势。

因此单独换一个更大的音乐模型解决不了这个需求。

### 替你补全

这是一个受约束的音乐生成问题。

用户可以明确要求：

- 只补左手；
- 只补右手；
- 给旋律补伴奏；
- 给某几个小节补内容；
- 从卡住的位置接着弹；
- 保留已有内容，只改指定部分。

MIDI-GPT 和 Anticipatory Music Transformer 比 Aria 更适合这一类任务，因为它们更强调补全和条件约束。

### 陪你练

这一模式不应重新发明一套 AI 系统。

HappyPianist 已经拥有练习、演奏观察、评估、指导和复测等能力。AI 陪练应该建立在这些事实之上，例如：

- 用户一直在某个小节失败，AI 降低伴奏密度；
- 用户正在慢速练习，AI 跟随当前速度；
- 用户只练右手，AI 陪左手；
- 用户需要重复某个乐句，AI 一起重复；
- 用户卡住时，AI 示范或接一句，而不是直接判错。

因此这里真正重要的是把“练习系统”和“实时陪伴底座”连接起来。

### 给你示范

很多情况下根本不需要音乐大模型。

如果用户正在练一份已有 MusicXML，HappyPianist 已经知道正确的音符、节奏和结构，首先应该使用确定性的乐谱播放与示范。

只有用户要求：

- 换一种表现方式；
- 生成不同力度或速度的版本；
- 做自由变奏；
- 给出另一种伴奏；

才需要调用生成模型。

## 从实时语音系统借鉴什么

GPT Realtime / Live、LiveKit Agents、Pipecat、TEN 等系统值得借鉴的是实时交互机制，而不是语音处理本身。

| 实时语音里的问题 | 钢琴里的对应问题 |
| --- | --- |
| 连续音频输入 | 连续 MIDI 和踏板事件 |
| 语音活动检测 | 用户现在是否仍在演奏 |
| 语义轮次判断 | 当前乐句是否趋于结束、用户是否在等待回应 |
| 终点判断 | 什么时候触发一次回应或更新未来演奏 |
| 抢话和打断 | 用户重新演奏后，AI 是否立刻让位或取消未来输出 |
| 提前生成 | 乐句完全结束前先准备短回应 |
| 流式语音 | 边生成 MIDI 事件边播放 |
| 对话上下文 | 最近演奏、节奏、力度、和声、踏板和乐谱位置 |

Moshi、PersonaPlex 等开源全双工语音模型还说明了一件事：长期来看，模型本身也可以支持“持续听着对方的同时持续输出”。但 HappyPianist 现阶段没有必要先训练这种音乐模型，可以先用现有音乐模型配合自己的实时陪伴底座验证产品体验。

## 值得研究的开源项目

### 实时交互框架

- **LiveKit Agents**：重点参考轮次判断、打断、提前生成和实时会话状态。
- **Pipecat**：重点参考事件流水线和取消传播。
- **TEN Framework**：重点参考实时多模态模块如何组合。
- **Moshi / PersonaPlex**：重点参考全双工模型的交互方式，不直接作为 MIDI 后端。

这些项目不需要直接成为 HappyPianist 的依赖。

### 音乐交互系统

- **Somax2**：实时听取外部 MIDI / 音频并作出音乐回应，重点参考共同即兴和交互策略。
- **ACCompanion**：实时钢琴伴奏、乐谱跟随、预测和表现性适应，与“陪你弹”和“跟着你变”最直接相关。
- **Magenta A.I. Duet / Performance RNN**：早期实时钢琴 AI 交互的重要基线。

### 音乐模型

- **Aria**：当前主要用于续奏和音乐对话。
- **MIDI-GPT**：重点用于声部、小节和局部补全。
- **Anticipatory Music Transformer**：重点研究伴奏和受约束生成。

## 与当前实现的差距

当前 HappyPianist 已经有一部分实时陪伴底座：

- DuetPhraseBuffer 已经持续保留最近演奏，而不是只等待完整乐句；
- CompanionDecisionBackendProtocol 已经成为实时陪伴决策的统一协议；决策后端只输出 listen / support / sparse / yield / respond 五种语义动作，当前 RuleBasedCompanionDecisionBackend 根据按键、踏板、演奏速度、力度趋势和音符密度做确定性判断；
- AIPerformanceService 大约每 100 毫秒重新判断一次；
- 用户产生新输入后，旧的生成结果可以失效，播放队列也会清理过期的未来窗口。

但还存在几个关键缺口：

1. **Aria 的 WebSocket 目前不是真正的流式生成。** 服务端仍然先完整生成，再切成多个网络分块；AVP 端又先收齐全部分块后才播放。因此首次出音仍要等待完整生成。
2. **当前后端接口仍然是假设“一次请求返回一整段结果”。** 以后需要支持逐步返回音符事件。
3. **当前实时判断主要还是低层统计。** 还需要逐步加入节拍、速度、乐句边界、和声、终止式以及有谱练习时的乐谱位置。
4. **现在仍然主要按后端名称组织能力。** 后续应该让后端明确声明自己支持续奏、伴奏、补全、乐谱感知、实时增量等哪些能力。
5. **“陪你弹”和“跟着你变”不能只靠生成模型。** 乐谱跟随、速度适应、重叠控制和低延迟播放同样是核心。

## 实时陪伴决策层的候选方案

“HappyPianist 自己负责实时陪伴”不等于“用代码规则把陪伴行为写死”。这里真正需要的是一个低延迟决策层：持续读取当前演奏状态，然后判断 AI 此刻应该继续听、轻量陪奏、稀疏陪奏、让位、回应、补全还是示范。

目前先保留四条技术路线，不提前确定最终方案。

### 方案一：确定性规则决策后端

当前实现明确命名为 RuleBasedCompanionDecisionBackend。它只是 CompanionDecisionBackendProtocol 的一个实现，根据按键、踏板、音符密度、最近活动等状态做确定性判断。以后本地小模型或专用分类模型通过同一协议接入，上层陪伴流程不需要绑定某一种决策方法。

优点是实现最容易、行为确定、方便调试，也适合作为后续学习型方案的基线。缺点是音乐语义一复杂，就容易堆积阈值；例如同样是短暂停顿，可能只是换手，也可能真的是在等 AI 回应。

因此确定性规则决策后端应继续保留为基线，但不默认它就是最终智能决策方式。

### 方案二：Qwen3.5-0.8B zero-token 决策后端

当前实验后端固定使用 `Qwen/Qwen3.5-0.8B`。模型不生成解释文本，而是只读取候选 token logits；Windows NVIDIA 电脑负责运行模型，visionOS 端通过 Bonjour + `/v1/classifier` 调用。RuleBasedCompanionDecisionBackend 继续作为默认稳定基线，选择 Qwen 后失败显式暴露，不自动回退。

产品不再让模型直接对 `listen / support / sparse / yield / respond` 五分类。统一协议先判断四个二元语义：`continuing / finished / space / reasserted`。每个语义都用固定 A/B 标签问两次，一次 `A=true / B=false`，一次 `A=false / B=true`；按语义标签对齐概率并取平均，降低候选位置偏置。之后统一用 `semantic-v1` 映射得到最终动作，`support / sparse` 只由相同的音符密度阈值区分。

结构化输入只保留按键数、踏板、IOI、力度趋势、最近音符密度、距最近用户事件/按键时间、音高中心和 AI 是否正在播放等汇总状态；不再发送逐音符 `recent_notes`。

#### Qwen3.5-0.8B 统一 Stage A

2026-09-26 在 Windows RTX 4060 上按模型无关的统一 Stage A 重测 120 个固定 case（MAESTRO + POP909，固定 seed / case IDs）。Qwen 的动作分布为：`listen=27 / support=6 / sparse=54 / yield=20 / respond=13`。关键语义里 `continuing`、`settled_end.finished`、`sustain_pause.continuing` 和 `takeover_overlay.reasserted` 已达到固定方向要求；仍失败的主要边界是 `active_dense.space` 与 `active_dense.reasserted`。

统一测试同时验证了 A/B 位置偏置真实存在，因此产品必须保留双顺序对齐。该轮 Windows server latency P95 约 1.10 秒、端到端 P95 约 1.16 秒，仍略高于 benchmark 的 1 秒 Gate；产品请求 timeout 暂设为 1.5 秒，不把提高 timeout 视为 benchmark 通过。

当前已经把 Qwen3.5-0.8B 接成**显式可选的第二个陪伴决策后端**，但默认仍使用 RuleBasedCompanionDecisionBackend，不做任何自动回退。Qwen 独立运行在电脑端本地服务，通过同一 CompanionDecisionBackendProtocol 返回 CompanionAction；音乐生成后端仍独立选择 Aria / CoreML / rule。

#### 历史旧协议验收（仅保留背景）

下面的 600-case / 60-case 结果来自更早的直接动作或旧语义协议，只用于解释问题演进，不再作为当前 Qwen 与其他模型的比较 Gate。当前模型比较一律使用统一二元语义 Stage A。

早期只使用仓库 6 个 Aria 示例 MIDI 的 30-case 测试，后来确认它只能证明协议和服务链路能跑，不能作为音乐语义验收：当时有些状态来自固定百分位或人工覆盖，并不能证明对应 MIDI 在那个时刻天然具有该语义。因此这套 30-case 结论不再作为当前验收依据。

现在改用两个公开语料：

- MAESTRO v3：1276 个真实 Disklavier 钢琴演奏 MIDI，保留真实力度和踏板信息；
- POP909：909 首流行钢琴编曲主 MIDI，用于补足 MAESTRO 偏古典的风格分布。

本地共使用 2185 个主 MIDI；数据目录 python_backend/.datasets/ 已忽略，不进入 Git。

验收分成三层。

##### 1. 建立可观测状态候选池

companion_acceptance_corpus.py 只根据 MIDI 本身的可观测事实找候选，不再要求每首都覆盖所有状态：

- active_dense：前 1 秒至少 8 个 onset，下一 onset ≤200 ms；
- active_sparse：前 1 秒最多 4 个 onset，下一 onset 约 50～550 ms；
- sustain_pause：真实 CC64 ≥64 的停顿；
- natural_silence：无物理按键保持、踏板抬起的长停顿；
- piece_end：真实最终音结束后的曲终边界；
- takeover_overlay：在自然 dense 用户片段上额外设置 AI 正在播放，专门测试用户重新接管；它是明确标记的合成状态，不是单人 MIDI 数据集提供的真值。

索引器对最终采样点再次执行状态不变量校验。当前结果：

- 2185/2185 个 MIDI 解析成功，0 错误；
- active_dense：6255 个候选，覆盖 2129 首；
- active_sparse：6286 个候选，覆盖 2154 首；
- sustain_pause：6147 个候选，覆盖 2072 首；
- natural_silence：1474 个候选，覆盖 692 首；
- piece_end：2185 个候选；
- takeover_overlay：6255 个合成候选，底层用户片段全部来自真实 dense MIDI。

修正候选器以后又做了全量范围检查：active_dense 的最终采样点全部满足密度 ≥8、下一 onset ≤170 ms；active_sparse 全部满足密度 ≤4、下一 onset 约 67～470 ms；sustain_pause 全部真实 CC64 ≥64；natural_silence 全部无按键保持且 CC64 <64。

必须区分可观测状态和语义真值。MAESTRO / POP909 没有 用户在等 AI、AI 应该回应、这次静默只是呼吸 等 turn-taking 人工标签，因此自然静默、踏板停顿、曲终等不能直接映射成唯一正确动作。没有人工标注前，不再报告这部分的准确率。

##### 2. 600 个分层 Qwen 决策样本

从 MAESTRO 与 POP909 中，按 6 种状态分别随机抽取每组 50 个，共 600 个 case，固定抽样 seed 为 20260920。

Qwen3.5-0.8B 的输出分布：

- respond：451；
- sparse：149；
- listen：0；
- support：0；
- yield：0。

决策延迟中位数 135 ms，范围 94～150 ms。两个数据集的趋势一致，所以此前观察到的 respond 偏置不是 6 个示例 MIDI 导致的偶然现象。

分状态看，100 个 piece_end 有 92 个 respond；100 个 natural_silence 有 91 个 respond；100 个真实 sustain_pause 有 61 个 respond。这些数字描述的是模型行为分布，不是准确率。

takeover_overlay 是例外：它的测试语义是明确的——AI 正在播放，同时用户进入自然 dense 演奏，产品预期至少应该具备 yield 能力。但 100 个样本中 yield=0，说明当前零样本 Qwen 明确没有学会这一关键交互行为。

##### 3. 60 个完整 Qwen → Aria → MIDI E2E

再从每个数据源、每种状态各抽 5 个，共 60 个完整 case，真实执行：

MIDI → 演奏状态 → Qwen /decision → Aria CUDA /generate → 输出 MIDI

最终完整运行结果：

- 60/60 次生成尝试成功；
- 60 个输出 MIDI 全部重新解析，Note On / Note Off 数量配平，没有挂音；
- Qwen 动作为 respond=46、sparse=14；
- Qwen 决策延迟中位数 133.5 ms（100～150 ms）；
- Aria 生成延迟中位数 1535.5 ms（1490～1901 ms）；
- 52/60（86.7%）在当前动作对应的 0.45～0.70 秒实时播放窗口内至少有一个可播放音符。

这证明服务级链路已经可以在比原来大得多、风格更分散的真实 MIDI 上运行，但同时暴露两个独立瓶颈：

1. Qwen 决策问题：零样本 0.8B 模型几乎只会 respond / sparse，缺少真正的 listen / support / yield 行为，需要微调或专用决策模型；
2. Aria 实时性问题：约 1.5 秒完成一次 64-token 生成仍明显慢于 0.45～0.70 秒交互窗口；即使最终 MIDI 合法，也不能简单等同于实时陪伴体验已经达标。

Aria 采样具有随机性。中间一次探索运行曾出现单个 case 返回无 NoteEvent；验收器现在会把这种情况记录为单 case 生成失败而不是中止整批测试。最终这次 60-case 完整运行没有生成失败，但后续应增加多次重复运行，而不是只依赖一次采样。

这轮真实验收此前还发现并修复了三类链路问题：决策 schema breaking change 未升协议版本、Swift/Python recent_notes 字段名不一致、Aria 对复杂 MIDI 的 prompt 事件顺序比较过严。当前均已从协议和续奏提取逻辑上修复。

当前 Qwen3.5-0.8B 因此继续保留为实验后端，默认仍是确定性规则决策后端。

visionOS 侧已经完成 Qwen classifier client、统一语义 backend、backend selection 与无静默回退的定向回归；当前相关定向测试 8/8 通过。完整模拟器测试仍包含若干与 Companion 无关的手部动画/本地 sampler 既有失败，因此不能把全套测试描述为全绿。真实 MIDI → Qwen → Aria → 播放链路仍需在当前统一二元协议下重新做产品级 E2E。

### Qwen3.5 微调方向

这条路线可以直接基于现有文本模型继续微调。近期优先尝试监督微调 / LoRA，而不是重新训练模型：

- 输入保持当前 compact structured state，不重新引入逐音符 `recent_notes`；
- 优先训练 `continuing / finished / space / reasserted` 四个语义边界，而不是重新回到直接五分类；
- 训练与推理仍应保留 zero-token / candidate-logit 路径，并继续用统一 `semantic-v1` mapping 生成最终动作；
- 服务启动参数支持任意模型目录，未来替换微调 checkpoint 不需要修改 Swift 协议；
- 可以分别比较 Qwen3.5-0.8B 与 Qwen3.5-0.8B-Base 的任务微调效果。

训练数据不能只用规则后端自动生成标签，否则最终只是把现有规则蒸馏进模型。规则标签可以作为冷启动数据，但必须记录标签来源，并逐步加入真实演奏中的人工校正、用户主动让位/接管等交互事实。

### 方案三：专用音乐交互分类模型

如果 Qwen 这类通用小模型最终证明“会做决策，但不够懂音乐”，可以训练一个专门的音乐交互模型。

它不生成 MIDI，只直接读取最近几秒的 MIDI 与音乐特征，输出例如：用户继续演奏概率、乐句结束概率、用户等待 AI 的概率、AI 应该让位的概率、AI 参与强度和推荐伴奏密度。

它可以直接使用音符按下和释放、力度、延音踏板、音符间隔、节拍、速度、和声、乐句边界、乐谱位置以及 AI 当前输出状态，不必先翻译成自然语言。

这相当于“音乐版语义轮次检测器”。它更可能真正理解音乐，也可能做到更低延迟，但需要可靠训练数据和标签，成本明显更高。

### 方案四：全双工音乐模型

长期可以研究类似 Moshi / PersonaPlex 的思路，让模型同时持续观察用户 MIDI 流和 AI 自己正在输出的 MIDI 流，然后直接预测下一时刻 AI 应该输出什么。

这种模型可能把“什么时候参与”和“具体弹什么”一起学掉，最接近真正的 AI 钢琴搭档。但它需要大量同步的双人演奏、伴奏、共同即兴或师生互动数据，因此不适合作为当前第一步。

## 候选方案之间的关系

这些路线不是互相排斥的。当前顺序是：确定性规则后端保留为基线；Qwen3.5-0.8B 作为唯一实验型网络决策后端继续优化统一二元语义判断；如果通用模型仍无法稳定满足固定 Stage A，再考虑专用音乐交互分类模型；等未来积累足够交互数据以后，再研究全双工音乐模型。

无论最终使用哪一种模型，底层确定性实时系统都必须存在。MIDI 连接、音符释放、延音踏板一致性、取消过期请求、播放调度、缓冲、网络超时和防止挂音等职责不能交给模型。

近期最值得做的低成本验证，是继续让 RuleBasedCompanionDecisionBackend 与 Qwen3.5-0.8B 面对同一批固定钢琴场景，对比延迟、稳定性和语义边界。所有模型都必须复用同一 compact state、二元问题、A/B 双顺序聚合、阈值、mapping、样本和 Gate。

## 当前探索原则

现阶段先不训练 HappyPianist 自己的通用音乐大模型，也不提前决定实时陪伴决策一定由规则或某一种神经网络实现。

共同方向是：

**现有模型优先负责音乐生成，HappyPianist 掌握实时陪伴这一产品层；当前实时陪伴决策由规则基线或 Qwen3.5-0.8B 实验后端实现，后续再根据统一 benchmark 决定是否需要专用音乐分类模型或全双工模型。**

也就是：

用户演奏 / 当前乐谱
→ 实时演奏状态
→ 陪伴决策
→ 选择合适能力
→ 生成或跟随
→ 增量 MIDI 事件
→ 实时播放

只有在真实接入并测试现有方案以后，明确发现某个关键陪伴能力无法达到要求，才考虑微调或训练专门模型。

## 参考项目

- OpenAI Realtime API: https://platform.openai.com/docs/api-reference/realtime
- LiveKit Agents: https://docs.livekit.io/agents/
- Pipecat: https://github.com/pipecat-ai/pipecat
- TEN Framework: https://github.com/TEN-framework/ten-framework
- Moshi: https://github.com/kyutai-labs/moshi
- PersonaPlex: https://github.com/NVIDIA/personaplex
- Somax2: https://github.com/DYCI2/Somax2
- ACCompanion: https://github.com/CPJKU/accompanion
- Aria: https://github.com/EleutherAI/aria
- MIDI-GPT: https://github.com/Metacreation-Lab/MIDI-GPT
- Anticipatory Music Transformer: https://github.com/jthickstun/anticipation
- Magenta / Performance RNN: https://github.com/magenta/magenta
- Kev（Jev 类本地决策模型）: https://github.com/jaredpalmer/kev
- NanoJev: https://github.com/TianyuCodings/NanoJev
- System One Lite: https://github.com/snellingio/system-one
- System One, open: https://github.com/mithalouni/system-one-open
- Qwen3.5-0.8B: https://huggingface.co/Qwen/Qwen3.5-0.8B
- Qwen3.5-0.8B-Base: https://huggingface.co/Qwen/Qwen3.5-0.8B-Base
