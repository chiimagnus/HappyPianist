# 故障排查

## 症状索引
| 症状 | 首查位置 | 典型原因 |
| --- | --- | --- |
| Start Listening 后无按键输出 | Accessibility / `statusMessage` | 权限没开 |
| Dialogue 没回复 | `/health` / 模型目录 | Python 服务没起或权重缺失 |
| Step 3 定位失败 | `practiceLocalizationStatusText` | 校准缺失 / provider 未运行 |
| 曲库能看到但不能练习 | 曲库与步骤生成 | MusicXML 没生成 steps |
| 试听没声音 | 曲库音频绑定 / 播放器 | 音频文件缺失或不可播 |
| PR Tests 没触发 | PR changed files / path filters | 改动路径未匹配 `pr-tests.yml` |
| macOS tests package graph 失败 | Actions log 的 `Resolve Package Graph` | runner 不是 `macos-26`，Swift tools 6.2 不匹配 |
| AVP tests 很久才结束 | `Run AVP tests` step | visionOS simulator 启动和测试会比 macOS 慢 |
| Swift Quality 没自动跑 | Actions workflow trigger | 设计上只允许 `workflow_dispatch` 手动运行 |

## macOS 排查
1. 检查 `hasAccessibilityPermission`。
2. 看 `connectionState` 和 `connectedSourceNames`。
3. 若无响应，先确认 MIDI 来源刷新成功。
4. 若 CI 编译失败，优先看第一条 `SwiftCompile` error；不要先改 workflow。

## AVP 排查
1. 确认 Step 1 已保存，而不是只捕获。
2. 确认已导入 MusicXML 且 `importedSteps` 非空。
3. 若定位失败，优先看 provider state / anchor 状态。
4. 若光柱位置异常，检查 `PianoKeyRegion.center`、`keyboardFrame.keyboardFromWorld` 和 debug axes。
5. 若 CI 找不到 simulator destination，先在日志或本地跑 `xcodebuild -showdestinations -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP`。

## Python 排查
1. `curl -s http://127.0.0.1:8765/health`
2. 检查 `AMT_MODEL_DIR` 或 `AMT_MODEL_ID`
3. 查看 `out/dialogue_debug/*`
4. 如果推理脚本失败，先区分模型权重、设备选择和协议字段三类问题。

## GitHub Actions 排查
| 场景 | 首查步骤 | 恢复 |
| --- | --- | --- |
| PR Tests 没出现 | PR 是否改到 path filters 列出的路径 | 修改匹配路径或手动触发其他验证 |
| macOS tests 失败 | `Run macOS tests` 第一条 compiler error | 修源码并推新 commit |
| AVP tests 失败 | `Run AVP tests` 和 `xcodebuild -list` | 判断是 scheme、destination、package graph 还是测试失败 |
| Package graph 报 Swift tools 6.2 | `Show Xcode version` | 确认 workflow 用 `macos-26` |
| AVP tests 运行约数分钟 | job still in progress | 通常是 simulator 启动/测试耗时；若长期卡住再降级为 build-for-testing |
| Swift Quality 产生 formatter commit | bot commit diff | 审查 diff，确认没有业务语义变化 |

## 恢复建议
| 场景 | 恢复 |
| --- | --- |
| Dialogue 卡住 | 停止对话后重启服务 |
| 校准不稳 | 回 Step 1 重新校准 |
| 索引与文件不一致 | 删除异常条目后重新导入 |
| 试听状态乱掉 | 停止播放并重新绑定音频 |
| AVP CI 不稳定 | 先改为 `build-for-testing` 作为 PR gate，再保留手动完整 `test` |
| Swift Quality 大量改动 | 拆小 PR 或先本地运行 SwiftFormat/SwiftLint 审查 |

## Coverage Gaps
- 目前没有统一日志聚合，因此排障页仍依赖本地状态、Actions job logs 和调试目录。
- Python smoke tests 尚未接入 Actions；Python 相关问题仍需本地复现。

## 更新记录（Update Notes）
- 2026-04-25: 增补 PR Tests、AVP simulator、Swift tools 6.2、Swift Quality 和光柱位置排查路径。
