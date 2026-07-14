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

`SongLibraryIndex` 只保存用户导入 entry 与最后选择项。entry 的可选 `scoreFileVersionID` 标识文件版本；旧 index 缺少该字段时按 `nil` 解码。bundled entries 由 `BundledSongLibraryProvider` 在启动时扫描后合并，并用 bundle identifier、short version、build version 与资源文件名生成确定性版本 token；缺失的 bundle 字段使用固定 sentinel，App 构建变化会保守地使旧 metadata 失配。

导入流程：

1. `SongLibraryImportTransactionService` 按选择顺序创建 operation，只在复制单个输入时持有短 security-scoped lease，并先写 preparing journal。
2. 输入以 `.partial` 同卷复制、同步并流式计算字节数与 SHA-256，随后原子改为原始安全文件名并写 staged journal；不会增加时间戳或 UUID 后缀。
3. actor 逐 operation 读取最新 index 与目标卷 resource facts。无冲突项先写 resolved journal，再移动到 `scores/` 原名目标并追加带非空 version token 的 entry；冲突项在任何 target/index mutation 前暂停。
4. 用户确认只回传 operation ID；actor 重新分类最新事实。indexed target 先按指纹备份旧文件再用 CAS 保留 song ID、显示名、音频、顺序和最后选择，missing target 直接修复同一 entry，filesystem orphan 备份同名未索引文件后建立新 entry。歧义目标不提供覆盖动作。
5. CAS 或 index 保存失败时仅在 staged/backup/target 指纹仍匹配时恢复确认前文件事实；已经提交但 cleanup 失败的 journal 由下次 bootstrap 幂等收尾。

只有 index 文件缺失时视为空库；零字节、空白或无法解码的 JSON 都保留原文件并阻塞读取及所有 mutation，禁止按空库继续写入。

每个导入事务目录只允许 UUID operation 目录、`journal.json`、`stage/` 与 `backup/`；`.partial` 只允许出现在 preparing 阶段。journal 只记录相对文件名、operation/song/token 标识、phase 及 staged/backup 指纹；不记录 URL、原始曲谱、错误正文或完整 index。恢复在 bootstrap 读取 index 前运行，删除或覆盖 staged、backup、target 前必须同时核对字节数和 SHA-256；符号链接、未知目录内容、文件身份变化或歧义一律阻塞启动快照发布。

删除用户曲目时同时删除曲谱、绑定音频和对应 song UUID 的练习进度。进度清理失败不回滚已完成的曲目删除。

## 练习进度

`progress-v1.json` 仍是唯一练习事实文件，包含 `songs` 与 `scoreMetadata` 两个数组。前者按 `song UUID + score revision digest` 区分事实版本；后者按 `song UUID + entry version token + score revision` 记录成功准备时的曲谱结构 metadata。旧文件只有 `songs` 或缺少数组时无需 migration 即可读取。

保存内容：

- active round configuration
- resume point
- source-measure facts
- 更新时间
- 曲谱版本 token、revision、唯一 source measure 总数与准备时间

不保存：

- SwiftUI presentation state
- cue、summary、hotspot 或 restoration map
- RealityKit entity 状态
- AI 文案或生成内容
- 原始逐帧麦克风、MIDI 或手部数据

repository 的 progress 与 metadata mutation 在 actor 内读取磁盘最新文档，只更新对应 concern 并保留另一数组；删除曲目同时删除两类记录。损坏或不受支持的数据返回明确错误、保留原文件并拒绝所有 mutation，不再隔离后按空文档覆盖。exact progress 重复记录使用共享的确定性 order 选择，避免数组顺序改变恢复结果。

`PracticeLaunchViewModel` 仅在 `PreparedPractice` 通过 steps/spans 校验且 applicator 确认安装成功后，写入 entry token、score revision、唯一 source measure 数量与准备时间。repeat occurrence 使用同一个 source identity，只计一次。ready publication 不等待 metadata 文件 IO；写入失败保留已安装 session 并记录不含路径/measure 列表的 typed warning。已经成功 apply 形成的 immutable metadata commit 不因随后切歌或 scene inactive 而取消。

`PracticeProgressCoordinator` 串行化 checkpoint，并用 song identity、round generation 与 progress generation 防止旧任务覆盖新状态。back、background、session replacement 和 completion 必须等待 flush。


## 诊断日志

`AppDiagnosticsReporter` 是业务代码的统一诊断入口。每个事件先进入 `os.Logger`；只有 `persistence == .exportable` 的低频事件才追加到每日 JSONL 文件。

规则：

- 默认保留7 个日历日，App 启动、写入与导出前执行清理。
- 导出 ZIP 固定包含 `diagnostics.jsonl`、`diagnostics.txt`、`environment.txt`。
- 导出由用户主动触发，不自动上传。
- 文件引用只保存文件名和 App 内相对路径。
- 不保存原始曲谱、逐音 MIDI、音频样本、手部帧、AI 正文、密钥、认证头或绝对路径。
- 写入失败只影响可导出副本，系统日志仍记录失败；不得阻止曲库或练习流程。

## Take library

`RecordingTakeStore` 使用 ISO 8601 日期编码，将全部 takes 原子写入 `takes.json`。MIDI 导出由 `RecordingMIDIExportService` 临时生成，不自动保存在 Documents。

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
