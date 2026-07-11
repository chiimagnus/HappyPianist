# Practice feedback usability checklist

验证环境：Apple Vision Pro Simulator 26.4（2026-07-12）。真机空间对齐与舒适度项未执行，标记为 skipped。

| 场景 | 现在练哪里 | 哪里需要照顾 | 下一步 | 遮挡/频率 | 结果 |
| --- | --- | --- | --- | --- | --- |
| 首次练习 | 当前谱面与 map 当前标记 | 无证据时不制造卡点 | 继续当前片段 | cue 不出现 | Pass（自动化） |
| 反复卡一个小节 | cue 与 map 标识当前小节 | 仅一个 typed issue/hotspot | 重练该小节或单手隔离 | 顶部非模态 cue，3 秒取消 | Pass（Simulator） |
| 完整片段达标 | summary 显示本轮片段 | 无惩罚文案 | 继续或扩大片段 | summary 位于谱面下方 | Pass（Simulator） |

## Accessibility

- Pass：状态同时使用图标、形状和中文标签，不只依赖颜色。
- Pass：cue、map 与按钮使用 Dynamic Type 文本和 VoiceOver label。
- Pass：Reduce Motion 下 restoration effect 仅使用静态透明度。
- Pass：新 attempt、换曲、退出窗口及 immersive dismiss 会取消 cue/effect。
- Skipped：Vision Pro 真机琴键对齐、眩晕舒适度、实际 VoiceOver 手势验收。

## Copy audit

通过：文案不包含失败、扣分、表现力、指法、踏板或其他无证据诊断。反馈不会比 typed user attempt 更频繁。
