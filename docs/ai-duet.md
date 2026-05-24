# A.I. Duet（本机后端）使用指南

本项目提供一个独立的本机后端 `piano_duet_server/`：AVP 通过局域网 + Bonjour 自动发现它，并用 `/generate` 生成“你弹一句 → AI 回一句”的回应。

## 1) 启动电脑端 `piano_duet_server`

在仓库根目录执行：

```bash
rtk ./piano_duet_server/scripts/run_server.sh
```

默认端口是 `8766`。启动成功后，你应能访问：

- `http://127.0.0.1:8766/health` → `{"status":"ok"}`

也可以先跑一次自检（会自动启动服务、请求 `/health` 与 `/generate`）：

```bash
rtk ./piano_duet_server/scripts/smoke_generate.sh
```

## 2) 在 AVP 中选择后端

1. 打开练习界面 → 设置页；
2. 打开「AI 即兴演奏（虚拟演奏家）」；
3. 在「即兴后端」选择「网络本地连接（A.I. Duet / Magenta）」；
4. 观察状态文案：
   - “正在发现…”：表示正在通过 Bonjour 查找电脑端服务；
   - “已找到 host:port”：表示已发现并可连接（用于排障时很有用）；
   - “Local Network 权限被拒”：按下方排障处理。

## 3) 我该怎么触发一次回应？

- 弹奏一段短句（建议 1–8 秒）；
- 停顿约 2 秒；
- 你会听到 AI 回一句（P1 阶段为占位生成；P2 才接入 Magenta Performance RNN）。

## 常见问题 / 排障

### A) 一直显示“正在发现…”

请依次检查：

1. 电脑端是否已启动 `piano_duet_server`（推荐先跑 `smoke_generate.sh` 确认服务可用）；
2. AVP 与电脑是否在同一 Wi‑Fi / 同一局域网；
3. Bonjour service type 是否能被系统看到（电脑端）：

```bash
rtk dns-sd -B _lpduet._tcp local.
```

> 说明：mDNS service type 的 service label 有 15 bytes 限制，因此这里使用较短的 `_lpduet._tcp`。

### B) 显示“Local Network 权限被拒”

这是系统拒绝了本地网络发现权限：

- 到系统设置中为 AVP App 开启 Local Network 权限；
- 返回 App 后重试（重新打开虚拟演奏家，或切换一次后端）。

### C) 已发现但生成失败 / 没有声音

建议先在电脑端确认后端可生成：

```bash
rtk ./piano_duet_server/scripts/smoke_generate.sh
```

如果后端正常但听不到声音：

- 检查设置页的「输出音量（AVP）」是否被调到 0；
- 若你在 Bluetooth MIDI 模式，确认发声路由与输出目的地设置正确。

## 验收清单（无需看代码）

1) 电脑端：
- 运行 `rtk ./piano_duet_server/scripts/run_server.sh`
- `rtk ./piano_duet_server/scripts/smoke_generate.sh` 输出 `health ok` 与 `generate ok`

2) AVP：
- 打开设置 → 开启「AI 即兴演奏（虚拟演奏家）」
- 在「即兴后端」选择「网络本地连接（A.I. Duet / Magenta）」
- 状态文案出现“正在发现…”并最终出现“已找到 host:port”（或能解释清楚为何找不到）

3) 交互：
- 弹 1–8 秒 → 停顿约 2 秒 → 能听到 AI 回一句

4) 排障能力：
- 关闭电脑端服务时，AVP 文案能提示“请先启动 piano_duet_server”
- 如果 Local Network 被拒，文案明确提示去系统设置开启

5) 可观测性（可选）：
- 运行 `rtk env DUET_DEBUG=1 ./piano_duet_server/scripts/run_server.sh`
- 触发一次生成后，在 `piano_duet_server/out/debug/requests/` 下看到新的请求目录
