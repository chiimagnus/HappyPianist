# Duet Service (Python)

一个本机运行的 HTTP 服务：接收 “对话音符 JSON 协议” 的 `/generate` 请求，并返回一段可播放的回复音符。

## 启动

```bash
rtk ./python_backend/scripts/run_duet_server.sh
```

默认端口为 `8766`。如需自定义：

```bash
rtk env PORT=8766 ./python_backend/scripts/run_duet_server.sh
```

启动成功后，访问：

- `GET /health` → `{"status":"ok"}`
- `POST /generate` → 返回一段 `notes`

## 快速自检（推荐）

```bash
rtk ./python_backend/scripts/smoke_duet_generate.sh
```

看到 `health ok` 与 `generate ok` 即表示服务可用。

## 启用 Magenta（Performance RNN）

P1 阶段默认使用占位生成器；要启用 Magenta Performance RNN：

1) 下载模型：

```bash
rtk ./python_backend/scripts/download_duet_model.sh
```

2) 用 Python 3.9 启动（并启用 `DUET_ENGINE=magenta`）：

```bash
rtk env DUET_ENGINE=magenta PYTHON=python3.9 ./python_backend/scripts/run_duet_server.sh
```

当 `DUET_ENGINE=magenta` 时，`run_duet_server.sh` 会额外安装 Magenta 依赖（优先使用 `requirements-magenta-locked.txt`；否则回退到 `requirements-magenta.txt`）。
如果 Magenta 依赖或模型缺失，服务会明确报错（不会静默降级到占位引擎）。

### 参数影响（简化版）

`/generate` 的参数会影响回应的长度与随机性：

- `max_tokens`：映射为回应时长（约 `max_tokens / 64` 秒，最终 clamp 到 2–12 秒）
- `top_p`：映射为 Magenta 的 `temperature`（更高更随机）

## 常见问题

- 发现不到 Python 3.9：当前这套 Magenta/TF pins 需要 Python 3.9。可用 Homebrew 安装 `python@3.9`，并用 `PYTHON=python3.9` 指定。
- AVP 连不上：确保服务用 `--host 0.0.0.0` 监听（本项目已默认），并确认端口与 Bonjour 广播一致（默认都是 `8766`）。

## Bonjour 发现（给排障用）

服务会广播：

- service type：`_lpduet._tcp.local.`
- TXT record：`path=/generate`、`protocol_version=1`、`engine=<placeholder|magenta>`、`engine_impl=<实际实现>`

你可以在电脑端用系统工具确认是否广播成功：

```bash
rtk dns-sd -B _lpduet._tcp local.
```
Note: mDNS service type 的 service label 有 15 bytes 的限制，所以这里使用了较短的 `_lpduet._tcp`。

## Debug bundle（排障包）

当你遇到“这次为什么生成慢/怪”的问题时，可以开启本地 debug bundle，把一次请求的输入/输出与摘要落盘到本机：

```bash
rtk env DUET_DEBUG=1 ./python_backend/scripts/run_duet_server.sh
```

输出目录：

- `python_backend/out/debug/requests/<req_id>/`

包含（best-effort）：

- `request.json` / `response.json`
- `prompt_notes.json` / `reply_notes.json`
- `summary.json`（耗时、note 数量、span、engine 等）
- `python_backend/out/debug/index.jsonl`（全局索引，一行一个请求，便于 grep）

### 文件含义与字段说明

这些文件的 schema 对应：

- `python_backend/shared/protocol_v1.py`（`GenerateRequest` / `ResultResponse`）
- `python_backend/shared/debug_artifacts.py`（debug bundle 的文件结构与 `summary/index` 字段）

#### `request.json`（客户端请求）

等价于一次 `/generate` 的请求体（`GenerateRequest`）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `type` | string | 固定为 `"generate"` |
| `protocol_version` | int | 协议版本（当前为 `1`） |
| `notes` | `DialogueNote[]` | 用户输入（prompt）的对话音符 |
| `params.top_p` | float | 采样随机性（Magenta 下会映射到 temperature） |
| `params.max_tokens` | int | 回复长度（后端会映射到约 `max_tokens/64` 秒，最终 clamp 到 2–12 秒） |
| `params.strategy` | string | 生成策略标识（目前主要用于 debug/实验） |
| `params.seed` | int\|null | 随机种子（placeholder 引擎会使用；Magenta 可忽略） |
| `session_id` | string\|null | session 标识（用于连续对话/调试关联） |

`DialogueNote` 的结构：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `note` | int | MIDI pitch（0–127） |
| `velocity` | int | MIDI velocity（0–127） |
| `time` | float | 相对时间（秒，>=0） |
| `duration` | float | 持续时间（秒，>0） |

#### `response.json`（服务端响应）

等价于一次 `/generate` 的响应体（`ResultResponse`）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `type` | string | 固定为 `"result"` |
| `protocol_version` | int | 协议版本（当前为 `1`） |
| `notes` | `DialogueNote[]` | AI 输出（reply）的对话音符 |
| `latency_ms` | int\|null | 生成耗时（毫秒，best-effort） |

#### `prompt_notes.json` / `reply_notes.json`

为了方便直接 diff/统计，单独把 `request.json.notes` 与 `response.json.notes` 抽出来保存：

- `prompt_notes.json`：等价于 `request.json.notes`
- `reply_notes.json`：等价于 `response.json.notes`

#### `summary.json`（一次请求的摘要）

`summary.json` 用于快速定位“为什么这次生成怪/慢”，字段（best-effort，可能随版本扩展）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `req_id` | string | debug bundle id（也就是目录名） |
| `timestamp` | string | 本地时间戳（生成/落盘时） |
| `session_id` | string\|null | 同 `request.session_id` |
| `engine` | string | 后端引擎名（如 `placeholder`/`magenta`） |
| `model_ref` | string\|null | 具体模型/权重引用（如可用） |
| `protocol_version` | int | 协议版本 |
| `params` | object | 请求参数快照（top_p/max_tokens/strategy/seed） |
| `prompt_note_count` | int | prompt note 数量 |
| `reply_note_count` | int | reply note 数量 |
| `prompt_span_sec.start/end/duration` | float | prompt 的时间跨度 |
| `reply_span_sec.start/end/duration` | float | reply 的时间跨度 |
| `latency_ms_total` | int | 生成总耗时（毫秒） |
| `write_debug_files_ms` | int | 写入 debug 文件耗时（毫秒） |

#### `python_backend/out/debug/index.jsonl`（全局索引）

每行是一个 JSON，字段示例（best-effort）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `req_id` | string | 请求 id |
| `timestamp` | string | 时间戳 |
| `request_dir` | string | 对应请求目录路径 |
| `session_id` | string\|null | session id |
| `engine` | string\|null | 引擎名 |
| `model_ref` | string\|null | 模型引用 |
| `latency_ms_total` | int\|null | 总耗时 |
| `prompt_note_count` | int\|null | prompt note 数 |
| `reply_note_count` | int\|null | reply note 数 |

> 提示：你可以用 `rg` 在 `index.jsonl` 里按 `engine`、`latency` 或 `session_id` 过滤，再进入对应 `request_dir` 查看详细输入/输出。

隐私说明：

- 不记录音频；不上传网络；仅写入本机文件。
