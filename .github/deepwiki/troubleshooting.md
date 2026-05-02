# 故障排查

## 症状索引
| 症状 | 首查位置 | 典型原因 |
| --- | --- | --- |
| Start Listening 后无按键输出 | Accessibility / `statusMessage` | 权限没开 |
| Dialogue 没回复 | `/health` / 模型目录 | Python 服务没起或权重缺失 |
| Step 3 定位失败 | `practiceLocalizationStatusText` | 校准缺失 / provider 未运行 |
| 曲库能看到但不能练习 | 曲库与步骤生成 | MusicXML 没生成 steps |
| 试听没声音 | 曲库音频绑定 / 播放器 | 音频文件缺失或不可播 |
| Step 3 点击「下一步」声音短促 | `modules/lonelypianist-avp-practice-audio.md` | 多余 stop + all-notes-off 竞态截断 note |
| 虚拟钢琴手指接触无声音 | `KeyContactDetectionService.detect` 输出 / `liveNotes` 集合 | 迟滞阈值未命中或 geometry 未生成 |
| 虚拟钢琴放置后键盘位置偏移 | `cachedVirtualPianoWorldAnchorID` / `latestGazePlaneHit` | anchor 未被正确追踪恢复或平面命中不稳定 |
| 虚拟钢琴开启后无法进入练习 | `ARGuideViewModel.practiceEntryBlockingReason` | 检查是否正确跳过校准检查 |
| AVP tests 很久才结束 | 本地 `xcodebuild test` 输出 | visionOS simulator 启动和测试会比 macOS 慢 |

## macOS 排查
1. 检查 `hasAccessibilityPermission`。
2. 看 `connectionState` 和 `connectedSourceNames`。
3. 若无响应，先确认 MIDI 来源刷新成功。
4. 若 CI 编译失败，优先看第一条 `SwiftCompile` error；不要先改 workflow。

## AVP 排查
1. 确认 Step 1 已保存，而不是只捕获。
2. 确认已导入 MusicXML 且 `importedSteps` 非空。
3. 若定位失败，优先看 provider state / anchor 状态。
4. 若贴皮高亮位置/尺寸/闪烁异常，检查 `PianoGuideBeamDescriptor`、`KeyDecalSoftRect`、`PianoKeyboardGeometry.frame.keyboardFromWorld` 和 debug axes。
5. 若找不到 simulator destination，先本地跑 `xcodebuild -showdestinations -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP`。
6. 若看到大量音频相关 stop/start 日志，先区分”识别服务”与”播放服务”（见下方常见音频日志）。
7. 若虚拟钢琴模式下手指接触琴键无声音，检查 `KeyContactDetectionService.detect` 的 `started` 输出和 `PracticeSequencerPlaybackServiceProtocol.liveNotes`。
8. 若虚拟钢琴放置后键盘位置偏移，检查：
   - `AppState.cachedVirtualPianoWorldAnchorID` 对应的 `WorldAnchor.isTracked` 是否稳定恢复
   - `ARGuideViewModel.latestGazePlaneHit` 是否频繁变为 `nil`（会导致确认立即 reset）
   - `VirtualKeyboardPoseService.computeWorldFromKeyboard` 的输入（plane pose / hand center / device pose）

### 常见音频日志（AVP）

| 日志片段 | 来自哪里 | 含义 | 优先动作 |
| --- | --- | --- | --- |
| `audio service stopped` | `PracticeSessionViewModel.stopAudioRecognition()` | 练习音频识别服务 stop（不是播放 stop） | 观察触发时机：是否切换 autoplay、manual replay、或离开 guiding |
| `audio service failed start generation=...` | `PracticeSessionViewModel.refreshAudioRecognitionForCurrentState()` | 识别引擎启动失败（麦克风/会话/格式问题） | 先检查系统麦克风权限，再看 `audioRecognitionStatus` / error message |
| `AURemoteIO ... -10851 ... 0 Hz` | iOS/visionOS 音频底层 | 输入/输出格式或会话状态异常导致 RemoteIO 启动失败 | 先按“识别引擎启动失败”路径排查；必要时重启 App/Simulator |

## Python 排查
1. `curl -s http://127.0.0.1:8765/health`
2. 检查 `AMT_MODEL_DIR` 或 `AMT_MODEL_ID`
3. 查看 `out/dialogue_debug/*`
4. 如果推理脚本失败，先区分模型权重、设备选择和协议字段三类问题。

## 自动化现状
当前仓库未提交 `.github/workflows/`，因此没有 GitHub Actions 排查路径；所有验证以本地 `xcodebuild test` 和 Python smoke 为准。

## 恢复建议
| 场景 | 恢复 |
| --- | --- |
| Dialogue 卡住 | 停止对话后重启服务 |
| 校准不稳 | 回 Step 1 重新校准 |
| 索引与文件不一致 | 删除异常条目后重新导入 |
| 试听状态乱掉 | 停止播放并重新绑定音频 |
| AVP simulator 不稳定/太慢 | 先用 `xcodebuild build-for-testing` 做轻量回归，再按需跑完整 `test` |
| SwiftFormat 大量改动 | 拆小改动或先本地运行 SwiftFormat 审查 |
| 虚拟钢琴无声音 | 检查 `KeyContactDetectionService` 迟滞阈值和 `liveNotes` 集合 |

## Coverage Gaps
- 目前没有统一日志聚合，因此排障页仍依赖本地状态与调试目录。
- 目前无 CI workflows；Python 相关问题仍需本地复现。

## 更新记录（Update Notes）
- 2026-04-25: 增补 PR Tests、AVP simulator、Swift tools 6.2、Swift Quality，并将光柱排查更新为丁达尔光束（keyboard geometry + atlas）。
- 2026-04-29: 增补 AVP 常见音频日志释义；新增「下一步短促音」症状入口并路由到排查记录页。
- 2026-04-30: 新增虚拟钢琴故障排查条目（放置偏移、按键无声音、进入练习失败）；增补 AVP 虚拟钢琴排查步骤。
- 2026-05-01: AVP 练习引导从光柱改为琴键贴皮高亮（decal），并移除 correct/wrong feedback 与 immersive pulse。
- 2026-05-02: 虚拟钢琴放置改为 gaze-plane + palm confirmation；移除 GitHub Actions 排障假设（当前仓库不含 `.github/workflows/`）。
