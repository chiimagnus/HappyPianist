# Fallbacks Inventory（回退/兜底清单）

本文件用于回答一个问题：当 “理想输入/理想数据链路” 缺失时，`LonelyPianistAVP` 会用哪些 **fallback（兜底/回退）** 继续让功能可用？  

> 口径：这里的 fallback 指“在关键数据为空/缺失时，代码主动选择一个替代行为继续运行”，可能导致播放/高亮/识别效果偏离 MusicXML 的真实语义。

---

## 给非技术同学的先读说明（白话版）

你可以把整个系统想成三层：

1. **MusicXML（谱面）**：像“电子谱”，里面有小节、音符、时值、速度变化（快慢）、表情记号（踏板、延长、渐强等）。
2. **App 内部的时间线**：为了能“自动播放/高亮”，我们会把谱面翻译成一条时间轴：什么时候按下哪个键（noteOn），什么时候松开（noteOff），什么时候踩/放踏板等。
3. **UI 高亮（Guide）**：屏幕上/键盘上的高亮提示，本质是“在某个时刻亮起、在某个时刻熄灭”的指令集合。

所谓 **fallback（兜底/回退）**：当我们“理想的那条数据”缺失时（比如某些 guide 没传进来、某些 tempo 没解析到），为了保证“至少还能播放/还能高亮/不崩溃”，代码会用一个“替代规则”把系统跑起来。

这类替代规则通常有一个共同特点：
- **可用性更重要**：先让功能还能用；
- **还原度可能变差**：播放听感、高亮时序可能不再 100% 贴谱面。

### 本文里常见词的白话解释

- **step**：App 为了练习/引导而人为切分出来的“步骤”。它不等同于小节，也不等同于真实演奏时间，只是一个“导航点”。
- **tick**：谱面内部的时间单位。你可以把它理解为“谱面里的刻度”，不是秒。tick 需要结合 tempo（BPM）才能换算成秒。
- **span（音符跨度）**：一个音符“从按下到松开”的真实持续范围（start tick → end tick）。
- **guide（高亮引导）**：屏幕/键盘高亮用的数据。里面最关键的是：什么时候亮（onTick），什么时候灭（offTick）。
- **tempoMap（速度表）**：谱面里“速度变化”的集合。如果 tempoMap 缺失，系统只能用一个默认速度一直走。

### 快速定位：你最关心哪一类？

- 如果你关心 **自动播放听起来快慢不对/踏板不对/音符松开不对**：优先看「1) 练习高亮（Guide）」和「2) Autoplay」。
- 如果你关心 **谱怎么解析出来的**：看「3) MusicXML 解析/解释」。
- 如果你关心 **音频识别（Step3）为什么会降级**：看「4) 音频识别相关」。

---

## 策略 A（宁可播不出来也不要播错）：哪些 fallback 应该“消灭”

你刚才说的 “应该消灭的兜底（内部链路缺数据）”，意思是：**这些数据本来就应该由 App 自己构建并传入**，一旦缺失，就代表我们已经无法保证“按 MusicXML 还原”，所以不应该继续靠兜底硬播，而应该：

- 自动播放直接禁用/报错（说人话的提示）；
- 让问题尽早暴露给开发者（而不是被“看似还能播”的兜底掩盖）。

对应到本文件的条目，优先级从高到低建议如下：

### ✅ 已完全消灭（实现代码已删除，不存在“暗中兜底继续播”分支）

- **F-Guide-01 / F-Autoplay-01 / F-Autoplay-03 / F-Guide-04 / F-Audio-01**
  - 现在的统一行为：**自动播放不启动 + 弹出“无法自动播放”提示（说人话）**。

- **F-Guide-01：`highlightGuides` 为空时，使用 fallback guides**  
  这是“内部链路缺关键数据”的典型。guide 为空时继续播，会直接改掉 noteOff / 踏板交互的时序语义，属于“看起来能播，实际上播错”。
  - UI 提示（示例文案）：`无法自动播放：缺少键盘高亮引导数据。请重新导入这份 MusicXML。`

- **F-Autoplay-01：`tempoMap` 缺失时，使用默认 tempo（120 BPM）**  
  tempoMap 是 tick→秒的核心。缺失时继续播，必然把原谱的快慢变化抹平，属于“看起来能播，实际上速度语义不再是原谱”。
  - UI 提示（示例文案）：`无法自动播放：缺少速度信息（tempo）。请重新导入这份 MusicXML。`

- **F-Autoplay-03：pedal / fermata timeline 缺失时的行为降级**  
  如果谱面本来就没有 pedal/fermata，这不是问题；但如果谱面有而 timeline 却是 nil，那就是内部链路丢了表达信息。策略 A 下应该“要么能还原（有 timeline），要么明确提示缺失并禁用对应还原能力”，而不是静默不做表情。
  - UI 提示（示例文案）：  
    - `无法自动播放：缺少踏板信息。请重新导入这份 MusicXML。`  
    - `无法自动播放：缺少延长停顿（fermata）信息。请重新导入这份 MusicXML。`

- **F-Guide-04：按 stepIndex 找不到 trigger guide 时的“定位 fallback”**  
  这条属于“导航/状态机兜底”。策略 A 下更推荐：出现这种不一致就直接提示（例如“引导数据不一致，无法定位当前 step 的高亮起点”），避免悄悄跳到附近的音造成误导。
  - UI 提示（示例文案）：`无法自动播放：引导数据不一致（找不到当前步骤的触发点）。请重新导入这份 MusicXML。`

- **F-Audio-01：`noteOutput` 未显式注入时，尝试从 `noteAudioPlayer` 推断**  
  这条不一定会“播错”，但会掩盖依赖注入/组装遗漏。策略 A 下更推荐：自动播放的播放后端必须显式可用（初始化失败就直接报错），而不是“猜一个出来继续跑”。
  - UI 提示（示例文案）：`无法自动播放：音频服务初始化失败。`

### ⚠️ 不算“内部链路缺数据”，一般不建议消灭

- **F-Guide-02 / F-Guide-03**：它们更多是在“谱面结构很复杂/导出差异大”时的对齐兜底。完全消灭会让很多谱直接无法高亮或无法生成完整 guide。  
  策略 A 下更合理的做法通常是：**保留构建兜底，但如果兜底比例过高或影响到演奏时序可信度，就禁用自动播放并提示**（而不是继续播放）。

---

## 1) 练习高亮（Guide）相关

### F-Guide-01：`highlightGuides` 为空时，使用 fallback guides

- 状态：**已完全消灭（策略 A）**。对应的 fallback 生成逻辑已删除，不存在“缺 guide 继续播放”的兜底分支。
- 现在的行为（用户视角）：
  - 自动播放不会启动；
  - 会弹出提示：`无法自动播放：缺少键盘高亮引导数据。请重新导入这份 MusicXML。`
- 以前为什么会有它（历史原因）：没有 guide 时，系统会临时用 step 去“猜”音符何时灭（offTick），但这会悄悄改变 noteOff / 踏板语义，导致“看起来能播，实际上播错”。

### F-Guide-02：Guide builder 的“source note”匹配失败兜底

- 白话解释：我们在构建 guide 时，会尝试把“step 里的某个音符”对应回“谱面里真正的那颗音符事件”。如果第一次对不上，就退一步用更粗的方式再找一次。
- 你会感知到什么：通常不容易直接看出来，但在复杂谱面（同一键很密、装饰音多、跨声部）时，高亮起止可能更“贴 step 而不是贴真实音符”。
- 为什么要有它：谱面导出千差万别，严格对齐可能失败；fallback 是为了避免“某些音完全没有 guide”。
- 工程触发条件（给工程师核对用）：按 `baseOnTick` 找不到 `MusicXMLNoteEvent`，回退按 `step.tick` 再找。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Services/Practice/PianoHighlightGuideBuilderService.swift`

### F-Guide-03：Guide builder 的 span 对齐失败兜底

- 白话解释：理想情况下，每个高亮音符都应该严格照着谱面的 span 来“何时亮、何时灭”。如果 span 对不上，我们就只能用一些“合理猜测”的规则生成一个 span。
- 你会感知到什么：
  - 某些音符高亮的持续时间可能偏短或偏长；
  - 极端情况下（连 duration 都拿不到），会变成“几乎一闪而过”。
- 为什么要有它：如果没有这个兜底，span 对不上就会导致该音符完全没有 offTick，容易出现 stuck（不灭/不松开）或直接漏高亮。
- 工程触发条件（给工程师核对用）：`spanByKey` miss。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Services/Practice/PianoHighlightGuideBuilderService.swift`

### F-Guide-04：按 stepIndex 找不到 trigger guide 时的“定位 fallback”

白话解释：当你点“下一步/跳转到某个 step”时，系统需要找到“从哪里开始高亮”。理想情况下它能找到“这个 step 专属的 trigger（触发点）guide”。如果找不到，就用更宽松的规则去找一个“最接近、能用的起点”。

- 状态：**已完全消灭（策略 A）**。不再做“就近定位”的回退分支；找不到 trigger 会直接失败并提示。
- 现在的行为（用户视角）：
  - 自动播放不会启动；
  - 会弹出提示：`无法自动播放：引导数据不一致（找不到当前步骤的触发点）。请重新导入这份 MusicXML。`
- 工程位置（给工程师核对用）：`LonelyPianistAVP/ViewModels/PracticeSessionViewModel.swift`

---

## 2) Autoplay（自动播放）时间轴相关

### F-Autoplay-01：`tempoMap` 缺失时，使用默认 tempo（120 BPM）

- 状态：**已完全消灭（策略 A）**。不再允许 tempoMap 缺失时继续播放（不存在“默认 120 BPM 继续播”的兜底分支）。
- 现在的行为（用户视角）：
  - 自动播放不会启动；
  - 会弹出提示：`无法自动播放：缺少速度信息（tempo）。请重新导入这份 MusicXML。`
- 备注：这条只针对 **tempoMap 缺失（内部链路没传/没构建）**。如果谱面本身没有写任何 tempo 事件，`MusicXMLTempoMap` 仍会使用其内部默认 BPM 以保证 tick→秒可计算（这属于“谱面缺语义时的行业约定”，不是内部链路丢数据）。

### F-Autoplay-02：`MusicXMLTempoMap` 在 tick=0 缺少 tempo 时的兜底

- 白话解释：就算有 tempo 事件，如果它们没有从“开头（tick=0）”开始，我们也要给开头补一个速度，不然时间轴没法从 0 开始算。
- 你会感知到什么：多数情况下你感知不到；但在“谱面开头没有写速度记号”的文件里，这条兜底决定了开头的默认速度。
- 为什么要有它：避免时间轴在起点没有速度导致计算失败。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Services/MusicXML/MusicXMLTempoMap.swift`

### F-Autoplay-03：pedal / fermata timeline 缺失时的行为降级

- 状态：**已完全消灭（策略 A）**。不再允许 pedal/fermata timeline 缺失时静默降级（缺失直接失败并提示）。
- 现在的行为（用户视角）：
  - 自动播放不会启动；
  - 会弹出提示（按缺失项）：
    - `无法自动播放：缺少踏板信息。请重新导入这份 MusicXML。`
    - `无法自动播放：缺少延长停顿（fermata）信息。请重新导入这份 MusicXML。`
- 工程位置（给工程师核对用）：`LonelyPianistAVP/ViewModels/PracticeSessionViewModel.swift`

---

## 3) MusicXML 解析/解释相关（常见兜底）

### F-Parse-01：`divisions` 缺失或非法时，按 1 处理

- 白话解释：MusicXML 里有一个基础换算单位 divisions，用来把“音符时值”换成 tick。如果这个值缺失或是 0，我们就假设它是 1。
- 你会感知到什么：在极端坏谱面里，节奏/时值可能整体不准，但至少不至于完全解析失败。
- 为什么要有它：这是“坏数据也尽量能读”的兜底。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Services/MusicXML/Parser/MusicXMLParserDelegate+Timing.swift`

### F-Score-01：优先 part（P1）不存在时的主声部选择兜底

- 白话解释：有些谱不是 P1/P2 这种命名，或者把钢琴分在别的 part。我们会尝试找到“最像主声部”的 part 来练习/播放。
- 你会感知到什么：可能会播放了“你以为是伴奏/左手”的那条，或者反过来；总之播放的轨道不符合直觉。
- 为什么要有它：避免因为谱面 partID 不标准而完全没法播放。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Models/MusicXML/MusicXMLScore+PartFiltering.swift`

### F-Expr-01：fermata 没有可用 note duration 时，按 quarter 估算

- 白话解释：fermata 表示“这里要停/延长”。如果我们找不到“该停多久”的可靠依据，就用“一个四分音符长度”来估算。
- 你会感知到什么：fermata 的停顿可能太短/太长，但至少会有个“停一下”的效果。
- 为什么要有它：避免 fermata 完全失效或时间轴计算中断。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Services/MusicXML/MusicXMLFermataTimeline.swift`

### F-Expr-02：力度（velocity）缺失时回退到默认力度

- 白话解释：如果谱面没有明确的强弱记号（或我们没解析到），就用一个“默认力度”来弹。
- 你会感知到什么：强弱变化不明显或不贴谱，但不至于忽大忽小或完全没声。
- 为什么要有它：保证稳定可听的输出。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Services/MusicXML/MusicXMLVelocityResolver.swift`

---

## 4) 音频输出 / Step3 音频识别相关

### F-Audio-01：`noteOutput` 未显式注入时，尝试从 `noteAudioPlayer` 推断

- 状态：**已完全消灭（策略 A）**。不再存在从某个播放器“推断音频输出后端”的分支；练习音频后端固定由 `PracticeSequencerPlaybackServiceProtocol` 提供（默认实现为 `AVAudioSequencerPracticePlaybackService`）。
- 现在的行为（用户视角）：
  - 自动播放不会启动；
  - 会弹出提示：`无法自动播放：音频服务初始化失败。`（或更具体的 sound font / engine 错误信息）
- 工程位置（给工程师核对用）：
  - `LonelyPianistAVP/Services/Audio/PracticeSequencerPlaybackService.swift`
  - `LonelyPianistAVP/ViewModels/PracticeSession/PracticeSessionViewModel+Autoplay.swift`

### F-Step3-01：音频识别性能/错误触发的“fallbackReason”

- 白话解释：音频识别有时会遇到“算得太慢”或“连续出错”的情况。我们会把这种状态标记出来，方便调试定位。
- 你会感知到什么：普通用户一般感知不到；开发/调试时会在 overlay 里看到 fallback reason 文本。
- 为什么要有它：这是诊断兜底（告诉你“识别此刻处于不稳定/降级状态”），不是为了让用户去调参数。
- 工程位置（给工程师核对用）：`LonelyPianistAVP/Services/AudioRecognition/PracticeAudioRecognitionService.swift`

---

## 5) 你关心的那条 fallback（总结）

你引用的那段话对应 **F-Guide-01**：`highlightGuides` 为空时使用 fallback guides。  
因为 autoplay 的 on/off 事件是由 guide 派生出来的，所以这条 fallback 会直接改变 noteOff（以及 pedal 交互）的时间语义。

如果你希望把这类风险进一步压低，最直接的策略是：
- 尽量保证生产路径总是传入由 `PianoHighlightGuideBuilderService.buildGuides(...)` 生成的 guides（而不是空数组触发 fallback）。

## 更新记录（Update Notes）
- 2026-04-29: 更新音频输出相关条目（F-Audio-01）以匹配当前 sequencer 播放后端与实际错误提示（移除过期的“音频输出未就绪”文案）。
