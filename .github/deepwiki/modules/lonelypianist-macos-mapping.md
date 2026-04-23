# macOS Mappings

## 范围
映射页覆盖单键、和弦、velocity 阈值和编辑持久化。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `DefaultMappingEngine` | 把 MIDIEvent 转成 resolved keystrokes |
| `MappingConfigPayload` | 可编码的映射载荷 |
| `KeyStroke` | 系统按键表示 |
| `SingleKeyMappingRule` | 单音映射 |
| `ChordMappingRule` | 和弦映射 |

## 规则语义
| 规则 | 行为 |
| --- | --- |
| 单键 | 按 note 精确匹配 |
| velocity | 超阈值时加 `.shift` |
| 和弦 | 按下集合必须严格等于规则集合 |
| 去重 | 同一个 chord rule 只触发一次，直到松开 |

## 编辑行为
- `setSingleKeyMapping` 会先清掉同 note 的旧规则，再写入新规则。
- `createChordRule` 会对 notes 去重、排序和 clamp。
- `updateChordRule` 会保持 rule id 不变，只更新内容。
- `deleteChordRule` 直接移除目标规则。

## 调试抓手
- `previewText` 会显示已触发的快捷键。
- `recentLogs` 会记录触发来源和 key label。
- `MappingConfigPayload` 编解码回归可直接防止配置漂移。


## Coverage Gaps
- 目前没有映射编辑器的 UI 自动化测试，主要依赖 view model 和 engine 单测。

