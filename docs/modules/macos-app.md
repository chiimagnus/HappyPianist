# macOS App

`HappyPianistMac` 是独立的 macOS 26 App host。它的 App Sandbox container 与 visionOS host 完全分离；不迁移、读取或共享后者的 Documents 数据。

它只链接 `Diagnostics`、`MusicXML`、`MIDI`、`Practice`、`Notation` 与 `Library`。`RealityKitContent`、ARKit、RealityKit、手部追踪、虚拟钢琴、音频识别和 AI 不属于该 target，也不允许以 source membership、链接产品或 entitlement 形式进入。曲目试听由 `Library.SongAudioPlayer` 使用共享的 `AVFAudio` 实现；macOS host 不保留另一份 AVFoundation source。

composition root 是 `MacAppGraph`：它显式提供空的 bundled-library provider，因此首次启动一定从用户导入开始。`MacLibraryViewModel` 先恢复未完成事务再读 index，并编排 `Library` 的导入、文件、共享曲目试听和进度 actors；View 只将 file importer 的 URL 回传给 ViewModel。用户曲目可绑定/替换 mp3 或 m4a、试听/停止并删除关联 score/audio/progress；选择、替换和删除都会使旧试听 intent 失效，绝不把外部 URL、bookmark 或绝对路径写入 index/诊断。`MIDISettingsViewModel` 持有输入选择与共享输出生命周期，View 不直接访问文件或 CoreMIDI。`MacPracticeViewModel` 从 resolver 取得沙盒曲谱，调用 shared preparation、`PracticeRoundConfigurationController`、`MIDIPracticeSession`、recorder、progress repository 与既有 `CoreMIDIPracticePlaybackService`；View 只发送 passage、hand、tempo、loop 和连续成功次数 intent，并展示 `Notation`、状态和可用输出上的当前步骤参考音。应用设置会失效旧输入 generation、从 active passage 首步安全重建输入；exact configuration/resume 直接恢复，失效配置或 resume 使用共享规则修复并立即写回，同时保留已批准的小节事实。当前步骤参考音始终受 active passage、hand 与 tempo 约束；缺少 output 只隐藏参考音，不阻断 MIDI 输入。设置只保存可选输入/输出 endpoint unique ID，显示名与枚举位置只用于本次列表；所选输入断开就停止且不自动 fallback，输出变更先 flush、all-notes-off/all-sound-off 再释放。没有 AVP 的 `LiveAppGraph`、seed score、audio player source 或 singleton 兼容路径。

macOS App 仅声明 App Sandbox。后续 `fileImporter` 接收 security-scoped URL，并在本地副本完成后释放 scope；它不保存外部 URL 或 bookmark，也不申请 Bluetooth、USB 或全盘文件权限。

验证入口是 `make build:mac` 与 `make test:mac`；两者只用 `HappyPianistMac`、`platform=macOS` 与独立 result bundle。自动化不构成硬件兼容性声明，wired/BLE route、物理 loopback 与 MIDI-Thru 仍保持 `pending evidence`，直到按测试协议观察并记录。
