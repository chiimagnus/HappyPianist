# 练习反馈与空间效果验收清单

同步日期：2026-07-12。

后续冗余清理修改了 feedback 模型、renderer 状态和部分测试，因此清理前的 Simulator Pass 不能作为清理后源码的最终证据。以下项目需在同一源码快照上重新执行。

## 自动化场景

| 场景 | 预期事实 | 预期 UI | 状态 |
| --- | --- | --- | --- |
| 第一次练习 | 无错误证据、无 hotspot | 不显示惩罚性 cue；map 标记当前小节 | 需重新执行 |
| 同一小节重复错音 | 只保留一个主要卡点 | cue 可重复呈现；summary 提供一个确定性下一步 | 需重新执行 |
| 同一 issue 连续出现 | feedback event 序号不同 | 第二次及后续仍能刷新 cue/effect | 需重新执行 |
| 部分小节稳定 | 只更新对应 source measure | 未覆盖全部片段时不得发布 passage stable | 需重新执行 |
| 全片段达到目标 | 全部目标小节满足 hand/tempo/streak | summary 标记稳定，loop 停止 | 需重新执行 |
| restart / 换曲 | round/song generation 改变 | 旧 cue、summary 和空间效果立即清理 | 需重新执行 |
| inactive -> active | presentation 先失效，再执行可取消 suspend | 旧反馈不在恢复后重现 | 需重新执行 |

## UI 与文案

- cue 必须非模态，不遮挡五线谱和主要控制。
- 一次只显示一个明确问题，不输出分数、羞辱性语言或无证据诊断。
- summary 显示片段、手别、速度、稳定状态和一个主动作。
- “继续”与“返回曲库”必须执行不同语义。
- measure map 需要可见小节编号、当前状态和 hotspot 标记。
- repeat occurrence 的范围文案必须保持顺序语义，不能显示“第 7–1 小节”。

## Accessibility

| 项目 | 验收标准 |
| --- | --- |
| Dynamic Type | 文本不被固定高度裁切，操作仍可访问。 |
| VoiceOver | cue、map、summary、按钮和状态具有可理解 label。 |
| Differentiate Without Color | 未开始、练习中、稳定和 hotspot 不只依赖颜色。 |
| Reduce Motion | restoration effect 使用静态或低运动替代。 |
| Focus / hover | visionOS 系统控件保留可见 hover 与焦点反馈。 |

## Simulator 验证

```bash
xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'platform=visionOS Simulator,id=<device-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

记录 executed、failed、skipped 数量和 `.xcresult`。针对反馈边界的测试通过后，再手工检查 practice window 的 cue、summary 和 map 布局。

## Vision Pro 验收

- 琴键恢复效果与真实琴位置对齐。
- 反馈不会造成闪烁、眩晕或注意力争夺。
- VoiceOver 手势可访问 summary 与 map。
- 进入后台、关闭窗口、退出 immersive 和换曲后没有残留 entity。
- 连续练习时 cue 频率不会超过 typed user attempt。

真机未执行的项目标记为 `Skipped`，并注明设备、visionOS 版本和原因。
