# AI 陪伴需求

我会把 HappyPianist 的 AI 能力从“生成模式”进一步收敛成几种陪伴关系：

- **陪你弹**：用户持续演奏，AI 实时伴奏、补左手、补和声。
- **和你对话**：你弹一句，AI 回一句；这是现在 Aria 最适合的模式。
- **跟着你变**：用户突然加快、减慢、转调、改变力度，AI 跟随，而不是按预生成 MIDI 播完。
- **替你补全**：只弹右手时补左手，只弹旋律时补伴奏，卡住时接下去。
- **陪你练**：AI 根据当前练习段落参与，而不是单纯评判“对/错”；例如故意减弱伴奏、重复某个乐句、陪用户慢速合奏。
- **给你示范**：同一个乐句由 AI 演奏一次，用户再跟弹；甚至展示不同力度、速度、风格的版本。

## 当前产品方向

HappyPianist 的 AI 现阶段优先服务于“陪伴用户弹钢琴”，而不是把“生成一段音乐”本身作为产品。用户首先选择 **我要 AI 做什么**；模型和后端属于实现细节，可以放在高级设置中，但一旦用户明确选择了后端，失败时不得静默切换到其他后端。

这意味着六种陪伴关系不是六个模型，而是六种产品意图。一个模型可以服务多个意图，一个意图也可以由模型、规则、乐谱跟随和实时交互逻辑共同实现。

## 从实时语音交互借鉴什么

GPT Realtime / Live 一类实时语音系统最值得借鉴的不是语音本身，而是持续双向交互的底层机制。OpenAI Realtime、LiveKit Agents、Pipecat 和 TEN 都把 turn detection、interruption、持续流式输入输出和会话状态作为核心问题；Moshi、PersonaPlex 则证明了 full-duplex 交互也可以直接进入模型层。

钢琴场景可以做如下映射：

| 实时语音 | HappyPianist |
| --- | --- |
| 连续音频帧 | 连续 MIDI Note / CC 事件 |
| VAD | 用户当前是否正在演奏、是否仍有 held note / sustain |
| semantic turn detection | 乐句是否趋于结束、用户是否在等待回应、是否仍想继续主导 |
| endpointing | 何时触发一次生成或更新未来演奏窗口 |
| barge-in / interruption | 用户重新演奏后，AI 立即让位、变稀疏或取消未来输出 |
| preemptive generation | 在乐句完全结束前预生成短时间窗，降低响应等待 |
| streaming speech | 边生成边调度 Note / CC，而不是生成完整 MIDI 后再播放 |
| conversation context | 滚动音乐上下文、当前调性/节奏/力度/踏板/乐谱位置 |

音乐与语音有一个关键差异：**音乐允许并且经常需要重叠。** 因此 HappyPianist 不应把“轮到谁”简化为二值 turn。AI 可能需要 support、sparse、yield、silent 等不同参与程度；用户重新演奏时也不一定永远是彻底停止 AI。

## 核心技术需求

### 持续监听，而不是等待完整乐句

AI 必须持续接收用户的 MIDI / 演奏 observation，维护当前 held notes、sustain、最近节奏、力度、音符密度、音高中心和必要的乐谱位置。系统不能要求用户明确“提交一段 MIDI”才开始理解当前演奏。

### 音乐交互判断独立于生成模型

HappyPianist 自己需要拥有 Musical Interaction / Turn-Taking 层，判断当前应该继续听、陪奏、稀疏演奏、回应、补全还是让位。不能把“什么时候弹、什么时候停、该不该覆盖用户”全部交给某一个生成模型。

该层至少需要区分：

- 用户是否正在主动演奏；
- 用户是否可能结束一个乐句；
- 用户是否正在等待 AI；
- AI 是否允许与用户重叠；
- 用户重新主导时，AI 应停止、让位还是降低密度；
- 当前生成结果是否已经因为新的用户输入而过期。

### 真正的增量生成与增量播放

“Streaming”不能只表示网络协议使用 WebSocket。只要模型仍然先生成完整结果、客户端再等全部结果收齐后播放，用户体验仍然是 batch generation。

实时陪伴要求：

- 模型尽可能增量产生 Note / CC；
- 已产生的短窗口可以立即进入调度器；
- 后续生成与当前播放并行；
- 用户输入使结果过期时，可以取消尚未播放的未来事件和仍在运行的生成；
- Note Off、sustain、all-notes-off 等状态必须在取消和切换时保持一致，不能留下挂音。

### 短时间窗与预生成

实时陪伴不应默认生成很长的一整段。交互层应以短时间窗维护未来演奏，并根据用户当前状态持续重算。对真正支持增量推理的模型，可以进一步采用预生成：在用户大概率接近乐句边界时开始计算，但只有在交互策略确认后才提交播放。

### 模型能力声明，而不是模型名称驱动产品

后端需要能够表达自己的能力，例如：

- continuation；
- realtime incremental generation；
- accompaniment；
- track / bar infill；
- score-aware generation；
- expressive timing / velocity / pedal；
- style / density / polyphony control。

产品模式依据能力选择可用实现，而不是在 UI 中把 Aria / MIDI-GPT / Performance RNN 直接等同于用户功能。

### 自由演奏与有谱练习必须区分

自由即兴主要依赖滚动音乐上下文；有谱练习还拥有 MusicXML、当前小节、目标声部和 score position。后者应该利用这些额外事实做跟随、补全和示范，而不是把所有场景退化成“给最近几秒 MIDI 做 continuation”。

用户演奏、AI 输出和系统示范必须继续保持 provenance 隔离；AI/system playback 不能反向成为用户演奏 observation，也不能污染 assessment 和 progress。

## 现有开源方案与可借鉴部分

### 实时对话基础设施

- **LiveKit Agents**：开源 realtime agent framework，已经把 turn detection、interruption、preemptive generation 和实时媒体流做成明确的会话机制。适合借鉴 session / turn / interruption 设计，不需要把 WebRTC/语音栈直接引入 HappyPianist。
- **Pipecat**：以 frame pipeline 组织实时多模态数据，turn start/stop 与 interruption 都是可以在 pipeline 中传播的事件。适合参考 MIDI event pipeline、取消传播和 processor 边界。
- **TEN Framework**：实时多模态 conversational AI 框架，包含 VAD、Turn Detection 和可组合扩展。适合参考模块化实时 pipeline。
- **Moshi / PersonaPlex**：开源 full-duplex speech-to-speech 模型。它们不能直接用于 MIDI，但说明“持续接收对方输入，同时持续产生自己的输出”可以是模型原生能力，而不必永远采用完整 turn 的 request/response。

### 音乐交互系统

- **Somax2**：IRCAM 的实时 co-improvisation 系统，持续监听外部 MIDI/音频，根据外部音乐上下文调整生成，并支持多 agent 和不同 interaction strategy。它最值得参考的是“AI 是一个会听、会反应的乐器/搭档”，而不是某个具体生成模型。Somax2 依赖 Max/Python 且采用 GPL-3.0，现阶段更适合作为交互设计与系统架构参考，而不是直接成为 HappyPianist 运行依赖。
- **ACCompanion**：针对钢琴演奏的 symbolic accompaniment system，包含实时 score following、预测、表现性伴奏生成以及对人类演奏表达变化的在线适应。它与“陪你弹”“跟着你变”最直接相关。
- **Magenta A.I. Duet / Performance RNN**：早期实时 AI piano interaction 的重要参考。Performance RNN 直接建模 note-on/off、time shift 和 velocity；适合作为轻量实时 baseline，但不是当前主力大模型方向。

### 音乐生成模型

- **Aria**：当前最适合“和你对话 / 接着弹”的主力模型。官方仓库本身就提供 real-time interactive piano-continuation demo，并针对表现性 solo-piano MIDI 训练。HappyPianist 已经接入 Aria，但还没有充分利用上游真正的实时生成方式。
- **MIDI-GPT**：适合“替你补全”。它支持 track/bar infill、多个音乐属性控制，并提供按 bar 触发的实时 OSC server。它更适合补左手、补声部、补小节和受约束生成，而不是取代 Aria 做所有连续钢琴交互。
- **Anticipatory Music Transformer**：专门处理 infilling 和 accompaniment 等“已知未来约束”的生成任务，适合作为伴奏与补全方向的候选研究模型。

## 六种需求真正依赖的能力

| 产品需求 | 核心能力 | 当前最相关的参考 |
| --- | --- | --- |
| **陪你弹** | 持续监听、允许重叠、实时 accompaniment、低延迟增量输出 | ACCompanion、Somax2、Anticipatory；Aria realtime 可继续验证 |
| **和你对话** | musical turn detection、continuation、快速回应、barge-in | Aria + HappyPianist Companion Policy |
| **跟着你变** | tempo/beat tracking、score following、力度/密度适应、overlap policy | ACCompanion、Somax2；生成模型只是执行者 |
| **替你补全** | track/bar infill、声部约束、和声/密度等控制 | MIDI-GPT、Anticipatory |
| **陪你练** | 当前练习上下文、assessment/coaching、难度与陪奏策略 | HappyPianist 现有练习系统为主，生成模型为辅 |
| **给你示范** | score-aware playback、表现性演奏、可控变体 | 现有 ScorePerformancePlan / playback 为基础，必要时再使用生成模型 |

因此，音乐大模型不是六种需求共同的唯一核心。**真正共同的核心是持续理解当前演奏状态，并把不同生成、跟随、播放能力组织成一个自然的陪伴过程。**

## 技术方向

当前更合理的路线不是先训练一个 HappyPianist 自己的万能音乐大模型，而是：**使用现有模型负责音乐生成，HappyPianist 自己负责实时陪伴逻辑。**

概念边界：

用户 MIDI / 当前乐谱 → Observation Stream → Musical Interaction Analyzer → Companion Policy → Capability-based Model Adapter → Incremental MIDI Event Stream → Playback Scheduler

其中 Companion Policy 决定继续听、support、sparse、yield、respond、complete 或 demonstrate；Model Adapter 再选择 Aria、MIDI-GPT、Anticipatory Music Transformer、Performance RNN 或后续模型承担具体生成能力。

这层 Companion Policy 才是 HappyPianist 自己需要长期掌握的核心产品能力。模型负责“弹什么”，系统负责“什么时候弹、为什么弹、弹多少、什么时候让开，以及用户改变以后如何立即跟着变”。

只有在现有模型经过真实接入和测试后，明确证明某个关键陪伴能力无法达到要求，才考虑微调或训练专门模型。现阶段没有必要从头训练一个新的通用音乐模型。

## 与当前实现的差距

当前代码已经有正确方向上的基础：

- DuetPhraseBuffer 持续保留滚动音乐上下文，而不是等待固定 phrase flush；
- DuetTurnTakingCore 已经根据 held notes、sustain、IOI、力度趋势、音符密度和最近活动在 support / sparse / yield / silent 之间决策；
- AIPerformanceService 以约 100 ms control tick 持续重新评估；
- 用户新输入会使旧 generation 失效，并让 playback queue 清理过期的未来窗口。

但目前仍有几个本质缺口：

1. **Aria WebSocket 目前不是真正的模型流式生成。** Python server 先调用 sample_batch 完整生成，再把完整结果切成多个 WebSocket chunk；AVP 的 WebSocket backend 又先收齐所有 chunk，最后才构建完整 schedule。网络叫 streaming，但 time-to-first-note 仍然包含完整生成时间。
2. **现有 backend contract 仍然是完整 request → 完整 CreativeDuetResponse。** 这个契约天然不适合长期 full-duplex incremental interaction。
3. **当前 turn-taking 主要依据低层统计特征。** 还没有把 tempo/beat、乐句闭合、和声、cadence、score position 等更接近音乐语义的信号纳入统一判断。
4. **当前能力仍以 backend kind 组织。** 还没有一层明确的 capability contract 来表达 continuation、accompaniment、infill、score-aware、incremental streaming 等差异。
5. **“陪你弹 / 跟着你变”不只是生成问题。** 需要 score following、tempo adaptation、overlap policy 与低延迟 playback 共同参与，单独换一个更大的模型无法解决。

在写 feature plan 之前，需要继续验证：现有 Aria realtime 路径能做到什么、MIDI-GPT / Anticipatory / ACCompanion / Somax2 分别能提供什么，以及 Musical Interaction Analyzer 应该观察哪些音乐事实。这里先记录需求与技术方向，不拆实现 task。

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
