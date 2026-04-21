# 工作流

## 进入仓库后的判断顺序
- 先确定改动落在哪条运行面：`LonelyPianist`（macOS）/`LonelyPianistAVP`（visionOS）/`piano_dialogue_server`（Python）。
- 先读入口文档：根 `README.md` -> 子目录 `README.md` -> `AGENTS.md` -> 对应模块页。
- 涉及跨进程能力（Dialogue）时，先确认本地 Python 服务是否可运行。

## 开发循环
| 阶段 | 动作 | 产物 | 注意事项 |
| --- | --- | --- | --- |
| 需求定位 | 锁定运行面与模块边界 | 改动范围清单 | 避免跨层混改 |
| 实现 | 按 MVVM + Services 修改 | 代码与模型变更 | View 不承载业务流程 |
| 验证 | 运行对应 `xcodebuild test`/脚本 | 测试结果与手工验收 | 权限与设备条件要纳入验证 |
| 文档同步 | 更新 deepwiki 与 README（必要时） | 可追溯知识层 | 优先以代码事实修正文档 |

## 按模块 / 产品线的工作方式
| 范围 | 先看哪里 | 默认验证 | 关键边界 |
| --- | --- | --- | --- |
| macOS Runtime/Mapping/Recorder | `LonelyPianist/ViewModels` + `Services` | macOS tests + 手工映射回放 | Accessibility、MIDI 输入/输出 |
| Dialogue | `Services/Dialogue` + `server/` | WS 健康与 test_client | 协议字段与状态机一致性 |
| AVP 引导 | `LonelyPianistAVP/AppModel` + `ViewModels` + `Services` | AVP tests + 沉浸式手工流程 | 校准与手部追踪 |

## 文档同步工作流
- 产品语义变化时先更新 `business-context.md`，再更新对应技术页链接。
- 技术事实变化时优先更新模块页与 `data-flow.md`/`configuration.md`。
- 若发现“文档与代码冲突”，以代码为准并显式记录 Coverage Gaps。

## 构建、测试与发布工作流
- 本地验证基线：
  - `xcodebuild test`（macOS / AVP）
  - `python -m uvicorn ...` + `/health`
  - `server/test_client.py`
- 发布形态：
  - App 主要通过 Xcode target 管理；
  - 仓库内未见正式 CI/release workflow。

## 变更清单
- 修改协议时同步：`LonelyPianist/Models/Dialogue`、`WebSocketDialogueService`、`server/protocol.py`。
- 修改持久化模型时同步：Entity + Repository + ModelContainer schema。
- 修改 AVP 校准或引导逻辑时，联动检查 `AppModel`、`PracticeSessionViewModel`、RealityKit overlay。

## 协作与评审关注点
- 优先检查是否保持依赖注入与单向分层，不引入隐藏全局状态。
- 关注高风险聚合点：
  - `LonelyPianistViewModel.handleMIDIEvent`
  - `DialogueManager`
  - `MusicXMLParser` 时间线逻辑
  - `DialogueManager` 状态机
- 评审中避免仅看 UI；必须确认数据契约与状态转换一致。

## 示例片段
```bash
# macOS 本地测试
xcodebuild test \
  -project LonelyPianist.xcodeproj \
  -scheme LonelyPianist \
  -destination "platform=macOS"
```

```bash
# Python 服务 + 健康检查
cd piano_dialogue_server
source .venv/bin/activate
python -m uvicorn server.main:app --host 127.0.0.1 --port 8765
curl -s http://127.0.0.1:8765/health
```

## Coverage Gaps
- 当前未见仓库内 CI workflow，无法描述“PR 自动门禁”的真实执行链。
- AVP 自动化运行对本地 simulator 环境耦合较高，跨机器稳定性需额外治理。

## 来源引用（Source References）
- `AGENTS.md`
- `README.md`
- `LonelyPianist/README.md`
- `LonelyPianistAVP/README.md`
- `piano_dialogue_server/README.md`
- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Services/Dialogue/DialogueManager.swift`
- `LonelyPianistAVP/AppModel.swift`
- `LonelyPianistAVP/ViewModels/PracticeSessionViewModel.swift`
- `piano_dialogue_server/server/protocol.py`
- `piano_dialogue_server/server/main.py`
