# AVP MusicXML

## 范围
这页覆盖 AVP 端从 MusicXML 导入到“可练习数据结构”的整条管线：导入与解析、结构展开与主声部选择、单谱表自动分手（补 staff）、step 生成（含左右手）、表达性开关与时间线构建、以及下游（Guide/Autoplay/五线谱/判定）如何消费这些数据。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `MusicXMLImportService` | 导入 MusicXML 到沙盒 |
| `MXLReader` | 解包 `.mxl` |
| `MusicXMLParser` | 解析 XML |
| `MusicXMLStructureExpander` |（可选）展开 repeat / structure，生成“更接近播放”的线性 score |
| `MusicXMLHandRouter` | 单谱表 score 自动补 staff=1/2（用于左右手与双谱表渲染） |
| `PracticeStepBuilder` | 从 score 生成 steps |
| `MusicXMLTempoMap` | 节拍到时间映射 |
| `MusicXML*Timeline` | pedal / fermata / slur / attribute 时间线 |
| `PracticePreparationService` | 把 score 处理为 `PreparedPractice`（steps + timelines + guides + measure spans） |

## 端到端管线（PreparePractice）

核心入口：`PracticePreparationService.prepare(from:file:)`。

| 阶段 | 输入 | 输出 | 关键点 |
| --- | --- | --- | --- |
| Parse | `scoreURL` | `MusicXMLScore` | 解析 `.musicxml` 或 `.mxl` |
| Expand (optional) | score | expanded score | 受 `MusicXMLRealisticPlaybackDefaults.shouldExpandStructure` 控制 |
| Primary part | score | filtered score | 选择 primary part（多声部曲谱会被收敛到单个 part 练习） |
| Hand routing | single-staff score | routed score | `MusicXMLHandRouter.routeIfNeeded` 可能补 staff=1/2 |
| Steps | routed score | `PracticeStep[]` | `PracticeStepBuilder.buildSteps` 生成 step/notes（含 hand） |
| Timelines | routed score | tempo/pedal/fermata/... | 为 autoplay 与 expressivity 生成时间线 |
| Guides | routed score + steps + spans | `PianoHighlightGuide[]` | 构建高亮引导链路（含 hand） |
| Output | all | `PreparedPractice` | 提供给 Step 3 session |

## 单谱表自动分手（staff routing）

动机：部分 MusicXML（尤其是从 PDF/图片转换或简化导出）只有单谱表或缺失 `staff` 信息。AVP 端需要“左右手语义 + 双谱表渲染 + 按手判定”的一致数据源，因此在导入管线中对**单谱表 score**做一次 deterministic routing。

实现：`MusicXMLHandRouter.routeIfNeeded(score:)`。

### 触发条件（何时会补 staff）
| 条件 | 行为 |
| --- | --- |
| score 任意 note 出现 `staff>=2` | **不处理**（认为 score 已显式双谱表） |
| 所有 note 都是 rest 或缺失 midiNote | **不处理** |
| score 音域过窄（`maxNote - minNote < 12`） | **不处理**（避免误分手） |
| 其他情况（典型：单谱表且音域够宽） | 对 `staff <= 1` 的 notes 按阈值补成 staff=1/2 |

### 阈值策略（splitThreshold）
| 项 | 当前行为 |
| --- | --- |
| 输入 | score 内所有 pitched notes（rest 会被跳过） |
| 阈值 | 取 MIDI 音高的 median；若 median 不在 `[50, 70]`，回退到 `60`（C4） |
| 路由规则 | `midiNote < threshold -> staff=2`（左手/下谱表），否则 staff=1（右手/上谱表） |

> 说明：这是“可解释、可重复”的工程策略，不追求音乐学上最优分手；但它保证下游链路（五线谱/高亮/判定）能在缺失 staff 的曲谱上工作起来。

## step 生成与左右手语义（ScoreHand）

### step 生成特点
- 仅保留可演奏区间内的 MIDI 音。
- grace / arpeggiate 会影响 onset tick。
- `unsupportedNoteCount` 会被上层转成可见提示。

### PracticeStepNote 的身份与去重维度

step builder 的去重 key 以 `midiNote + staff + voice` 为主（同一 tick 内），保证：
- 同音高但不同 staff/voice 不会被误合并（用于左右手区分与多声部）。
- `PracticeStepNote.id` 把 `hand/rawValue` 也纳入，避免左右手同音高时的 UI diff/高亮冲突。

### hand 的来源
| 数据 | 来源 |
| --- | --- |
| `PracticeStepNote.staff` | MusicXML note.staff（或由 `MusicXMLHandRouter` 补全） |
| `PracticeStepNote.hand` | `ScoreHand.fromStaff(staff)`（`staff<=1` 右手；`staff>=2` 左手；nil 视为右手） |

## 表达性开关
| 开关 | 影响 |
| --- | --- |
| structure | 结构展开 |
| wedge | 动态渐强/渐弱 |
| grace | 装饰音处理 |
| fermata | 延长时值 |
| arpeggiate | 分解和弦偏移 |
| words semantics | words 事件派生 tempo / pedal |
| performance timing | 更贴近演奏时值 |

## 下游消费点（谁会用到 staff/hand）

| 下游 | 读取什么 | 用途 |
| --- | --- | --- |
| `PianoHighlightGuideBuilderService` | score.notes staff/voice + steps | 构建高亮 guide，并把 hand 贯穿到 `PianoHighlightNote` |
| `GrandStaffNotationView` / `GrandStaffNotationLayoutService` | guides + note.staff | 把 notes 渲染到上/下谱表（并绘制 barline/context） |
| 2D 键盘高亮 | guide.note.hand | 左手用青色（cyan），右手用默认色 |
| 3D/AR decal 高亮 | guide.note.hand | 左/右手使用不同 guide color |
| Step 匹配（可选 gate） | step.notes hand | 当开启“左右手分别满足”时，按左右手分别满足才通过 |

## 调试抓手
- `importErrorMessage`
- `tempoMap`
- `pedalTimeline`
- `fermataTimeline`
- `attributeTimeline`
- `slurTimeline`
- `unsupportedNoteCount`
- `highlightGuides.count` / `currentPianoHighlightGuide`
- （单谱表）导入后 notes 是否出现 staff=2（用于确认 `MusicXMLHandRouter` 是否触发）

## 相关测试
| 测试 | 覆盖 |
| --- | --- |
| `LonelyPianistAVPTests/MusicXMLHandRouterTests.swift` | 单谱表 fixture 的 deterministic routing |
| `LonelyPianistAVPTests/PracticeStepBuilderTests.swift` | step 构建去重与 staff/voice 维度 |
| `LonelyPianistAVPTests/PianoHighlightGuideBuilderServiceTests.swift` | guide 链路贯穿 hand 信息 |
| `LonelyPianistAVPTests/MusicXMLParser*.swift` | parser 回归（grace/tuplet/dynamics/wedge/...） |

## Coverage Gaps
- 支持的表达性语义仍是显式开关驱动，未自动识别所有谱面意图。
- 单谱表自动分手是“工程启发式”；对某些极端曲谱（交错声部、左手高音、右手低音）可能产生不符合人类手分配的结果，但仍保持 deterministic。
