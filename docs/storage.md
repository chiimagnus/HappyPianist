# 存储

HappyPianistAVP 当前使用 Documents 目录中的 JSON 和用户导入文件；不使用 SwiftData。

## 文件布局

| 数据 | 代码 | 默认位置 |
| --- | --- | --- |
| 世界锚点校准 | `WorldAnchorCalibrationStore` | `Documents/piano-worldanchor-calibration.json` |
| 曲库索引 | `SongLibraryIndexStore` | `Documents/SongLibrary/index.json` |
| 用户曲谱 | `SongLibraryImportTransactionService` / `SongFileStore` | `Documents/SongLibrary/scores/` |
| 用户试听音频 | `AudioImportService` | `Documents/SongLibrary/audio/` |
| 曲谱导入事务 | `SongLibraryImportTransactionService` | `Documents/SongLibrary/transactions/<operation-id>/` |
| 练习录制 take | `RecordingTakeStore` | `Documents/TakeLibrary/takes.json` |
| 小节级练习进度 | `FilePracticeProgressRepository` | `Documents/PracticeProgress/progress-v1.json` |
| 可导出诊断日志 | `FileDiagnosticsStore` | `Documents/Diagnostics/diagnostics-YYYY-MM-DD.jsonl` |

bundled MusicXML 和 App 资源来自 bundle，不写入 Documents。

## 曲库

`SongLibraryIndex` 只保存用户导入 entry 与最后选择项。entry 的必填 `scoreFileVersionID` 标识文件版本；非空 index 缺少该字段时按 corruption 处理。bundled entries 由 `BundledSongLibraryProvider` 在启动时扫描后合并，并用 bundle identifier、short version、build version 与资源文件名生成确定性版本 token；缺失的 bundle 字段使用固定 sentinel，App 构建变化会保守地使旧 metadata 失配。

导入流程：

1. `SongLibraryImportTransactionService` 按选择顺序创建 operation，只在复制单个输入时持有短 security-scoped lease，并先写 preparing journal。
2. 输入以 `.partial` 同卷复制、同步并流式计算字节数与 SHA-256，随后原子改为原始安全文件名并写 staged journal；不会增加时间戳或 UUID 后缀。
3. actor 逐 operation 读取最新 index 与目标卷 resource facts。无冲突项先写 resolved journal，再移动到 `scores/` 原名目标并追加带非空 version token 的 entry；冲突项在任何 target/index mutation 前暂停。
4. 用户确认只回传 operation ID；actor 重新分类最新事实。indexed target 先按指纹备份旧文件再用 CAS 保留 song ID、显示名、音频、顺序和最后选择，missing target 直接修复同一 entry，filesystem orphan 备份同名未索引文件后建立新 entry。歧义目标不提供覆盖动作。
5. CAS 或 index 保存失败时仅在 staged/backup/target 指纹仍匹配时恢复确认前文件事实；已经提交但 cleanup 失败的 journal 由下次 bootstrap 幂等收尾。

index 文件缺失、零字节或仅包含空白时视为空库，首次 mutation 会原子写出有效 JSON；非空但无法解码的 JSON 保留原文件并阻塞读取及所有 mutation，禁止按空库继续写入。

每个导入事务目录只允许 UUID operation 目录、`journal.json`、`stage/` 与 `backup/`；`.partial` 只允许出现在 preparing 阶段。journal 只记录相对文件名、operation/song/token 标识、phase 及 staged/backup 指纹；不记录 URL、原始曲谱、错误正文或完整 index。恢复在 bootstrap 读取 index 前运行，删除或覆盖 staged、backup、target 前必须同时核对字节数和 SHA-256；符号链接、未知目录内容、文件身份变化或歧义一律阻塞启动快照发布。

删除用户曲目时同时删除曲谱、绑定音频和对应 song UUID 的练习进度。进度清理失败不回滚已完成的曲目删除。

## 练习进度

`progress-v1.json` 是唯一练习事实文件。当前 schema version 为 2，严格包含显式 `schemaVersion` 与必填的 `songs`、`scoreMetadata`、`sessions` 三个数组；缺版本的现有文件按 version 1 读取，并在下次写入时升级，未知版本 fail closed。songs 按 `song UUID + score revision digest` 区分小节事实版本；metadata 按 `song UUID + entry version token + score revision` 记录成功准备时的曲谱结构；session 按稳定 `song UUID` 保留跨 revision 历史。文件不存在表示全新空 store；非空文件缺少任一数组、字段非法或 JSON 损坏都返回 corruption。

保存内容：

- 当前轮配置
- 恢复点
- 源小节事实
- 小节级 performance maturity、metric summaries、sample counts、rubric version 与 evidence coverage
- 更新时间
- 曲谱版本 token、revision、唯一 source measure 总数与准备时间
- 原始 session identity、开始/结算时间、本地练习日、最后 checkpoint、window/active duration 与 termination

不保存：

- SwiftUI 展示状态
- cue、summary、hotspot 或 restoration map
- target profile、逐音 alignment/assessment evidence、`MusicalIssue`、coaching decision 或 before/after 关联
- `PianoOutputMeasurementMetadata`、真机 latency/jitter 样本、设备序列号或音频路由显示名
- RealityKit entity 状态
- AI 文案或生成内容
- 原始逐帧麦克风、MIDI 或手部数据

repository 的 progress、metadata 与 session mutation 在 actor 内读取磁盘最新文档，只更新对应 concern 并保留另外两类数组；删除曲目同时删除三类记录。临时 IO 失败与 corruption 使用不同 typed result；corruption 保留原文件并拒绝 mutation，只有用户确认后才把损坏文件备份并创建空 store，备份失败不得覆盖原文件。exact progress 重复记录使用共享的确定性 order 选择，避免数组顺序改变恢复结果。

`PracticeLaunchViewModel` 仅在 `PreparedPractice` 通过 steps/spans 校验且 applicator 确认安装成功后，写入 entry token、score revision、唯一 source measure 数量与准备时间。repeat occurrence 使用同一个 source identity，只计一次。ready publication 不等待 metadata 文件 IO；写入失败保留已安装 session 并记录不含路径/measure 列表的 typed warning。已经成功 apply 形成的 immutable metadata commit 不因随后切歌或 scene inactive 而取消。

`PracticeProgressCoordinator` 串行化 checkpoint，并用 song identity、round generation 与 progress generation 防止旧任务覆盖新状态。back、background、session replacement 和 completion 必须等待 flush。

`PracticeSessionRecorder` 是 composition root 持有的 actor。首次进入 guiding 时创建同一 window visit 唯一 session；scene、guiding、设置、round 和退出边界立即 checkpoint，连续 active guiding 最多每 30 秒一次。周期写失败保留最新待写记录供下一边界重试。正常返回等待 final flush；读取遗留 `.open` session 时 repository 只结算到 `lastPersistedAt` 并标记 `recoveredAfterInterruption`。


## 诊断日志

`AppDiagnosticsReporter` 是业务代码的统一诊断入口。每个事件先进入 `os.Logger`；只有 `persistence == .exportable` 的低频事件才追加到每日 JSONL 文件。实时路径通过同步 `recordSystem` 记录不可导出的系统事件，不直接持有 `Logger`，也不触发文件 IO。

规则：

- 默认保留7 个日历日，App 启动、写入与导出前执行清理。
- 导出 ZIP 固定包含 `diagnostics.jsonl`、`diagnostics.txt`、`environment.txt`。
- 导出由用户主动触发，不自动上传。
- 文件引用只保存文件名和 App 内相对路径。
- 不保存原始曲谱、逐音 MIDI、音频样本、手部帧、AI 正文、密钥、认证头或绝对路径。
- 输出可靠性只记录低频聚合 bucket；可选 `PianoOutputMeasurementMetadata` 仅允许 calibration ID/version、sample count、设备/OS 与枚举 audio route，且不是 `progress-v1.json` 的字段。
- 写入失败只影响可导出副本，系统日志仍记录失败；不得阻止曲库或练习流程。

## 录制库

`RecordingTakeStore` 使用 ISO 8601 日期编码，将全部 takes 原子写入 `takes.json`。当前 schema v2 为每个 take 保存来源能力、曲谱身份、时钟映射、延迟与校准版本；可评价的 channel voice 事件同时保存原始 `PerformanceObservation` 和仅供 MIDI 回放的 7/14-bit 投影。旧 JSON 缺少 schema、metadata 或 observation 时在读取边界直接解码为当前模型，不建立第二套 legacy store，也不丢弃原事件。

take 不保存设备显示名、绝对路径、原始曲谱、音频样本或手部帧。metadata 与 observation 内的 source/clock/calibration/contact 标识在编码和解码边界都拒绝路径、URL、XML 与超长内容。MIDI 导出由 `RecordingMIDIExportService` 临时生成，不自动保存在 Documents。

## 清理

重置 AVP 用户数据时，根据需要清理：

```text
Documents/SongLibrary/
Documents/TakeLibrary/
Documents/PracticeProgress/
Documents/Diagnostics/
Documents/piano-worldanchor-calibration.json
```

不要删除 App bundle 资源，也不要把测试 fixture 当作用户数据。
