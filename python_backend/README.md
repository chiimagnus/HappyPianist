# Python Backend Workspace

本目录是 LonelyPianist 的 Python 后端工作区（可包含多个独立服务与模型）。

## Services

- 当前仓库不再内置任何可运行的 Duet（A.I. Duet）Python 服务实现。
- 如需新增/维护其他 Python 服务，请在 `python_backend/` 下新建独立目录，并把可运行入口脚本放到 `python_backend/scripts/`。

## Shared

- `shared/`：通用模块（协议模型、Bonjour/调试产物工具等），用于支撑 Python 侧工具或服务复用。
