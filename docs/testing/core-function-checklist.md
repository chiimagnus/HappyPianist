# HappyPianist 核心功能测试清单

> 这是一份日常功能验证清单，不是发布前 Gate，也不要求一次完成全部测试。  
> 目的：优先验证会直接影响选曲、进入练习、输入判定、进度恢复和 App 稳定性的行为。

## 暂不包含

本清单暂不覆盖：

- Python 服务与 Python 测试
- Bonjour、局域网发现与网络重连
- AI 网络后端、WebSocket 与远程模型故障
- 诊断 ZIP 导出
- 极端超大文件与安全压力测试
- 完整无障碍专项矩阵
- 多台 MIDI 设备同时连接
- 长时间性能、电量与压力测试

这些项目仍可在相关功能进入重点开发时单独验证。

## 2026-07-15 P1 启动所有权 Gate 记录

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| Library 调用图不触达 prepare/apply/score read | Pass | `codegraph sync/explore` 显示 `PracticePreparationService.prepare` 的唯一生产调用方为 `PracticeLaunchViewModel`；旧 Library symbols 全仓零命中。 |
| resolve/prepare/apply、return、scene inactive、session replacement 与连续 retry 竞态 | Pass | controllable continuation 与 lifecycle tests 全部实际运行。 |
| visionOS Simulator 完整测试 | Pass | Apple Vision Pro visionOS 26.4：653 次设备配置测试运行通过，0 failed，0 skipped，xcresult 无 runtime warning。 |
| visionOS Simulator App build | Pass | `xcodebuild build` 成功，无 Swift 编译 warning。 |
| 主内容右下角按钮在最小/理想/最大窗口不遮挡试听控件 | Not Run | 当前环境没有可见的 Simulator GUI/应用窗口，不能取得可复现的目标窗口截图。 |
| VoiceOver 名称与 hint、键盘/间接输入 | Not Run | 需要可交互 Simulator GUI 或真机。 |
| loading/failure/retry/return 与 scene inactive 的人工交互 | Not Run | 自动化状态机与竞态已通过；交互呈现仍需可见 Simulator GUI 或真机。 |

## 2026-07-15 P2 曲库事实 Ornament Gate 记录

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| never/current/needs rebuild/unavailable 事实边界与 A→B→A 乱序 | Pass | snapshot builder、受控 actor history 与 metadata failure 回归测试实际运行。 |
| Library/Ornament 不触达 score、prepare、session 或配置 controller | Pass | CodeGraph 调用图、score access spy 与静态符号 gate。 |
| visionOS Simulator 完整测试与 App build | Pass | Apple Vision Pro visionOS 26.4 的本轮 `xcodebuild test` / `build` 结果。 |
| Ornament 各状态与 min/ideal/max 窗口 | Not Run | 当前环境没有可见的 Simulator GUI/应用窗口。 |
| 最大 Dynamic Type、VoiceOver | Not Run | 需要可交互 Simulator GUI 或真机。 |
| Reduce Motion、Differentiate Without Color | Not Run | 自动化构建覆盖相应 SwiftUI 分支；人工呈现需要可交互 Simulator GUI 或真机。 |

## 1. 构建与自动化测试

先查看可用 Simulator：

```bash
xcodebuild -showdestinations \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP
```

构建 App：

```bash
xcodebuild build \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'generic/platform=visionOS' \
  CODE_SIGNING_ALLOWED=NO
```

运行完整测试：

```bash
xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'platform=visionOS Simulator,id=<device-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

检查：

- [ ] App target 与测试 target 均能编译
- [ ] 测试实际执行，不只是 `build-for-testing`
- [ ] 测试失败数量为 0
- [ ] 没有新增且无法解释的 warning

## 2. 曲谱库与试听

### 曲谱库

1. 启动 App 并进入曲谱库。
2. 左右切换至少三首曲目。
3. 返回其他窗口，再次打开曲谱库。

检查：

- [ ] 曲谱库正常打开，不崩溃、不空白
- [ ] 唱片切换流畅，不会自动跳回第一首
- [ ] 曲名、作曲家与当前唱片一致
- [ ] 唯一“开始练习”按钮始终对应当前曲目
- [ ] 再次打开时仍选中上次曲目
- [ ] trailing Ornament 随当前曲目显示 never/current/needs rebuild/unavailable 对应状态
- [ ] Ornament 只有事实与说明，没有配置控件或第二个练习按钮
- [ ] 从练习窗口返回后，同一曲目的最新 metadata/facts 会刷新

### 试听

1. 播放一首带音频的曲目。
2. 暂停后继续。
3. 拖动播放进度。
4. 播放过程中切换曲目。

检查：

- [ ] 播放、暂停和继续正常
- [ ] 暂停后不会回到开头
- [ ] 拖动后从正确位置继续
- [ ] 切歌后旧音频立即停止
- [ ] 不会同时播放两首音频

## 3. 进入练习与恢复

1. 选择一首有历史进度的曲目。
2. 点击“开始练习”。
3. 返回曲库后再次进入。
4. 在 preparation loading 时切到后台再恢复。

检查：

- [ ] 不出现第二套重复设置弹窗
- [ ] loading / failure 状态不会短暂显示上一首曲目的练习内容
- [ ] exact revision 的片段、手别、速度、循环、成功目标和恢复位置均正确
- [ ] 无效 passage/resume 回退到整首且下一次启动不再重复失败
- [ ] 点击一次只创建一个练习 Session
- [ ] 快速连续点击不会打开多个练习窗口
- [ ] 曲谱尚未准备好或准备失败时在练习窗口有明确状态、技术详情、重试和返回

## 4. 正常练习与单手练习

1. 选择 2–4 个小节。
2. 分别测试右手、左手与双手。
3. 设置 60%–80% 速度。
4. 完成至少一轮练习。

检查：

- [ ] 从所选范围第一步开始
- [ ] 不进入范围外的小节
- [ ] 当前小节、谱面高亮与键盘提示一致
- [ ] 速度设置真实影响播放速度
- [ ] 右手模式不会被左手专属 step 卡死
- [ ] 左手模式不会被右手专属 step 卡死
- [ ] 达到连续成功目标后能结束本轮
- [ ] 开启循环后，达标时不会无限循环
- [ ] 自动播放、回放或 AI 输出不会被当作用户输入

## 5. 保存与继续练习

1. 练到片段中间。
2. 返回曲谱库。
3. 关闭曲谱库窗口。
4. 重新打开曲谱库。
5. 点击“继续练习”。

检查：

- [ ] 恢复到正确曲目
- [ ] 恢复正确的小节范围、手别与速度
- [ ] 恢复到正确小节或 step
- [ ] 恢复后保持暂停
- [ ] 打开窗口时不会自动发声
- [ ] 进度不会倒退到更早位置

再测试一次“从头练习”：

- [ ] 从当前选择范围的第一小节开始
- [ ] 不继续使用上次的中途位置

## 6. 后台与窗口生命周期

1. 练习中让 App 进入 inactive 或后台。
2. 数秒后恢复。
3. 关闭练习窗口并马上重新打开。
4. 连续执行两次。

检查：

- [ ] 后台期间不继续判定输入
- [ ] 恢复后可以继续练习
- [ ] 输入不会永久失效
- [ ] 不会重复订阅 MIDI 或麦克风
- [ ] 最后有效进度已经保存
- [ ] 不会显示上一轮遗留的反馈动画
- [ ] 不会在关闭窗口后继续发声
- [ ] 返回曲谱库后不残留虚拟钢琴或琴键高亮

## 7. MIDI 真机测试

必须使用 Apple Vision Pro 和真实 MIDI 钢琴。

### 基本输入

- [ ] 第一个音不会丢失
- [ ] 正确单音可以推进
- [ ] 完整和弦可以推进
- [ ] 错音不会被判为成功
- [ ] 同一个输入不会被处理两次

### 快速停止与重新开始

连续执行 5 次：播放或练习中停止，然后立即重新开始。

- [ ] 没有持续音或重复音
- [ ] 旧 note-off 不会关闭新一轮音符
- [ ] 上一轮事件不会推进新一轮 step
- [ ] App 不崩溃

### 断开与重连

- [ ] 练习中断开设备不会崩溃
- [ ] UI 能显示设备不可用
- [ ] 重连后无需重启 App 即可继续
- [ ] 重连后不会产生重复事件

## 8. 麦克风真机测试

必须在 Apple Vision Pro 上执行。

### 基本识别

- [ ] 正确单音可以推进
- [ ] 错音不会被判为成功
- [ ] 无声音时不会自动推进
- [ ] 麦克风权限被拒绝时不崩溃，并显示明确状态

### 旧结果隔离

1. 在一个 step 上持续发声。
2. 立即停止练习或切换输入模式。
3. 马上进入新 step 或新 Session。

检查：

- [ ] 上一轮分析结果不会作用到新 step
- [ ] 旧声音不会让新 Session 自动成功或失败
- [ ] 重新开启麦克风后仍能正常识别

## 9. MusicXML 导入与删除

至少准备：

- 一个普通 `.musicxml`
- 一个 `.mxl`
- 两个同名但内容不同的曲谱

### 导入

- [ ] 导入后立即出现在曲库
- [ ] 重启 App 后曲目仍然存在
- [ ] 两个同名曲目都能显示
- [ ] 同名曲目不会共享错误的练习进度
- [ ] 导入失败不会留下半成品曲目

### 删除

1. 为测试曲目产生练习进度。
2. 删除曲目。
3. 重启 App。

检查：

- [ ] 曲目不会重新出现
- [ ] 对应练习进度被清理
- [ ] 其他曲目和进度不受影响

## 10. 最小 UI 与体验检查

- [ ] “开始练习”不遮挡试听与拖动进度控件
- [ ] 曲名、作曲家、试听控件和按钮不被裁切
- [ ] “开始练习”和“返回曲库”可点击
- [ ] 核心按钮有文字，不是无法理解的纯图标
- [ ] 练习反馈不会遮住谱面或阻止输入
- [ ] 错误反馈没有羞辱性或惩罚性表达
- [ ] 开启 Reduce Motion 后没有持续的大幅运动
- [ ] 曲库窗口在 min/ideal/max 尺寸下 Ornament 与主内容均不裁切关键事实或唯一按钮
- [ ] 最大 Dynamic Type 下事实可换行，VoiceOver 能读出状态、计数与单位
- [ ] Reduce Motion 下 never 状态为静态图形；Differentiate Without Color 下稳定/练习中仍有文字与图标区分

### 曲库连续切换

分别使用左右按钮、水平拖拽和 VoiceOver adjustable action 执行：

1. 在 200 ms 内连续切换至少三首，包含一首小曲谱和一首大曲谱。
2. 选择最终曲目后立即点击“开始练习”。
3. 选择曲目后立即离开曲库，再重新进入。

检查：

- [ ] 每次选择后唱片、曲名和来源立即更新，不等待磁盘写入
- [ ] 快速连续切换时动画无明显停顿，曲库不会调用 resolver、prepare 或 ARGuide
- [ ] 只有按钮传入的内存 song ID 在练习窗口进入 ready 或 failure
- [ ] 离开曲库后不继续保存或发布旧选择结果
- [ ] 开启 Reduce Motion 后仍满足上述状态与取消规则

## 11. 小规模用户测试

自动化测试只能证明功能按规则运行，不能证明练习体验容易理解。可先找 3–5 位用户完成一次短测试。

用户任务：

1. 选择一首曲子。
2. 点击唯一的“开始练习”按钮。
3. 开始练习。
4. 故意弹错几次。
5. 完成一轮。
6. 返回曲谱库并继续上次练习。

只观察四个问题：

- [ ] 用户能否自己找到练习入口
- [ ] 用户是否理解曲库 selection 与“开始练习”的关系
- [ ] 弹错后的反馈是否让用户愿意再次尝试
- [ ] 用户是否理解“继续练习”和“从头练习”的区别

若多位用户在同一环节卡住，应优先检查该环节的文案、层级和操作路径。

## 测试记录模板

```text
测试日期：
测试人员：
Xcode：
visionOS：
设备/Simulator：
MIDI 设备：

1. 构建与自动化：Pass / Fail / Not Run
2. 曲谱库与试听：Pass / Fail / Not Run
3. 练习设置：Pass / Fail / Not Run
4. 正常与单手练习：Pass / Fail / Not Run
5. 保存与恢复：Pass / Fail / Not Run
6. 后台与窗口生命周期：Pass / Fail / Not Run
7. MIDI：Pass / Fail / Not Run
8. 麦克风：Pass / Fail / Not Run
9. MusicXML 导入与删除：Pass / Fail / Not Run
10. 最小 UI：Pass / Fail / Not Run
11. 小规模用户测试：Pass / Fail / Not Run

发现的问题：
1.
2.

本次测试结论：
```
