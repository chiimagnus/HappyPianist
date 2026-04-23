# AVP MusicXML

## 范围
这页覆盖导入、解析、时间线、step 生成和 expressivity 选项。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `MusicXMLImportService` | 导入 MusicXML 到沙盒 |
| `MXLReader` | 解包 `.mxl` |
| `MusicXMLParser` | 解析 XML |
| `PracticeStepBuilder` | 从 score 生成 steps |
| `MusicXMLTempoMap` | 节拍到时间映射 |
| `MusicXML*Timeline` | pedal / fermata / slur / attribute 时间线 |

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

## step 生成特点
- 仅保留可演奏区间内的 MIDI 音。
- grace / arpeggiate 会影响 onset tick。
- `unsupportedNoteCount` 会被上层转成可见提示。

## 调试抓手
- `importErrorMessage`
- `tempoMap`
- `pedalTimeline`
- `fermataTimeline`
- `attributeTimeline`
- `slurTimeline`


## Coverage Gaps
- 支持的表达性语义仍是显式开关驱动，未自动识别所有谱面意图。

