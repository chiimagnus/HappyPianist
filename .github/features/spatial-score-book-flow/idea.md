# Spatial Score Book Flow

## 为什么要做

HappyPianist 当前的核心选曲、看谱和练习仍然主要发生在普通 Window 中，空间能力没有成为产品主体验。

这个 feature 的目标是把“选曲 → 看谱 → 准备钢琴 → 练习 → 结果 → 返回曲库”收敛成一条连续的 Reality-first 流程：用户看到的是现实环境、现实钢琴和现实双手，曲库、乐谱、Piano Guide、Companion Hands 与练习反馈围绕真实钢琴自然存在于空间中。

---

## 产品目标

最终主流程：

```text
辅助 Library Window
  ↓
Spatial Book Flow
  ↓ 选中 / 确认
Spatial Book Spread
  ↓ 开始练习
必要时完成现有钢琴准备 / 校准
  ↓
同一本 Spatial Book Spread 移动到现实钢琴上方
  + Piano Guide
  + 一双 Companion Hands
  + 空间反馈 / 高频控制
  ↓
完成练习 / 保存
  ↓
返回 Spatial Library
```

普通 Window 继续承担导入、诊断、复杂设置、录音库等辅助职责，但不再作为核心选曲和核心练习界面。

---

## 正式视觉参考

以下 8 张设计稿是本 feature 的产品结构、空间关系、信息层级和视觉语言参考：

1. `.github/features/spatial-2026-09-30/设计稿/images/01-Book-Flow曲库.png`
2. `.github/features/spatial-2026-09-30/设计稿/images/02-双页Book-Spread曲目详情.png`
3. `.github/features/spatial-2026-09-30/设计稿/images/03-现实钢琴-MIDI准备.png`
4. `.github/features/spatial-2026-09-30/设计稿/images/04-正常练习.png`
5. `.github/features/spatial-2026-09-30/设计稿/images/05-Companion教学.png`
6. `.github/features/spatial-2026-09-30/设计稿/images/06-Companion陪弹.png`
7. `.github/features/spatial-2026-09-30/设计稿/images/07-实时反馈与空间控制.png`
8. `.github/features/spatial-2026-09-30/设计稿/images/08-练习结果与重练.png`

同时遵守：
- `.github/features/spatial-2026-09-30/设计稿/视觉契约.md`

这些图不是逐像素复刻任务。现实环境继续来自 passthrough，钢琴来自用户真实乐器，谱面来自真实 MusicXML，封面与元数据只使用真实已知数据。

不要复制设计稿中的固定房间、固定钢琴型号、家具、灯光、示意曲名、示意封面或 AI 生成图中的透视/文字瑕疵。

---

## 必须满足的产品行为

### 1. Book Flow

- 曲库的核心视觉从 Vinyl / Turntable 隐喻切换为书本 / folio。
- 用户可以浏览、选中并确认一本曲谱。
- 中央选中的 folio 用于打开 Book Spread；试听继续是独立动作，不能和“再次点击已选中 item”混成同一个行为。
- 大曲库仍然必须可浏览，不能只适用于少量曲目。
- 空曲库必须回到明确的导入入口，不能制造假的空间书本。

### 2. Book Spread

- 一首曲谱展开后是双页 Book Spread。
- 每页可以纵向容纳多个 Grand Staff systems，而不是把旧的单 viewport 缩成两份。
- Library 与 Practice 必须共享同一套谱面内容、分页和页码语义。
- 当前已经支持的记谱事实不能因为分页丢失，包括谱号、调号、拍号、休止、连线、连音、beam、反复结构和已支持的演奏标记。
- Library detail 中应直接表达练习状态，包括 stable / learning / resume / focus 等已存在的真实练习事实。

### 3. 翻页

- Library 中支持手动前后翻页。
- Practice 中支持随演奏进度自动翻页。
- 自动翻页由真实练习 / playback 位置驱动，不能新增独立的猜测时钟。
- 快速跳转时应收敛到最终目标页，不能积压一串过时翻页动画。

### 4. Spatial Library

- Spatial Book Flow 存在于现实世界坐标中，而不是贴脸 HUD。
- 用户移动头部后，曲库仍保持原来的世界位置。
- 每本 folio 是独立空间对象，不是一整块伪 3D 平面窗口。
- 选中的 folio 可以在空间中展开为 Book Spread。
- Spatial Library 与 Calibration / Practice 属于同一条连续空间体验，不应因为模式切换反复关闭和重开整个沉浸场景。

### 5. Spatial Score Placement

- 开始练习后，Library 中已经打开的那一本 Book Spread 继续存在，并移动到现实钢琴上方；不能创建第二份独立谱面状态。
- 乐谱位置以已校准的真实钢琴坐标为基准，而不是以用户头部为基准。
- Real Audio 与 Bluetooth MIDI 模式共享同一套现实钢琴空间定位语义。
- 用户可以对乐谱进行有限的位置微调并重置。
- 用户偏好只保存钢琴局部坐标下的偏移，不保存一次会话中的世界坐标。

### 6. Reality-first Practice

练习时现实空间中保留：

- 现实钢琴；
- 用户自己的 passthrough 双手；
- Spatial Book Spread；
- Piano Guide；
- 一双 Companion Hands；
- 必要的空间反馈和高频控制。

练习不再重复展示一套主要 Window 乐谱、二维练习钢琴和永久底部控制栏。

复杂设置、调试和低频管理能力可以继续留在辅助 Window。

### 7. Companion Hands

- 用户真实双手保持 passthrough，不再额外渲染一双 Neon 用户手。
- Teaching / Demonstration 与 AI Duet 共用同一双 Companion Hands。
- 不保留第二套虚拟演奏者、第二台 AI piano 或完整 Xiaocheng 角色作为当前生产路径。
- Companion Hands 的动作必须来自真实要播放的音符和真实播放时间，而不是 UI 自己猜测。
- Demonstration 与 AI 可以共享同一套钢琴手指法 / motion pipeline，但不能为了动画效果改变真实音频内容。
- 某只虚拟手无法安全生成动作时，可以不显示该只手；不能伪造“已正确演奏”的动作覆盖。

### 8. 练习反馈与结果

- 高频操作应尽量出现在乐谱或钢琴附近的空间 UI 中。
- 即时反馈应围绕当前练习上下文展示，而不是要求用户不断回到 Window。
- 一轮练习结束后的结果、重点小节、重练、继续等主要动作应回到 Spatial Book Spread 语境中。
- Window Alert 不再承担核心 round-result 产品流程。

### 9. 返回曲库

- 结束练习时必须先完成现有 progress 保存 / flush / discard 决策，再改变空间归属。
- 保存失败时继续停留在 Practice，不能假装已经返回 Library。
- 成功结束后，在同一个空间体验中从 Practice 返回 Spatial Library。
- 返回后仍保持原来选中的曲目，并回到对应 folio / Book Flow。
- 不允许因为 Practice Window 消失而再次关闭已经恢复的 Spatial Library。

---

## 必须保留的现有能力与安全边界

本 feature 是产品形态重构，不是删除数据正确性和硬件安全边界。

必须保留：

- MusicXML 作为正式练习谱面来源；
- 现有 import transaction 的原子性、冲突确认、取消和恢复；
- bundled 曲目不可删除；
- import active 时禁止不安全的删除 / 开始练习；
- Practice progress 的保存、恢复、失败与 explicit discard 语义；
- 麦克风、Bluetooth MIDI、虚拟钢琴现有输入能力；
- A0 / C8 现实钢琴校准流程；
- source/performed identity 和 score revision 语义；
- 任务取消、generation 隔离、后台 / scene teardown 后拒绝过时结果；
- 已有 Piano Guide 的职责与真实性。

新空间体验不得通过静默 fallback、伪造数据或复制第二份状态来掩盖失败。

---

## 重要迁移决定

- 旧 Vinyl / Turntable / Record / Crate 核心曲库视觉退出 production，由 Book Flow 取代。
- 旧连续横向滚谱退出 production，由稳定分页的 Book Spread 取代。
- Library 与 Practice 不维护两份独立 page state；同一首曲谱共享同一分页语义。
- 旧 Neon user-hand renderer、旧 Demonstration renderer、VirtualPerformer / Xiaocheng / 第二台 performer piano 退出当前 production 路径。
- Demonstration 是一次性的练习动作，不是永久开关。
- Spatial Library / Spatial Score 不为普通会话位置创建多余的持久 WorldAnchor。
- 不新增“旧 UI / 新 UI”长期 feature flag 或兼容模式；新路径接管后旧路径退出 production。

---

## 非目标

本 feature 不负责：

- 逐像素复制设计稿；
- 固定用户房间、钢琴型号、家具或灯光；
- 为曲谱生成假的封面、假的音符或假的练习历史；
- 新建第二套 MusicXML parser / notation projection；
- 新建第二套钢琴校准体系；
- 新建第二个 AI 音频播放引擎或独立动画时钟；
- 当前版本重新引入完整 Companion 虚拟角色；
- 因为“空间化”而删除导入恢复、保存失败、权限 / provider 失败等真实安全边界；
- 把所有复杂设置全部塞进空间 UI。

---

## 验收结果

### Book / Notation

- 核心曲库不再以唱片 / 唱臂作为 production 浏览体验。
- Book Spread 每页能显示多个 Grand Staff systems，并保持现有记谱正确性。
- 相同曲谱在 Library 与 Practice 中拥有稳定一致的分页。
- Library 可以手动翻页；Practice 可以按真实进度自动翻页。
- 旧连续横向滚谱不再作为 production Practice 谱面。

### Spatial Library / Score

- Spatial Book Flow 在用户移动头部后仍保持世界位置。
- 每个 folio 都是独立空间对象。
- 选中 folio 可以在空间中打开同一本 Book Spread。
- 开始练习时，同一本 Spread 移动到现实钢琴上方，而不是重新创建一份。
- Real Audio / Bluetooth MIDI 共用同一现实钢琴定位语义。
- 乐谱位置微调可重置，并且不会把 session world transform 当成长期偏好保存。

### Reality-first Practice

- 用户真实手保持 passthrough，不再出现 Neon duplicate hands。
- Teaching 与 AI Duet 只使用一双 Companion Hands。
- production 不再存在 VirtualPerformer / Xiaocheng / 第二台 AI piano 路径。
- Companion Hands 与实际播放音符和播放开始时间同步。
- Piano Guide 仍是唯一琴键引导 renderer。
- 核心练习操作、反馈与 round result 可以在空间中完成。
- 保存失败不会错误返回 Library；保存 / discard 成功后能在同一空间体验中回到原曲目的 Spatial Library。

### Evidence

- 产品决定（2026-10-01）：全项目删除系统辅助模式专用代码、描述器、测试及要求；界面改用系统语义字体，保留普通按钮文本、显式放大阅读与正式记谱几何。
- Simulator / build 只证明软件路径；world stability、现实琴键对齐、阅读舒适度和 Companion finger alignment 必须由 physical Apple Vision Pro 证据支持。
