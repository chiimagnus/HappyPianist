# Python Backend Workspace

本目录是 LonelyPianist 的 Python 后端工作区（可包含多个独立服务与模型）。

## Services

- `duet/`：A.I. Duet 本机后端（Bonjour `_lpduet._tcp.local.` + `POST /generate`）。

## Quick Start

```bash
rtk ./python_backend/scripts/run_duet_server.sh
```

```bash
rtk ./python_backend/scripts/smoke_duet_generate.sh
```
