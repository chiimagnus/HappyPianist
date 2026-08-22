# 钢琴演奏与专业质量边界

本页是产品能力措辞与证据门的唯一入口。代码证明规则存在，不能单独证明听感、真机可靠性、评价有效性或教学效果。

## 当前可作的表述

HappyPianist 提供 MusicXML 驱动的回放、按输入 capability 裁剪的练习观察、客观的小节级事实，以及一个有范围和完成条件的练习动作。

不得宣称钢琴家级示范、专业评分、教师替代、所有 MusicXML 无损解释，或三种输入能产生等价证据。参考回放是确定性谱面解释，AI 对弹是用户选择后端产生的运行期创意响应，两者都不是评分基准。

| 输入 | 可评价 | 不能推导 |
| --- | --- | --- |
| Bluetooth MIDI | pitch、onset、release、velocity、controller、polyphony | hand、finger、姿势 |
| 定向麦克风 | 目标音集合、有限 onset/confidence | 逐音 release、velocity、复杂复调、完整踏板 |
| 手部接触 | 键位、接触生命周期、hand/finger、估算 velocity | 未经真机验证的精确力度、姿势质量、踏板 |

unknown、低置信度、`insufficient` 或 degraded capability 必须保留其语义，不能展示成用户错误；完整的数据边界见[数据流](data-flow.md)。

## 能力门

| 能力 | 当前允许措辞 | 必需证据 |
| --- | --- | --- |
| CG-001 乐谱忠实示范 | 已覆盖语义的可审查 MusicXML 驱动示范 | 合法多 exporter corpus、真机输出、钢琴家盲评 |
| CG-002 MIDI 演奏评价 | capability-aware 客观指标 | 真机 MIDI 与独立教师标注一致性 |
| CG-003 表现力虚拟琴 | 版本化校准映射接触速度到 velocity | 分设备 latency/jitter、可靠性、钢琴家听感 |
| CG-004 专业虚拟指导 | 基于证据选择一个可复测动作 | assessment validity、coaching before/after 研究 |

四项目前均为 `pending evidence`；缺少合法语料、硬件或参与者授权时为 `blocked evidence`。只有同一 app/score/rubric 或 calibration version 的所有必需层均完成且复核，才能标记 `passed`。自动化不能替代真机、盲评、教师标注或研究。

运行方式、真机协议和记录模板见[测试](testing.md)。
