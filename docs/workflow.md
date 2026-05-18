# 工作流

## 进入仓库的判断顺序
1. 先判断改动属于 macOS / visionOS / Python / CI 哪一面。
2. 再找对应入口：App、ViewModel、Service、Test、Workflow。
3. 涉及 Dialogue 先确认 `piano_dialogue_server` 已启动。
4. 涉及 AVP 先确认 Step 1 校准和 Step 2 曲库是否就绪。
5. 自动化现状见下文；本仓库默认以本地 `xcodebuild test` 与脚本验证为准。

## 开发循环
| 阶段 | 做什么 | 产物 | 验证 |
| --- | --- | --- | --- |
| 定位 | 锁定业务和模块边界 | 变更范围 | 阅读 docs + 搜索代码 |
| 实现 | 按 MVVM + Services 改代码 | 代码变更 | 本地 build/test |
| 验证 | 跑对应用例和脚本 | 测试结果 | 本地 macOS/AVP tests + Python smoke |
| 同步 | 更新 docs / README | 知识层 | INDEX 和 Coverage Gaps 同步 |
| 质量维护 | 手动运行 formatter | 格式化 diff 或 no-op | 本地 SwiftFormat（可选） |

## 按运行面修改
| 运行面 | 默认入口 | 常见联动 | 本地验证 |
| --- | --- | --- | --- |
| macOS | `LonelyPianist/ViewModels/LonelyPianistViewModel.swift` | MIDI service、storage、Dialogue | macOS tests |
| visionOS | `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` + `ViewModels/Library/SongLibraryViewModel.swift` | tracking、musicxml、playback、RealityKit overlay | AVP tests |
| Python | `piano_dialogue_server/server/api/main.py` + `server/engines/*` | protocol、bonjour、debug artifacts、upload-expand、三种生成策略 | 本地 smoke（curl/WS/Playground），暂未自动 CI |
| CI | （无） | 当前仓库不含 `.github/workflows/` | — |

## 自动化现状
当前仓库未提交 GitHub Actions workflows，因此没有 PR 自动测试或自动格式化；所有验证以本地运行命令为准（见下文「本地验证命令」）。

## 本地验证命令
| 场景 | 命令 |
| --- | --- |
| macOS tests | `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` |
| 获取 visionOS simulator id | `xcodebuild -showdestinations -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP` |
| AVP tests（visionOS simulator） | `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO` |
| SwiftFormat（可选） | `swiftformat --config .swiftformat LonelyPianist LonelyPianistAVP LonelyPianistTests LonelyPianistAVPTests` |
| Python server（本地启动） | `cd piano_dialogue_server && ./scripts/run_server.sh` |
| Python health check | `curl -s http://127.0.0.1:8765/health` |

## 常见变更清单
| 变更 | 需要同步 | 推荐验证 |
| --- | --- | --- |
| Dialogue 协议字段 | Swift model + WebSocket service + Python protocol | macOS tests + Python WS smoke |
| AVP 后端发现/HTTP 生成 | AVP discovery/client + Python `/generate` + Info.plist 权限 | AVP tests + 同网段真机冒烟 |
| 曲库字段 | SongLibrary models + store + seeder | AVP library tests |
| 校准字段 | StoredWorldAnchorCalibration + store + localization | AVP calibration tests |
| MusicXML 规则 | parser + step builder + practice view model | MusicXML parser/timeline tests |
| AR 贴皮高亮样式 | `PianoGuideOverlayController` + practice docs | AVP tests + Vision Pro 手工观察 |
| BLE MIDI 录制/回放 | `BluetoothMIDIInputEventSourceService` + `MIDIRecordingAdapter` + `RecordingTakeStore` + `TakePlaybackController` | AVP tests + Vision Pro 真机冒烟 |
| 钢琴模式增删改 | `PianoModeProtocol` 实现 + `PianoModeRegistryService` 注册 + `PianoTypePickerView` + `FlowState.selectedPianoModeID` | AVP tests + 类型选择 UI 验证 |
| Xcode target / package | project + scheme | macOS + AVP tests |
| SwiftFormat 规则 | `.swiftformat` | 手动 SwiftFormat（可选） |

## CI 调试流程
| 现象 | 先看哪里 | 常见处理 |
| --- | --- | --- |
| Package graph resolve 失败 | Xcode build 日志 | 确认依赖版本和 Swift tools 版本 |
| 找不到 scheme | `xcodebuild -list` | 检查 shared scheme / project 文件 |
| 找不到 AVP destination | `xcodebuild -showdestinations` | 使用 concrete device id：`platform=visionOS Simulator,id=<device-id>` |
| macOS compile failed | `SwiftCompile` 第一条 error | 修源码 |
| AVP test 运行很久 | 本地测试输出 | visionOS simulator 启动慢属预期 |
| SwiftFormat 产生大 diff | formatter diff | 审查格式化改动后再继续集成 |

## 维护 docs
- 业务语义变化先改 `overview.md`。
- 技术边界变化再改 `architecture.md`、`data-flow.md`。
- 配置变化改 `configuration.md`。
- 本地验证命令变化改本页。
- CI/协作流程变化改本页。
- 新增运行面时新增 module page，并在 `overview.md` 的「按问题导航」里补入口。
- 更新 `GENERATION.md` 记录 commit、branch、页面清单和 Coverage Gaps。

## 发布与分支
| 分支 / PR | 角色 | 注意事项 |
| --- | --- | --- |
| `main` | 默认分支 | 建议合并前本地跑完 macOS/AVP tests |
| feature branches | 功能开发 | PR 到 `main` 后需要手动运行本地测试 |
| docs update commits | 文档更新 | 只改 `docs/**` 时仍建议做最小链接/命令自检 |

## Coverage Gaps
- 没有统一发布流水线；因此本页只记录开发、验证和文档同步路径。
- Python smoke tests 尚无自动化门禁。
- 当前仓库未提交 CI workflows，自动化测试需要在本地手动运行。
