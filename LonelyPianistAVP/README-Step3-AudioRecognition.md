# Step3 Audio Recognition - Vision Pro 实机调参与验收清单

## 目标

本清单用于在 Vision Pro 真机上验证 Step3 音频识别链路，覆盖误通过、漏通过、连续跳步、权限失败与降级行为。

## 记录模板

请每次实机调试都填写以下信息：

- 设备：Vision Pro 型号 / visionOS 版本
- 环境：房间大小、噪音级别（安静/中等/嘈杂）
- 钢琴类型：原声/电钢 + 型号
- 音区：低音区 / 中音区 / 高音区
- 曲目 / Step：例如 `C4-E4-G4`、`连续 C4`
- 模式：`lowLatency` / `stricter`
- 体感延迟：低 / 中 / 高（可附大致毫秒）
- Debug 快照要点：
  - `inputLevel`
  - `expectedMIDINotes`
  - `recentDetectedNotes`
  - `matchProgress`
  - `handGate`
  - `suppress`
  - `generation`
  - `lastDecisionReason`
- 结果：通过 / 失败
- 阈值建议：是否需要调整 `singleNoteThreshold`、`wrongDominanceRatio`、`aggregationWindow`、`harmonicWeights`

## 验收清单

### 权限与生命周期

- [ ] 首次进入 Step3 时触发麦克风权限请求。
- [ ] 拒绝权限后，不崩溃；可继续手势 fallback / 手动下一步。
- [ ] 在系统设置重新授权后，可恢复音频识别。
- [ ] 退出 Step3、重置 session、自动播放开启时，音频识别停止或隔离。

### 单音与和弦

- [ ] 单音 `C4 / E4 / G4` 在 `lowLatency` 模式下可稳定通过。
- [ ] 三音和弦（如 `C4-E4-G4`）可稳定达到 `2/3` 通过。
- [ ] 二音和弦（如 `C4-E4`）必须两个都命中才通过。

### 音高容差与错音

- [ ] `±20 cents` 偏差仍归到同一 MIDI。
- [ ] 相邻半音（如 `C4` vs `C#4`）不会误通过。
- [ ] wrong evidence 强时可触发 wrong 或阻止 matched。
- [ ] 已 matched 后短窗口出现错音不会回滚已推进 step（只记录 debug/log）。

### 连续同音与抑制

- [ ] 连续两个相同音（如 `C4 -> C4`）不会被余音连跳。
- [ ] 播放“提示音/示范音”期间不会误触发 matched。
- [ ] suppress 窗口结束后，新 onset 能正常推进。

### 自动播放与降级

- [ ] autoplay 开启时，麦克风事件不推动 `advanceToNextStep()`。
- [ ] autoplay 关闭后，音频识别可恢复。
- [ ] hand tracking denied 时，音频识别仍可独立推进。
- [ ] world tracking 不稳定时，2D Step3 + 音频路径仍可使用。

## 调参建议输出格式

每次实机调参后，按以下格式追加一条记录：

```text
[YYYY-MM-DD HH:mm]
Device:
Environment:
Piano:
Step/Range:
Mode:
Observed:
Snapshot:
Decision:
Parameter Proposal:
```
