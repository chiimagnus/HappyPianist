# 工作流

## 进入仓库后的判断顺序
1. 判定改动运行面：`LonelyPianist` / `LonelyPianistAVP` / `piano_dialogue_server`。
2. 读取入口文档：根 `README.md`、子目录 `README.md`、`AGENTS.md`、对应模块页。
3. 若涉及 Dialogue，先确认 Python 服务可用（`/health`）。
4. 若涉及 AVP Step 3，先确认是否已有“已导入曲目 + 已保存校准”。

## 标准开发循环
| 阶段 | 动作 | 产物 | 关注点 |
| --- | --- | --- | --- |
| 需求定位 | 锁定模块边界与数据契约 | 变更清单 | 避免跨层混改 |
| 实现 | 按 MVVM + Services 修改 | 代码变更 | View 不承载业务流程 |
| 验证 | 跑对应测试与脚本 | 测试结果 | 覆盖权限/设备边界 |
| 文档同步 | 更新 deepwiki/README | 可追溯知识层 | 代码事实优先 |

## 按运行面的实施路径
| 运行面 | 推荐入口 | 默认验证 |
| --- | --- | --- |
| macOS | `ViewModels/LonelyPianistViewModel.swift` + `Services/` | macOS `xcodebuild test` + 手工映射/录制 |
| AVP | `Views/ContentView.swift` + `ViewModels/ARGuideViewModel.swift` + `ViewModels/Library/SongLibraryViewModel.swift` | AVP tests + Step 1/2/3 冒烟 |
| Python | `server/main.py` + `server/protocol.py` + `server/inference.py` | `/health` + `test_client.py` + `scripts/test_generate.py` |

## AVP 三步流协作约束
- Step 1（校准）改动通常会联动：`WorldAnchorCalibrationStore`、`ARTrackingService`、`ARGuideViewModel`。
- Step 2（选曲）改动通常会联动：`SongLibraryViewModel`、`SongFileStore`、`SongLibraryIndexStore`。
- Step 3（练习）改动通常会联动：`PracticeSessionViewModel`、`PressDetectionService`、Overlay controllers。

## 文档同步流程
- 业务旅程有变化：先改 `business-context.md`，再更新技术页路由。
- 数据/状态流有变化：更新 `data-flow.md` 与相关模块页。
- 配置/权限变化：更新 `configuration.md` 与 `troubleshooting.md`。

## 变更清单（高频联动）
- 协议改动：Swift `DialogueNote` ↔ Python `protocol.py` 同步。
- AVP 曲库格式改动：`SongLibraryEntry` ↔ `SongLibraryIndexStore` ↔ 迁移逻辑同步。
- 校准字段改动：`StoredWorldAnchorCalibration` ↔ `WorldAnchorCalibrationStore` ↔ 定位流程同步。

## 评审关注点
- 是否仍保持依赖注入与单向数据流。
- 是否在失败路径有明确状态回落与用户提示。
- 是否补齐对应测试（尤其状态机与存储一致性）。

## Coverage Gaps
- 目前缺少 CI 自动化门禁与统一发布流水线文档。

## 来源引用（Source References）
- `AGENTS.md`
- `README.md`
- `LonelyPianist/README.md`
- `LonelyPianistAVP/README.md`
- `piano_dialogue_server/README.md`
- `LonelyPianistAVP/Views/ContentView.swift`
- `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift`
- `LonelyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift`
- `piano_dialogue_server/server/main.py`
- `.xcodebuildmcp/config.yaml`
