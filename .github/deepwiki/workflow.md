# 工作流

## 进入仓库的判断顺序
1. 先判断改动属于 macOS / visionOS / Python 哪一面。
2. 再找对应入口：App、ViewModel、Service、Test。
3. 涉及 Dialogue 先确认 `piano_dialogue_server` 已启动。
4. 涉及 AVP 先确认 Step 1 校准和 Step 2 曲库是否就绪。

## 开发循环
| 阶段 | 做什么 | 产物 |
| --- | --- | --- |
| 定位 | 锁定业务和模块边界 | 变更范围 |
| 实现 | 按 MVVM + Services 改代码 | 代码变更 |
| 验证 | 跑对应用例和脚本 | 测试结果 |
| 同步 | 更新 deepwiki / README | 知识层 |

## 按运行面修改
| 运行面 | 默认入口 | 常见联动 |
| --- | --- | --- |
| macOS | `LonelyPianist/ViewModels/LonelyPianistViewModel.swift` | MIDI service、storage、Dialogue |
| visionOS | `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` + `ViewModels/Library/SongLibraryViewModel.swift` | tracking、musicxml、playback |
| Python | `piano_dialogue_server/server/main.py` + `inference.py` | protocol、debug artifacts |

## 常见变更清单
| 变更 | 需要同步 |
| --- | --- |
| Dialogue 协议字段 | Swift model + WebSocket service + Python protocol |
| 曲库字段 | SongLibrary models + store + seeder |
| 校准字段 | StoredWorldAnchorCalibration + store + localization |
| MusicXML 规则 | parser + step builder + practice view model |

## 维护 deepwiki
- 业务变化先改 `business-context.md`
- 技术边界变化再改 `architecture.md`、`data-flow.md`
- 配置变化改 `configuration.md`
- 测试命中面变化改 `testing.md`
- 新增运行面时新增 module page，并补 `INDEX.md`

## Coverage Gaps
- 没有统一发布流水线；因此工作流页只记录本地开发和验证路径。
