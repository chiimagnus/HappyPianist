# macOS App

`HappyPianistMac` 是独立的 macOS 26 App host。它的 App Sandbox container 与 visionOS host 完全分离；不迁移、读取或共享后者的 Documents 数据。

它只链接 `Diagnostics`、`MusicXML`、`MIDI`、`Practice`、`Notation` 与 `Library`。`RealityKitContent`、ARKit、RealityKit、手部追踪、虚拟钢琴、音频识别、AVFoundation 和 AI 不属于该 target，也不允许以 source membership、链接产品或 entitlement 形式进入。

composition root 是 `MacAppGraph`：它显式提供空的 bundled-library provider，因此首次启动一定从用户导入开始。`MacLibraryViewModel` 先恢复未完成事务再读 index，且仅编排 `Library` actors；`MIDISettingsViewModel` 持有输入选择与共享输出生命周期，View 不直接访问文件或 CoreMIDI。`MacPracticeViewModel` 从 resolver 取得沙盒曲谱，调用 shared preparation、`MIDIPracticeSession`、recorder 与 progress repository，View 仅展示 `Notation` 与状态。设置只保存可选输入/输出 endpoint unique ID，显示名与枚举位置只用于本次列表；所选输入断开就停止且不自动 fallback，输出变更先 flush、all-notes-off/all-sound-off 再释放。曲库、端点设置与 MIDI-only practice 会在同一 host 内逐步接入共享 core；没有 AVP 的 `LiveAppGraph`、seed score、audio player 或 singleton 兼容路径。

macOS App 仅声明 App Sandbox。后续 `fileImporter` 接收 security-scoped URL，并在本地副本完成后释放 scope；它不保存外部 URL 或 bookmark，也不申请 Bluetooth、USB 或全盘文件权限。
