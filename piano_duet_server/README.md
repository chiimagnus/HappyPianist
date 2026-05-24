# piano_duet_server

一个本机运行的 HTTP 服务：接收 “对话音符 JSON 协议” 的 `/generate` 请求，并返回一段可播放的回复音符。

P1 阶段只提供占位生成器（用于打通 AVP 端到端链路）；P2 才接入 Magenta Performance RNN。

## 启动

```bash
rtk PYTHON=python3.10 ./scripts/run_server.sh
```

默认端口为 `8766`（避免与 `piano_dialogue_server` 默认 `8765` 冲突）。如需自定义：

```bash
rtk PORT=8766 PYTHON=python3.10 ./scripts/run_server.sh
```

启动成功后，访问：

- `GET /health` → `{"status":"ok"}`
- `POST /generate` → 返回一段 `notes`

## 快速自检（推荐）

```bash
rtk PYTHON=python3.10 ./scripts/smoke_generate.sh
```

看到 `health ok` 与 `generate ok` 即表示服务可用。

## 常见问题

- 发现不到 Python 3.10：安装 Python 3.10，或用 `PYTHON=python3` 指向你本机的 Python。
- AVP 连不上：确保服务用 `--host 0.0.0.0` 监听（本项目已默认），并确认端口与 Bonjour 广播一致（P2 会补齐 Bonjour）。

## Bonjour 发现（给排障用）

服务会广播：

- service type：`_lpduet._tcp.local.`
- TXT record：`path=/generate`、`protocol_version=1`、`engine=magenta`

你可以在电脑端用系统工具确认是否广播成功：

```bash
dns-sd -B _lpduet._tcp local.
```
Note: mDNS service type 的 service label 有 15 bytes 的限制，所以这里使用了较短的 `_lpduet._tcp`。
