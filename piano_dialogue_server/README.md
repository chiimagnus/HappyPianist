# Piano Dialogue — Python Workspace

本目录用于在本机跑通 **MIDI → AI → MIDI** 的离线验证（P1）与本地 WebSocket 服务（P2）。

## 目录结构（会逐步长出来）

- `requirements.txt`：Python 依赖
- `scripts/`：离线验证脚本（P1）
- `server/`：FastAPI WebSocket 服务（P2）
- `out/`：生成的 `.mid`（不会提交）

## 环境要求

- Python：建议 `3.10+`
- macOS（推荐 Apple Silicon）：可走 PyTorch `mps`；若不可用则退回 CPU

## 安装依赖

在仓库根目录：

```bash
cd piano_dialogue_server
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

提示：

- 模型权重体积很大（GB 级），不要提交到仓库。
- 若你希望把权重缓存放在本目录内，可用 `piano_dialogue_server/models/`（已在 `.gitignore` 忽略）。
- Apple Silicon 上如遇到算子不支持，可尝试：
  - `export PYTORCH_ENABLE_MPS_FALLBACK=1`

## P1：离线验证（生成 MIDI）

```bash
source .venv/bin/activate
python scripts/test_generate.py
python scripts/test_infilling.py
```

输出：

- `out/output.mid`
- `out/output_infilling.mid`

## 变量/默认值

脚本会读取以下环境变量（可选）：

- `AMT_MODEL_ID`：HuggingFace 模型 ID（默认值以脚本里为准）
- `AMT_DEVICE`：`mps` / `cuda` / `cpu`（默认自动选择）

