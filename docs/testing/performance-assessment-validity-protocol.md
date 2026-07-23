# 演奏 assessment 与教师标注一致性协议

状态：`pending evidence`。本协议验证 assessment 是否与独立教师标注一致；自动化 replay、代码覆盖或单次演示都不能替代实际标注语料与结果。

## 标注语料与冻结条件

每轮建立独立的 expert label corpus。每个匿名 take 必须绑定 score revision、plan ID、输入 source/capability、calibration version（如有）、设备/OS、app version、rubric version 与目标带 provenance。语料按曲目、难度、输入模式和有效/降级能力分层抽样，避免将一种设备或单一曲风推广为整体准确率。

至少两位合格教师独立标注，不查看系统结果、其他教师标签或预期结论。评分开始前冻结：

- 维度定义、判定单位（note、chord、measure 或 passage）、边界样例与 `unknown` / `insufficient` 规则；
- rubric version、每维度 target band、provenance（score default、teacher、user confirmed 或 generic approximation）；
- 分层、样本量、聚合方式、inter-rater agreement 指标与通过阈值。

任何改动都创建新的 corpus 或 rubric version；不得用新阈值重写旧结果。

## 分维度标签与系统比较

| 研究维度 | 教师标签 | 对应系统维度 | 结果 |
| --- | --- | --- | --- |
| pitch | 正确、extra、missing 或无法判定 | `exactPitch`、`extraNotes`、`missingNotes` | 分开统计 precision / recall，不能只给总分 |
| timing | onset、相对速度、和弦同步与连续性 | `onset`、`tempoRelativeTiming`、`chordSpread`、`tempoContinuity`、`phraseContinuity` | 分类一致性与连续测量相关性 |
| duration | 音值、release 与连贯性 | `duration`、`release`、`articulation` | 分维度 precision / recall / correlation |
| dynamics | velocity 与 dynamic contour | `velocity`、`dynamicContour` | 分维度相关性与方向一致性 |
| voicing | 声部平衡与旋律突出 | `voicing` | 分维度相关性与错误类型 |
| pedal | 踏板时机与数值 | `pedalTiming`、`pedalValue` | 分维度 precision / recall / correlation |

对离散错误标签记录 confusion matrix、precision、recall、F1 与支持数；对连续量记录预先声明的相关系数、偏差与有效样本数。总体汇总必须同时列出每个分层和维度，不能以总体平均掩盖某个维度或设备的退化。

## unknown、degraded 与 insufficient

教师无法在现有证据下判断时标记 `unknown`；缺少可靠输入、同步或必要 controller 数据时标记 `insufficient`。它们不是真阳性、真阴性、miss 或错误标签，也不得被转写为系统失败。

系统的 `observed`、`degraded`、`notObserved` 与 `insufficient` 必须原样记录。主 precision / recall / correlation 只在双方预先定义为可比较的有效样本中计算；另行报告被排除的原因与数量。若教师标签与系统 evidence status 冲突，保留冲突而非强行归类。

## 一致性、报告与结论

先报告教师之间的 agreement，再解释系统与共识标签的差异。离散标签使用预先指定且适配类别不平衡的 agreement 指标；连续评分使用预先指定的相关/一致性指标。不能在看到结果后挑选最有利的统计方法或阈值。

每个结果文件至少包含：状态（`pending` / `passed` / `blocked`）、corpus/rubric/target version、教师匿名 ID 与经验分层、设备与 capability 分层、每维度的 agreement、precision、recall、correlation、有效/unknown/insufficient 样本数、阈值与证据位置。未完成独立标注或未达到预先绑定的阈值时，能力声明保持 `pending evidence` 或 `blocked`。
