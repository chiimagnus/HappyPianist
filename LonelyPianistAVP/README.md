# visionOS App：LonelyPianistAVP

这是 Apple Vision Pro 端的原型工程，核心目标是：

**导入 MusicXML → 校准钢琴空间位置 → 追踪手势与按键 → 以 AR 方式引导练习。**

## 运行面

- **2D Window**：导入谱面、设置校准、控制练习
- **Immersive Space**：显示 reticle、指尖点位和空间高亮

## 最短闭环（当前主流程）

1. 选择钢琴类型：真实钢琴 / 虚拟钢琴
2. 完成准备阶段：
   - 真实钢琴：按提示完成 A0 / C8 两点校准
   - 虚拟钢琴：在准备阶段完成 3D 88 键键盘放置
3. 进入选曲库：选择内置曲目或导入 `MusicXML`
4. 点击“开始练习”，进入练习页查看键位高亮与步骤推进

## 关键限制

- 当前 MVP 依赖 **A0 / C8 两点校准**
- 内置曲目来自 app bundle 的 `Resources/SeedScores`，与用户导入曲目在曲库中合并展示（内置曲目不可删除/绑定外部音频）。
- 虚拟钢琴入口不在练习页设置中切换，而是在“钢琴类型选择”阶段决定。
- `SalC5Light2.sf2` 默认需要放在：

```text
LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2
```

## 调试

- 练习设置中可以开启 **调试：显示键盘坐标轴（X/Y/Z）**，用于确认键盘 frame 的原点与轴向。

## 运行说明

```text
打开 LonelyPianist.xcodeproj
选择 / 创建 LonelyPianistAVP scheme
运行到 visionOS Simulator 或真机
```

仓库当前只提交了 macOS 的共享 scheme；`LonelyPianistAVP` 在本地 Xcode 中选择或创建 scheme 后即可运行。

## 相关页面

- [`../README.md`](../README.md)
- [`../.github/deepwiki/modules/lonelypianist-avp.md`](../.github/deepwiki/modules/lonelypianist-avp.md)
- [`../.github/deepwiki/modules/lonelypianist-avp-practice.md`](../.github/deepwiki/modules/lonelypianist-avp-practice.md)

## Step3 Targeted Harmonic Template Matching

Step3 音频识别当前使用 `harmonicTemplate` detector。V2 的谐波模板方案只围绕当前 step 的 expected notes 与少量 wrong candidates 检测，不做完整转谱。调参说明见 `Documentation/Step3HarmonicTemplateTuning.md`，方案说明见 `Documentation/Step3TargetedHarmonicTemplateMatching.md`。
