# piano_duet_server

一个本机运行的 HTTP 服务：接收 “对话音符 JSON 协议” 的 `/generate` 请求，并返回一段可播放的回复音符。

P1 阶段只提供占位生成器（用于打通 AVP 端到端链路）；P2 才接入 Magenta Performance RNN。

## 启动

```bash
rtk ./scripts/run_server.sh
```

默认端口为 `8766`（避免与 `piano_dialogue_server` 默认 `8765` 冲突）。如需自定义：

```bash
rtk env PORT=8766 ./scripts/run_server.sh
```

启动成功后，访问：

- `GET /health` → `{"status":"ok"}`
- `POST /generate` → 返回一段 `notes`

## 快速自检（推荐）

```bash
rtk ./scripts/smoke_generate.sh
```

看到 `health ok` 与 `generate ok` 即表示服务可用。

## 启用 Magenta（Performance RNN）

P1 阶段默认使用占位生成器；要启用 Magenta Performance RNN：

1) 下载模型：

```bash
rtk ./scripts/download_model.sh
```

2) 用 Python 3.10 启动（并启用 `DUET_ENGINE=magenta`）：

```bash
rtk env DUET_ENGINE=magenta PYTHON=python3.10 ./scripts/run_server.sh
```

当 `DUET_ENGINE=magenta` 时，`run_server.sh` 会额外安装 `requirements-magenta.txt`。
如果 Magenta 依赖或模型缺失，服务会明确报错（不会静默降级到占位引擎）。

### 参数影响（简化版）

`/generate` 的参数会影响回应的长度与随机性：

- `max_tokens`：映射为回应时长（约 `max_tokens / 64` 秒，最终 clamp 到 2–12 秒）
- `top_p`：映射为 Magenta 的 `temperature`（更高更随机）

## 常见问题

- 发现不到 Python 3.10：Magenta 依赖链需要 Python 3.9/3.10。建议使用 `pyenv` 安装 `3.10.x` 并用 `PYTHON=python3.10` 指定。
- AVP 连不上：确保服务用 `--host 0.0.0.0` 监听（本项目已默认），并确认端口与 Bonjour 广播一致（默认都是 `8766`）。

## Bonjour 发现（给排障用）

服务会广播：

- service type：`_lpduet._tcp.local.`
- TXT record：`path=/generate`、`protocol_version=1`、`engine=magenta`、`engine_impl=<实际实现>`

你可以在电脑端用系统工具确认是否广播成功：

```bash
rtk dns-sd -B _lpduet._tcp local.
```
Note: mDNS service type 的 service label 有 15 bytes 的限制，所以这里使用了较短的 `_lpduet._tcp`。

## Debug bundle（排障包）

当你遇到“这次为什么生成慢/怪”的问题时，可以开启本地 debug bundle，把一次请求的输入/输出与摘要落盘到本机：

```bash
rtk env DUET_DEBUG=1 ./scripts/run_server.sh
```

输出目录：

- `piano_duet_server/out/debug/requests/<req_id>/`

包含（best-effort）：

- `request.json` / `response.json`
- `prompt_notes.json` / `reply_notes.json`
- `summary.json`（耗时、note 数量、span、engine 等）

隐私说明：

- 不记录音频；不上传网络；仅写入本机文件。
