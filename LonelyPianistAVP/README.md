# visionOS App：LonelyPianistAVP（AR Guide）

这里是 **Apple Vision Pro（visionOS）端**的原型工程目录，核心目标是：

**导入 MusicXML → 校准钢琴空间位置 → 手部追踪判定按键 → 用 AR 高亮提示下一步。**

## 沉浸式 vs 非沉浸式（用户体验）

visionOS 里我们把体验拆成两部分：

- **非沉浸式（2D Window）**：用于“文件导入、按钮控制、状态文字”（例如 `Import MusicXML…`、`Start AR Guide`、`Set A0/C8`、`Skip` 等）。
- **沉浸式（Immersive Space）**：用于“空间内容与追踪”（指尖绿点、黄色 reticle 球、AR 高亮等）。

你没进入沉浸式时：通常只会看到一个 2D 窗口（像一个面板）。

你进入沉浸式后：你会看到 2D HUD 面板 + 空间中的视觉指引（reticle/手部点位/高亮）。

## 功能范围（MVP）

- MusicXML 导入（来自外部下载或人工准备）
- AR Guide：HUD + reticle + 指尖点位
- A0 / C8 两点校准（决定键位对齐）
- `Skip` / `Mark Correct` 推进（便于功能验收）

## 验收流程（最短闭环）

1. **导入谱子（MusicXML）**：在 2D 窗口点 `Import MusicXML…`，看到 `Steps: N`（N>0）。
2. **进入 AR Guide**：点 `Start AR Guide`，首次会弹出手部追踪权限弹窗，点允许。
3. **确认沉浸式状态可见**：你应看到 HUD（`AR Guide` 面板）+ 黄色 reticle 球 + 手指绿点（指尖）。
4. **校准（A0 / C8）**：在 HUD 点 `Set A0` / `Set C8`，把左手食指按在对应琴键上，等待 reticle 变绿后用右手捏合确认，然后 `Save`。
5. **练习指引**：校准完成后会显示当前 step 的键位高亮；可用 `Skip` / `Mark Correct` 辅助推进验证流程。

> 重要：当前 MVP 的键位对齐依赖 **A0 / C8 两点校准**。如果高亮位置明显漂移，先重新校准再判断判定逻辑。

## 依赖与输入

- 推荐输入：`MusicXML`
- 如果你只有 PDF/图片谱：请先在其他工具里转换并下载 MusicXML，再回到这里导入。
