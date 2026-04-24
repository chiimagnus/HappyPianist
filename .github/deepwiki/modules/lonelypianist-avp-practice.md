# AVP Practice

## 范围
练习页覆盖 step 推进、按键匹配、视觉反馈、autoplay、pedal / fermata / timing。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `PracticeSessionViewModel` | 练习状态机 |
| `PressDetectionService` | 指尖到键位的按键检测 |
| `ChordAttemptAccumulator` | 和弦尝试匹配 |
| `SoundFontPracticeNoteAudioPlayer` | 练习音色播放 |
| `PracticeMIDINoteOutputProtocol` | note on/off 输出 |
| `PianoGuideOverlayController` | RealityKit 空间高亮（键位提示） |

## 行为
- `handleFingerTipPositions` 根据 key regions 检测按键。
- 匹配成功会进入 correct feedback，并在 autoplay 关闭时推进下一步。
- autoplay 会按 note span / pedal / fermata 驱动。
- `skip()` 可手动跳步。
- 空间高亮基于 `PianoKeyRegion.center` 放置；由于 A0/C8 语义为“前沿线”，key center 会通过 `frontEdgeToKeyCenterLocalZ` 从前沿线偏移到按键中心线。
- 当前高亮方块不再额外抬高（贴 keyboard-local `Y = 0`），以减少“悬浮”错觉。

## 状态
| 状态 | 含义 |
| --- | --- |
| `idle` | 尚未开始 |
| `ready` | 已准备好 |
| `guiding(stepIndex:)` | 正在引导 |
| `completed` | 完成 |

## 调试抓手
- `pressedNotes`
- `feedbackState`
- `autoplayHighlightedMIDINotes`
- `audioErrorMessage`
- `currentMusicXMLAttributeSummaryText`

## 调试开关
- `debugKeyboardAxesOverlayEnabled`：显示键盘坐标轴（含 X/Y/Z 标注），便于确认 keyboard frame 是否正确对齐 A0/C8。

## Coverage Gaps
- 视觉反馈和空间布局仍主要依赖手工体验，不是纯逻辑测试就能完全覆盖。
