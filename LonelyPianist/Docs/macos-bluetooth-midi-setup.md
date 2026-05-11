# macOS：用系统方式连接蓝牙 MIDI（BLE MIDI）

本文用于把实体钢琴/键盘（例如 Roland FP-30X）通过 **macOS 系统层**连接成 BLE MIDI 设备，让 `LonelyPianist` 这类基于 CoreMIDI 的 App 能直接看到并使用该 MIDI Source。

> 关键点：**先在系统里连上 BLE MIDI**，App 才能在 `MIDIGetNumberOfSources()` 里看到它。

## 连接步骤（推荐：在 App 内打开系统蓝牙 MIDI 窗口）

如果你使用的是 LonelyPianist 内置的连接入口：

1. 打开 App，点工具栏 `Bluetooth MIDI…`
2. 在弹出的系统窗口里找到你的设备并点击 Connect
3. 连接成功后，设备会自动出现在系统 CoreMIDI sources 中（App 侧会自动刷新）

> 这会使用系统提供的 CoreAudioKit 蓝牙 MIDI 浏览窗口，不需要手动打开 Audio MIDI Setup。

## 连接步骤（备选：Audio MIDI Setup）

1. 打开 **Audio MIDI Setup.app**
   - Finder → Applications → Utilities → `Audio MIDI Setup`
2. 打开 **MIDI Studio**
   - 菜单栏：Window → Show MIDI Studio（若已打开可跳过）
3. 打开 **Bluetooth** 面板
   - 在 MIDI Studio 里找到 **Bluetooth**（蓝牙）图标，双击打开
4. 确保钢琴处于可被发现状态
   - 打开钢琴蓝牙（具体按钢琴型号操作）
   - 有些钢琴会区分 “Audio Bluetooth” 与 “MIDI Bluetooth”，确保启用的是 MIDI
5. 在 Bluetooth 面板中找到你的设备并点击 **Connect**
6. 等待连接完成
   - 通常会显示连接计时、RSSI 等信息

连接完成后，macOS 会把该设备暴露为 CoreMIDI 的 Source/Destination（取决于设备能力）。

## 在 LonelyPianist 中验证

1. 启动 App（或确保 App 正在运行）
2. 点击工具栏 `Bluetooth MIDI…`，在系统窗口里 Connect 你的钢琴
   - 如果系统弹出“允许访问蓝牙”的提示，请选择允许
3. 连接成功后回到 App，弹奏键盘进行验证
   - 期望结果：弹奏时 App 的 MIDI 事件计数增加 / 能录到 notes

## 常见问题与排障

### 1) App 里显示 sources 为 0

优先按顺序检查：

1. 系统层是否真的连上了 BLE MIDI
   - 回到 Audio MIDI Setup → Bluetooth 面板，看是否处于 Connected
   - 或在 App 里再次打开 `Bluetooth MIDI…`，确认设备处于 Connected
2. 断开再重连
   - Disconnect → Connect
3. 重启 App
   - 某些情况下，App 启动时刷新 sources 更稳定
4. 重启蓝牙 / 重启钢琴
5. 确认钢琴的蓝牙模式
   - 部分型号需要切到 “MIDI over Bluetooth” 而不是音频蓝牙
6. 检查蓝牙权限是否被拒绝
   - System Settings → Privacy & Security → Bluetooth → 允许 `LonelyPianist`

### 2) 已连接，但 App 仍收不到 note on/off

1. 确认钢琴是否在发送 MIDI（不是本地静音/特殊模式）
2. 先用一个 MIDI 监视工具验证（任选其一）
   - DAW（Logic/GarageBand）或 MIDI monitor 工具
3. 如果监视工具有数据但 App 没有：
   - 等待 1–2 秒（系统可能正在创建 CoreMIDI endpoints）
   - 断开再重连 BLE MIDI（在 App 的 `Bluetooth MIDI…` 窗口中操作）
   - 确认 App 的 CoreMIDI 输入实现连接到了该 source

### 3) 蓝牙面板能看到设备，但连接失败

1. 把钢琴从 macOS 蓝牙设备列表里 “忘记设备”，再重新配对/连接
2. 尽量靠近设备、避免同时连接到其它主机（例如 iPad/iPhone）
3. 如果设备同时支持音频蓝牙，先关闭音频连接再尝试 MIDI

### 4) 点击 `Bluetooth MIDI…` 提示 “MIDI over Bluetooth is not supported / An unknown error has occurred”

这通常不是“设备不支持”，而是系统蓝牙状态或权限导致：

1. 打开 System Settings → Privacy & Security → Bluetooth，允许 `LonelyPianist`
2. 确认系统蓝牙已开启（System Settings → Bluetooth）
3. 重启 App 再试（第一次授权后需要重新触发连接流程）

## 给开发者的提示（为什么要走系统连接）

在 macOS 上，“系统层先连接 BLE MIDI，再由 CoreMIDI 枚举 sources”通常更稳定、可调试性也更好：

- App 不需要自己维护 CoreBluetooth 扫描/连接/授权状态机
- CoreMIDI 的 Source/Destination 列表与系统一致，排障路径更明确
- 用户也更熟悉 Audio MIDI Setup 的连接方式
