# 验证与测试

本页说明每层测试能证明什么，以及如何记录不能由自动化替代的证据。能力措辞和 `pending` / `blocked` 定义以[质量边界](piano-performance-quality.md)为准。

## 日常命令

```bash
make doctor
make destinations
make build:simulator
make test:simulator
swift test --package-path Packages/HappyPianistCore
```

`make test:simulator` 会限制 Simulator boot（180 秒）、destination 查找（60 秒）和整次 action（900 秒），并开启单测试 timeout（默认 120 秒、最大 300 秒）。`make test:device` 使用相同的 destination 和单测试 timeout。Simulator 超时会终止独立进程组，并把不含 app container 的诊断写至 `.build/TestResults`。受控异步测试必须使用有界等待（如 `TestAsyncWait`），不得使用无界 `Task.yield()` 轮询；需要调整时只覆盖相应 Make 变量，不得移除边界。

`make clean` 会清理 AVP scheme。`build-for-testing`、语法检查或 Linux harness 都不能替代实际 `xcodebuild test`。

Makefile 默认使用 `XCODEBUILD_FLAGS=-quiet`，避免日常构建刷屏；需要完整日志时传入 `XCODEBUILD_FLAGS=`。

## 证据分层

| 层级 | 可证明 | 不能替代 |
| --- | --- | --- |
| Swift Testing / fixture | 纯模型、reducer、range、matcher、alignment、assessment、coaching | Apple 平台、硬件、听感、教学效果 |
| `xcodebuild test` / Simulator | Swift 6、target 集成、生命周期、资源协议、持久化 | 真机 latency、追踪精度、音频听感 |
| Apple Vision Pro 真机 | MIDI、麦克风、手部、audio route 的 latency/jitter/恢复 | 钢琴家审美、教学有效性 |
| 钢琴家盲评 | 回放 fidelity、voicing、pedal、articulation、style | 用户演奏评价正确性 |
| 教师标注 / coaching 研究 | assessment 一致性和指导前后改善 | 代码正确性、平台可靠性 |

每次实际运行记录 commit、Xcode、OS、destination、命令、退出结果、score/fixture revision 和适用的 calibration。跳过的私有 SoundFont、CoreML 或 SeedScores 资源测试不等于资源集成通过。

会替换既有 App key window 的 Book/Library 原生测试统一放在 `NativeBookWindowTests` 的 serialized suite 中，完成后恢复原 root 与窗口限制。Xcode 的单 simulator destination 不等于 Swift Testing 的函数串行；普通纯值和 ViewModel 测试无需因此串行化。只使用现有指定 AVP，不创建验证设备。曲库与练习页缘真实点击仍需单独记录，不能用 VM 方法调用代替。真实曲库测试读取当前用户已有恢复位置，不假设 progress 为空，也不删除用户记录来满足断言。

## 必须覆盖的自动化边界

- MusicXML parser 到 `PreparedPractice`、14 种标准 note type、缺失/非标准 type 的 typed failure，以及 measure spans；
- source/performed identity、range/loop、MIDI/音频输出 reset、generation、interruption 与无残留发声；
- observation 的 capability、unknown/insufficient、alignment、assessment、单一 coaching action；
- recording、session、progress 的 checkpoint、flush-before-teardown、恢复与持久化边界；
- 完整 PreparedPractice 到双页分页的 step/measure 导航、局部范围、末步恢复、休止时的 autoplay、暂停、重练和换谱；分页几何不因演奏位置或范围改变。保存失败保留会话与原进度，取消返回不卸载谱面。原生窗口测试使用生产 Book View，不代替完整 Practice 宿主、Immersive 或真机验收；
- 共用翻页状态覆盖同双页仅更新高亮、相邻正反向、大跳直接到达、翻动期间新目标取代、换谱与旧 completion 拒绝；真实 transport 的休止边界与暂停不得产生第二导航时钟；
- 练习手动翻页移动正式会话位置：有音符页、纯休止页、练习范围裁切、旧曲身份拒绝、实际 transport 重建和旧 poll 拒绝、明确暂停与继续、文件 checkpoint；直接定位取消逐步前进的延迟高亮，休止页在原 120ms 过渡之后仍不点亮未来音符；跳页不制造小节结果，导航不重建 PagePlan；
- AI 请求取消、乱序响应、generation 隔离与 teardown；Qwen Companion 专用 schema、固定 model identity、服务端 A/B 双顺序聚合/semantic mapping 与失败不回退；Aria v3 strict schema、CC64 输入、single-flight busy 与共享 350ms discovery+HTTP deadline；

### 示范手纯值 Gate

`HandMotionCorpus/manifest.json` 覆盖音阶、琶音、密集和弦、重复音、大跳进、跨手和 pause/range 用例。`PianoHandMotionQualityTests` 对运行期同一纯值 clip builder 断言每个 fixture/occurrence 的 coverage、P95 接触残差不大于 5 mm、P95 时序误差不大于 50 ms、最大时序误差不大于 100 ms、单位四元数和无 collision 降级；builder 专属测试覆盖首击准备、held contact 与过渡约束。

这只验证程序化 skeleton，不能证明 Blender 网格真机接触、遮挡、舒适度或音画同步；缺资产时回退键面贴片必须仍可见。

## 手工与真机记录

日常 smoke 至少检查：导入/恢复和冲突、单一练习入口、range/tempo/loop、正确/错误/未知分流、切换或断开输入输出、stop/seek/后台/窗口关闭后的无残留发声、progress 脱敏、界面文字及谱面可读性。

真机按独立设备、OS、route、score revision 与 calibration 记录 p50/p95/p99 latency/jitter、miss/false-positive/stuck-note、断连/中断/route change 恢复。无可靠同步、tracking 或 onset 的样本标 `insufficient`，不计为 miss；仅保存聚合桶与样本数，不保存原始 MIDI、音频、手部帧、序列号或绝对路径。

涉及专业表述时，使用已授权材料：钢琴家盲评在收样前冻结 rubric 并随机化 sample；教师标注至少两名独立盲标；coaching 研究冻结目标、before、action、完成条件、对照与练习剂量，并报告迁移和副作用。

## 证据状态与模板

| 证据 | 状态 | 不能替代 |
| --- | --- | --- |
| Simulator 自动化 suite | `failed`：2026-09-30，基于 `3ba1f4e`；visionOS 27.0 新建 Apple Vision Pro Simulator 上 1033 tests，1022 通过、11 失败、0 skipped。失败集中在 hand rig / hand motion / local sampler / demonstration hands；`make build:simulator` 通过 | 真机、听感、教师或教学证据 |
| Book Flow / 双页 / 翻页集成 | `passed`：2026-10-01，项目清理前，Xcode 27 beta、visionOS 27.0；现有 Apple Vision Pro（28DABA38…）上实际定向 174/174、0 skipped，含 serialized 原生窗口与 live 纸面动画检查；build 通过。实际 Library 页缘和 Practice 手动/恢复/休止跨页截图已检查 | 真实页缘点击、真机 Immersive 与听感；定向成功不等于全量通过 |
| 全项目专项清理 / 系统字体 | `passed`：2026-10-01，现有同一 AVP 上实际定向 191/191、0 failed/skipped，含 4 个串行原生窗口测试、guide/反馈/角色生命周期；`.build/TestResults/Project-Cleanup-Verified-Gate-1790832767.xcresult`。macOS package 257/257，包含字体来源、几何缩放与粗斜体检查；`make build:simulator` 通过。标准视觉 golden 按原生 caption 字体更新，图像尺寸保持 351×229 | 完整 target、真实页缘点击、真机追踪及听感；不修改系统控件的原生行为 |
| 练习手动翻页 / 曲库入口 | `passed`：2026-10-01，现有同一 AVP 定向 194/194、0 failed/skipped，含原生窗口、文件保存与真正 transport 重新加载；`.build/TestResults/Manual-Page-Turn-Verified-1790834502.xcresult`，`make build:simulator` 通过 | 用户真实按钮操作与卷页视觉另行验收；不以 VM 导航替代点击 |
| 清理后完整 Simulator target | `failed`：2026-10-01，同一 AVP 上 1059 tests，1048 通过、11 失败、0 skipped；`.build/TestResults/Project-Cleanup-Full-1790832858.xcresult`。11 个失败 ID 全部匹配原基线，仍为 hand rig/motion/local sampler/demonstration hands；本次没有新增失败。Recorder 调度敏感测试本轮通过，未宣称修复 | 不能声称全量通过，也不能用定向通过掩盖原失败 |
| 本轮完整 Simulator target | `failed`：2026-10-01，执行前 HEAD `e16d3fe1` 加本轮测试串行收口；1062 tests，1050 通过、12 失败、0 skipped，`.build/TestResults/BookFlow-P3-full-1790804842.xcresult`。11 个失败 ID 与 `3ba1f4e` 基线一致；另首次观察到 `recorderSemanticEventsReturnBeforeSlowPersistenceCompletes()` 失败，其测试及 Recorder 实现与基线完全相同，定向复核 1/1 通过。该测试用固定 20 次 yield 观察调度完成，结果具有调度敏感性；不将其冒称已修复 | 不能声称全量通过，也不将旧 rig/资源或未改动 Recorder 的偶发失败归因于翻页 |
| Qwen / Companion 定向回归 | `passed`：2026-09-30；Qwen 已固定为本地 NF4 4-bit，Python Qwen/Stage A/service-E2E 定向回归 26/26；Stage A 固定 120 cases，延迟仅记录；服务级 E2E 固定 60 cases 双跑均为 0 action mismatch、11/11 Aria 生成成功、0 generation failure，生成 MIDI 均通过重解析与 note-on/off 配平；最新 visionOS Simulator 全量 suite 中 Qwen/Companion 相关测试无失败 | `settled_end` 语义质量缺口、Vision Pro 真实设备网络与产品 playback E2E |
| Aria true-streaming P3 probe | `No-Go`：2026-09-30；P2 的 11 个 generating cases 上，oracle-compatible incremental decoder 与最终 `AbsTokenizer.detokenize()` 11/11 完全一致；first complete event median 75.9ms，但安全 `<T>` commit median 820.9ms，3/11 在 full completion 前没有安全 boundary；350ms 内安全 commit 仅 2/11，其中仅 1/11 含 note | 单个完整 token/event 不能替代安全 playable window；当前继续保留 HTTP full-response，不宣称产品实时 streaming |
| 多 exporter 合法 fixture | `blocked evidence` | 内部 fixture、伪造 provenance、不明来源下载 |
| 真机硬件、钢琴家盲评、教师标注、coaching 研究 | `pending evidence` | Simulator bucket、诊断字段、点击次数或单个 demo |

```text
日期：YYYY-MM-DD
commit：
Xcode / OS / device 或 Simulator：
输入与输出 route：
fixture / score revision / calibration：
结果：Pass / Fail / Not Run / pending / blocked
失败步骤与复现：
证据位置：
```
