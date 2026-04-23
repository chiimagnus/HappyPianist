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

## 行为
- `handleFingerTipPositions` 根据 key regions 检测按键。
- 匹配成功会进入 correct feedback，并在 autoplay 关闭时推进下一步。
- autoplay 会按 note span / pedal / fermata 驱动。
- `skip()` 可手动跳步。

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


## Coverage Gaps
- 视觉反馈和空间布局仍主要依赖手工体验，不是纯逻辑测试就能完全覆盖。

