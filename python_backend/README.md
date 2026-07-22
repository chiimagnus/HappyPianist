# Python 后端工作区

本目录是 HappyPianist 的 **Mac 侧** Python 工作区：用于放置“可选”的本地服务/工具（例如给 AVP 真机提供网络即兴后端），**不是** AVP App 运行的必需依赖。

## 服务

- 当前仓库 **没有** “A.I. Duet / Performance RNN” 的 Python 服务实现：
  - AVP 默认使用 **设备端 CoreML**（本地模型）与本地 rule 后端。
  - 网络后端（Bonjour + HTTP/WS）目前实现的是 **Aria v2**（在 Mac 上跑，用于 AVP 选择网络后端时连接）。
- 新增/维护其他 Python 服务时：在 `python_backend/` 下新建独立目录（每个服务一个 project），并把可运行入口脚本放到 `python_backend/scripts/`。

## 目录结构

- `python_backend/aria/`：Aria 模型源码（用于本机推理；模型权重不入 git）。
- `python_backend/aria_server/`：HappyPianist 的 Aria v2 本地服务工程（uv project）。
- `python_backend/shared/`：Python 侧共享模块（Bonjour、v2 协议、CC policy、MIDI<->events 转换等）。
- `python_backend/scripts/`：可运行入口与 smoketests（从这里启动服务/跑自检）。

## 快速开始：为 AVP 真机运行 Aria v2 服务（Apple 芯片）

前置条件：
- 同一局域网：Vision Pro 与 Mac 连接到同一 Wi‑Fi。
- Python：3.11+；依赖管理使用 `uv`。
- 模型权重：确保 `python_backend/aria/hf/model-demo.safetensors` 存在（该目录按约定被忽略，不会随仓库分发）。

1) 安装依赖（首次/更新后执行一次）
- `cd python_backend/aria_server && uv sync`

2) 启动服务（建议监听全网卡，便于真机访问）
- `cd python_backend && uv run --project aria_server python scripts/aria_server.py --host 0.0.0.0 --port 8766`

3) 本机自检（不依赖 AVP）
- HTTP：`cd python_backend && uv run --project aria_server python scripts/aria_server_smoketest.py --host 127.0.0.1 --port 8766`
- WebSocket：`cd python_backend && uv run --project aria_server python scripts/ws_client_smoketest.py ws://127.0.0.1:8766/stream`

4) AVP 端操作（真机）
- 进入练习设置，后端选择：
  - `网络本地连接（Aria v2）`（HTTP `/generate`），或
  - `网络本地连接（Aria v2 Streaming）`（WS `/stream`）。
- 首次使用会弹 Local Network 权限；需允许，才能 Bonjour 发现 `_lpduet._tcp` 服务并连接。

## 故障排查

- AVP 找不到服务：
  - 确认服务启动时输出的端口与 host（建议 `--host 0.0.0.0`）。
  - 检查 macOS 防火墙是否拦截 Python/uv 进程对外监听。
  - 在 Mac 上用 `dns-sd -B _lpduet._tcp`（或类似工具）确认 Bonjour 广播是否可见。
- 请求报 checkpoint missing：
  - 缺少 `python_backend/aria/hf/model-demo.safetensors`；需自行下载并放到该路径，或启动时传 `--checkpoint <path>`。

## 共享模块

- `shared/`：通用模块（协议模型、Bonjour 等），用于支撑 Python 侧工具或服务复用。
