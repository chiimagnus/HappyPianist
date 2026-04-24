# visionOS App：LonelyPianistAVP

这是 Apple Vision Pro 端的原型工程，核心目标是：

**导入 MusicXML → 校准钢琴空间位置 → 追踪手势与按键 → 以 AR 方式引导练习。**

## 运行面

- **2D Window**：导入谱面、设置校准、控制练习
- **Immersive Space**：显示 reticle、指尖点位和空间高亮

## 最短闭环

1. 导入一个外部准备好的 `MusicXML`
2. 进入 AR Guide
3. 按提示完成 A0 / C8 两点校准
4. 进入 Step 3 后查看键位高亮与自动推进

## 关键限制

- 当前 MVP 依赖 **A0 / C8 两点校准**
- App 启动时会尝试自动导入内置 seed（Opus 的 MusicXML）以便快速进入 Step 3；你也可以在 Step 2 导入外部 `MusicXML`。
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
