# 故障排查

## 症状索引
| 症状 | 首查位置 | 典型原因 |
| --- | --- | --- |
| Start Listening 后无按键输出 | Accessibility / `statusMessage` | 权限没开 |
| Dialogue 没回复 | `/health` / 模型目录 | Python 服务没起或权重缺失 |
| Step 3 定位失败 | `practiceLocalizationStatusText` | 校准缺失 / provider 未运行 |
| 曲库能看到但不能练习 | 曲库与步骤生成 | MusicXML 没生成 steps |
| 试听没声音 | 曲库音频绑定 / 播放器 | 音频文件缺失或不可播 |

## macOS 排查
1. 检查 `hasAccessibilityPermission`。
2. 看 `connectionState` 和 `connectedSourceNames`。
3. 若无响应，先确认 MIDI 来源刷新成功。

## AVP 排查
1. 确认 Step 1 已保存，而不是只捕获。
2. 确认已导入 MusicXML 且 `importedSteps` 非空。
3. 若定位失败，优先看 provider state / anchor 状态。

## Python 排查
1. `curl -s http://127.0.0.1:8765/health`
2. 检查 `AMT_MODEL_DIR` 或 `AMT_MODEL_ID`
3. 查看 `out/dialogue_debug/*`

## 恢复建议
| 场景 | 恢复 |
| --- | --- |
| Dialogue 卡住 | 停止对话后重启服务 |
| 校准不稳 | 回 Step 1 重新校准 |
| 索引与文件不一致 | 删除异常条目后重新导入 |
| 试听状态乱掉 | 停止播放并重新绑定音频 |

## Coverage Gaps
- 目前没有统一日志聚合，因此排障页只能依赖本地状态和调试目录。
