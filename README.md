# 🎹 LonelyPianist

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14%2B-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License">
</p>

<p align="center">
  <em>弹个音符打字，按个和弦触发快捷键，来段旋律启动快捷指令。</em><br>
  <strong>你的钢琴，不只是钢琴。</strong>
</p>

---

## ✨ 功能亮点

| 场景 | 能力 |
|------|------|
| 🎵 **单音符 → 文本** | 把任意音符映射成字符、单词或整段文本 |
| 🎼 **和弦 → 组合键** | 一个和弦触发 `⌘C`、`⌘V`、`⌘⇧Z` 等任意快捷键 |
| 🎶 **旋律 → 快捷指令** | 弹一段旋律，自动启动 macOS Shortcuts 或输入文本 |
| 🎚️ **力度区分** | 同一个键，轻弹和重弹输出不同内容（如小写/大写） |
| 🔄 **多 Profile 切换** | 编程、写作、演示……一键切换映射方案 |
| 🎙️ **录音与回放** | 录制你的演奏，钢琴卷帘窗可视化 |
| 📌 **菜单栏常驻** | 不占 Dock，安静待命，随叫随到 |

## 🚀 快速上手

1. **启动应用** → 菜单栏出现钢琴图标
2. **授予权限** → 点击 `Grant Permission`（首次必做，否则无法注入按键）
3. **开始监听** → 点击 `Start Listening` 监听 MIDI 输入
4. **打开面板** → 点击 `Open LonelyPianist` 进入主窗口
5. **添加规则** → 在 `Mappings` 页面配置你的映射
6. **开始演奏** 🎹

> ⚠️ **必须授予辅助功能权限**
> 
> 路径：`系统设置 > 隐私与安全性 > 辅助功能` → 勾选 **LonelyPianist**
> 
> 没有此权限，应用无法跨应用注入按键。授权后无需重启应用，状态会自动刷新。

---

## 🎛️ 使用指南

### 单音符映射

将 MIDI 音符（如 C4）映射为文本输出。支持力度阈值：

- **普通力度**：输出小写字母（如 `a`）
- **高力度**：输出大写字母（如 `A`）

默认 QWERTY Profile 将 MIDI 48-83 映射到 `a-z`、`0-9`，力度阈值 100。

### 和弦映射

同时按下多个音符触发组合键：

- **C+E+G** → `⌘C`（复制）
- **D+F+A** → `⌘V`（粘贴）
- **A+D+F** → `⌘Z`（撤销）

支持三种动作类型：文本输入、组合键、macOS 快捷指令。

### 旋律触发

按顺序弹奏音符，在时间窗口内完成即可触发：

- **E → E → G**（间隔 ≤ 500ms）→ 输入 "hello "
- **C → D → E → G** → 启动 "Open Notion" 快捷指令

### 录音与回放

1. 切换到 `Recorder` 面板
2. 点击录制按钮，开始演奏
3. 停止后自动生成 Recording Take
4. 在钢琴卷帘窗中查看音符分布
5. 支持播放、暂停、拖拽进度条

### 多 Profile 管理

- **新建**：基于当前 Profile 创建新方案
- **克隆**：完整复制当前 Profile
- **切换**：下拉选择器即时切换
- **删除**：删除当前激活的 Profile 时，自动激活最近更新的方案

---

## 🧑‍💻 开发与启动（从源码）

环境要求：

- macOS 14+
- Xcode 16+（推荐用最新稳定版）

启动方式二选一：

1) 用 Xcode 打开工程：

```bash
open LonelyPianist.xcodeproj
```

2) 用脚本一键 build + open（推荐）：

```bash
.github/scripts/build-open.sh
```

验证构建（Debug）：

```bash
xcodebuild -project LonelyPianist.xcodeproj -scheme LonelyPianist -configuration Debug build
```

运行单测：

```bash
xcodebuild -project LonelyPianist.xcodeproj -scheme LonelyPianist -configuration Debug test
```

---

## 🤖 Piano Dialogue（AI 钢琴对话模式）

> Turn-based：你弹一段 → 停顿 → AI 回一段（AI 音符会用橙色显示，并保存到 Recorder 的同一个 take 内）。

### 1) 准备 Python 后端（首次必做）

本仓库自带本机后端工作区：`piano_dialogue_server/`。

创建虚拟环境并安装依赖：

```bash
cd piano_dialogue_server
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

准备模型权重（不要提交仓库）：

- 模型：`stanford-crfm/music-large-800k`
- 放置路径：
  - `piano_dialogue_server/models/music-large-800k/model.safetensors`
  - `piano_dialogue_server/models/music-large-800k/config.json`

（可选）如果你把模型放在其他目录，后端支持：

```bash
export AMT_MODEL_DIR=/path/to/music-large-800k
```

### 2) 启动后端服务（保持运行）

在一个独立终端（或 tmux）里启动：

```bash
cd piano_dialogue_server/server
../.venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 8765
```

健康检查：

```bash
curl -s http://127.0.0.1:8765/health
```

期望输出：

```json
{"status":"ok"}
```

（可选）端到端测试（会生成 `piano_dialogue_server/out/server_reply.mid`）：

```bash
cd piano_dialogue_server/server
../.venv/bin/python test_client.py
```

### 3) 在 App 中使用 Dialogue

1. 启动 LonelyPianist（从菜单栏打开主窗口）
2. 首次使用仍需授予 **辅助功能权限**（否则无法开始监听）
3. 点击 `Start Listening`
4. 在侧边栏选择 `Dialogue`，点击 `Start Dialogue`
5. 弹一段，停顿（默认静默 2s + 踏板抬起）后触发 AI 回应
6. 回应会自动回放到你选择的 playback output，并保存为 take（Recorder 里可见）

回放期间的输入策略（可持久化，默认 B）：

- A Ignore：忽略你的输入
- B Interrupt：你一按键就打断 AI，立刻开始收集下一句（默认）
- C Queue：排队，AI 播完后再生成下一句

---

## 🎹 没有实体 MIDI 键盘？

没问题！你可以用虚拟 MIDI 键盘测试：

- 推荐 [MidiKeys](https://github.com/flit/MidiKeys)（开源免费）
- 打开 MidiKeys 后，在 LonelyPianist 中点击 `Refresh MIDI Sources` 即可识别

> 💡 **避坑提示**：不要用库乐队（GarageBand）测试 — 它的 MIDI 事件不会广播给外部应用。

---

## 🗺️ Roadmap

- [x] **Piano Dialogue（Turn-based）** — 弹一句，AI 接一句（本机后端 `ws://127.0.0.1:8765/ws`）
- [ ] **Piano Dialogue（Real-time）** — 真同台即兴（流式生成 + 持续输出，规划中）

---

<p align="center">
  Made with 🎹 by <a href="https://github.com/chiimagnus">chiimagnus</a>
</p>
