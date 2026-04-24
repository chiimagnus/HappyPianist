# 术语表

## 业务术语
| 术语 | 定义 |
| --- | --- |
| Piano Dialogue | 你弹一句、AI 回一句的轮转式流程 |
| Step 1 / 2 / 3 | 校准、选曲、练习三步流 |
| Take | 一次录音或对话回放的持久化产物 |

## 架构术语
| 术语 | 定义 |
| --- | --- |
| `MIDIEvent` | macOS 统一输入模型 |
| `DialogueNote` | Swift 和 Python 共享的音符契约 |
| `PracticeStep` | AVP 练习推进单元 |
| `DataProviderState` | AR tracking provider 的运行状态 |
| `KeyboardFrame` | 从 A0/C8 推导的键盘局部坐标系（A0 为原点，+X 指向 C8） |
| `frontEdgeToKeyCenterLocalZ` | 在 keyboard-local 中，前沿线（z=0）到按键中心线的 Z 偏移（通常为 ±keyDepth/2） |

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

## Coverage Gaps
- 发布和版本语义仍散落在 README 和流程中，没有独立页面。
