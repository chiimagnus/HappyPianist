# 钢琴家盲听与演奏验证协议

状态：`pending evidence`。本协议只定义招募、采样、匿名化和评分方法；在完成独立评审并保存聚合记录前，不产生专业演奏、听感或可练习性的通过结论。

## 曲目与样本

每轮以已授权、可追溯的 score fixture 或录制片段建立匿名样本包，并至少覆盖下列曲风与织体：

| 覆盖 | 最少样本要求 | 关注点 |
| --- | --- | --- |
| Bach | 一段复调或多声部片段 | 声部独立性、articulation、织体清晰度 |
| Mozart 或 Haydn | 一段古典奏鸣曲式片段 | timing、平衡、风格与可练习性 |
| Beethoven | 一段有动态或踏板变化的片段 | dynamic contour、pedal、结构张力 |
| Chopin | 一段旋律与伴奏分层片段 | voicing、rubato、pedal 与连贯性 |
| Debussy 或 Ravel | 一段色彩和声片段 | pedal、音色层次与风格可信度 |
| Liszt 或 Rachmaninoff 类织体 | 一段高密度、宽音域或和弦织体 | 和弦平衡、timing、可练习性 |

同一曲目应同时保存 score revision、渲染/输出版本、设备与音频路由。未获授权的第三方录音、曲谱或身份信息不得进入样本包。

## 盲法与匿名化

1. 协调人生成随机 sample ID 与评审顺序；评分者只看到 sample ID、必要的演奏任务和统一播放条件。
2. 评分者不得获知系统模式、生成条件、预期结论、参与者身份或其他评分者的结果；需要比较时，条件标签在评分锁定后才解盲。
3. 参与者只记录匿名 participant ID、经验分层、设备类别、OS、输入/音频路由和 app/score/rubric version。联系方式、原始录音、逐音输入与可识别自由文本与评分表分离保存，并按授权处理。
4. 同一参与者的样本不连续出现；缺失音频、不同版本或无法确认输出条件的样本标记 `insufficient`，不计为低分或失败。

## 评分 rubric

每位钢琴家独立对每个有效样本填写每项评分、`insufficient` 标记与简短理由；评分刻度、锚点与 rubric version 必须在收样前冻结。

| 维度 | 评分对象 | 不能由什么替代 |
| --- | --- | --- |
| fidelity | 音高、节奏、记谱结构和显式演奏记号是否忠实 | 自动化事件相等性 |
| timing | 脉冲、相对时值、和弦同步与节奏弹性 | 单一 latency 数值 |
| voicing | 旋律、内声部与低音的层次 | 总体音量 |
| pedal | 踏板进入、释放、混响清晰度与风格适配 | controller 是否存在 |
| articulation | 连、断、重音、重复音和触键轮廓 | note-on/note-off 数量 |
| style plausibility | 与所覆盖曲风相符的乐句、力度与表达可信度 | 评分者个人偏好 |
| 可练习性 | 反馈、速度、听觉结果是否足以让钢琴家完成指定练习 | 点击或播放次数 |

## 执行与结论

每轮开始前登记样本清单、版本、评分 rubric、匿名化方式和异常处理规则。完成后只报告分曲目类别与分维度的聚合结果、有效/insufficient 样本数、缺失原因和版本；不得以单个 demo、单位评审或未执行清单宣布通过。

记录模板：

```text
状态：pending / passed / blocked
study / sample batch ID：
app / score / rubric version：
匿名 participant IDs 与经验分层：
设备、OS、输入/音频路由：
曲目覆盖与 sample IDs：
每维度有效 / insufficient 样本数与聚合结果：
盲法、随机顺序与解盲时间：
异常、缺失和证据位置：
```
