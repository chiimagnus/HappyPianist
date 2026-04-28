# 术语表

## 业务术语
| 术语 | 定义 |
| --- | --- |
| Piano Dialogue | 你弹一句、AI 回一句的轮转式流程 |
| Step 1 / 2 / 3 | 校准、选曲、练习三步流 |
| Take | 一次录音或对话回放的持久化产物 |
| Fallback（兜底） | 当理想数据缺失时，系统主动选择替代行为继续运行；可能导致还原度偏离 MusicXML 语义 |

## 架构术语
| 术语 | 定义 |
| --- | --- |
| `MIDIEvent` | macOS 统一输入模型 |
| `DialogueNote` | Swift 和 Python 共享的音符契约 |
| `PracticeStep` | AVP 练习推进单元 |
| `DataProviderState` | AR tracking provider 的运行状态 |
| `KeyboardFrame` | 从 A0/C8 推导的键盘局部坐标系（A0 为原点，+X 指向 C8） |
| `frontEdgeToKeyCenterLocalZ` | 在 keyboard-local 中，前沿线（z=0）到按键中心线的 Z 偏移（通常为 ±keyDepth/2） |
| `AutoplayPerformanceTimeline` | 统一调度 note on/off、踏板、guide、step 和 fermata pause 的播放时间线 |
| `PianoHighlightGuide` | 钢琴高亮引导元素，包含 trigger/release/gap 三种类型 |
| `PianoHighlightGuideKind` | 引导类型：trigger（按下）、release（松开）、gap（空闲） |
| `MusicXMLExpressivityOptions` | MusicXML 表现力选项，控制 wedge、grace、fermata、arpeggiate、words semantics 的启用 |

## 音频识别术语
| 术语 | 定义 |
| --- | --- |
| `HarmonicTemplateScorer` | 谐波模板评分器，通过谐波能量比和支配度计算音符匹配置信度 |
| `TargetedHarmonicTemplateDetector` | 目标谐波模板检测器，针对预期音符和错误候选音符进行检测 |
| `partial completeness` | 谐波分片完整性，用于判断是否有足够的谐波能量支持音符识别 |
| `tonalRatio` | 谐波能量比，谐波区域能量与周围能量的比值 |
| `dominance` | 支配度，预期音符相对于错误候选音符的能量优势 |
| `rms noise gate` | RMS 噪声门，过滤低能量静音段 |

## 存储术语
| 术语 | 定义 |
| --- | --- |
| `StoredWorldAnchorCalibration` | A0/C8 世界锚点校准 |
| `SongLibraryIndex` | 曲库索引（entries + lastSelectedEntryID） |
| `SongLibraryEntry` | 单条曲目元数据 |
| `dialogue_debug bundle` | Python 调试落盘目录 |

## 易混淆概念
- **stored calibration**：持久化的 anchor ID。
- **runtime calibration**：当前场景里根据 tracked anchors 解析出来的几何结果。
- **导入成功** 不等于 **可开始练习**：还要能生成有效 steps，并成功定位。
- **fallback（兜底）** 不等于 **error handling（错误处理）**：fallback 是主动选择替代行为继续运行，error handling 是捕获错误并恢复。

## Coverage Gaps
- 发布和版本语义仍散落在 README 和流程中，没有独立页面。
- 音频识别的各种 fallback 状态和模式切换仍在演进中。
