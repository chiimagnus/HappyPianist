# 模块：piano_dialogue_server

## 边界
- 负责：`GET /health`、`POST /generate`、`WS /ws`、`POST /upload-expand`、协议校验、推理和调试包、Bonjour 广播与最小静态前端。
- 不负责：macOS / AVP UI。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `server/api/main.py` | FastAPI / WS 入口（挂载 static、协议校验、策略分流） |
| `server/api/protocol.py` | Pydantic 契约（`strategy=model/deterministic/rule`） |
| `server/api/test_client.py` | WS 回环测试（`python -m server.api.test_client`） |
| `server/engines/model_inference.py` | 模型策略（`model`）+ deterministic 策略（`deterministic`） |
| `server/engines/rule_inference.py` | 规则策略（`rule`）的 API 适配层 |
| `server/engines/rule_backend.py` | 规则即兴器核心（harmonic/rhythm/motif rules） |
| `server/media/bonjour.py` | Bonjour（mDNS/DNS-SD）广播 |
| `server/media/debug_artifacts.py` | 调试落盘（request/response/midi/summary） |
| `server/media/midi_generation.py` | MIDI 解析、分析与扩展生成（含 deterministic 的素材生成） |
| `server/media/midi_utils.py` | MIDI 读写/切窗/合并/（可选）WAV 合成工具 |
| `server/media/musicxml_generation.py` | 从 MIDI/分析生成最小 MusicXML（用于上传扩展工具链） |
| `scripts/run_server.sh` | 一键启动（venv + install + uvicorn） |
| `scripts/expand_midi.py` | 离线扩展 MIDI 脚本入口 |
| `static/index.html` | `GET /` 对应的最小前端页面（Playground） |
| `static/app.js` | `/generate` + `/upload-expand` 的浏览器侧测试逻辑 |
| `static/styles.css` | Playground 样式 |

## 入口与生命周期
| 入口 | 行为 |
| --- | --- |
| `/health` | 返回 `{"status":"ok"}` |
| `/` | 若存在 `static/index.html` 则返回页面，否则返回 fallback HTML |
| `/generate` | 接收 `GenerateRequest`（HTTP JSON），返回 `ResultResponse` |
| `/ws` | 收到 `generate` 请求后返回 `result` / `error` |
| `/upload-expand` | 上传 MIDI（multipart），返回 base64 MIDI 与 analysis（用于前端下载） |
| `BonjourServiceBroadcaster` | 服务启动时 best-effort 广播 `_lonelypianist._tcp.local.`（TXT: `path=/generate` 等） |
| `get_inference_engine()` | 懒加载并缓存模型 |
| `write_debug_bundle()` | 在 debug 开启时落盘工件 |

## 重要子页
- [Protocol](piano-dialogue-server-protocol.md)
- [Inference](piano-dialogue-server-inference.md)
- [Debug artifacts](piano-dialogue-server-debug.md)

## 风险点
- 模型目录存在但缺权重
- 安全 logits patch
- debug 写盘失败
- Bonjour 广播失败（应不影响主路径；仅影响自动发现）


## Coverage Gaps
- 没有并发压测和高负载稳定性数据。
- `/upload-expand` 的行为（生成质量/参数）主要面向手工使用与前端自测，缺少系统性回归基线。
